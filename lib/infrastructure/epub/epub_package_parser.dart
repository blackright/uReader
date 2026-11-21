import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../../domain/books.dart';
import 'epub_limits.dart';
import 'bounded_xml_job.dart';
import 'epub_projection_worker.dart';

/// Implementations must complete ZIP size/CRC verification before returning bytes.
/// Unused entries must also be drained/verified before any book becomes ready.
abstract interface class EpubArchive {
  List<String> get names;
  Future<Uint8List> read(String name, {required int maxBytes});
}

abstract interface class VerifiedEpubArchive implements EpubArchive {
  Future<void> verifyRemaining();
  Future<void> close();
}

String resolveEpubReference(String base, String reference) {
  if (reference.isEmpty ||
      reference.contains(r'\') ||
      reference.contains(RegExp(r'[\x00-\x20\x7f]'))) {
    throw const BookFailure(BookError.unsafeLink);
  }
  Uri uri;
  try {
    uri = Uri.parse(reference);
  } catch (_) {
    throw const BookFailure(BookError.unsafeLink);
  }
  if (uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.path.startsWith('/')) {
    throw const BookFailure(BookError.unsafeLink);
  }
  String path;
  try {
    path = Uri.decodeComponent(uri.path);
  } catch (_) {
    throw const BookFailure(BookError.unsafeLink);
  }
  // Percent escapes surviving the one decode are ambiguous and are refused.
  if (path.contains('%') ||
      path.contains(r'\') ||
      path.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw const BookFailure(BookError.unsafeLink);
  }
  if (path.isEmpty) return base;
  final parts = base.split('/')..removeLast();
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isEmpty) throw const BookFailure(BookError.unsafeLink);
      parts.removeLast();
    } else {
      if (part.contains(':')) throw const BookFailure(BookError.unsafeLink);
      parts.add(part);
    }
  }
  if (parts.isEmpty) throw const BookFailure(BookError.unsafeLink);
  return parts.join('/');
}

const _fontTypes = {
  'application/vnd.ms-opentype',
  'application/font-sfnt',
  'font/otf',
  'font/ttf',
  'font/woff',
  'font/woff2',
  'application/font-woff',
  'application/x-font-woff',
  'application/x-font-ttf',
  'application/x-font-opentype',
};

class EpubItem {
  const EpubItem(this.id, this.href, this.mediaType, this.properties);
  final String id, href, mediaType;
  final Set<String> properties;
}

class EpubPackage {
  EpubPackage({
    required this.title,
    required this.authors,
    required this.languages,
    required this.items,
    required this.spine,
    required this.chapterTitles,
    required this.cover,
    this.metadataElements = 0,
  });
  final String title;
  final List<String> authors, languages;
  final List<EpubItem> items, spine;
  final Map<String, String> chapterTitles;
  final String? cover;
  final int metadataElements;
}

/// Instantiate/run on an import worker isolate. Metadata DOMs are individually
/// capped at 2 MiB after lexical preflight; XHTML remains event-stream projected.
class EpubPackageParser {
  EpubPackageParser(
    this.archive, {
    bool Function()? cancelled,
    this.fallbackTitle,
  }) : _cancelled = cancelled ?? (() => false);
  final EpubArchive archive;
  final String? fallbackTitle;
  final bool Function() _cancelled;
  final _clock = Stopwatch()..start();
  int _metadataBytes = 0, _metadataElements = 0;
  void _check() {
    if (_cancelled()) throw const BookFailure(BookError.cancelled);
    if (_clock.elapsed > EpubLimits.analysisDeadline) {
      throw const BookFailure(BookError.deadlineExceeded);
    }
  }

  Future<XmlDocument> _xml(String name) async {
    _check();
    final bytes = await archive.read(
      name,
      maxBytes: EpubLimits.metadataDocumentBytes,
    );
    _metadataBytes += bytes.length;
    if (bytes.length > EpubLimits.metadataDocumentBytes ||
        _metadataBytes > EpubLimits.metadataTotalBytes) {
      throw const BookFailure(BookError.limitExceeded);
    }
    try {
      final source = utf8.decode(bytes);
      final document = await BoundedXmlJob.run(
        source,
        _validatedMetadata,
        cancelled: _cancelled,
      );
      _check();
      _metadataElements += document.elements;
      if (_metadataElements > EpubLimits.xmlElements) {
        throw const BookFailure(BookError.limitExceeded);
      }
      return document.document;
    } on BookFailure {
      rethrow;
    } catch (_) {
      throw const BookFailure(BookError.invalidContent);
    }
  }

  Iterable<XmlElement> _children(XmlElement node, String local) =>
      node.childElements.where(
        (e) =>
            e.name.local == local &&
            e.namespaceUri == 'http://www.idpf.org/2007/opf',
      );
  List<String> _tokens(String value) => value
      .split(RegExp(r'[\x09\x0a\x0c\x0d\x20]+'))
      .where((s) => s.isNotEmpty)
      .toList();

  String _fallback() {
    var title = (fallbackTitle ?? '')
        .split(RegExp(r'[/\\]'))
        .last
        .replaceFirst(RegExp(r'\.epub$', caseSensitive: false), '')
        .trim();
    return title.isEmpty ? 'Livre sans titre' : title;
  }

  Future<EpubPackage> parse() async {
    _check();
    final names = archive.names.toSet();
    if (names.length != archive.names.length ||
        names.length > EpubLimits.entries ||
        !names.contains('mimetype') ||
        !names.contains('META-INF/container.xml')) {
      throw const BookFailure(BookError.invalidArchive);
    }
    if (utf8.decode(
          await archive.read('mimetype', maxBytes: 64),
          allowMalformed: true,
        ) !=
        'application/epub+zip') {
      throw const BookFailure(BookError.invalidArchive);
    }
    final container = await _xml('META-INF/container.xml');
    if (container.rootElement.name.local != 'container' ||
        container.rootElement.namespaceUri !=
            'urn:oasis:names:tc:opendocument:xmlns:container') {
      throw const BookFailure(BookError.invalidArchive);
    }
    final roots = container
        .findAllElements(
          'rootfile',
          namespaceUri: 'urn:oasis:names:tc:opendocument:xmlns:container',
        )
        .where(
          (e) =>
              e.getAttribute('media-type') == 'application/oebps-package+xml',
        );
    if (roots.isEmpty) throw const BookFailure(BookError.invalidArchive);
    final rawPath = roots.first.getAttribute('full-path') ?? '';
    final opf = resolveEpubReference('root', rawPath);
    if (opf != rawPath || !names.contains(opf)) {
      throw const BookFailure(BookError.invalidArchive);
    }
    final package = (await _xml(opf)).rootElement;
    if (package.name.local != 'package' ||
        package.namespaceUri != 'http://www.idpf.org/2007/opf' ||
        ![
          '2.0',
          '3.0',
          '3.1',
          '3.2',
          '3.3',
        ].contains(package.getAttribute('version'))) {
      throw const BookFailure(BookError.unsupportedFormat);
    }
    final metadata = _children(package, 'metadata').toList(),
        manifests = _children(package, 'manifest').toList(),
        spines = _children(package, 'spine').toList();
    if (metadata.length != 1 || manifests.length != 1 || spines.length != 1) {
      throw const BookFailure(BookError.invalidArchive);
    }
    final meta = metadata.single;
    for (final element in meta.childElements) {
      if (element.name.local == 'meta' &&
          element.getAttribute('property') == 'rendition:layout' &&
          element.innerText.trim() == 'pre-paginated') {
        throw const BookFailure(BookError.fixedLayoutUnsupported);
      }
      if (element.name.local == 'meta' &&
          element.getAttribute('name') == 'fixed-layout' &&
          element.getAttribute('content') == 'true') {
        throw const BookFailure(BookError.fixedLayoutUnsupported);
      }
    }
    List<String> dc(String local) => meta.childElements
        .where(
          (e) =>
              e.name.local == local &&
              e.namespaceUri == 'http://purl.org/dc/elements/1.1/',
        )
        .map((e) => e.innerText.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final items = <EpubItem>[], ids = <String>{}, hrefs = <String>{};
    for (final element in _children(manifests.single, 'item')) {
      _check();
      final id = element.getAttribute('id') ?? '',
          type = element.getAttribute('media-type') ?? '';
      final href = resolveEpubReference(
        opf,
        element.getAttribute('href') ?? '',
      );
      if (id.isEmpty ||
          !ids.add(id) ||
          !hrefs.add(href) ||
          (!names.contains(href) && !_fontTypes.contains(type))) {
        throw const BookFailure(BookError.invalidArchive);
      }
      items.add(
        EpubItem(
          id,
          href,
          type,
          Set.unmodifiable(_tokens(element.getAttribute('properties') ?? '')),
        ),
      );
    }
    final byId = {for (final i in items) i.id: i};
    final spine = <EpubItem>[];
    for (final element in _children(spines.single, 'itemref')) {
      if (element.getAttribute('linear') == 'no') continue;
      final item = byId[element.getAttribute('idref')];
      if (item == null) throw const BookFailure(BookError.invalidArchive);
      if (item.mediaType != 'application/xhtml+xml' ||
          item.properties.contains('rendition:layout-pre-paginated')) {
        throw const BookFailure(BookError.fixedLayoutUnsupported);
      }
      if (spine.contains(item)) {
        throw const BookFailure(BookError.invalidArchive);
      }
      spine.add(item);
    }
    if (spine.isEmpty) throw const BookFailure(BookError.invalidContent);
    if (names.contains('META-INF/encryption.xml')) {
      final encryption = await _xml('META-INF/encryption.xml');
      for (final reference in encryption.findAllElements(
        'CipherReference',
        namespaceUri: 'http://www.w3.org/2001/04/xmlenc#',
      )) {
        final href = resolveEpubReference(
          'root',
          reference.getAttribute('URI') ?? '',
        );
        final matching = items.where((i) => i.href == href).toList();
        // Only optional fonts may be ignored; encrypted text and other resources fail.
        if (matching.length != 1 ||
            ![
              'application/vnd.ms-opentype',
              'application/font-sfnt',
              'font/otf',
              'font/ttf',
              'application/x-font-ttf',
              'application/x-font-opentype',
            ].contains(matching.single.mediaType)) {
          throw const BookFailure(BookError.protectedContent);
        }
      }
    }
    final titles = <String, String>{};
    final nav = items.where((i) => i.properties.contains('nav')).toList();
    if (nav.length > 1) throw const BookFailure(BookError.invalidArchive);
    if (nav.isNotEmpty) {
      final item = nav.single;
      final doc = await _xml(item.href);
      for (final a in doc.findAllElements(
        'a',
        namespaceUri: 'http://www.w3.org/1999/xhtml',
      )) {
        final ref = a.getAttribute('href');
        if (ref == null) continue;
        final target = resolveEpubReference(item.href, ref);
        if (a.innerText.trim().isNotEmpty) {
          titles.putIfAbsent(target, () => a.innerText.trim());
        }
      }
    } else {
      final ncx = byId[spines.single.getAttribute('toc')];
      if (ncx != null) {
        final doc = await _xml(ncx.href);
        for (final point in doc.findAllElements(
          'navPoint',
          namespaceUri: 'http://www.daisy.org/z3986/2005/ncx/',
        )) {
          final content = point.childElements
              .where((e) => e.name.local == 'content')
              .firstOrNull;
          final label = point.childElements
              .where((e) => e.name.local == 'navLabel')
              .firstOrNull
              ?.innerText
              .trim();
          if (content != null && label != null && label.isNotEmpty) {
            titles.putIfAbsent(
              resolveEpubReference(ncx.href, content.getAttribute('src') ?? ''),
              () => label,
            );
          }
        }
      }
    }
    final propertyCover = items
        .where((i) => i.properties.contains('cover-image'))
        .firstOrNull
        ?.href;
    final title = dc('title');
    return EpubPackage(
      title: title.isEmpty ? _fallback() : title.first,
      authors: List.unmodifiable(dc('creator')),
      languages: List.unmodifiable(dc('language')),
      items: List.unmodifiable(items),
      spine: List.unmodifiable(spine),
      chapterTitles: Map.unmodifiable(titles),
      cover:
          propertyCover ??
          byId[meta.childElements
                  .where(
                    (e) =>
                        e.name.local == 'meta' &&
                        e.getAttribute('name') == 'cover',
                  )
                  .firstOrNull
                  ?.getAttribute('content')]
              ?.href,
      metadataElements: _metadataElements,
    );
  }
}

Future<({XmlDocument document, int elements})> _validatedMetadata(
  String source,
) async {
  final elements = await EpubProjectionWorker.validateMetadataXml(source);
  return (document: XmlDocument.parse(source), elements: elements);
}
