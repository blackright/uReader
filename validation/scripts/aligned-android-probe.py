"""Explicit USB provisioning or collection for the isolated aligned Android probe."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[2]
ADB = [str(Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk/platform-tools/adb.exe'), '-d']
REMOTE = 'files/ureader-aligned-generation/'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def provision():
    bundle = ROOT / 'validation/private/aligned-bundle-01'
    audit = json.loads((bundle / 'audit-lock.json').read_text(encoding='utf-8'))
    files = audit['files']
    if len(files) != 7 or audit['expectedVoiceOffset'] != 168:
        raise ValueError('Invalid aligned audit')
    for e in files:
        if Path(e['name']).name != e['name'] or e['name'] != e['relativePath']:
            raise ValueError('Unsafe file entry')
        p = bundle / e['name']
        if p.stat().st_size != e['byteSize'] or sha(p) != e['sha256']:
            raise ValueError('Aligned bundle integrity failed')
    subprocess.run(ADB + ['shell', 'run-as', 'com.ureader.prototype', 'mkdir', '-p', REMOTE], check=True, timeout=20)
    for name in [e['name'] for e in files] + ['audit-lock.json', 'aligned-cases.json']:
        path = bundle / name
        with path.open('rb') as stream:
            subprocess.run(ADB + ['exec-in', "run-as com.ureader.prototype sh -c 'cat > " + REMOTE + name + "'"],
                stdin=stream, check=True, timeout=120)
        actual = subprocess.check_output(ADB + ['shell', 'run-as', 'com.ureader.prototype',
            'sha256sum', REMOTE + name], timeout=30).decode().split()[0]
        if actual != sha(path):
            raise ValueError('USB transfer SHA-256 mismatch')
    print('Nine private files provisioned with SHA-256; application resolver unchanged.')


def collect(prefix, protocol=False):
    if not re.fullmatch(r'[a-z0-9-]+', prefix):
        raise ValueError('Unsafe output prefix')
    names = subprocess.check_output(ADB + ['shell', 'run-as', 'com.ureader.prototype', 'ls', REMOTE], timeout=30).decode().split()
    outputs = {}
    for role in (['cases'] if protocol else ['cases', 'cancellation']):
        pattern = rf'{"protocol" if protocol else "aligned"}-{role}-report-\d+\.json'
        reports = sorted(n for n in names if re.fullmatch(pattern, n))
        if not reports:
            raise ValueError('Missing Android report: ' + role)
        report = json.loads(subprocess.check_output(ADB + ['exec-out', 'run-as', 'com.ureader.prototype',
            'cat', REMOTE + reports[-1]], timeout=30))
        report['remoteReportName'] = reports[-1]
        if role == 'cases':
            for case in report['cases']:
                allowed_ids = {'fr-01-p1', 'fr-04-p1'} if protocol else {'numbers', 'agreements', 'leap-year'}
                if case['caseId'] not in allowed_ids:
                    raise ValueError('Unsafe case ID')
                name = case['wav']
                pattern = r'protocol-fr-(01|04)-p1-\d+\.wav' if protocol else r'aligned-(numbers|agreements|leap-year)-\d+\.wav'
                if not re.fullmatch(pattern, name):
                    raise ValueError('Unsafe audio name')
                target = ROOT / f"validation/reference-audio/{prefix}-{case['caseId']}.wav"
                data = subprocess.check_output(ADB + ['exec-out', 'run-as', 'com.ureader.prototype',
                    'cat', REMOTE + name], timeout=60)
                with target.open('xb') as handle:
                    handle.write(data)
                case['collectedWav'] = target.relative_to(ROOT).as_posix()
                case['wavSha256'] = sha(target)
        path = ROOT / f'validation/reports/g0/{prefix}-{role}.json'
        with path.open('x', encoding='utf-8') as handle:
            json.dump(report, handle, ensure_ascii=False, indent=2); handle.write('\n')
        outputs[role] = path.relative_to(ROOT).as_posix()
    print(json.dumps(outputs))


def collect_memory(prefix):
    if not re.fullmatch(r'[a-z0-9-]+', prefix):
        raise ValueError('Unsafe output prefix')
    names = subprocess.check_output(ADB + ['shell', 'run-as', 'com.ureader.prototype', 'ls', REMOTE], timeout=30).decode().split()
    reports = sorted(n for n in names if re.fullmatch(r'aligned-memory-report-\d+\.json', n))
    if not reports:
        raise ValueError('Missing memory report')
    report = json.loads(subprocess.check_output(ADB + ['exec-out', 'run-as', 'com.ureader.prototype',
        'cat', REMOTE + reports[-1]], timeout=30))
    report['remoteReportName'] = reports[-1]
    report['bundleAuditSha256'] = sha(ROOT / 'validation/private/aligned-bundle-01/audit-lock.json')
    report['fixtureSha256'] = sha(ROOT / 'validation/private/aligned-bundle-01/aligned-cases.json')
    target = ROOT / f'validation/reports/g0/{prefix}-memory.json'
    with target.open('x', encoding='utf-8') as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2); handle.write('\n')
    print(json.dumps({'report': target.relative_to(ROOT).as_posix(), 'status': report['status']}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['provision', 'collect', 'collect-memory', 'collect-protocol'])
    parser.add_argument('--output-prefix', default='aligned-android-01')
    args = parser.parse_args()
    if args.action == 'provision':
        provision()
    elif args.action == 'collect-memory':
        collect_memory(args.output_prefix)
    elif args.action == 'collect-protocol':
        collect(args.output_prefix, protocol=True)
    else:
        collect(args.output_prefix)
