"""Read-only source/device audit; no book, URI or raw log payload is exported."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'validation/epub/reports'
SCOPES = ('lib/features/library', 'lib/features/book_reader',
          'lib/infrastructure/epub', 'lib/infrastructure/diagnostics',
          'android/app/src/main/kotlin/com/ureader/prototype/epub')
pattern = re.compile(r'\b(?:debugPrint|print|HttpClient|Socket|WebView)\s*\(|\bLog\.[vdiew]\s*\(')
files, findings = [], []
for scope in SCOPES:
    for path in sorted((ROOT / scope).rglob('*')):
        if path.suffix not in ('.dart', '.kt'):
            continue
        relative = path.relative_to(ROOT).as_posix()
        data = path.read_bytes()
        files.append({'path': relative, 'sha256': hashlib.sha256(data).hexdigest()})
        for number, line in enumerate(data.decode('utf-8').splitlines(), 1):
            for match in pattern.finditer(line):
                findings.append({'path': relative, 'line': number, 'token': match.group()})
permissions = {}
for variant, name in (
    ('main_source', 'android/app/src/main/AndroidManifest.xml'),
    ('debug_source', 'android/app/src/debug/AndroidManifest.xml'),
    ('debug_merged', 'build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml'),
    ('profile_merged_historical', 'build/app/intermediates/merged_manifests/profile/processProfileManifest/AndroidManifest.xml')):
    path = ROOT / name
    if path.exists():
        tree = ET.parse(path)
        permissions[variant] = sorted({element.attrib.get('{http://schemas.android.com/apk/res/android}name')
                                       for element in tree.findall('uses-permission')})
report = {'date': '2026-11-18', 'scope': 'static token scan plus manual review; not packet capture',
          'files': files, 'findings': findings, 'permissions': permissions,
          'trafficCapture': 'not_evaluated', 'privateContentLogCanary': 'not_evaluated',
          'releaseApkManifest': 'not_evaluated'}
(OUT / 'phase7-static-audit.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

adb = str(Path(os.environ['LOCALAPPDATA']) / 'Android/sdk/platform-tools/adb.exe')
def read_device(*args):
    value = subprocess.run([adb, '-d', 'shell', *args], capture_output=True, text=True, timeout=20)
    return value.stdout.strip() if value.returncode == 0 else None

device = {'date': '2026-11-18', 'readOnly': True,
          'model': read_device('getprop', 'ro.product.model'),
          'api': read_device('getprop', 'ro.build.version.sdk'),
          'abi': read_device('getprop', 'ro.product.cpu.abi'),
          'pageSizeBytes': read_device('getconf', 'PAGE_SIZE'),
          'airplaneMode': read_device('settings', 'get', 'global', 'airplane_mode_on'),
          'stayAwake': read_device('settings', 'get', 'global', 'stay_on_while_plugged_in'),
          'diskDataSnapshot': read_device('df', '-k', '/data'),
          'note': 'Filesystem free space is not app allocation or peak disk usage; no app action or setting changed.'}
(OUT / 'phase7-device-observation.json').write_text(json.dumps(device, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'scannedFiles': len(files), 'findings': len(findings), 'device': device['model']}))
