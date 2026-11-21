"""Read-only product snapshot via ADB; public output contains counts, no texts."""
from pathlib import Path
import json
import os
import sqlite3
import subprocess
import argparse

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--campaign', choices=('us2', 'us3', 'us4'), default='us2')
parser.add_argument('--before', action='store_true')
args = parser.parse_args()
campaign = args.campaign
adb = str(Path(os.environ['LOCALAPPDATA']) / 'Android/sdk/platform-tools/adb.exe')
dest = root / ('validation/epub/private/' + campaign + ('-before-db' if args.before else '-final-db'))
dest.mkdir(exist_ok=True)
for suffix in ('', '-wal', '-shm'):
    result = subprocess.run([adb, '-d', 'exec-out', 'run-as', 'com.ureader.prototype',
        'cat', 'files/ureader-prototype/prototype.sqlite' + suffix], capture_output=True)
    if result.returncode == 0:
        (dest / ('prototype.sqlite' + suffix)).write_bytes(result.stdout)
    elif not suffix:
        raise RuntimeError('Product snapshot unavailable')
    else:
        (dest / ('prototype.sqlite' + suffix)).unlink(missing_ok=True)
if args.before:
    print('Private baseline captured for ' + campaign)
    raise SystemExit(0)
baseline = root / ('validation/epub/private/us4-before-db/prototype.sqlite' if campaign == 'us4' else 'validation/epub/private/us1-final-db/prototype.sqlite')
if not baseline.exists():
    raise RuntimeError('Capture the current product baseline before device tests')
before = sqlite3.connect(baseline)
after = sqlite3.connect(dest / 'prototype.sqlite')
def rows(db, table):
    return db.execute('SELECT * FROM ' + table + ' ORDER BY 1,2').fetchall()
tables = [r[0] for r in before.execute("SELECT name FROM sqlite_master WHERE type='table'")]
preserved = {}
for table in tables:
    if table.startswith('sqlite_'):
        continue
    old, new = rows(before, table), rows(after, table)
    # The native-source fingerprint changes on an authorized APK upgrade.
    # Report voice identity/status/path separately from its attestation.
    if table == 'installed_bundles':
        columns = [r[1] for r in before.execute('PRAGMA table_info(' + table + ')')]
        keep = [i for i, name in enumerate(columns) if name not in ('manifest_digest', 'verified_at')]
        old = [tuple(r[i] for i in keep) for r in old]
        new = [tuple(r[i] for i in keep) for r in new]
    preserved[table] = old == new
report = {'status': 'passed' if all(preserved.values()) else 'failed',
    'schema': after.execute('PRAGMA user_version').fetchone()[0],
    'quickCheck': after.execute('PRAGMA quick_check').fetchone()[0],
    'foreignKeyViolations': len(after.execute('PRAGMA foreign_key_check').fetchall()),
    'preservedTables': preserved, 'historicalPositions': len(rows(after, 'positions')),
    'readyBooks': after.execute("SELECT count(*) FROM books WHERE state='ready'").fetchone()[0],
    'snapshotPrivate': True}
manifest = root / 'assets/models/manifest.json'
import hashlib
expected_digest = hashlib.sha256(manifest.read_bytes()).hexdigest()
report['voiceManifestReattested'] = after.execute('SELECT manifest_digest FROM installed_bundles').fetchone()[0] == expected_digest
(root / ('validation/epub/reports/' + campaign + '-data-preservation.json')).write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
