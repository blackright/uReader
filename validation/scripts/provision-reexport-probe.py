"""Explicit USB provisioning of independently reproduced graphs; no activation or downloads."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

import onnx


def main():
    root = Path(__file__).resolve().parents[2]
    sources = [('main', 'repro-main-03'), ('flow', 'repro-flow-03'), ('mimi', 'repro-mimi-04')]
    graphs = []
    for role, folder in sources:
        directory = root / 'validation/private' / folder
        report = json.loads((directory / 'result.json').read_text(encoding='utf-8'))
        name = f'{role}-official-int8.onnx'
        entry = next(e for e in report['files'] if e['name'] == name)
        source = directory / name
        if source.stat().st_size != entry['byteSize'] or hashlib.sha256(source.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError('Export integrity mismatch')
        graph = onnx.load(str(source), load_external_data=False).graph
        graphs.append({**entry, 'role': role, 'inputCount': len(graph.input), 'outputCount': len(graph.output)})
    manifest = {'purpose': 'Reproduced graph load test only; not G0 or product bundle', 'graphs': graphs}
    local = root / 'validation/private/android-runtime/reexport-probe.json'
    local.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    command = [str(Path(os.environ['LOCALAPPDATA']) / 'Android/SDK/platform-tools/adb.exe'), '-d']
    remote_root = 'files/ureader-reexport-probe/'
    subprocess.run(command + ['shell', 'run-as', 'com.ureader.prototype', 'mkdir', '-p', remote_root], check=True, timeout=15)
    paths = [root / 'validation/private' / folder / f'{role}-official-int8.onnx' for role, folder in sources] + [local]
    for source in paths:
        with source.open('rb') as stream:
            subprocess.run(command + ['exec-in', "run-as com.ureader.prototype sh -c 'cat > " + remote_root + source.name + "'"],
                           stdin=stream, check=True, timeout=90)
        actual = subprocess.check_output(command + ['shell', 'run-as', 'com.ureader.prototype',
            'sha256sum', remote_root + source.name], timeout=30).decode().split()[0]
        if actual != hashlib.sha256(source.read_bytes()).hexdigest():
            raise ValueError('Private transfer integrity mismatch')
    print('Three reproduced INT8 graphs provisioned separately with verified SHA-256. No model activated.')


if __name__ == '__main__':
    main()
