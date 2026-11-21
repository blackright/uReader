"""Inspect every packaged ELF LOAD alignment; never substitutes a 16-KiB device test."""
import argparse
import hashlib
import json
import struct
import zipfile
from pathlib import Path


def inspect(apk):
    libraries = []
    with zipfile.ZipFile(apk) as archive:
        for item in archive.infolist():
            if not item.filename.startswith('lib/') or not item.filename.endswith('.so'):
                continue
            data = archive.read(item)
            if data[:4] != b'\x7fELF' or data[5] != 1 or data[4] not in (1, 2):
                raise ValueError('Expected ELF32/64 little endian')
            machine = struct.unpack_from('<H', data, 18)[0]
            elf64 = data[4] == 2
            offset = struct.unpack_from('<Q' if elf64 else '<I', data, 32 if elf64 else 28)[0]
            size, count = struct.unpack_from('<HH', data, 54 if elf64 else 42)
            segments = []
            for index in range(count):
                values = struct.unpack_from('<IIQQQQQQ' if elf64 else '<IIIIIIII', data, offset + size * index)
                if elf64:
                    kind, flags, file_offset, address, _, _, _, alignment = values
                else:
                    kind, file_offset, address, _, _, _, flags, alignment = values
                if kind == 1:
                    segments.append({'alignment': alignment,
                                     'congruent16KiB': file_offset % 16384 == address % 16384})
            passed = bool(segments) and all(s['alignment'] >= 16384 and s['congruent16KiB'] for s in segments)
            libraries.append({'entry': item.filename, 'bytes': len(data),
                              'sha256': hashlib.sha256(data).hexdigest(), 'machine': machine,
                              'loadSegments': segments, 'alignment16KiB': passed})
    return {'apkSha256': hashlib.sha256(Path(apk).read_bytes()).hexdigest(),
            'status': 'passed' if libraries and all(l['alignment16KiB'] for l in libraries) else 'failed',
            'scope': 'ELF LOAD alignment only; ZIP alignment and runtime tested separately',
            'libraries': libraries}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.apk)
    args.report.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': result['status'], 'libraries': len(result['libraries'])}))
    raise SystemExit(0 if result['status'] == 'passed' else 1)
