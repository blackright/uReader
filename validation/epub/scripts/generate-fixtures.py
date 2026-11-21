"""Generate owned, synthetic EPUB fixtures; never read personal books or extract ZIPs.

Python standard library only. Outputs are laboratory inputs, not importer results.
Re-running preserves existing files only when their bytes match exactly.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import platform
import stat
import struct
import warnings
from xml.sax.saxutils import escape
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
STAMP = (2026, 11, 14, 0, 0, 0)
RIGHTS = "Original synthetic uReader fixture, dedicated to CC0-1.0; no personal or third-party book."


def png(width=2, height=2):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    # Oversized variants deliberately contain insufficient pixel data: never decode them.
    raw = b'\0' + b'\x20\x60\xa0' * min(width, 2)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw * min(height, 2))) + chunk(b'IEND', b''))


def archive(entries):
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w') as z:
        for name, data in entries:
            info = zipfile.ZipInfo(name, STAMP)
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | 0o600) << 16
            info.compress_type = zipfile.ZIP_STORED if name == 'mimetype' else zipfile.ZIP_DEFLATED
            z.writestr(info, data.encode('utf-8') if isinstance(data, str) else data)
    return out.getvalue()


def xhtml(body, lang):
    return ('<?xml version="1.0" encoding="UTF-8"?>'
            f'<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="{lang}">'
            '<head><title>Fixture</title><link rel="stylesheet" type="text/css" href="style.css"/></head>'
            f'<body>{body}</body></html>')


def make_book(index):
    version = 2 if index <= 5 else 3
    lang = 'en' if index in (5, 10) else 'fr'
    title = f'Fixture EPUB {index:02}'
    missing_title, missing_author, cover = index == 2, index in (2, 7), index not in (2, 7)
    chapters, references, features = [], [], []
    for chapter in range(3):
        heading = f'Chapter {chapter + 1}' if lang == 'en' else f'Chapitre {chapter + 1}'
        text = (f'The reader opens chapter {chapter + 1} and follows the garden path.' if lang == 'en'
                else f'Léa ouvre le chapitre {chapter + 1} et suit le chemin du jardin.')
        body = f'<h1 id="start">{heading}</h1><p id="passage">{escape(text)}</p>'
        blocks = [{'id': f'c{chapter}-b0-s0', 'text': heading},
                  {'id': f'c{chapter}-b1-s0', 'text': text}]
        extra = []
        if chapter == 0 and index == 3:
            body += '<p id="unicode">Bon<em>jour</em> Léa<br/>A&#160; B &amp; C : é e&#x301; 😀.</p><pre> A  B\nC </pre>'
            extra = ['Bonjour Léa\nA\u00a0 B & C : é e\u0301; 😀.', ' A  B\nC ']
            features += ['inline', 'br', 'entities', 'combining_unicode', 'surrogate_pair', 'preformatted']
        if chapter == 0 and index == 4:
            body += '<p class="hidden">NE PAS AFFICHER NI LIRE.</p><p hidden="hidden">MASQUÉ.</p><p style="visibility:hidden">MASQUÉ AUSSI.</p>'
            features += ['css_visibility', 'hidden_attribute']
        if chapter == 0 and index == 6:
            body += '<p>Une citation <a href="chapter2.xhtml#passage">interne</a>.</p><blockquote><p>Le jardin reste ouvert.</p></blockquote><ul><li>Une pomme</li><li>Deux poires</li></ul>'
            extra = ['Une citation interne.', 'Le jardin reste ouvert.', 'Une pomme', 'Deux poires']
            features += ['internal_link', 'blockquote', 'list']
        if chapter == 0 and index == 7:
            body += '<p>Le texte principal continue.</p><aside epub:type="footnote" id="note" xmlns:epub="http://www.idpf.org/2007/ops"><p>Note consultable.</p></aside>'
            extra = ['Le texte principal continue.']
            features += ['identified_footnote_excluded_from_narration']
        if chapter == 0 and index == 8:
            body += '<table><tr><th>Fruit</th><th>Nombre</th></tr><tr><td>Pomme</td><td>Trois</td></tr></table><p><a href="https://example.org/">Lien externe</a></p>'
            # Table serialization is a gate decision; these cells are content references, not invented projector output.
            extra = ['Lien externe']
            features += ['table', 'external_https_confirmation']
        if chapter == 0 and index == 9:
            long_text = 'é' * 8191 + '😀' + ' fin.'
            body += f'<p id="long">{long_text}</p>'
            extra = [long_text]
            for n in range(120):
                sentence = f'Paragraphe de continuité numéro {n + 1}.'
                body += '<p>' + sentence + '</p>'
                extra.append(sentence)
            features += ['long_chapter', 'block_split_8192_utf16', 'window_boundary_64_blocks']
        if chapter == 0 and cover:
            body += '<p><img src="cover.png" alt="Carré bleu de référence"/></p>'
        chapters.append((f'OEBPS/chapter{chapter + 1}.xhtml', xhtml(body, lang)))
        references.append({'chapterId': f'c{chapter}', 'href': f'OEBPS/chapter{chapter + 1}.xhtml',
                           'title': heading, 'initialCanonicalBlocks': blocks,
                           'additionalVisibleMainTextInOrder': extra,
                           'expectedAnchors': ['start', 'passage'],
                           'lastMainText': extra[-1] if extra else text})
    metadata = '<dc:identifier id="bookid">urn:ureader:fixture:' + str(index) + '</dc:identifier>'
    if not missing_title:
        metadata += '<dc:title>' + title + '</dc:title>'
    if not missing_author:
        metadata += '<dc:creator>Auteur synthétique uReader</dc:creator>'
    metadata += '<dc:language>' + lang + '</dc:language>'
    if version == 3:
        metadata += '<meta property="dcterms:modified">2026-11-14T00:00:00Z</meta>'
    if cover:
        metadata += '<meta name="cover" content="cover"/>'
    manifest = ''.join(f'<item id="c{n}" href="chapter{n + 1}.xhtml" media-type="application/xhtml+xml"/>' for n in range(3))
    manifest += '<item id="css" href="style.css" media-type="text/css"/>'
    if cover:
        manifest += '<item id="cover" href="cover.png" media-type="image/png"' + (' properties="cover-image"' if version == 3 else '') + '/>'
    toc = ''.join(f'<navPoint id="n{n}" playOrder="{n + 1}"><navLabel><text>{r["title"]}</text></navLabel><content src="chapter{n + 1}.xhtml#start"/></navPoint>' for n, r in enumerate(references))
    ncx = '<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="urn:ureader:fixture:' + str(index) + '"/><meta name="dtb:depth" content="1"/><meta name="dtb:totalPageCount" content="0"/><meta name="dtb:maxPageNumber" content="0"/></head><docTitle><text>' + title + '</text></docTitle><navMap>' + toc + '</navMap></ncx>'
    nav = xhtml('<nav xmlns:epub="http://www.idpf.org/2007/ops" epub:type="toc"><ol>' + ''.join(f'<li><a href="chapter{n + 1}.xhtml#start">{r["title"]}</a></li>' for n, r in enumerate(references)) + '</ol></nav>', lang)
    manifest += ('<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>' if version == 2 else '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>')
    opf = f'<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="{version}.0" unique-identifier="bookid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">{metadata}</metadata><manifest>{manifest}</manifest><spine' + (' toc="ncx"' if version == 2 else '') + '>' + ''.join(f'<itemref idref="c{n}"/>' for n in range(3)) + '</spine></package>'
    entries = [('mimetype', 'application/epub+zip'), ('META-INF/container.xml', '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'), ('OEBPS/content.opf', opf), ('OEBPS/style.css', 'body { color: #202020; } .hidden { display: none; }'), *chapters, ('OEBPS/toc.ncx' if version == 2 else 'OEBPS/nav.xhtml', ncx if version == 2 else nav)]
    if cover:
        entries.append(('OEBPS/cover.png', png()))
    return entries, {'id': f'epub-{index:02}', 'epubVersion': version, 'language': lang,
                     'titleAbsent': missing_title, 'authorAbsent': missing_author,
                     'coverAbsent': not cover, 'features': features, 'chapters': references,
                     'expectedImport': 'ready_with_metadata_fallback' if missing_title or missing_author else 'ready',
                     'conformance': 'synthetic import-profile input; not EPUBCheck certified; absent mandatory metadata is intentional',
                     'rights': RIGHTS}


def hostile_cases(base):
    yield 'not-zip', b'Not an EPUB archive.', 'reject_container'
    for case, name in [('traversal', '../escape.txt'), ('absolute', '/escape.txt'), ('backslash', 'OEBPS\\escape.txt')]:
        data = archive(base + [(name, 'never extract')])
        if case == 'backslash':
            # ZipInfo normalizes the host separator on Windows. Mutate both
            # headers explicitly so this really is a hostile backslash name.
            data = data.replace(b'OEBPS/escape.txt', b'OEBPS\\escape.txt')
        yield case, data, 'reject_archive'
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', UserWarning)
        yield 'duplicate-entry', archive(base + [('OEBPS/chapter1.xhtml', 'duplicate')]), 'reject_archive'
    data = bytearray(archive(base));pos = data.index(b'PK\x01\x02')
    data[6:8] = struct.pack('<H', 1);data[pos + 8:pos + 10] = struct.pack('<H', 1)
    yield 'encrypted-flag', bytes(data), 'reject_archive'
    data = bytearray(archive(base));data[38] ^= 1
    yield 'crc-mismatch', bytes(data), 'reject_archive'
    data = bytearray(archive(base));pos = data.index(b'PK\x01\x02');data[pos + 38:pos + 42] = struct.pack('<I', (stat.S_IFLNK | 0o777) << 16)
    yield 'symlink-entry', bytes(data), 'reject_archive'
    data = bytearray(archive(base));pos = data.index(b'PK\x01\x02');data[pos + 42:pos + 46] = struct.pack('<I', len(data) + 100)
    yield 'offset-outside-source', bytes(data), 'reject_archive'
    yield 'truncated-eocd', archive(base)[:-12], 'reject_archive'
    data = bytearray(archive(base));pos = data.rindex(b'PK\x05\x06');data[pos + 10:pos + 12] = b'\xff\xff'
    yield 'zip64-sentinel-without-index', bytes(data), 'reject_archive'
    yield 'expansion-ratio', archive(base + [('OEBPS/bomb.txt', 'A' * 262144)]), 'reject_expansion_ratio'
    yield 'too-many-entries', archive(base + [(f'extra/{n}.txt', '') for n in range(5001)]), 'reject_entry_count'
    yield 'entry-name-too-long', archive(base + [('x' * 1025, '')]), 'reject_entry_name'
    changes = {
        'xml-depth': ('<div>' * 129 + 'Texte' + '</div>' * 129, 'reject_xml_depth'),
        'xml-attributes': ('<p ' + ' '.join(f'a{n}="v"' for n in range(65)) + '>Texte</p>', 'reject_xml_attribute_count'),
        'xml-huge-attribute': ('<p title="' + 'A' * 16385 + '">Texte</p>', 'reject_xml_attribute_size'),
        'active-content': ('<script>fetch("https://example.invalid/")</script><p onclick="alert(1)">Texte sûr.</p>', 'filter_active_content_no_execution_or_network'),
        'unsafe-link': ('<p><a href="javascript:alert(1)">Texte sûr.</a></p>', 'disable_unsafe_link_keep_text'),
    }
    for case, (body, expected) in changes.items():
        entries = [(n, xhtml(body, 'fr') if n == 'OEBPS/chapter1.xhtml' else d) for n, d in base]
        yield case, archive(entries), expected
    xml = '<?xml version="1.0"?><!DOCTYPE html [<!ENTITY remote SYSTEM "https://example.invalid/never">]><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Fixture</title></head><body><p>&remote;</p></body></html>'
    yield 'external-entity', archive([(n, xml if n == 'OEBPS/chapter1.xhtml' else d) for n, d in base]), 'reject_dtd_internal_subset_no_network'
    for case, css, expected in [('remote-css', '@import "https://example.invalid/never"; p { background: url(https://example.invalid/never); }', 'ignore_remote_css_no_network'), ('css-selector-count', ','.join(f'.x{n}' for n in range(5001)) + '{color:red}', 'reject_css_selector_budget')]:
        yield case, archive([(n, css if n == 'OEBPS/style.css' else d) for n, d in base]), expected
    yield 'oversized-image-dimensions', archive([(n, png(8193, 1) if n == 'OEBPS/cover.png' else d) for n, d in base]), 'placeholder_image_keep_main_text'
    yield 'corrupt-image', archive([(n, b'not an image' if n == 'OEBPS/cover.png' else d) for n, d in base]), 'placeholder_image_keep_main_text'
    yield 'metadata-document-too-large', archive([(n, '<?xml version="1.0"?>' + ' ' * (2 * 1024 * 1024) if n == 'OEBPS/content.opf' else d) for n, d in base]), 'reject_metadata_or_expansion_budget'


def put(path, data, verify=False):
    if not path.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError('Refusing output outside EPUB validation workspace')
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ValueError('Refusing symlink output: ' + str(path))
    if path.exists():
        if path.read_bytes() != data:
            raise ValueError('Existing output differs; preserve it and choose a new directory: ' + str(path))
        return
    if verify:
        raise ValueError('Missing expected fixture: ' + str(path))
    with path.open('xb') as handle:
        handle.write(data)


def generate(output, verify=False):
    # This script writes only its fixed laboratory subtree, not a caller-supplied path.
    allowed = (ROOT / 'private').resolve()
    if not output.resolve().is_relative_to(allowed) or output.is_symlink():
        raise ValueError('Output must stay inside validation/epub/private')
    books, hostile = [], []
    for index in range(1, 11):
        entries, reference = make_book(index)
        data = archive(entries)
        file = output / (reference['id'] + '.epub')
        put(file, data, verify)
        reference.update(path=file.relative_to(ROOT).as_posix(), bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
        reference['referenceSha256'] = hashlib.sha256(json.dumps(reference['chapters'], ensure_ascii=False, sort_keys=True).encode()).hexdigest()
        books.append(reference)
    for case, data, expected in hostile_cases(make_book(1)[0]):
        file = output / 'hostile' / (case + '.epub')
        put(file, data, verify)
        hostile.append({'id': case, 'path': file.relative_to(ROOT).as_posix(), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'expectedPolicy': expected, 'actualImporterResult': 'not_evaluated'})
    result = {'schemaVersion': 1, 'date': '2026-11-14', 'rights': RIGHTS,
              'rightsUrl': 'https://creativecommons.org/publicdomain/zero/1.0/',
              'generator': 'scripts/generate-fixtures.py', 'pythonVersion': platform.python_version(),
              'zlibVersion': zlib.ZLIB_VERSION, 'purpose': 'Authored content references; no importer, renderer, EPUBCheck or TTS success inferred.',
              'books': books, 'hostile': hostile,
              'futureOnDemandCases': ['source >100 MiB', 'inflation >500 MiB', 'entry >50 MiB', 'central directory >8 MiB', 'valid ZIP64 boundaries', 'overlapping records', 'forged compressed sizes', 'deadline/cancellation', 'truncated JPEG and JPEG dimensions', 'CSS selector complexity', 'giant XML token', 'protected/fixed-layout/missing-spine package']}
    manifest = ROOT / 'corpus-manifest.json'
    put(manifest, (json.dumps(result, ensure_ascii=False, indent=2) + '\n').encode('utf-8'), verify)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true', help='Regenerate in memory and compare with existing exact files')
    args = parser.parse_args()
    if args.verify and not (ROOT / 'corpus-manifest.json').is_file():
        parser.error('Generate the corpus first')
    result = generate(ROOT / 'private/corpus', args.verify)
    print(json.dumps({'books': len(result['books']), 'hostileCases': len(result['hostile']), 'mode': 'exact regeneration' if args.verify else 'generated or verified'}))
