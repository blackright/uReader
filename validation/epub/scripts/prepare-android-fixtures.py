"""Copy only SHA-verified synthetic fixtures into ignored instrumentation assets."""
from pathlib import Path
import hashlib
import io
import json
import stat
import struct
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[3]
LAB = ROOT / 'validation/epub'
DEST = ROOT / 'android/app/src/androidTest/assets/epub-gate'


def zip64():
    name, data = b'a', b'abc'
    crc = zlib.crc32(data)
    extra = struct.pack('<HHQQ', 1, 16, len(data), len(data))
    local = struct.pack('<IHHHHHIIIHH', 0x04034b50, 45, 0, 0, 0, 0, crc,
                        0xffffffff, 0xffffffff, 1, len(extra)) + name + extra + data
    extra = struct.pack('<HHQQQ', 1, 24, len(data), len(data), 0)
    central = struct.pack('<IHHHHHHIIIHHHHHII', 0x02014b50, 3 << 8 | 45, 45,
                          0, 0, 0, 0, crc, 0xffffffff, 0xffffffff,
                          1, len(extra), 0, 0, 0, (stat.S_IFREG | 0o600) << 16, 0xffffffff) + name + extra
    end64 = struct.pack('<IQHHIIQQQQ', 0x06064b50, 44, 45, 45, 0, 0, 1, 1, len(central), len(local))
    locator = struct.pack('<IIQI', 0x07064b50, 0, len(local)+len(central), 1)
    end = struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, 65535, 65535, 0xffffffff, 0xffffffff, 0)
    return local + central + end64 + locator + end


def forged_size():
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        info = zipfile.ZipInfo('a', (2026,11,14,0,0,0))
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, b'A' * 131072)
    data = bytearray(stream.getvalue())
    central = data.index(b'PK\x01\x02')
    struct.pack_into('<I', data, 22, 1)
    struct.pack_into('<I', data, central + 24, 1)
    return bytes(data)


def overlapping():
    def local(name, data):
        return struct.pack('<IHHHHHIIIHH',0x04034b50,20,0,0,0,0,zlib.crc32(data),len(data),len(data),len(name),0)+name+data
    inner_data=b'xyz'
    inner=local(b'b',inner_data)
    outer_data=b'prefix'+inner+b'suffix'
    outer=local(b'a',outer_data)
    def central(name,data,offset):
        return struct.pack('<IHHHHHHIIIHHHHHII',0x02014b50,3<<8|20,20,0,0,0,0,zlib.crc32(data),len(data),len(data),len(name),0,0,0,0,(stat.S_IFREG|0o600)<<16,offset)+name
    directory=central(b'a',outer_data,0)+central(b'b',inner_data,31+6)
    end=struct.pack('<IHHHHIIH',0x06054b50,0,0,2,2,len(directory),len(outer),0)
    return outer+directory+end


def write(name, data):
    target = DEST / name
    if target.is_symlink() or not target.resolve().is_relative_to(DEST.resolve()):
        raise ValueError('Unsafe fixture destination')
    if target.exists() and target.read_bytes() != data:
        raise ValueError('Preserve differing instrumentation fixture')
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    return {'name': name, 'sha256': hashlib.sha256(data).hexdigest()}


if __name__ == '__main__':
    manifest = json.loads((LAB / 'corpus-manifest.json').read_text(encoding='utf-8'))
    records = []
    zip_rejections = {'not-zip','traversal','absolute','backslash','duplicate-entry',
        'encrypted-flag','crc-mismatch','symlink-entry','offset-outside-source',
        'truncated-eocd','zip64-sentinel-without-index','expansion-ratio',
        'too-many-entries','entry-name-too-long'}
    for row in manifest['books'] + manifest['hostile']:
        if row['id'] not in zip_rejections and row not in manifest['books']:
            continue
        data = (LAB / row['path']).read_bytes()
        assert hashlib.sha256(data).hexdigest() == row['sha256']
        record = write(row['id']+'.epub', data)
        record['accepted'] = row in manifest['books']
        records.append(record)
    for name, data, accepted in [('valid-zip64.epub',zip64(),True),
                                  ('forged-real-output.epub',forged_size(),False),
                                  ('overlapping-records.epub',overlapping(),False)]:
        record = write(name,data);record['accepted']=accepted;records.append(record)
    write('manifest.json',(json.dumps(records,indent=2)+'\n').encode())
    (LAB/'reports/android-fixture-preparation.json').write_text(json.dumps({'assets':records,'personalBooksCopied':False},indent=2)+'\n')
    print(json.dumps({'assets':len(records),'positive':sum(r['accepted'] for r in records)}))
