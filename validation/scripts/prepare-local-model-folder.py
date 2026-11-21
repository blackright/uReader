"""Copy only the seven pinned existing artifacts into a new phone Downloads folder."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
ADB = [str(Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk/platform-tools/adb.exe'), '-d']
manifest = json.loads((ROOT / 'assets/models/manifest.json').read_text(encoding='utf-8'))
source = ROOT / 'validation/private/aligned-bundle-01'
entries = manifest['files']
assert len(entries) == 7
for entry in entries:
    name = entry['relativePath']
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]+', name) or '..' in name:
        raise ValueError('Unsafe pinned filename')
    data = (source / name).read_bytes()
    if len(data) != entry['byteSize'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
        raise ValueError('Source integrity mismatch')
folder = '/sdcard/Download/uReader-voice-fr-phase5-' + str(int(time.time()))
if subprocess.run(ADB + ['shell', 'test', '-e', folder], capture_output=True, timeout=15).returncode == 0:
    raise FileExistsError('Phone folder already exists; refusing overwrite')
subprocess.run(ADB + ['shell', 'mkdir', folder], check=True, timeout=15)
with (ROOT / 'validation/raw/phase5-folder-transfer-01.log').open('x', encoding='utf-8') as log:
    for entry in entries:
        subprocess.run(ADB + ['shell', 'input', 'keyevent', '224'], capture_output=True, timeout=15)
        subprocess.run(ADB + ['push', str(source / entry['relativePath']), folder + '/' + entry['relativePath']], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=240)
        print('Copied:', entry['relativePath'], flush=True)
record = {'phoneSourceFolder': folder, 'files': entries, 'bytes': sum(e['byteSize'] for e in entries), 'networkDownload': False, 'sourceOnComputerPreserved': True, 'laboratoryPrivateBundlePreserved': True}
with (ROOT / 'validation/reports/us2/source-folder-01.json').open('x', encoding='utf-8') as handle:
    json.dump(record, handle, indent=2); handle.write('\n')
print('Folder ready:', folder)
