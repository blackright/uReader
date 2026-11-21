"""Install the locally verified debug preview via ModelInstaller, preserving rollback."""
import hashlib
import json
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PACKAGE = 'com.ureader.prototype'


def main():
    private = ROOT / 'validation/reader/private/voice-preview-20261120-01'
    catalog = json.loads((ROOT / 'assets/models/manifest.json').read_text(encoding='utf-8'))
    for entry in catalog['files']:
        name = entry['relativePath']
        if not re.fullmatch(r'[a-zA-Z0-9_.-]+', name):
            raise ValueError('Unexpected bundle filename')
        file = private / 'bundle' / name
        with file.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        if file.stat().st_size != entry['byteSize'] or digest != entry['sha256']:
            raise ValueError('Source integrity failure')
    adb = str(Path(os.environ['LOCALAPPDATA']) / 'Android/sdk/platform-tools/adb.exe')
    devices = subprocess.check_output([adb, 'devices'], text=True).splitlines()
    ids = [line.split()[0] for line in devices if line.endswith('\tdevice')]
    if len(ids) != 1:
        raise ValueError('Exactly one authorized device required')

    def command(*args, timeout=180):
        return subprocess.check_output([adb, '-s', ids[0], *args], stderr=subprocess.STDOUT, timeout=timeout)

    product = private / 'product.apk'
    original = ROOT / 'validation/reader/private/continuous-runtime-20261120-01/original.apk'
    installer = private / 'installer.apk'
    for apk in (product, original, installer):
        if not apk.is_file():
            raise ValueError('Prepare all APKs before changing the device')
    report = {'status': 'failed', 'g1Verdict': 'not_evaluated', 'normalAppRestored': False}
    published = False
    stage = '/data/local/tmp/ureader-preview-' + str(time.time_ns())
    source = 'files/alignment-preview-source'
    try:
        listing = subprocess.run([adb, '-s', ids[0], 'shell', 'run-as', PACKAGE,
                                  'ls', '-ld', source], capture_output=True)
        existing = listing.returncode == 0 and listing.stdout.startswith(b'd')
        if not existing:
            command('shell', 'run-as', PACKAGE, 'mkdir', source)
            command('push', str(private / 'bundle'), stage)
        for entry in catalog['files']:
            name = entry['relativePath']
            if existing:
                # Resume only an exact previous staging copy; never overwrite it.
                digest = command('shell', 'run-as', PACKAGE, 'sha256sum', source + '/' + name).decode().split()[0]
                if digest != entry['sha256']:
                    raise ValueError('Existing staging file differs')
            else:
                command('shell', 'run-as', PACKAGE, 'cp', stage + '/' + name, source + '/' + name)
        if subprocess.run([adb, '-s', ids[0], 'shell', 'run-as', PACKAGE, 'ls',
                           'files/alignment-preview-install.json'], capture_output=True).returncode == 0:
            raise ValueError('Stale installation receipt: inspect before retrying')
        command('shell', 'am', 'force-stop', PACKAGE)
        command('install', '-r', str(installer))
        command('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity')
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            result = subprocess.run([adb, '-s', ids[0], 'exec-out', 'run-as', PACKAGE, 'cat',
                                     'files/alignment-preview-install.json'], capture_output=True)
            if result.returncode == 0:
                # Some ADB exec-out versions return zero for remote cat errors;
                # a newly created file may also be observed before its flush.
                try:
                    receipt = json.loads(result.stdout)
                except (ValueError, UnicodeDecodeError):
                    time.sleep(2)
                    continue
                if receipt.get('status') != 'installed' or receipt.get('version') != catalog['bundleVersion']:
                    raise ValueError('Unexpected installation receipt')
                report['receipt'] = receipt
                published = True
                break
            time.sleep(2)
        if not published:
            raise TimeoutError('No successful product-installer receipt')
        report['status'] = 'installed'
    except Exception as error:
        report['failure'] = type(error).__name__
        raise
    finally:
        try:
            restore = product if published else original
            command('shell', 'am', 'force-stop', PACKAGE)
            command('install', '-r', str(restore))
            path = command('shell', 'pm', 'path', PACKAGE).decode().strip()
            if not path.startswith('package:/data/app/') or '\n' in path:
                raise ValueError('Unexpected installed APK path')
            actual = command('shell', 'sha256sum', path.removeprefix('package:')).decode().split()[0]
            with restore.open('rb') as stream:
                expected = hashlib.file_digest(stream, 'sha256').hexdigest()
            if actual != expected:
                raise ValueError('Restored APK hash mismatch')
            command('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity')
            report['normalAppRestored'] = True
        except Exception as error:
            report['restorationFailure'] = type(error).__name__
            raise
        finally:
            (ROOT / 'validation/reader/reports/development-preview-install-20261120.json').write_text(
                json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
