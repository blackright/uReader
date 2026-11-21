"""Freeze three bounded corpus extracts using the pinned official text preparation, optionally provision via USB."""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import socket
import subprocess

os.environ['HF_HUB_OFFLINE'] = '1'


def offline(*args, **kwargs):
    raise RuntimeError('Network forbidden during G0 preparation')


socket.socket.connect = socket.socket.connect_ex = socket.create_connection = socket.getaddrinfo = offline

import numpy as np
from tokenizers import Tokenizer
from pocket_tts.models.text_chunking import prepare_text_prompt


def main(output, provision):
    root = Path(__file__).resolve().parents[2]
    if importlib.metadata.version('pocket-tts') != '3.3.0':
        raise ValueError('Pinned Pocket TTS 3.3.0 required')
    bundle = root / 'validation/private/repro-bundle-01'
    protocol = json.loads((bundle / 'manifest.json').read_text())
    corpus_bytes = (root / 'assets/corpus/fr_demo.json').read_bytes()
    corpus = json.loads(corpus_bytes)
    tokenizer = Tokenizer.from_file(str(bundle / 'tokenizer.json'))
    cases = []
    for passage_id in ['fr-01-p1', 'fr-04-p1', 'fr-05-p1']:
        passage = next(p for t in corpus['texts'] for p in t['passages'] if p['id'] == passage_id)
        raw = passage['text'].split('.', 1)[0] + '.'
        prepared, _ = prepare_text_prompt(raw, False, True, replace_characters=protocol['replace_characters'])
        ids = tokenizer.encode(prepared).ids
        if not 1 <= len(ids) <= 50:
            raise ValueError('G0 case exceeds token bound')
        cases.append({'id': passage_id, 'text': prepared, 'tokenIds': ids,
                      'sourceTextSha256': hashlib.sha256(raw.encode()).hexdigest(),
                      'preparedTextSha256': hashlib.sha256(prepared.encode()).hexdigest(),
                      'startOffsetUtf16': 0, 'endOffsetUtf16': len(raw.encode('utf-16-le')) // 2})
    data = {'schemaVersion': 1, 'officialVersion': '3.3.0', 'cases': cases,
            'manifestSha256': hashlib.sha256((root / 'assets/models/manifest.json').read_bytes()).hexdigest(),
            'corpusSha256': hashlib.sha256(corpus_bytes).hexdigest(), 'noiseSeed': 0,
            'noise': np.random.default_rng(0).normal(0, np.sqrt(.3), (250, 32)).astype(np.float32).reshape(-1).tolist()}
    with output.open('x', encoding='utf-8') as handle:
        json.dump(data, handle, ensure_ascii=True)
    if provision:
        adb = Path(os.environ['LOCALAPPDATA'])/'Android/SDK/platform-tools/adb.exe'
        remote = 'files/ureader-reexport-generation/g0-cases.json'
        with output.open('rb') as stream:
            subprocess.run([str(adb), '-d', 'exec-in', "run-as com.ureader.prototype sh -c 'cat > "+remote+"'"],stdin=stream,check=True,timeout=30)
        actual=subprocess.check_output([str(adb),'-d','shell','run-as','com.ureader.prototype','sha256sum',remote],timeout=15).decode().split()[0]
        if actual!=hashlib.sha256(output.read_bytes()).hexdigest(): raise ValueError('Case transfer integrity failed')
    print(json.dumps({'cases': [{'id': c['id'], 'tokens': len(c['tokenIds']), 'endOffsetUtf16': c['endOffsetUtf16']} for c in cases], 'provisioned': provision}))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--provision',action='store_true')
    args=parser.parse_args();main(args.output,args.provision)
