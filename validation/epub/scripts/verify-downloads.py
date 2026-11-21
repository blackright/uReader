"""Verify manually downloaded Pub archives without extraction or installation."""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
DOWNLOADS = ROOT / 'private/downloads'


def verify():
    candidates = json.loads((ROOT / 'reports/candidate-metadata.json').read_text())
    results = []
    for candidate in candidates:
        if candidate['name'] not in ('xml', 'petitparser'):
            continue
        name = f"{candidate['name']}-{candidate['version']}.tar.gz"
        path = DOWNLOADS / name
        row = {'archive': name, 'expectedSha256': candidate['archiveSha256']}
        if path.is_symlink() or not path.resolve().is_relative_to(DOWNLOADS.resolve()):
            row['status'] = 'refused_path'
        elif not path.is_file():
            row['status'] = 'missing'
        elif path.stat().st_size > 50 * 1024 * 1024:
            row['status'] = 'refused_oversized_archive'
        else:
            digest = hashlib.sha256()
            with path.open('rb') as handle:
                for chunk in iter(lambda: handle.read(65536), b''):
                    digest.update(chunk)
            row['actualSha256'] = digest.hexdigest()
            row['status'] = 'verified' if digest.hexdigest() == row['expectedSha256'] else 'sha256_mismatch'
        results.append(row)
    return {'schemaVersion': 1, 'archives': results, 'allVerified': len(results) == 2 and all(r['status'] == 'verified' for r in results),
            'extracted': False, 'installed': False}


if __name__ == '__main__':
    report = verify()
    (ROOT / 'reports/download-verification.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    sys.exit(0 if report['allVerified'] else 2)
