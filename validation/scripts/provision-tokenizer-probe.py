"""Golden token IDs from the pinned Python tokenizer; explicit private USB provisioning."""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import random
import subprocess

from tokenizers import Tokenizer


def main(adb):
    root = Path(__file__).resolve().parents[2]
    model = root / 'validation/private/models/fr-6l/tokenizer.json'
    lock = json.loads((root / 'validation/model-lock.json').read_text(encoding='utf-8'))
    entry = next(e for e in lock['downloadFiles'] if e['relativePath'] == 'tokenizer.json')
    digest = hashlib.sha256(model.read_bytes()).hexdigest()
    if digest != entry['sha256'] or model.stat().st_size != entry['byteSize']:
        raise ValueError('Tokenizer integrity failed')
    if importlib.metadata.version('tokenizers') != '0.22.2':
        raise ValueError('Pinned reference tokenizers 0.22.2 required')
    tokenizer = Tokenizer.from_file(str(model))
    corpus = json.loads((root / 'assets/corpus/fr_demo.json').read_text(encoding='utf-8'))
    texts = [p['text'] for t in corpus['texts'] for p in t['passages']]
    texts += ['', ' ', '  bon jour', '\tBonjour\n', '▁bonjour', 'e\u0301', '🌱',
              ' bon', 'Bonjour', 'œuf Æther Noël, 12,50 € !', '\u00a0\u2003',
              '中文 العربية русский', '\x00\x01\x1f', '🌱🌱👩\u200d🔬', 'a' * 1000]
    rng = random.Random(731)
    alphabet = 'abcéèêœçÉàù  ,.!?;:\n\t0123456789🌱漢\u0301▁'
    texts += [''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 180)))
              for _ in range(100)]
    fixture = {'schemaVersion': 1, 'reference': 'tokenizers', 'version': '0.22.2',
               'tokenizerSha256': digest,
               'cases': [{'id': i, 'text': text, 'ids': tokenizer.encode(text).ids}
                         for i, text in enumerate(texts)]}
    local = root / 'validation/private/android-runtime/tokenizer-fixtures.json'
    local.write_text(json.dumps(fixture, ensure_ascii=True, indent=2), encoding='utf-8')
    command = [str(adb), '-d']
    subprocess.run(command + ['shell', 'run-as', 'com.ureader.prototype', 'mkdir', '-p',
                              'files/ureader-g0-probe'], check=True, timeout=15)
    for source in [model, local]:
        remote = "run-as com.ureader.prototype sh -c 'cat > files/ureader-g0-probe/" + source.name + "'"
        with source.open('rb') as handle:
            subprocess.run(command + ['exec-in', remote], stdin=handle, check=True, timeout=30)
        actual = subprocess.check_output(command + ['shell', 'run-as', 'com.ureader.prototype',
            'sha256sum', 'files/ureader-g0-probe/' + source.name], timeout=15).decode().split()[0]
        if actual != hashlib.sha256(source.read_bytes()).hexdigest():
            raise ValueError('Private transfer integrity failed')
    print(f'Provisioned {len(texts)} tokenizer cases with SHA-256; no speech activated.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', type=Path, default=Path(os.environ.get('LOCALAPPDATA', '')) /
                        'Android/SDK/platform-tools/adb.exe')
    main(parser.parse_args().adb)
