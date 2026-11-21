"""Prepare CC0-only US1 device cases; no personal documents or network access."""
import hashlib
import importlib.util
import io
import json
import struct
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[3]
LAB = ROOT / 'validation/epub'
DEST = LAB / 'private/us1-device'


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((LAB / 'corpus-manifest.json').read_text(encoding='utf-8'))
    cases = []

    def add(name, data, policy, **extra):
        target = DEST / (name + '.epub')
        if target.is_symlink() or not target.resolve().is_relative_to(DEST.resolve()):
            raise ValueError('Unsafe fixture target')
        if target.exists() and target.read_bytes() != data:
            raise ValueError('Preserve differing fixture: ' + name)
        if not target.exists():
            target.write_bytes(data)
        case = dict(id=name, filename=target.name, policy=policy, bytes=len(data),
                    sha256=hashlib.sha256(data).hexdigest(), **extra)
        cases.append(case)
        return case

    for entry in manifest['books']:
        data = (LAB / entry['path']).read_bytes()
        assert hashlib.sha256(data).hexdigest() == entry['sha256']
        add(entry['id'], data, 'ready', reference=entry)
    originals = list(cases)
    for i, entry in enumerate(originals):
        data = (DEST / entry['filename']).read_bytes()
        add('renamed-' + entry['id'] if i < 5 else 'repeat-' + entry['id'], data,
            'existing', original=entry['id'])
    source = DEST / originals[0]['filename']

    def changed(replacements=None, extra=None, case_name=None):
        out = io.BytesIO()
        with zipfile.ZipFile(source) as z, zipfile.ZipFile(out, 'w') as writer:
            for info in z.infolist():
                value = z.read(info.filename)
                for old, new in (replacements or {}).get(info.filename, []):
                    value = value.replace(old, new)
                writer.writestr(info, value)
            for name, value in (extra or {}).items():
                info = zipfile.ZipInfo(name, (2026, 11, 14, 0, 0, 0))
                if case_name and (DEST / (case_name + '.epub')).exists():
                    with zipfile.ZipFile(DEST / (case_name + '.epub')) as prior:
                        info = prior.getinfo(name)
                writer.writestr(info, value, compress_type=zipfile.ZIP_STORED)
        return out.getvalue()

    for i in [1, 2]:
        add('same-title-edition-' + str(i), changed(extra={'edition.txt': str(i).encode()}, case_name='same-title-edition-'+str(i)),
            'edition', expectedTitle='Fixture EPUB 01')
    for entry in manifest['hostile']:
        data = (LAB / entry['path']).read_bytes()
        assert hashlib.sha256(data).hexdigest() == entry['sha256']
        accept = entry['id'] in ['active-content', 'unsafe-link', 'remote-css',
                                 'oversized-image-dimensions', 'corrupt-image']
        add('negative-' + entry['id'], data, 'filtered' if accept else 'reject',
            category=entry['id'])
    with zipfile.ZipFile(source) as z:
        opf = z.read('OEBPS/package.opf') if 'OEBPS/package.opf' in z.namelist() else None
        opf_name = next(n for n in z.namelist() if n.endswith('.opf'))
        opf = z.read(opf_name)
    # Deliberately invalid main packages: no protected-content workaround.
    add('negative-fixed', changed({opf_name: [(b'</metadata>', b'<meta property="rendition:layout">pre-paginated</meta></metadata>')]}), 'reject', category='fixed-layout')
    add('negative-missing-spine', changed({opf_name: [(b'<spine', b'<absent'), (b'</spine>', b'</absent>')]}), 'reject', category='missing-spine')
    encrypted = b'<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="urn:drm"/><CipherData><CipherReference URI="OEBPS/chapter1.xhtml"/></CipherData></EncryptedData></encryption>'
    add('negative-protected', changed(extra={'META-INF/encryption.xml': encrypted}, case_name='negative-protected'), 'reject', category='protected-text')
    add('negative-empty-main', changed({'OEBPS/chapter%d.xhtml' % i: [(b'<body>', b'<body><script>'), (b'</body>', b'</script></body>')] for i in [1, 2, 3]}), 'reject', category='empty-main')
    add('negative-resource-size', changed(extra={'large.bin': b'X' * (50 * 1024 * 1024 + 1)}, case_name='negative-resource-size'), 'reject', category='resource-size')
    add('negative-source-size', b'X' * (100 * 1024 * 1024 + 1), 'reject', category='source-size')
    # A 2-MiB PNG with a 20-Mpixel header: replace before any image decoder.
    spec = importlib.util.spec_from_file_location('fixtures', LAB / 'scripts/generate-fixtures.py')
    fixture_module = importlib.util.module_from_spec(spec); spec.loader.exec_module(fixture_module)
    with zipfile.ZipFile(source) as z:
        image_name = next(n for n in z.namelist() if n.endswith('.png'))
    png = fixture_module.png(5000, 4000)
    out = io.BytesIO()
    with zipfile.ZipFile(source) as z, zipfile.ZipFile(out, 'w') as writer:
        for info in z.infolist():
            if info.filename == image_name:
                image_info = zipfile.ZipInfo(info.filename, (2026, 11, 14, 0, 0, 0))
                if (DEST / 'negative-image-20mp.epub').exists():
                    with zipfile.ZipFile(DEST / 'negative-image-20mp.epub') as prior:
                        image_info = prior.getinfo(info.filename)
                writer.writestr(image_info, png + b'\0' * (2 * 1024 * 1024 - len(png)), compress_type=zipfile.ZIP_STORED)
            else:
                writer.writestr(info, z.read(info.filename))
    add('negative-image-20mp', out.getvalue(), 'filtered', category='image-dimensions-2MiB')
    # Corrupt the CRC of the optional cover, not the main package.
    damaged = bytearray(source.read_bytes())
    with zipfile.ZipFile(source) as z:
        image = next(i for i in z.infolist() if i.filename.endswith('.png'))
        struct.pack_into('<I', damaged, image.header_offset + 14, image.CRC ^ 1)
        at = z.start_dir
        while damaged[at:at+4] == b'PK\x01\x02':
            size, extra_size, comment_size = struct.unpack_from('<HHH', damaged, at+28)
            name = damaged[at+46:at+46+size].decode()
            if name == image.filename:
                struct.pack_into('<I', damaged, at+16, image.CRC ^ 1)
                break
            at += 46 + size + extra_size + comment_size
    add('negative-optional-image-crc', bytes(damaged), 'reject', category='optional-image-crc')
    for i in range(5):
        add('cancel-copy-%d' % i, changed(extra={'cancel-marker.txt': str(i).encode(), 'cancel-padding.bin': b'Z' * (2 * 1024 * 1024)}, case_name='cancel-copy-%d'%i), 'cancel')
    for i, point in enumerate(['before-validated', 'validated', 'renamed', 'committed', 'tampered']):
        add('interrupt-%d' % i, changed(extra={'fault-marker.txt': str(i).encode()}, case_name='interrupt-%d'%i), 'interrupt', checkpoint=point)
    add('lost-source', changed(extra={'lost-marker.txt': b'1'}, case_name='lost-source'), 'lost')
    result = dict(schemaVersion=1, rights=manifest['rights'], cases=cases)
    recovery=dict(result,cases=[c for c in cases if c['policy'] in ['ready','cancel','interrupt','lost'] or c['id'] in ['negative-active-content','negative-remote-css','negative-external-entity']])
    (DEST / 'recovery-config.json').write_text(json.dumps(recovery,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (DEST / 'config.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'cases': len(cases), 'directory': str(DEST)}))


if __name__ == '__main__':
    main()
