import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/epub/epub_package_parser.dart';

class Archive implements EpubArchive {
  Archive(this.data);
  final Map<String, String> data;
  final reads = <String>[];
  @override
  List<String> get names => data.keys.toList();
  @override
  Future<Uint8List> read(String name, {required int maxBytes}) async {
    reads.add(name);
    final value = utf8.encode(
      data[name] ?? (throw const BookFailure(BookError.invalidArchive)),
    );
    if (value.length > maxBytes) {
      throw const BookFailure(BookError.limitExceeded);
    }
    return Uint8List.fromList(value);
  }
}

Map<String, String> fixture({
  String extra = '',
  String spine = '<itemref idref="ch"/>',
}) => {
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
  'OPS/book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Mon &amp; livre</dc:title><dc:creator>Auteur</dc:creator><dc:language>en</dc:language>$extra</metadata><manifest><item id="ch" href="text/ch.xhtml" media-type="application/xhtml+xml"/></manifest><spine>$spine</spine></package>',
  'OPS/text/ch.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>English book.</p></body></html>',
};
void main() {
  test(
    'EPUB3 metadata, relative spine and visual English remain source values',
    () async {
      final book = await EpubPackageParser(Archive(fixture())).parse();
      expect(book.title, 'Mon & livre');
      expect(book.languages, ['en']);
      expect(book.spine.single.href, 'OPS/text/ch.xhtml');
    },
  );
  test('metadata replacement does not depend on a voice', () async {
    final f = fixture();
    f['OPS/book.opf'] = f['OPS/book.opf']!.replaceAll(
      '<dc:title>Mon &amp; livre</dc:title>',
      '',
    );
    expect(
      (await EpubPackageParser(Archive(f)).parse()).title,
      'Livre sans titre',
    );
  });
  test('unsafe hrefs and unusable spine fail', () async {
    for (final href in [
      '../../escape.xhtml',
      'https://example.org/ch.xhtml',
      '%2e%2e/%2e%2e/out',
      'text%252fch.xhtml',
      'text\\ch.xhtml',
    ]) {
      final f = fixture();
      f['OPS/book.opf'] = f['OPS/book.opf']!.replaceAll('text/ch.xhtml', href);
      await expectLater(
        EpubPackageParser(Archive(f)).parse(),
        throwsA(isA<BookFailure>()),
      );
    }
    await expectLater(
      EpubPackageParser(Archive(fixture(spine: '<itemref idref="missing"/>')))
          .parse(),
      throwsA(isA<BookFailure>()),
    );
  });
  test(
    'fixed layout, text encryption and external entities are refused',
    () async {
      await expectLater(
        EpubPackageParser(
          Archive(
            fixture(
              extra: '<meta property="rendition:layout">pre-paginated</meta>',
            ),
          ),
        ).parse(),
        throwsA(isA<BookFailure>()),
      );
      final f = fixture();
      f['META-INF/encryption.xml'] = '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:e="http://www.w3.org/2001/04/xmlenc#"><e:EncryptedData><e:CipherData><e:CipherReference URI="OPS/text/ch.xhtml"/></e:CipherData></e:EncryptedData></encryption>';
      await expectLater(
        EpubPackageParser(Archive(f)).parse(),
        throwsA(isA<BookFailure>()),
      );
      f.remove('META-INF/encryption.xml');
      f['META-INF/container.xml'] = '<!DOCTYPE container [<!ENTITY x SYSTEM "file:///private">]><container>&x;</container>';
      await expectLater(
        EpubPackageParser(Archive(f)).parse(),
        throwsA(isA<BookFailure>()),
      );
    },
  );
  test('resolver accepts legitimate parents but never decodes twice', () {
    expect(
      resolveEpubReference('OPS/text/ch.xhtml', '../images/a.png'),
      'OPS/images/a.png',
    );
    expect(
      () => resolveEpubReference('OPS/ch.xhtml', '%252e%252e/x'),
      throwsA(isA<BookFailure>()),
    );
  });
  test(
    'missing optional font falls back without hiding usable main text',
    () async {
      final f = fixture();
      f['OPS/book.opf'] = f['OPS/book.opf']!.replaceFirst(
        '</manifest>',
        '<item id="font" href="fonts/missing.ttf" media-type="font/ttf"/></manifest>',
      );
      expect(
        (await EpubPackageParser(Archive(f)).parse()).spine.single.href,
        'OPS/text/ch.xhtml',
      );
    },
  );
  test('EPUB2 NCX recognized public declaration is parsed without external resolution', () async {
    final f = fixture();
    f['OPS/book.opf'] = f['OPS/book.opf']!
        .replaceFirst('version="3.0"', 'version="2.0"')
        .replaceFirst(
          '</manifest>',
          '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>',
        )
        .replaceFirst('<spine>', '<spine toc="ncx">');
    f['OPS/toc.ncx'] = '<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd"><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap><navPoint><navLabel><text>Chapitre NCX</text></navLabel><content src="text/ch.xhtml#passage"/></navPoint></navMap></ncx>';
    final package = await EpubPackageParser(Archive(f)).parse();
    expect(package.chapterTitles['OPS/text/ch.xhtml'], 'Chapitre NCX');
  });
}
