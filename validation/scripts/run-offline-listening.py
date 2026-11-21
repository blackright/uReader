"""Install with -r, attach Flutter driver to the running test APK; never uninstall app data."""
import os
import argparse
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.parse import urlsplit, urlunsplit

ROOT = Path(__file__).resolve().parents[2]
ADB = [str(Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk/platform-tools/adb.exe'), '-d']
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('run_id', nargs='?', default='01')
parser.add_argument('--target', choices=['integration_test/offline_listening_test.dart', 'integration_test/corpus_listening_test.dart', 'integration_test/feasibility_phase4_test.dart', 'integration_test/model_setup_test.dart'], default='integration_test/offline_listening_test.dart')
parser.add_argument('--timeout-seconds', type=int, default=300)
args = parser.parse_args()
run_id = args.run_id
if not 30 <= args.timeout_seconds <= 1800:
    raise ValueError('Timeout outside validation bounds')
if not re.fullmatch(r'\d{2}', run_id):
    raise ValueError('Expected a two-digit run ID')
log_path = ROOT / f'validation/raw/offline-listening-driver-{run_id}.log'
serial = subprocess.check_output(ADB + ['get-serialno'], timeout=15).decode().strip()
host_port = None
try:
    with log_path.open('xb') as log:
        installing = subprocess.Popen(ADB + ['install', '-r', '-t', str(ROOT / 'build/app/outputs/apk/debug/app-debug.apk')], stdout=log, stderr=subprocess.STDOUT)
        install_deadline = time.monotonic() + 180
        while installing.poll() is None:
            if time.monotonic() > install_deadline:
                installing.kill(); installing.wait(); raise TimeoutError('APK installation timed out')
            subprocess.run(ADB + ['shell', 'input', 'keyevent', '224'], capture_output=True, timeout=15)
            time.sleep(4)
        if installing.returncode != 0:
            raise RuntimeError('APK installation failed')
        subprocess.run(ADB + ['shell', 'input', 'keyevent', '224'], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=15)
        subprocess.run(ADB + ['shell', 'wm', 'dismiss-keyguard'], stdout=log, stderr=subprocess.STDOUT, timeout=15)
        subprocess.run(ADB + ['shell', 'am', 'force-stop', 'com.ureader.prototype'], check=True, timeout=20)
        subprocess.run(ADB + ['shell', 'am', 'start', '-n', 'com.ureader.prototype/.MainActivity'],
            stdout=log, stderr=subprocess.STDOUT, check=True, timeout=30)
        uri = None
        for _ in range(30):
            lookup = subprocess.run(ADB + ['shell', 'pidof', '-s', 'com.ureader.prototype'], capture_output=True, timeout=15)
            pid = lookup.stdout.decode().strip() if lookup.returncode == 0 else ''
            if pid:
                output = subprocess.check_output(ADB + ['logcat', '-d', '--pid', pid, '-s', 'flutter'], timeout=15).decode(errors='replace')
                matches = re.findall(r'Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+)', output)
                if matches:
                    uri = matches[-1]; break
            time.sleep(1)
        if uri is None:
            raise RuntimeError('Test VM service unavailable; inspect device state')
        parsed = urlsplit(uri)
        host_port = subprocess.check_output(ADB + ['forward', 'tcp:0', f'tcp:{parsed.port}'], timeout=15).decode().strip()
        forwarded = urlunsplit((parsed.scheme, '127.0.0.1:' + host_port, parsed.path, '', ''))
        command = ['C:/dev/flutter/bin/cache/dart-sdk/bin/dart.exe',
            'C:/dev/flutter/bin/cache/flutter_tools.snapshot', '--suppress-analytics', 'drive',
            '--no-pub', '--driver=test_driver/integration_test.dart',
            '--target=' + args.target, '--use-existing-app=' + forwarded,
            '-d', serial]
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + args.timeout_seconds
        while process.poll() is None:
            if time.monotonic() > deadline:
                process.kill(); process.wait(); raise TimeoutError('Integration driver timed out')
            subprocess.run(ADB + ['shell', 'input', 'keyevent', '224'], capture_output=True, timeout=15)
            time.sleep(4)
    print('Flutter driver exit code:', process.returncode)
    if process.returncode != 0:
        raise SystemExit(process.returncode)
finally:
    if host_port:
        subprocess.run(ADB + ['forward', '--remove', 'tcp:' + host_port], capture_output=True, timeout=15)
    if log_path.exists():
        text = log_path.read_text(encoding='utf-8', errors='replace').replace(serial, '<device>')
        text = re.sub(r'(?:http|ws)://127\.0\.0\.1:\d+/[^\s]+', '<local-debug-service>', text)
        log_path.write_text(text, encoding='utf-8')
