"""Freeze exact fr-01/fr-04 extracts for aligned Android, optionally transfer fixture via USB."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess

os.environ['HF_HUB_OFFLINE'] = '1'


def offline(*args, **kwargs):
    raise RuntimeError('Network forbidden during protocol preparation')


socket.socket.connect = socket.socket.connect_ex = socket.create_connection = socket.getaddrinfo = offline

import numpy as np
from pocket_tts.models.text_chunking import prepare_text_prompt
from tokenizers import Tokenizer


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(output, provision):
    root = Path(__file__).resolve().parents[2]
    manifest_path = root / 'assets/models/manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    if manifest['bundleId'] != 'fr-official-aligned' or manifest['activationGate']['g0Verdict'] != 'not_demonstrated':
        raise ValueError('Expected locked aligned manifest')
    if manifest['textPreparation']['sourceSha256'] != sha(root / 'lib/features/listening/french_text_normalizer.dart'):
        raise ValueError('Normalizer source mismatch')
    bundle = root / 'validation/private/aligned-bundle-01'
    for entry in manifest['files']:
        path = bundle / entry['relativePath']
        if path.stat().st_size != entry['byteSize'] or sha(path) != entry['sha256']:
            raise ValueError('Embedded trust manifest does not match provisioned bundle')
    normalized_path = root / 'validation/reports/g0/normalized-protocol-cases-01.json'
    normalized = json.loads(normalized_path.read_text(encoding='utf-8'))
    if normalized['normalizerVersion'] != manifest['textPreparation']['version']:
        raise ValueError('Unexpected text preparation version')
    corpus_path = root / 'assets/corpus/fr_demo.json'
    corpus = json.loads(corpus_path.read_text(encoding='utf-8'))
    protocol = json.loads((bundle / 'manifest.json').read_text(encoding='utf-8'))
    tokenizer = Tokenizer.from_file(str(bundle / 'tokenizer.json'))
    cases = []
    if [c['id'] for c in normalized['cases']] != ['fr-01-p1', 'fr-04-p1']:
        raise ValueError('Exact protocol case IDs required')
    for case in normalized['cases']:
        passage = next(p for t in corpus['texts'] for p in t['passages'] if p['id'] == case['id'])
        raw = passage['text'].split('.', 1)[0] + '.'
        if case['sourceText'] != raw or case['synthesisText'] != raw:
            raise ValueError('These nonnumeric extracts must remain identical to corpus')
        text, _ = prepare_text_prompt(raw, False, True, replace_characters=protocol['replace_characters'])
        ids = tokenizer.encode(text).ids
        if not 1 <= len(ids) <= 50:
            raise ValueError('Native token bound exceeded')
        cases.append({**case, 'text': text, 'tokenIds': ids, 'startOffsetUtf16': 0,
            'endOffsetUtf16': len(raw.encode('utf-16-le')) // 2})
    fixture = {'cases': cases, 'normalizerVersion': normalized['normalizerVersion'],
        'normalizerSourceSha256': manifest['textPreparation']['sourceSha256'],
        'corpusSha256': sha(corpus_path), 'manifestSha256': sha(manifest_path),
        'preparationSha256': sha(normalized_path),
        'noise': np.random.default_rng(0).normal(0, np.sqrt(.3), (250, 32)).astype(np.float32).reshape(-1).tolist()}
    with output.open('x', encoding='utf-8') as handle:
        json.dump(fixture, handle, ensure_ascii=True)
    if provision:
        adb = [str(Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk/platform-tools/adb.exe'), '-d']
        remote = 'files/ureader-aligned-generation/aligned-protocol-cases.json'
        with output.open('rb') as stream:
            subprocess.run(adb + ['exec-in', "run-as com.ureader.prototype sh -c 'cat > " + remote + "'"],
                stdin=stream, check=True, timeout=30)
        actual = subprocess.check_output(adb + ['shell', 'run-as', 'com.ureader.prototype', 'sha256sum', remote], timeout=20).decode().split()[0]
        if actual != sha(output):
            raise ValueError('USB fixture hash mismatch')
    print(json.dumps({'cases': [{'id': c['id'], 'tokens': len(c['tokenIds']), 'endOffsetUtf16': c['endOffsetUtf16']} for c in cases], 'provisioned': provision}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--provision', action='store_true')
    args = parser.parse_args()
    main(args.output, args.provision)
