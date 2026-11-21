"""Populate the Pub cache from the two manually supplied, pinned archives. No network."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import tarfile

ROOT = Path(__file__).resolve().parents[1]


def safe_parts(name):
    parts = PurePosixPath(name).parts
    if not parts or name.startswith('/') or '\\' in name:
        raise ValueError('Unsafe archive path')
    for part in parts:
        if (part in ('.', '..') or re.search(r'[<>:"|?*\x00-\x1f]', part)
                or part.endswith(('.', ' '))
                or re.fullmatch(r'(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?', part, re.I)):
            raise ValueError('Unsafe archive component')
    return parts


def install(cache):
    metadata = json.loads((ROOT / 'reports/candidate-metadata.json').read_text())
    records = []
    for item in metadata:
        if item['name'] not in ('xml', 'petitparser'):
            continue
        identity = item['name'] + '-' + item['version']
        archive = ROOT / 'private/downloads' / (identity + '.tar.gz')
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != item['archiveSha256']:
            raise ValueError('Archive SHA mismatch: ' + identity)
        target = cache / 'hosted/pub.dev' / identity
        if target.is_symlink() or not target.resolve().is_relative_to(cache.resolve()):
            raise ValueError('Cache target escapes root')
        with tarfile.open(archive, 'r:gz') as source:
            members = source.getmembers()
            if len(members) > 5000 or sum(m.size for m in members) > 50 * 1024 * 1024:
                raise ValueError('Archive exceeds laboratory budget')
            seen = set()
            # Validate every path and member type before writing any package file.
            for member in members:
                parts = safe_parts(member.name)
                key = '/'.join(parts).casefold()
                if key in seen or not (member.isfile() or member.isdir()):
                    raise ValueError('Duplicate or unsupported tar member')
                seen.add(key)
                destination = target.joinpath(*parts)
                if destination.is_symlink() or not destination.resolve().is_relative_to(target.resolve()):
                    raise ValueError('Archive destination escapes target')
            license_bytes = source.extractfile('LICENSE').read()
            expected_license = (ROOT / 'private/dependency-metadata' / (item['name'] + '-license-tag.txt')).read_bytes()
            if license_bytes != expected_license:
                raise ValueError('Archive license differs from audited publisher tag')
            for member in members:
                destination = target.joinpath(*safe_parts(member.name))
                if member.isdir():
                    destination.mkdir(parents=True, exist_ok=True)
                    continue
                data = source.extractfile(member).read()
                if destination.exists():
                    if destination.read_bytes() != data:
                        raise ValueError('Preserving differing cache file: ' + member.name)
                    continue
                destination.parent.mkdir(parents=True, exist_ok=True)
                with destination.open('xb') as handle:
                    handle.write(data)
        hash_file = cache / 'hosted-hashes/pub.dev' / (identity + '.sha256')
        hash_file.parent.mkdir(parents=True, exist_ok=True)
        if hash_file.exists() and hash_file.read_text().strip() != digest:
            raise ValueError('Existing cache archive hash differs')
        hash_file.write_text(digest, encoding='ascii')
        records.append({'package': identity, 'archiveSha256': digest, 'members': len(members),
                        'licenseMatchesAuditedTag': True, 'networkUsed': False})
    (ROOT / 'reports/manual-cache-installation.json').write_text(json.dumps({'packages': records}, indent=2) + '\n')
    return records


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(install(args.cache.resolve())))
