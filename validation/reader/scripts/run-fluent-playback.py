"""Run the isolated audible Flutter test; restore APK, USB setting and forwarding."""
import argparse
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--normal-apk', required=True, type=Path)
    parser.add_argument('--test-apk', required=True, type=Path)
    parser.add_argument('--timeout-seconds', type=int, default=480)
    args = parser.parse_args()
    if not 120 <= args.timeout_seconds <= 1800:
        raise ValueError('Invalid driver timeout')
    if not re.fullmatch(r'[a-z0-9-]{1,64}', args.run_id):
        raise ValueError('Invalid run ID')
    run = ROOT / 'validation/reader/private' / args.run_id
    run.mkdir(exist_ok=False)
    adb = str(Path(os.environ['LOCALAPPDATA']) / 'Android/sdk/platform-tools/adb.exe')
    devices = subprocess.check_output([adb, 'devices'], text=True).splitlines()
    ids = [line.split()[0] for line in devices if line.endswith('\tdevice')]
    if len(ids) != 1:
        raise ValueError('Exactly one authorized device required')

    def command(*words, timeout=180):
        return subprocess.check_output([adb, '-s', ids[0], *words], stderr=subprocess.STDOUT, timeout=timeout)

    path = command('shell', 'pm', 'path', PACKAGE).decode().strip()
    if not path.startswith('package:/data/app/') or '\n' in path:
        raise ValueError('Unexpected installed APK path')
    original = run / 'original.apk'
    command('pull', path.removeprefix('package:'), str(original))
    normal = args.normal_apk.resolve()
    test = args.test_apk.resolve()
    if not normal.is_file() or not test.is_file():
        raise ValueError('Prepare APKs first')
    stay = command('shell', 'settings', 'get', 'global', 'stay_on_while_plugged_in').decode().strip()
    if stay != 'null' and not re.fullmatch(r'\d+', stay):
        raise ValueError('Unexpected USB setting')
    port = None
    passed = False
    report = {'status': 'failed', 'audioPlaybackRequested': True, 'g1': 'not_evaluated', 'restored': False}
    try:
        command('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', '3')
        command('shell', 'am', 'force-stop', PACKAGE)
        command('install', '-r', str(test))
        command('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity')
        deadline = time.monotonic() + 60
        match = None
        while time.monotonic() < deadline:
            try:
                pid = command('shell', 'pidof', PACKAGE).decode().strip()
            except subprocess.CalledProcessError:
                time.sleep(.5)
                continue
            if re.fullmatch(r'\d+', pid):
                log = command('logcat', '-d', '--pid=' + pid, '-s', 'flutter').decode(errors='replace')
                match = re.search(r'http://127\.0\.0\.1:(\d+)/([^\s]+)', log)
                if match:
                    break
            time.sleep(.5)
        if not match:
            raise ValueError('VM service not available')
        port = command('forward', 'tcp:0', 'tcp:' + match[1]).decode().strip()
        if not re.fullmatch(r'\d+', port):
            raise ValueError('Invalid forwarded port')
        uri = 'http://127.0.0.1:' + port + '/' + match[2]
        driver_env = os.environ.copy()
        driver_env['FLUTTER_TEST_OUTPUTS_DIR'] = str(run.resolve())
        with (run / 'driver.log').open('wb') as output:
            result = subprocess.run(['C:/dev/flutter/bin/cache/dart-sdk/bin/dart.exe',
                'C:/dev/flutter/bin/cache/flutter_tools.snapshot', 'drive', '--no-pub', '-d', ids[0],
                '--driver=test_driver/integration_test.dart', '--use-existing-app=' + uri,
                '--keep-app-running'], cwd=ROOT, env=driver_env, stdout=output, stderr=subprocess.STDOUT, timeout=args.timeout_seconds)
        passed = result.returncode == 0 and 'All tests passed.' in (run / 'driver.log').read_text(errors='replace')
        metrics_file = run / 'integration_response_data.json'
        if metrics_file.is_file():
            report['metrics'] = json.loads(metrics_file.read_text(encoding='utf-8'))
        if not passed:
            raise ValueError('Audible integration test did not pass')
        metrics = report.get('metrics', {})
        if metrics.get('status') != 'passed' or metrics.get('playlistOpens') != 1:
            raise ValueError('Missing or unexpected integration metrics')
        report['metrics'] = metrics
        report['status'] = 'passed'
    except Exception as error:
        report['failure'] = type(error).__name__
    finally:
        try:
            if port:
                command('forward', '--remove', 'tcp:' + port)
            command('shell', 'am', 'force-stop', PACKAGE)
            restore = normal if passed else original
            command('install', '-r', str(restore))
            installed = command('shell', 'pm', 'path', PACKAGE).decode().strip().removeprefix('package:')
            if not installed.startswith('/data/app/') or '\n' in installed:
                raise ValueError('Unexpected restored APK path')
            actual = command('shell', 'sha256sum', installed).decode().split()[0]
            with restore.open('rb') as stream:
                report['restored'] = actual == hashlib.file_digest(stream, 'sha256').hexdigest()
        finally:
            if stay == 'null':
                command('shell', 'settings', 'delete', 'global', 'stay_on_while_plugged_in')
            else:
                command('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', stay)
            if report['restored']:
                command('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity')
            (ROOT / 'validation/reader/reports' / (args.run_id + '.json')).write_text(
                json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))
    if not passed or not report['restored']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
