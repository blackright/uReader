"""Private, non-overwriting snapshot and strict logical comparison. No restore/delete command."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tarfile
import time

ROOT=Path(__file__).resolve().parents[3]
PRIVATE=ROOT/'validation/reader/private'
PACKAGE='com.ureader.prototype'
APP_ROOT='ureader-prototype'
MAX_BYTES=4*1024**3

def digest_stream(stream):
    h=hashlib.sha256()
    while chunk:=stream.read(1024*1024): h.update(chunk)
    return h.hexdigest()

def inspect_archive(archive, destination):
    """Never extract arbitrary archive paths; copy only the three fixed SQLite files."""
    files={}; seen=set(); logical=0
    with tarfile.open(archive,'r:') as tar:
        for member in tar:
            name=member.name
            path=PurePosixPath(name)
            if path.is_absolute() or '..' in path.parts or '\\' in name or not path.parts or path.parts[0]!=APP_ROOT:
                raise ValueError('Unsafe archive entry')
            canonical=str(path)
            if canonical in seen: raise ValueError('Duplicate archive entry')
            seen.add(canonical)
            if len(seen)>100000: raise ValueError('Archive entry quota exceeded')
            if member.isdir(): continue
            if not member.isfile(): raise ValueError('Links and special archive entries refused')
            logical+=member.size
            if logical>MAX_BYTES: raise ValueError('Archive size quota exceeded')
            with tar.extractfile(member) as src: files[canonical]={'bytes':member.size,'sha256':digest_stream(src)}
            if canonical in [APP_ROOT+'/prototype.sqlite'+suffix for suffix in ('','-wal','-shm')]:
                if member.size>1024**3: raise ValueError('Database snapshot too large')
                target=destination/path.name
                with tar.extractfile(member) as src, target.open('xb') as dst: shutil.copyfileobj(src,dst,1024*1024)
    dbfile=destination/'prototype.sqlite'
    if not dbfile.exists(): raise ValueError('Product database absent')
    db=sqlite3.connect(dbfile.as_uri()+'?mode=ro',uri=True)
    try:
        if db.execute('PRAGMA quick_check').fetchall()!=[('ok',)]: raise ValueError('Database quick_check failed')
        if db.execute('PRAGMA foreign_key_check').fetchone() is not None: raise ValueError('Foreign key violations')
        tables={}
        for (name,) in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"):
            quoted='"'+name.replace('"','""')+'"'
            columns=[row[1] for row in db.execute('PRAGMA table_info('+quoted+')')]
            sql='SELECT * FROM '+quoted+' ORDER BY '+','.join(str(i+1) for i in range(len(columns)))
            h=hashlib.sha256(); count=0
            for row in db.execute(sql):
                h.update((repr(tuple(row))+'\n').encode('utf-8'));count+=1
            tables[name]={'columns':columns,'rows':count,'sha256':h.hexdigest()}
        return {'schema':db.execute('PRAGMA user_version').fetchone()[0],
                'quickCheck':'ok','foreignKeyViolations':0,'files':files,'tables':tables}
    finally: db.close()

def snapshot(run_id, stop_app, database_only=False):
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}',run_id): raise ValueError('Invalid snapshot ID')
    PRIVATE.mkdir(parents=True,exist_ok=True)
    destination=PRIVATE/run_id
    destination.mkdir(exist_ok=False) # never overwrite an earlier snapshot
    adb=str(Path(os.environ['LOCALAPPDATA'])/'Android/sdk/platform-tools/adb.exe')
    def call(*args): return subprocess.run([adb,'-d',*args],capture_output=True,timeout=30)
    ready=call('get-state')
    if ready.returncode or ready.stdout.strip()!=b'device': raise ValueError('One authorized Android device required')
    running=call('shell','pidof',PACKAGE)
    was_running=running.returncode==0 and bool(running.stdout.strip())
    if was_running and not stop_app: raise ValueError('App running: stop explicitly or use --stop-app; no live database snapshot')
    stopped=False
    try:
        if stop_app:
            result=call('shell','am','force-stop',PACKAGE)
            if result.returncode: raise ValueError('Unable to stop app')
            stopped=True
        if call('shell','pidof',PACKAGE).stdout.strip(): raise ValueError('App still running')
        archive=destination/'product.tar.partial'
        # ADB streams only the fixed product root; no shell interpolation of personal paths.
        if shutil.disk_usage(PRIVATE).free<(1024**3 if database_only else MAX_BYTES)+256*1024**2: raise ValueError('Insufficient bounded snapshot space')
        entries=[APP_ROOT]
        if database_only:
            entries=[APP_ROOT+'/prototype.sqlite']
            for suffix in ('-wal','-shm'):
                name=APP_ROOT+'/prototype.sqlite'+suffix
                result=call('shell','run-as',PACKAGE,'stat','-c','%F','files/'+name)
                if result.returncode==0:
                    if result.stdout.strip()!=b'regular file':raise ValueError('Unexpected database sidecar type')
                    entries.append(name)
                elif b'No such file or directory' not in result.stderr+result.stdout:
                    raise ValueError('Unable to inspect database sidecar')
        with archive.open('xb') as output, (destination/'adb-stderr.txt').open('xb') as errors:
            child=subprocess.Popen([adb,'-d','exec-out','run-as',PACKAGE,'tar','-cf','-','-C','files',*entries],stdout=output,stderr=errors)
            started=time.monotonic()
            try:
                while child.poll() is None:
                    if time.monotonic()-started>600 or archive.stat().st_size>MAX_BYTES:
                        raise ValueError('Snapshot timeout or byte limit')
                    time.sleep(.1)
                if child.returncode or archive.stat().st_size>MAX_BYTES: raise ValueError('Snapshot transfer failed')
            finally:
                if child.poll() is None: child.kill();child.wait()
        if call('shell','pidof',PACKAGE).stdout.strip(): raise ValueError('App restarted during snapshot; invalid snapshot')
        archive.rename(destination/'product.tar')
        report=inspect_archive(destination/'product.tar',destination)
        report['scope']='database_only' if database_only else 'full_product_root'
        with (destination/'manifest.json').open('x',encoding='utf-8') as f: json.dump(report,f,indent=2)
        print(json.dumps({'status':'captured','snapshotId':run_id,'schema':report['schema'],
              'tables':len(report['tables']),'files':len(report['files']),'private':True}))
    finally:
        if stopped and was_running:
            result=call('shell','am','start','-n',PACKAGE+'/.MainActivity')
            if result.returncode: raise ValueError('Snapshot ended but app restart failed; relaunch app manually')

def compare(before,after):
    def load(run):
        if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}',run): raise ValueError('Invalid snapshot ID')
        return json.loads((PRIVATE/run/'manifest.json').read_text(encoding='utf-8'))
    a,b=load(before),load(after)
    scope=a.get('scope','full_product_root')
    if scope!=b.get('scope','full_product_root'):raise ValueError('Different snapshot scopes')
    tables={name:a['tables'][name]==b['tables'].get(name) for name in a['tables']}
    # Schema pages/WAL naturally change on migration; compare table values instead.
    files={name:meta==b['files'].get(name) for name,meta in a['files'].items()
           if name not in [APP_ROOT+'/prototype.sqlite'+suffix for suffix in ('','-wal','-shm')]}
    result={'status':'passed' if all(tables.values()) and all(files.values()) else 'failed',
      'scope':scope,
      'beforeSchema':a['schema'],'afterSchema':b['schema'],'oldTablesCompared':len(tables),
      'unchangedOldTables':sum(tables.values()),'oldFilesCompared':len(files),
      'unchangedOldFiles':sum(files.values()),'quickCheck':b['quickCheck'],
      'foreignKeyViolations':b['foreignKeyViolations'],
      'note':'Strict comparison; authorized cache/voice attestation differences need explicit review, never silent exclusion.'}
    print(json.dumps(result))
    return 0 if result['status']=='passed' else 1

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='command',required=True)
    p=sub.add_parser('snapshot');p.add_argument('run_id');p.add_argument('--stop-app',action='store_true');p.add_argument('--database-only',action='store_true')
    p=sub.add_parser('compare');p.add_argument('before');p.add_argument('after')
    args=parser.parse_args()
    try:
        if args.command=='snapshot': snapshot(args.run_id,args.stop_app,args.database_only);return 0
        return compare(args.before,args.after)
    except (ValueError,OSError,sqlite3.Error,tarfile.TarError,subprocess.SubprocessError):
        print(json.dumps({'status':'failed','reason':'snapshot_or_comparison_unavailable','details':'Private artifacts retained; no data cleared or restored.'}))
        return 2

if __name__=='__main__': raise SystemExit(main())
