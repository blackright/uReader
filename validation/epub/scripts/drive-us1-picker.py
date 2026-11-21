"""Drive only synthetic US1 SAF choices over ADB; no personal file selection.

Run alongside flutter drive. A request must name a SHA-pinned case from config.
Raw UI snapshots stay private. Original test files are renamed, then restored.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
LAB = ROOT / 'validation/epub'
ADB = str(Path(os.environ['LOCALAPPDATA']) / 'Android/sdk/platform-tools/adb.exe')
PACKAGE = 'com.ureader.prototype'
PHONE = '/sdcard/Download/uReader-us1-validation-20261117'
APP_ROOT = 'files/ureader-prototype'
ORDERED=[]


def adb(*args, check=True, data=None):
    return subprocess.run([ADB, '-d', *args], check=check, input=data,
                          capture_output=True, timeout=45)


def app_read(name):
    r = adb('exec-out', 'run-as', PACKAGE, 'cat', APP_ROOT + '/' + name, check=False)
    try:
        return json.loads(r.stdout) if r.returncode == 0 else None
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None


def app_write(name, value):
    adb('shell', 'run-as', PACKAGE, 'sh', '-c',
        '"cat > ' + APP_ROOT + '/' + name + '"', data=json.dumps(value).encode())


def nodes():
    r = adb('shell', 'uiautomator', 'dump', '/data/local/tmp/ureader-us1-picker.xml', check=False)
    if r.returncode:
        return []
    r = adb('exec-out', 'cat', '/data/local/tmp/ureader-us1-picker.xml')
    try:
        return list(ET.fromstring(r.stdout).iter('node'))
    except ET.ParseError:
        return []


def tap(node):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.attrib['bounds']))
    adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))


def select(filename):
    # Avoid the Samsung/API29 DocumentsUI search-fragment lifecycle crash.
    # Browse only the owned folder, in list mode, using exact pinned filenames.
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        current = nodes()
        if not any('documentsui' in n.get('package', '') for n in current):
            time.sleep(.3); continue
        own = any(n.get('text') == PHONE.rsplit('/',1)[1] for n in current)
        if not own:
            folder = next((n for n in current if n.get('text') == PHONE.rsplit('/',1)[1]),None)
            if folder is not None:
                tap(folder); continue
            downloads = next((n for n in current if n.get('text') == 'Downloads' and n.get('resource-id') == 'android:id/title'),None)
            if downloads is not None:
                tap(downloads); continue
            roots = next((n for n in current if n.get('content-desc') in ['Show roots','Afficher les racines']),None)
            if roots is not None:
                tap(roots); continue
            time.sleep(.3); continue
        # A matching folder row at Downloads must be entered before any file tap.
        title = next((n for n in current if n.get('text') == PHONE.rsplit('/',1)[1]),None)
        if title is not None and title.get('resource-id') == 'android:id/title' and int(re.findall(r'\d+',title.get('bounds','[0,0][0,0]'))[1]) >= 500:
            tap(title); continue
        list_mode = next((n for n in current if n.get('content-desc') in ['List view','Vue liste']),None)
        if list_mode is not None:
            tap(list_mode); continue
        files = [n for n in current if n.get('resource-id') == 'android:id/title'
                 and n.get('text','').endswith('.epub') and n.get('bounds') != '[0,0][0,0]'
                 and 520 <= int(re.findall(r'\d+',n.get('bounds'))[1]) <= 2680]
        match = next((n for n in files if n.get('text') == filename),None)
        if match is not None:
            tap(match)
            for _ in range(25):
                active = adb('shell','dumpsys','activity','activities').stdout.decode(errors='replace')
                resumed = next((line for line in active.splitlines() if 'mResumedActivity' in line),'')
                latest = app_read('us1-validation-request.json')
                if ('com.ureader.prototype/.MainActivity' in resumed or
                    (latest and latest.get('filename') != filename)):
                    return
                time.sleep(.1)
            continue
        if files:
            upward = filename.lower() >= min(n.get('text','').lower() for n in files)
            ordered=ORDERED
            first=min(n.get('text','') for n in files)
            gap=abs(ordered.index(filename)-ordered.index(first))
            if ordered.index(filename)>=len(ordered)-18 and gap>15:
                for _ in range(8):
                    adb('shell','input','swipe','700','2500','700','650','100')
                continue
            steps=min(8,max(1,(gap-6)//3))
            for _ in range(steps):
                adb('shell','input','swipe','700','1900' if upward else '1000','700','1000' if upward else '1900','800')
        else:
            if title is not None and not any(n.get('content-desc')=='Show roots' for n in current):
                adb('shell','input','keyevent','4')
            time.sleep(.3)
    raise RuntimeError('Synthetic SAF selection timeout: ' + filename)


def main():
    global PHONE,ORDERED
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--resume', action='store_true')
    parser.add_argument('--recovery', action='store_true')
    parser.add_argument('--minutes', type=int, default=25)
    args = parser.parse_args()
    directory = LAB / 'private/us1-device'
    config = json.loads((directory / ('recovery-config.json' if args.recovery else 'config.json')).read_text(encoding='utf-8'))
    if args.recovery: PHONE+='-recovery'
    ORDERED=sorted(c['filename'] for c in config['cases'])
    allowed = {c['filename']: c['sha256'] for c in config['cases']}
    if args.prepare:
        adb('shell', 'mkdir', '-p', PHONE)
        for filename, digest in allowed.items():
            local = directory / filename
            if hashlib.sha256(local.read_bytes()).hexdigest() != digest:
                raise ValueError('Fixture SHA mismatch')
            adb('push', str(local), PHONE + '/' + filename)
        # Fixed, private synthetic config. No URI passed directly to the product.
        app_write('us1-validation-config.json', config)
        app_write('us1-validation-request.json', {})
        app_write('us1-validation-result.json', {'status': 'prepared'})
        app_write('us1-validation-ack.json', {})
        print(json.dumps({'prepared': len(allowed), 'phoneDirectory': PHONE}), flush=True)
        return
    events_path=LAB/'reports/us1-picker-events.json'
    events=json.loads(events_path.read_text(encoding='utf-8')) if args.resume and events_path.exists() else []
    seen={e['sequence'] for e in events}
    samples = []
    deadline = time.monotonic() + args.minutes * 60
    hidden = False
    try:
        while time.monotonic() < deadline:
            request = app_read('us1-validation-request.json')
            if request and request['sequence'] not in seen:
                seq, action = request['sequence'], request['action']
                pid = adb('shell','pidof',PACKAGE,check=False).stdout.decode().strip()
                if pid.isdigit():
                    status = adb('exec-out','run-as',PACKAGE,'cat','/proc/'+pid+'/status',check=False).stdout.decode(errors='replace')
                    memory = {k:int(v)*1024 for k,v in re.findall(r'(VmRSS|VmHWM):\s+(\d+) kB',status)}
                    disk = adb('exec-out','run-as',PACKAGE,'du','-k',APP_ROOT+'/books',check=False).stdout.decode(errors='replace')
                    allocated = sum(int(line.split()[0])*1024 for line in disk.splitlines() if re.search(r'/us1val-[^/]+$',line))
                    samples.append(dict(sequence=seq,allocatedTestBooksBytes=allocated,**memory))
                if action == 'select':
                    filename = request['filename']
                    if filename not in allowed:
                        raise ValueError('Unpinned document request')
                    select(filename)
                    events.append({'sequence': seq, 'action': action, 'filename': filename})
                elif action == 'hide-originals':
                    adb('shell', 'mv', PHONE, PHONE + '-temporarily-hidden')
                    hidden = True
                    app_write('us1-validation-ack.json', {'sequence': seq})
                    events.append({'sequence': seq, 'action': action})
                elif action == 'restore-originals':
                    if hidden:
                        adb('shell', 'mv', PHONE + '-temporarily-hidden', PHONE)
                        hidden = False
                    events.append({'sequence': seq, 'action': action})
                    break
                else:
                    raise ValueError('Unknown action')
                seen.add(seq)
                print(json.dumps(events[-1]), flush=True)
            result = app_read('us1-validation-result.json')
            if result and result.get('status') in ['passed', 'failed']:
                break
            time.sleep(.4)
        else:
            raise RuntimeError('US1 driver deadline')
    finally:
        if hidden:
            adb('shell', 'mv', PHONE + '-temporarily-hidden', PHONE)
        (LAB / 'reports/us1-picker-events.json').write_text(json.dumps(events, indent=2)+'\n', encoding='utf-8')
        (LAB / 'reports/us1-host-measurements.json').write_text(json.dumps(samples, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
