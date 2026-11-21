"""Offline export experiment from pinned official Pocket TTS; never replaces a candidate bundle."""
import argparse
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


def deny_network(*args, **kwargs):
    raise RuntimeError('Network forbidden during official flow export')


socket.socket.connect = deny_network
socket.socket.connect_ex = deny_network
socket.create_connection = deny_network
socket.getaddrinfo = deny_network

import numpy as np
import onnx
from onnx.reference import ReferenceEvaluator
import onnxruntime as ort
from onnxruntime.quantization import QuantType, quantize_dynamic
import torch
import yaml


class Flow(torch.nn.Module):
    def __init__(self, network):
        super().__init__()
        self.network = network

    def forward(self, c, s, t, x):
        return self.network(c, s, t, x)


def metrics(expected, actual):
    a = np.asarray(expected, dtype=np.float64)
    b = np.asarray(actual, dtype=np.float64)
    if a.shape != b.shape or not np.isfinite(a).all() or not np.isfinite(b).all():
        raise ValueError('Shape or finite-value check failed')
    return {'maxAbsoluteError': float(np.abs(a - b).max()),
            'rmse': float(np.sqrt(np.mean((a - b) ** 2)))}


def run(output, aligned_reference=False):
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
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    for directory, entries in [(reference, lock['officialReference']['downloadFiles']),
                               (candidate, lock['downloadFiles'])]:
        errors = verifier.verify(directory, entries)
        if errors:
            raise ValueError('; '.join(errors))
    versions = {name: importlib.metadata.version(name) for name in
                ['pocket-tts', 'torch', 'onnx', 'onnxruntime', 'numpy', 'tokenizers', 'safetensors', 'PyYAML']}
    for name, expected in {'pocket-tts': '3.3.0', 'torch': '2.11.0', 'onnx': '1.21.0',
                           'onnxruntime': '1.25.0', 'numpy': '2.2.6'}.items():
        if versions[name] != expected:
            raise ValueError('Export environment version mismatch: ' + name)
    output.mkdir(parents=True, exist_ok=False)
    scratch = output.resolve() / 'scratch'
    scratch.mkdir()
    tempfile.tempdir = str(scratch)
    report = {'status': 'started', 'scope': 'Official flow only; not a complete bundle or G0',
              'sourceSelection': 'official_3.3_default_aligned' if aligned_reference else 'previous_explicit_weights',
              'officialCodeRevision': lock['officialReference']['codeRevision'],
              'scriptSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'originalWeightsSha256': next(e['sha256'] for e in lock['officialReference']['downloadFiles']
                                           if e['relativePath'] == 'model.safetensors'),
              'python': platform.python_version(), 'platform': platform.system(), 'versions': versions,
              'export': {'backend': 'legacy TorchScript', 'dynamo': False, 'opset': 18, 'batch': 1},
              'fp32Tolerance': {'absolute': 1e-5, 'relative': 1e-4},
              'int8NumericAcceptanceThreshold': None, 'networkAllowed': False,
              'existingCandidateReplaced': False, 'g0': 'not_demonstrated'}
    (output / 'environment.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    from pocket_tts import TTSModel
    torch.set_num_threads(1)
    torch.manual_seed(0)
    config = yaml.safe_load(importlib.resources.files('pocket_tts').joinpath('config/french.yaml').read_text(encoding='utf-8'))
    config['weights_path'] = str((reference / 'model.safetensors').resolve())
    config['weights_path_without_voice_cloning'] = None
    config['flow_lm']['lookup_table']['tokenizer_path'] = str((candidate / 'tokenizer.json').resolve())
    local_config = output / 'official-local.yaml'
    local_config.write_text(yaml.safe_dump(config, allow_unicode=False), encoding='ascii')
    model = TTSModel.load_model(config=local_config, temp=0.3, sampler_decode_steps=1, eos_threshold=-4.0)
    network = Flow(model.flow_lm.flow_net).eval()
    fp32 = output / 'flow-official-fp32.onnx'
    int8 = output / 'flow-official-int8.onnx'
    example = (torch.zeros(1, 1024), torch.zeros(1, 1), torch.ones(1, 1), torch.zeros(1, 32))
    with torch.inference_mode():
        torch.onnx.export(network, example, str(fp32), input_names=['c', 's', 't', 'x'],
                          output_names=['direction'], opset_version=18, dynamo=False,
                          export_params=True, external_data=False)
    onnx.checker.check_model(str(fp32))
    quantize_dynamic(str(fp32), str(int8), weight_type=QuantType.QInt8, per_channel=False,
                     reduce_range=False, op_types_to_quantize=['MatMul', 'Gemm'])
    onnx.checker.check_model(str(int8))
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
    session = ort.InferenceSession(str(fp32), options, providers=['CPUExecutionProvider'])
    # Independent INT8 evaluator avoids the diagnosed x86 saturated accumulator as an oracle.
    quantized = ReferenceEvaluator(onnx.load(str(int8), load_external_data=False))
    cases = []
    with torch.inference_mode():
        for seed, scale in [(0, 0), (1, .01), (2, 1), (3, 3), (4, .25)]:
            rng = np.random.default_rng(seed)
            inputs = {'c': rng.normal(0, scale, (1, 1024)).astype(np.float32),
                      's': np.zeros((1, 1), np.float32), 't': np.ones((1, 1), np.float32),
                      'x': rng.normal(0, np.sqrt(.3), (1, 32)).astype(np.float32)}
            expected = network(*(torch.from_numpy(inputs[k]) for k in ['c', 's', 't', 'x'])).numpy()
            actual = session.run(None, inputs)[0]
            passed = bool(np.allclose(expected, actual, atol=1e-5, rtol=1e-4))
            cases.append({'seed': seed, 'conditioningScale': scale, 'fp32Passed': passed,
                          'fp32': metrics(expected, actual),
                          'int8DiagnosticOnly': metrics(expected, quantized.run(None, inputs)[0])})
    report['cases'] = cases
    report['files'] = [{'name': p.name, 'byteSize': p.stat().st_size,
                        'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in [fp32, int8]]
    report['status'] = 'flow_export_and_fp32_comparison_passed' if all(c['fp32Passed'] for c in cases) else 'fp32_comparison_failed'
    (output / 'result.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--aligned-reference', action='store_true')
    args = parser.parse_args()
    result = run(args.output_directory, args.aligned_reference)
    print(json.dumps({'status': result['status'], 'cases': len(result['cases']),
                      'g0': result['g0']}, ensure_ascii=True))
    sys.exit(0 if result['status'] == 'flow_export_and_fp32_comparison_passed' else 1)
