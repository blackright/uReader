"""Offline stateful exports from official Pocket TTS 3.3.0, with independent state checks."""
import argparse
import copy
import hashlib
import importlib.metadata
import importlib.resources
import importlib.util
import json
import os
from pathlib import Path
import platform
import socket
import sys
import tempfile

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'


def offline(*args, **kwargs):
    raise RuntimeError('Network forbidden during export')


socket.socket.connect = socket.socket.connect_ex = socket.create_connection = socket.getaddrinfo = offline

import numpy as np
import onnx
import onnxruntime as ort
from onnxruntime.quantization import QuantType, quantize_dynamic
import torch
import yaml
from pocket_tts import TTSModel
from pocket_tts.modules.attention import StreamingMultiheadAttention
from pocket_tts.modules.stateful_module import increment_steps

ort.disable_telemetry_events()


class AppendCache:
    """Functional valid-prefix cache; no Python scalar extraction from dynamic offsets.

    Only batch-one, unpadded inference is supported. The original official attention,
    RoPE and context mask remain in use; the allocation/write backend alone changes.
    """
    def rope_offset(self, state, batch_size, device):
        return state['offset'].reshape(-1)[0]

    def append_and_get(self, k, v, state):
        keys = torch.cat((state['cache'][0], k), dim=1)
        values = torch.cat((state['cache'][1], v), dim=1)
        state['cache'] = torch.stack((keys, values))
        positions = torch.arange(keys.shape[1], device=k.device, dtype=torch.long).reshape(1, -1)
        return keys.transpose(1, 2), values.transpose(1, 2), positions, state['offset']


def functional_attention(module):
    for child in module.modules():
        if isinstance(child, StreamingMultiheadAttention):
            child._cache_backend = AppendCache()


class Main(torch.nn.Module):
    def __init__(self, lm, layers):
        super().__init__()
        self.lm = copy.deepcopy(lm)
        self.layers = layers
        functional_attention(self.lm)

    def forward(self, sequence, text_embeddings, *flat):
        state = {name: {'cache': flat[2*i], 'offset': flat[2*i+1]}
                 for i, name in enumerate(self.layers)}
        sequence = torch.where(torch.isnan(sequence), self.lm.bos_emb, sequence)
        hidden = self.lm.backbone(self.lm.input_linear(sequence), text_embeddings,
                                  sequence, model_state=state).float()[:, -1]
        eos = self.lm.out_eos(hidden)
        length = sequence.shape[1] + text_embeddings.shape[1]
        result = [hidden, eos]
        for name in self.layers:
            result += [state[name]['cache'], state[name]['offset'] + length]
        return tuple(result)


class Mimi(torch.nn.Module):
    def __init__(self, model, specs):
        super().__init__()
        self.mimi = copy.deepcopy(model.mimi)
        self.register_buffer('std', model.flow_lm.emb_std.detach().clone())
        self.register_buffer('mean', model.flow_lm.emb_mean.detach().clone())
        self.specs = specs
        self.steps = int(model.mimi.encoder_frame_rate / model.mimi.frame_rate)
        functional_attention(self.mimi)

    def forward(self, latent, *flat):
        state = {}
        for entry, tensor in zip(self.specs, flat):
            state.setdefault(entry['name'], {})[entry['key']] = tensor.clone()
        audio = self.mimi.decode_from_latent(latent * self.std + self.mean, state)
        result = [audio]
        for entry in self.specs:
            value = state[entry['name']][entry['key']]
            if entry['key'] == 'offset':
                value = value + latent.shape[1] * self.steps
            result.append(value)
        return tuple(result)


def original_state(flat, specs, added):
    state = {}
    for value, spec in zip(flat, specs):
        state.setdefault(spec['name'], {})[spec['key']] = value.clone()
    for values in state.values():
        if 'cache' in values:
            prefix = values['cache']
            shape = list(prefix.shape)
            shape[2] += added
            full = torch.full(shape, float('nan'), dtype=prefix.dtype)
            full[:, :, :prefix.shape[2]] = prefix
            values['cache'] = full
    return state


def snapshot(state, specs):
    result = []
    for spec in specs:
        value = state[spec['name']][spec['key']]
        if spec['key'] == 'cache':
            value = value[:, :, :int(state[spec['name']]['offset'].item())]
        result.append(value.detach().clone())
    return result


def comparison(expected, actual):
    if len(expected) != len(actual):
        raise ValueError('Output count mismatch')
    passed = True
    maximum = 0.0
    for a, b in zip(expected, actual):
        a = a.detach().numpy() if isinstance(a, torch.Tensor) else a
        b = b.detach().numpy() if isinstance(b, torch.Tensor) else b
        if a.shape != b.shape or a.dtype != b.dtype:
            return {'passed': False, 'reason': 'shape_or_dtype_mismatch'}
        if a.dtype.kind == 'f':
            if not np.isfinite(a).all() or not np.isfinite(b).all():
                return {'passed': False, 'reason': 'non_finite'}
            if a.size:
                maximum = max(maximum, float(np.max(np.abs(a - b))))
            passed &= bool(np.allclose(a, b, atol=1e-4, rtol=1e-4))
        else:
            passed &= bool(np.array_equal(a, b))
    return {'passed': passed, 'maxAbsoluteError': maximum}


def run(graph, output, aligned_reference=False):
    root = Path(__file__).resolve().parents[2]
    lock = json.loads((root / 'validation/model-lock.json').read_text(encoding='utf-8'))
    reference = root / 'validation/private/reference-fr'
    if aligned_reference:
        aligned = json.loads((root / 'validation/reference-3.3-aligned-lock.json').read_text(encoding='utf-8'))
        reference = root / aligned['directory']
        lock['officialReference']['downloadFiles'] = aligned['downloadFiles']
        package = importlib.resources.files('pocket_tts')
        for path, key in [('config/french.yaml', 'frenchConfigSha256'), ('utils/utils.py', 'voiceResolverSourceSha256')]:
            if hashlib.sha256(package.joinpath(path).read_bytes()).hexdigest() != aligned['sourceEvidence'][key]:
                raise ValueError('Aligned official source hash mismatch')
    candidate = root / 'validation/private/models/fr-6l'
    spec = importlib.util.spec_from_file_location('verify_files', Path(__file__).with_name('verify-model-files.py'))
    verifier = importlib.util.module_from_spec(spec); spec.loader.exec_module(verifier)
    for directory, entries in [(reference, lock['officialReference']['downloadFiles']), (candidate, lock['downloadFiles'])]:
        errors = verifier.verify(directory, entries)
        if errors:
            raise ValueError('; '.join(errors))
    versions = {name: importlib.metadata.version(name) for name in
                ['pocket-tts', 'torch', 'onnx', 'onnxruntime', 'numpy', 'tokenizers', 'safetensors', 'PyYAML']}
    for name, value in {'pocket-tts': '3.3.0', 'torch': '2.11.0', 'onnx': '1.21.0',
                        'onnxruntime': '1.25.0', 'numpy': '2.2.6'}.items():
        if versions[name] != value:
            raise ValueError('Version mismatch: ' + name)
    output.mkdir(parents=True, exist_ok=False)
    (output / 'scratch').mkdir()
    tempfile.tempdir = str((output / 'scratch').resolve())
    report = {'graph': graph, 'status': 'started', 'versions': versions,
              'sourceSelection': 'official_3.3_default_aligned' if aligned_reference else 'previous_explicit_weights',
              'python': platform.python_version(), 'officialCodeRevision': lock['officialReference']['codeRevision'],
              'scriptSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'weightsSha256': lock['officialReference']['downloadFiles'][0]['sha256'],
              'fp32Tolerance': {'absolute': 1e-4, 'relative': 1e-4}, 'batch': 1, 'opset': 18,
              'networkAllowed': False, 'existingCandidateReplaced': False, 'g0': 'not_demonstrated'}
    report['stateComparisonMode'] = 'Independent official and ONNX state carried across successive steps'
    (output / 'environment.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    torch.set_num_threads(1); torch.manual_seed(0)
    config = yaml.safe_load(importlib.resources.files('pocket_tts').joinpath('config/french.yaml').read_text(encoding='utf-8'))
    config['weights_path'] = str((reference / 'model.safetensors').resolve())
    config['weights_path_without_voice_cloning'] = None
    config['flow_lm']['lookup_table']['tokenizer_path'] = str((candidate / 'tokenizer.json').resolve())
    config_file = output / 'official-local.yaml'
    config_file.write_text(yaml.safe_dump(config, allow_unicode=False), encoding='ascii')
    model = TTSModel.load_model(config=config_file, temp=.3, sampler_decode_steps=1, eos_threshold=-4)
    manifest = json.loads((candidate / 'manifest.json').read_text(encoding='utf-8'))
    rng = np.random.default_rng(47)
    if graph == 'main':
        layers = [entry['name'] for entry in manifest['flow_layers']]
        specs = [{'name': name, 'key': key} for name in layers for key in ['cache', 'offset']]
        wrapper = Main(model.flow_lm, layers).eval()
        names = ['sequence', 'text_embeddings'] + [f'{key}_{i}' for i in range(6) for key in ['cache', 'offset']]
        outputs = ['conditioning', 'eos'] + [f'next_{name}' for name in names[2:]]
        example = [torch.randn(1, 2, 32), torch.randn(1, 3, 1024)]
        for _ in layers: example += [torch.zeros(2, 1, 2, 16, 64), torch.tensor([2])]
        axes = {'sequence': {1: 'sequence_length'}, 'text_embeddings': {1: 'text_length'}}
        for i in range(6):
            axes[f'cache_{i}'] = {2: 'past_length'}
            axes[f'next_cache_{i}'] = {2: 'total_length'}
    else:
        specs = manifest['mimi_states']
        wrapper = Mimi(model, specs).eval()
        names = ['latent'] + [f'mimi_{i}' for i in range(len(specs))]
        outputs = ['audio'] + [f'next_mimi_{i}' for i in range(len(specs))]
        example = [torch.randn(1, 4, 32) * .03]
        for entry in specs:
            shape = list(entry['shape'])
            if entry['key'] == 'cache': shape[2] = 2
            value = torch.ones(shape, dtype=torch.bool) if entry['dtype'] == 'bool' else torch.zeros(shape, dtype={'float32': torch.float32, 'int64': torch.int64}[entry['dtype']])
            if entry['key'] == 'offset': value[:] = 2
            example.append(value)
        axes = {'latent': {1: 'latent_length'}, 'audio': {2: 'audio_length'}}
        for i, entry in enumerate(specs):
            if entry['key'] == 'cache':
                axes[f'mimi_{i}'] = {2: 'past_length'}; axes[f'next_mimi_{i}'] = {2: 'total_length'}
    fp32 = output / f'{graph}-official-fp32.onnx'
    with torch.inference_mode():
        torch.onnx.export(wrapper, tuple(example), str(fp32), input_names=names, output_names=outputs,
                          dynamic_axes=axes, opset_version=18, dynamo=False, external_data=False)
    onnx.checker.check_model(str(fp32))
    options = ort.SessionOptions(); options.intra_op_num_threads = 1; options.inter_op_num_threads = 1
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
    session = ort.InferenceSession(str(fp32), options, providers=['CPUExecutionProvider'])
    cases = []
    with torch.inference_mode():
        if graph == 'main':
            voice = model.get_state_for_audio_prompt(reference / 'estelle.safetensors')
            flat = snapshot(voice, specs)
            reference_flat = [value.clone() for value in flat]
            tokens = json.loads((root / 'validation/reports/g0/onnx-smoke-01.json').read_text())['tokenIds']
            embeddings = model.flow_lm.conditioner.embed(torch.tensor([tokens])).float()
            steps = [(torch.empty(1, 0, 32), embeddings), (torch.full((1, 1, 32), float('nan')), torch.empty(1, 0, 1024))]
            steps += [(torch.from_numpy(rng.normal(0, .1, (1, 1, 32)).astype(np.float32)), torch.empty(1, 0, 1024)) for _ in range(3)]
            for index, (sequence, embeddings) in enumerate(steps):
                count = sequence.shape[1] + embeddings.shape[1]
                state = original_state(reference_flat, specs, count)
                sequence_bos = torch.where(torch.isnan(sequence), model.flow_lm.bos_emb, sequence)
                hidden = model.flow_lm.backbone(model.flow_lm.input_linear(sequence_bos), embeddings, sequence_bos, state).float()[:, -1]
                increment_steps(model.flow_lm, state, count)
                expected = [hidden, model.flow_lm.out_eos(hidden)] + snapshot(state, specs)
                inputs = [sequence, embeddings] + flat
                eager = wrapper(sequence, embeddings, *reference_flat)
                actual = session.run(None, {name: tensor.numpy() for name, tensor in zip(names, inputs)})
                cases.append({'step': index, 'sequenceLength': sequence.shape[1], 'textLength': embeddings.shape[1],
                              'eagerVsOfficial': comparison(expected, eager), 'onnxVsOfficial': comparison(expected, actual)})
                flat = [torch.from_numpy(value.copy()) for value in actual[2:]]
                reference_flat = snapshot(state, specs)
        else:
            flat = [torch.ones(entry['shape'], dtype=torch.bool) if entry['dtype'] == 'bool' else
                    torch.zeros(entry['shape'], dtype={'float32': torch.float32, 'int64': torch.int64}[entry['dtype']]) for entry in specs]
            reference_flat = [value.clone() for value in flat]
            for index, frames in enumerate([1, 4, 12, 2]):
                latent = torch.from_numpy(rng.normal(0, .03, (1, frames, 32)).astype(np.float32))
                count = frames * wrapper.steps
                state = original_state(reference_flat, specs, count)
                audio = model.mimi.decode_from_latent(latent * model.flow_lm.emb_std + model.flow_lm.emb_mean, state)
                # The export protocol contains decoder state only; the official helper
                # also visits the unused encoder, whose state is intentionally absent.
                for name, module in model.mimi.named_modules():
                    if isinstance(module, StreamingMultiheadAttention) and name in state:
                        module.increment_step(state[name], count)
                expected = [audio] + snapshot(state, specs)
                inputs = [latent] + flat
                eager = wrapper(latent, *reference_flat)
                actual = session.run(None, {name: tensor.numpy() for name, tensor in zip(names, inputs)})
                cases.append({'step': index, 'latentFrames': frames, 'eagerVsOfficial': comparison(expected, eager),
                              'onnxVsOfficial': comparison(expected, actual)})
                flat = [torch.from_numpy(value.copy()) for value in actual[1:]]
                reference_flat = snapshot(state, specs)
    report['cases'] = cases
    passed = all(c['eagerVsOfficial']['passed'] and c['onnxVsOfficial']['passed'] for c in cases)
    files = [fp32]
    if passed:
        int8 = output / f'{graph}-official-int8.onnx'
        quantize_dynamic(str(fp32), str(int8), weight_type=QuantType.QInt8, per_channel=False,
                         reduce_range=False, op_types_to_quantize=['MatMul', 'Gemm'])
        onnx.checker.check_model(str(int8)); files.append(int8)
    report['files'] = [{'name': p.name, 'byteSize': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]
    report['status'] = 'export_and_state_checks_passed' if passed else 'state_comparison_failed'
    report['int8AndroidValidated'] = False
    (output / 'result.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--graph', required=True, choices=['main', 'mimi'])
    parser.add_argument('--output-directory', required=True, type=Path)
    parser.add_argument('--aligned-reference', action='store_true')
    args = parser.parse_args()
    result = run(args.graph, args.output_directory, args.aligned_reference)
    print(json.dumps({'graph': args.graph, 'status': result['status'], 'cases': len(result['cases'])}))
    sys.exit(0 if result['status'] == 'export_and_state_checks_passed' else 1)
