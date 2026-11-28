"""Remove only replaceable model/data copies from completed private Kokoro phone probes."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
PRIVATE = ROOT / 'validation/reader/private'
PACKAGE = 'com.ureader.prototype'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args()
    if not args.report.resolve().is_relative_to(PRIVATE.resolve()) or args.report.exists():
        raise ValueError('New private report required')
    adb = str(Path(os.environ['LOCALAPPDATA']) / 'Android/sdk/platform-tools/adb.exe')
    devices = subprocess.check_output([adb, 'devices'], text=True)
    serials = [line.split()[0] for line in devices.splitlines() if line.endswith('\tdevice')]
    if len(serials) != 1:
        raise ValueError('One authorized device required')
    base = [adb, '-s', serials[0], 'shell', 'run-as', PACKAGE]

    def call(*words, check=True):
        return subprocess.run(base + list(words), capture_output=True, check=check, timeout=60)

    def exists(path):
        result = call('stat', '-c', '%F', path, check=False)
        if result.returncode == 0:
            return True
        if b'No such file or directory' in result.stderr + result.stdout:
            return False
        raise ValueError('Unable to inspect cleanup target')

    report = {'scope': 'completed_kokoro_probe_model_and_frontend_copies_only',
              'booksTouched': False, 'audioEvidenceDeleted': False, 'removed': [], 'regularFileBytesRemoved': 0}
    try:
        receipts=list(PRIVATE.glob('french-quality-kokoro-native-*/run-report.json'))
        receipts+=list(PRIVATE.glob('french-quality-kokoro-installed-*/run-report.json'))
        for receipt in sorted(receipts):
            run = receipt.parent.name
            if not re.fullmatch(r'french-quality-kokoro-(?:native-(?:0[1-6]|20261126-[0-9]{2})|installed-20261126-[0-9]{2})', run):
                continue
            previous = json.loads(receipt.read_text(encoding='utf-8'))
            if previous.get('appRestored') is not True:
                continue
            relative = 'files/' + run
            if not exists(relative):
                continue
            canonical = call('readlink', '-f', relative).stdout.decode().strip()
            if canonical not in (f'/data/user/0/{PACKAGE}/files/{run}', f'/data/data/{PACKAGE}/files/{run}'):
                raise ValueError('Unexpected canonical test root')
            artifact_names=('kokoro.onnx', 'siwis.f32', 'vocab.json', 'espeak-ng-data')
            if '-installed-' in run:
                artifact_names=tuple('ureader-prototype/models/fr-kokoro-siwis/1.0.0-development/'+name
                    for name in ('kokoro.onnx','siwis.f32','vocab.json','tokenizer.json','espeak-data.zip'))
            for name in artifact_names:
                target = relative + '/' + name
                if not exists(target):
                    continue
                resolved = call('readlink', '-f', target).stdout.decode().strip()
                if resolved != canonical + '/' + name:
                    raise ValueError('Unexpected canonical cleanup target')
                directory = name == 'espeak-ng-data'
                size = 0 if directory else int(call('stat', '-c', '%s', target).stdout.strip())
                call('rm', '-rf' if directory else '-f', target)
                if exists(target):
                    raise ValueError('Cleanup target still exists')
                report['removed'].append({'run': run, 'name': name, 'directory': directory, 'bytes': None if directory else size})
                report['regularFileBytesRemoved'] += size
        report['status'] = 'completed'
    finally:
        with args.report.open('x', encoding='utf-8') as stream:
            json.dump(report, stream, indent=2)
            stream.write('\n')
    print(json.dumps({'status': report['status'], 'artifactsRemoved': len(report['removed']),
                      'regularFileBytesRemoved': report['regularFileBytesRemoved']}))


if __name__ == '__main__':
    main()
