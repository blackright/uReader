"""Private aligned G0 bundle, fresh official FP16 resources, no activation or download."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'


def offline(*args, **kwargs):
    raise RuntimeError('Network forbidden during aligned assembly')


socket.socket.connect = socket.socket.connect_ex = socket.create_connection = socket.getaddrinfo = offline

import numpy as np
import torch
from pocket_tts import TTSModel
from pocket_tts.models.text_chunking import prepare_text_prompt
from tokenizers import Tokenizer


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(output):
    root = Path(__file__).resolve().parents[2]
    aligned = json.loads((root / 'validation/reference-3.3-aligned-lock.json').read_text(encoding='utf-8'))
    reference = root / aligned['directory']
    spec = importlib.util.spec_from_file_location('verifier', Path(__file__).with_name('verify-model-files.py'))
    verifier = importlib.util.module_from_spec(spec); spec.loader.exec_module(verifier)
    if verifier.verify(reference, aligned['downloadFiles']):
        raise ValueError('Aligned source integrity failed')
    selection = [('main', 'flow_lm_main_int8.onnx'), ('flow', 'flow_lm_flow_int8.onnx'),
                 ('mimi', 'mimi_decoder_int8.onnx')]
    reports = {}
    for role, _ in selection:
        folder = root / f'validation/private/aligned-{role}-01'
        report = json.loads((folder / 'result.json').read_text(encoding='utf-8'))
        if report['sourceSelection'] != 'official_3.3_default_aligned' or 'passed' not in report['status']:
            raise ValueError('Aligned export not validated')
        if report.get('weightsSha256', report.get('originalWeightsSha256')) != aligned['downloadFiles'][0]['sha256']:
            raise ValueError('Wrong export weights')
        entry = next(e for e in report['files'] if e['name'] == f'{role}-official-int8.onnx')
        source = folder / entry['name']
        if source.stat().st_size != entry['byteSize'] or sha(source) != entry['sha256']:
            raise ValueError('Export digest mismatch')
        reports[role] = report
    output.mkdir(parents=True, exist_ok=False)
    for role, name in selection:
        shutil.copyfile(root / f'validation/private/aligned-{role}-01/{role}-official-int8.onnx', output / name)
    tokenizer_path = root / 'validation/private/models/fr-6l/tokenizer.json'
    lock = json.loads((root / 'validation/model-lock.json').read_text(encoding='utf-8'))
    tokenizer_pin = next(e for e in lock['downloadFiles'] if e['relativePath'] == 'tokenizer.json')
    if sha(tokenizer_path) != tokenizer_pin['sha256']:
        raise ValueError('Tokenizer integrity failed')
    shutil.copyfile(tokenizer_path, output / 'tokenizer.json')
    torch.set_num_threads(1); torch.manual_seed(0)
    model = TTSModel.load_model(config=root / 'validation/private/aligned-main-01/official-local.yaml',
        temp=.3, sampler_decode_steps=1, eos_threshold=-4)
    with torch.no_grad():
        table = model.flow_lm.conditioner.embed(torch.arange(4001).reshape(1, -1)).reshape(4001, 1024).numpy()
    table.astype('<f2').tofile(output / 'text_embeddings.f16')
    protocol = json.loads((root / 'validation/private/models/fr-6l/manifest.json').read_text(encoding='utf-8'))
    voice = model.get_state_for_audio_prompt(reference / 'estelle.safetensors')
    offsets = []
    with (output / 'estelle.f16').open('xb') as handle:
        for layer in protocol['flow_layers']:
            state = voice[layer['name']]
            offset = int(state['offset'].item())
            if offset != 168:
                raise ValueError('Unexpected aligned voice offset')
            values = state['cache'][:, :, :offset].numpy()
            if values.shape != (2, 1, offset, 16, 64) or not np.isfinite(values).all():
                raise ValueError('Invalid official voice cache')
            handle.write(values.astype('<f2').tobytes())
            offsets.append(offset)
    if not np.isfinite(table).all():
        raise ValueError('Invalid official embedding table')
    protocol['voices']['estelle']['offsets'] = offsets
    protocol['voices']['estelle']['file'] = 'estelle.f16'
    protocol['voices']['estelle']['origin'] = aligned['downloadFiles'][1]['url']
    protocol['source']['weights'] = aligned['downloadFiles'][0]['url']
    protocol['source']['voice'] = aligned['downloadFiles'][1]['url']
    protocol['localExport'] = {'sourceSelection': 'official_3.3_default_aligned',
        'weightsSha256': sha(reference / 'model.safetensors'),
        'voiceSha256': sha(reference / 'estelle.safetensors'),
        'assemblyScriptSha256': sha(Path(__file__)),
        'exportScriptDigests': {role: report['scriptSha256'] for role, report in reports.items()}}
    (output / 'manifest.json').write_text(json.dumps(protocol, indent=2) + '\n', encoding='utf-8')
    names = [name for _, name in selection] + ['text_embeddings.f16', 'tokenizer.json', 'estelle.f16', 'manifest.json']
    files = [{'name': name, 'relativePath': name, 'byteSize': (output / name).stat().st_size,
              'sha256': sha(output / name)} for name in names]
    audit = {'files': files, 'downloadFiles': files, 'expectedVoiceOffset': 168,
        'sourceSelection': 'official_3.3_default_aligned', 'productTrustManifest': False,
        'applicationActivated': False, 'g0': 'not_demonstrated', 'recipe': protocol['localExport']}
    (output / 'audit-lock.json').write_text(json.dumps(audit, indent=2) + '\n', encoding='utf-8')
    cases = json.loads((root / 'validation/reports/g0/normalized-cases-03.json').read_text(encoding='utf-8'))
    tokenizer = Tokenizer.from_file(str(output / 'tokenizer.json'))
    prepared = []
    for case in cases['cases']:
        text, _ = prepare_text_prompt(case['synthesisText'], False, True,
            replace_characters=protocol['replace_characters'])
        ids = tokenizer.encode(text).ids
        if not 1 <= len(ids) <= 50:
            raise ValueError('Normalized Android case exceeds native token bound')
        prepared.append({**case, 'text': text, 'tokenIds': ids})
    fixture = {'cases': prepared, 'normalizerVersion': cases['normalizerVersion'],
        'preparationSha256': sha(root / 'validation/reports/g0/normalized-cases-03.json'),
        'noise': np.random.default_rng(0).normal(0, np.sqrt(.3), (250, 32)).astype(np.float32).reshape(-1).tolist()}
    (output / 'aligned-cases.json').write_text(json.dumps(fixture, ensure_ascii=True), encoding='utf-8')
    if verifier.verify(output, files):
        raise ValueError('Assembled file integrity failed')
    print(json.dumps({'files': len(files), 'voiceOffsets': offsets,
        'caseTokens': [len(c['tokenIds']) for c in prepared], 'productActivated': False}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-directory', required=True, type=Path)
    main(parser.parse_args().output_directory)
