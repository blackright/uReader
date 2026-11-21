"""Run the dedicated profile bench APK, preserving normal models/positions.

Install phase8_measurement_test.dart as a profile APK with adb install -r first.
The test-only private counter selects five cold processes, one five-warm process,
then a 20-minute session. Never clear data or use this against the normal APK.
"""
import argparse
import json
import queue
import re
import subprocess
import threading
import time
from pathlib import Path


def main(adb, destination, start_run=1):
    destination.mkdir(parents=True, exist_ok=True)
    for index in range(start_run, 8):
        if (destination / f'bench-run-{index:02}.json').exists():
            raise FileExistsError('Use a new report directory; existing measurements must be preserved')
    def shell(*args):
        return subprocess.check_output([adb, '-d', 'shell', *args], timeout=20,
                                       stderr=subprocess.DEVNULL).decode(errors='replace')

    def snapshot():
        result = {'hostMonotonic': time.monotonic()}
        for command, fields in [
            (('dumpsys', 'battery'), {'level': r'^\s*level: (\d+)',
                                     'temperatureTenthsC': r'^\s*temperature: (\d+)',
                                     'usbPowered': r'^\s*USB powered: (\w+)'}),
            (('dumpsys', 'meminfo', 'com.ureader.prototype'),
             {'pssKiB': r'^\s*TOTAL\s+(\d+)', 'totalPssKiB': r'TOTAL PSS:\s*(\d+)'})]:
            try:
                text = shell(*command)
                for field, pattern in fields.items():
                    match = re.search(pattern, text, re.M)
                    if match:
                        result[field] = int(match[1]) if match[1].isdigit() else match[1]
            except (subprocess.SubprocessError, OSError):
                pass
        return result

    conditions = {'model': shell('getprop', 'ro.product.model').strip(),
                  'androidApi': shell('getprop', 'ro.build.version.sdk').strip(),
                  'abi': shell('getprop', 'ro.product.cpu.abi').strip(),
                  'pageBytes': shell('getconf', 'PAGE_SIZE').strip(),
                  'airplaneMode': shell('settings', 'get', 'global', 'airplane_mode_on').strip(),
                  'wifiSettingRaw': shell('settings', 'get', 'global', 'wifi_on').strip(),
                  'buildMode': 'profile', 'audioCache': 'isolated_benchmark_store',
                  'systemCachePurged': False, 'firstAudibleSoundMeasured': False}
    (destination / 'device-conditions.json').write_text(json.dumps(conditions, indent=2) + '\n')
    for index in range(start_run - 1, 7):
        expected = 'cold' if index < 5 else 'warm' if index == 5 else 'duration'
        shell('am', 'force-stop', 'com.ureader.prototype')
        events = queue.Queue()
        log = subprocess.Popen([adb, '-d', 'logcat', '-T', '1', '-s', 'flutter:I', '*:S'],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               text=True, encoding='utf-8', errors='replace')
        def consume():
            for line in log.stdout:
                if 'UREADER_PHASE8:' in line:
                    try:
                        events.put(json.loads(line.split('UREADER_PHASE8:', 1)[1]))
                    except json.JSONDecodeError:
                        events.put({'kind': 'unreadable_measurement'})
        threading.Thread(target=consume, daemon=True).start()
        report = {'mode': expected, 'run': index + 1, 'events': [], 'systemSamples': []}
        start = time.monotonic()
        next_sample = start
        duration_started = None
        report_path = destination / f'bench-run-{index + 1:02}.json'
        try:
            shell('am', 'start', '-n', 'com.ureader.prototype/.MainActivity')
            while time.monotonic() - start < (1500 if expected == 'duration' else 240):
                now = time.monotonic()
                if now >= next_sample:
                    sample = snapshot()
                    sample['runElapsedSeconds'] = round(now - start, 3)
                    report['systemSamples'].append(sample)
                    next_sample = now + (30 if expected == 'duration' else 5)
                    print(json.dumps({'mode': expected, 'elapsedSeconds': round(now - start),
                                      'memoryPssKiB': sample.get('pssKiB', sample.get('totalPssKiB'))}), flush=True)
                try:
                    event = events.get(timeout=1)
                except queue.Empty:
                    continue
                report['events'].append(event)
                if event.get('kind') == 'begin':
                    if event.get('mode') != expected or event.get('run') != index + 1:
                        raise RuntimeError('Unexpected benchmark sequence; do not reset data to force it')
                if event.get('kind') == 'duration_started':
                    duration_started = time.monotonic()
                if event.get('kind') == 'done':
                    if event.get('status') != 'passed':
                        raise RuntimeError('Benchmark reported failure')
                    report['status'] = 'passed'
                    break
                report_path.write_text(json.dumps(report, indent=2) + '\n')
            else:
                raise TimeoutError('No completed measurement received')
            report['hostElapsedSeconds'] = time.monotonic() - start
            report['durationSinceFirstStartedSeconds'] = None if duration_started is None else time.monotonic() - duration_started
            report_path.write_text(json.dumps(report, indent=2) + '\n')
            print(json.dumps({'run': index + 1, 'mode': expected, 'status': 'passed'}), flush=True)
        except Exception as error:
            report['status'] = 'incomplete'
            report['failureType'] = type(error).__name__
            report_path.write_text(json.dumps(report, indent=2) + '\n')
            raise
        finally:
            log.terminate()
            try:
                log.wait(timeout=5)
            except subprocess.TimeoutExpired:
                log.kill()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--start-run', type=int, choices=range(1, 8), default=1)
    args = parser.parse_args()
    main(args.adb, args.directory, args.start_run)
