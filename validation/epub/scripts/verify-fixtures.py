"""Check fixture integrity and authored references, not application behavior."""
import collections
import hashlib
import io
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def verify():
    manifest = json.loads((ROOT / 'corpus-manifest.json').read_text(encoding='utf-8'))
    assert len(manifest['books']) == 10
    assert collections.Counter(b['epubVersion'] for b in manifest['books']) == {2: 5, 3: 5}
    assert collections.Counter(b['language'] for b in manifest['books']) == {'fr': 8, 'en': 2}
    ns = {'x': 'http://www.w3.org/1999/xhtml', 'opf': 'http://www.idpf.org/2007/opf',
          'dc': 'http://purl.org/dc/elements/1.1/'}
    for record in manifest['books'] + manifest['hostile']:
        path = ROOT / record['path']
        data = path.read_bytes()
        assert len(data) == record['bytes']
        assert hashlib.sha256(data).hexdigest() == record['sha256']
    for book in manifest['books']:
        with zipfile.ZipFile(ROOT / book['path']) as archive:
            assert archive.testzip() is None
            infos = archive.infolist()
            assert infos[0].filename == 'mimetype' and infos[0].compress_type == zipfile.ZIP_STORED
            assert archive.read('mimetype') == b'application/epub+zip'
            assert all(i.file_size <= 50 * 1024 * 1024 and i.file_size <= 100 * max(1, i.compress_size) for i in infos)
            package = ET.fromstring(archive.read('OEBPS/content.opf'))
            assert len(package.findall('opf:spine/opf:itemref', ns)) == len(book['chapters']) == 3
            assert (package.find('opf:metadata/dc:title', ns) is None) == book['titleAbsent']
            assert (package.find('opf:metadata/dc:creator', ns) is None) == book['authorAbsent']
            for chapter in book['chapters']:
                document = ET.fromstring(archive.read(chapter['href']))
                heading = document.find('x:body/x:h1', ns)
                paragraph = document.find('x:body/x:p', ns)
                assert heading.text == chapter['initialCanonicalBlocks'][0]['text']
                assert paragraph.text == chapter['initialCanonicalBlocks'][1]['text']
                assert document.find('.//*[@id="passage"]') is not None
            if not book['coverAbsent']:
                image = archive.read('OEBPS/cover.png')
                assert image[:8] == b'\x89PNG\r\n\x1a\n'
                assert struct.unpack('>II', image[16:24]) == (2, 2)
    cases = {c['id']: (ROOT / c['path']).read_bytes() for c in manifest['hostile']}
    assert b'OEBPS\\escape.txt' in cases['backslash']
    with zipfile.ZipFile(io.BytesIO(cases['crc-mismatch'])) as archive:
        assert archive.testzip() == 'mimetype'
    with zipfile.ZipFile(io.BytesIO(cases['expansion-ratio'])) as archive:
        entry = archive.getinfo('OEBPS/bomb.txt')
        assert entry.file_size > entry.compress_size * 100
    with zipfile.ZipFile(io.BytesIO(cases['too-many-entries'])) as archive:
        assert len(archive.infolist()) > 5000
    # Never decompress hostile XML/CSS or oversized sources to "validate" an importer.
    return {'date': '2026-11-14', 'status': 'passed', 'books': 10,
            'hostileInputsHashed': len(cases), 'positiveChapterReferences': 30,
            'crcFaultConfirmed': True, 'expansionFaultConfirmed': True,
            'entryCountFaultConfirmed': True, 'applicationImport': 'not_evaluated',
            'epubCheckConformance': 'not_evaluated', 'humanRenderingAndSpeech': 'not_evaluated'}


if __name__ == '__main__':
    report = verify()
    (ROOT / 'reports/fixture-verification.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
