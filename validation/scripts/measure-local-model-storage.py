"""Record allocated space separately for installed bundle, cache and retained sources."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ADB = [str(Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk/platform-tools/adb.exe'), '-d']
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--run', required=True)
args = parser.parse_args()
if not re.fullmatch(r'[a-z0-9-]{1,32}', args.run):
    raise ValueError('Unsafe run ID')
manifest = json.loads((ROOT / 'assets/models/manifest.json').read_text(encoding='utf-8'))
source = json.loads((ROOT / 'validation/reports/us2/source-folder-01.json').read_text(encoding='utf-8'))
folder = source['phoneSourceFolder']
if not re.fullmatch(r'/sdcard/Download/uReader-voice-fr-phase5-\d+', folder):
    raise ValueError('Unexpected validation source path')
for key in ['bundleId', 'bundleVersion']:
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]+', manifest[key]) or '..' in manifest[key]:
        raise ValueError('Unexpected bundle identifier')
paths = {
    'installedBundle': ('files/ureader-prototype/models/' + manifest['bundleId'] + '/' + manifest['bundleVersion'], True),
    'audioCache': ('files/ureader-prototype/cache/audio', True),
    'retainedLaboratoryBundle': ('files/ureader-aligned-generation', True),
    'sourceInDownloads': (folder, False),
}
report = {'expectedBundleBytes': sum(f['byteSize'] for f in manifest['files']), 'allocationUnit': 'KiB', 'measurements': {}}
for key, (path, private) in paths.items():
    prefix = ['shell', 'run-as', 'com.ureader.prototype'] if private else ['shell']
    result = subprocess.run(ADB + prefix + ['du', '-sk', path], capture_output=True, timeout=30)
    value = None
    if result.returncode == 0:
        value = int(result.stdout.decode().split()[0])
    report['measurements'][key] = {'allocatedKiB': value, 'status': 'measured' if value is not None else 'absent_or_unavailable'}
output = ROOT / f'validation/reports/us2/storage-{args.run}.json'
with output.open('x', encoding='utf-8') as handle:
    json.dump(report, handle, indent=2); handle.write('\n')
print(json.dumps(report))
