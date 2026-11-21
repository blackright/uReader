"""Make an isolated rehearsal from the authorized phone backup, never restore it to phone."""
from pathlib import Path
import datetime
import hashlib
import json
import shutil
import sqlite3
import tarfile

ROOT = Path(__file__).resolve().parents[3]
LAB = ROOT/'validation/epub'
QUERIES = {
    'positions':'SELECT * FROM positions ORDER BY text_id,mode',
    'bundleIdentity':'SELECT bundle_id,version,relative_directory,status FROM installed_bundles ORDER BY bundle_id,version',
    'operations':'SELECT * FROM operations ORDER BY id',
}

if __name__ == '__main__':
    backup = json.loads((LAB/'reports/device-backup.json').read_text())
    archives = list((LAB/'private').glob('epub-phase2-before-*.tar'))
    matches = [p for p in archives if hashlib.file_digest(p.open('rb'),'sha256').hexdigest()==backup['sha256']]
    if len(matches)!=1:
        raise ValueError('Expected exactly the verified, authorized device snapshot')
    manifest=json.loads((ROOT/'assets/models/manifest.json').read_text())
    if shutil.disk_usage(LAB/'private').free < sum(f['byteSize'] for f in manifest['files'])+50*1024*1024:
        raise ValueError('Insufficient free space for isolated rehearsal')
    output=LAB/'private'/('migration-rehearsal-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    output.mkdir(exist_ok=False)
    directory='models/'+manifest['bundleId']+'/'+manifest['bundleVersion']
    required=['prototype.sqlite',*[directory+'/'+f['relativePath'] for f in manifest['files']]]
    with tarfile.open(matches[0]) as archive:
        names=set(archive.getnames())
        required += [name for name in ['prototype.sqlite-journal','prototype.sqlite-wal','prototype.sqlite-shm'] if 'ureader-prototype/'+name in names]
        for relative in required:
            target=output/relative
            if not target.resolve().is_relative_to(output.resolve()):raise ValueError('Unsafe rehearsal destination')
            member=archive.getmember('ureader-prototype/'+relative)
            if not member.isfile():raise ValueError('Only regular files are copied')
            target.parent.mkdir(parents=True,exist_ok=True)
            with archive.extractfile(member) as source,target.open('xb') as sink:shutil.copyfileobj(source,sink,65536)
    database=sqlite3.connect(output/'prototype.sqlite')
    try:
        version=database.execute('PRAGMA user_version').fetchone()[0]
        hashes={name:hashlib.sha256(json.dumps(database.execute(sql).fetchall(),ensure_ascii=False,separators=(',',':')).encode()).hexdigest() for name,sql in QUERIES.items()}
    finally:database.close()
    ownership={'sourceBackupSha256':backup['sha256'],'initialSchema':version,'tableHashes':hashes,'queries':QUERIES}
    (output/'rehearsal-owned.json').write_text(json.dumps(ownership,indent=2)+'\n')
    (LAB/'private/current-rehearsal.json').write_text(json.dumps({'relativeRoot':output.relative_to(ROOT).as_posix()})+'\n')
    print(json.dumps({'created':output.relative_to(ROOT).as_posix(),'schemaBefore':version,'phoneModified':False}))
