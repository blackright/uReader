"""Explicitly provision a bounded French generation experiment, not an activated bundle."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

import numpy as np
from tokenizers import Tokenizer


def main():
    root = Path(__file__).resolve().parents[2]
    directory = root / 'validation/private/models/fr-6l'
    spec = importlib.util.spec_from_file_location('inspection', Path(__file__).with_name('inspect-onnx.py'))
    inspection = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inspection)
    lock = inspection.verify_files(directory)
    manifest = json.loads((directory / 'manifest.json').read_text(encoding='utf-8'))
    corpus = json.loads((root / 'assets/corpus/fr_demo.json').read_text(encoding='utf-8'))
    text = corpus['texts'][0]['passages'][0]['text'].split('.', 1)[0] + '.'
    prepared = ' '.join(text.translate(str.maketrans(manifest['replace_characters'])).split())
    if manifest['remove_semicolons']:
        prepared = prepared.replace(';', ',')
    ids = Tokenizer.from_file(str(directory / 'tokenizer.json')).encode(prepared).ids
    assert 1 <= len(ids) <= 50
    # Same NumPy PCG64 stream as the retained ONNX PC experiment, for reproducible inputs.
    noise = np.random.default_rng(0).normal(0, np.sqrt(0.3), (250, 32)).astype(np.float32)
    fixture = {'purpose': 'bounded private generation experiment; not a trusted product bundle',
               'text': prepared, 'tokenIds': ids, 'noise': noise.reshape(-1).tolist(),
               'files': [{'name': Path(e['relativePath']).name, 'byteSize': e['byteSize'],
                          'sha256': e['sha256']} for e in lock['downloadFiles']]}
    local = root / 'validation/private/android-runtime/generation-fixtures.json'
    local.write_text(json.dumps(fixture, ensure_ascii=True), encoding='utf-8')
    command = [str(Path(os.environ['LOCALAPPDATA']) / 'Android/SDK/platform-tools/adb.exe'), '-d']
    sources = [*(directory / e['relativePath'] for e in lock['downloadFiles']), local]
    for source in sources:
        destination = 'files/ureader-g0-probe/' + source.name
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        current = subprocess.run(command + ['shell', 'run-as', 'com.ureader.prototype',
            'sha256sum', destination], capture_output=True, timeout=15)
        if current.returncode != 0 or current.stdout.decode().split()[0] != digest:
            with source.open('rb') as handle:
                subprocess.run(command + ['exec-in', "run-as com.ureader.prototype sh -c 'cat > " + destination + "'"],
                               stdin=handle, check=True, timeout=90)
        actual = subprocess.check_output(command + ['shell', 'run-as', 'com.ureader.prototype',
            'sha256sum', destination], timeout=30).decode().split()[0]
        if actual != digest:
            raise ValueError('Private generation transfer integrity failed')
    print('Seven verified candidate files and bounded generation inputs provisioned; no voice activated.')


if __name__ == '__main__':
    main()
