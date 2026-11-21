import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:xml/xml.dart' show XmlDefaultEntityMapping;
import 'package:xml/xml_events.dart';

import '../../domain/books.dart';
import 'epub_limits.dart';
import 'bounded_xml_job.dart';
import 'safe_css.dart';

part 'streaming_projection.dart';

class ProjectionResult {
  ProjectionResult(
    List<BookBlock> blocks,
    Map<String, BookLocator> anchors,
    Set<String> warnings, [
    Map<String, String> imageSources = const {},
    Map<String, int> usage = const {},
  ]) : blocks = List.unmodifiable(blocks),
       anchors = Map.unmodifiable(anchors),
       warnings = Set.unmodifiable(warnings),
       imageSources = Map.unmodifiable(imageSources),
       usage = Map.unmodifiable(usage);
  final List<BookBlock> blocks;
  final Map<String, BookLocator> anchors;
  final Set<String> warnings;
  final Map<String, String> imageSources;
  final Map<String, int> usage;
}

/// A single bounded resource, never a public importer or UI source.
/// XhtmlProjector and the package parser enforce book-wide totals; the importer
/// persists canonical blocks in bounded batches.
abstract final class EpubProjectionWorker {
  static Future<List<String>> linkedStyles(
    String source, {
    bool Function()? cancelled,
  }) => BoundedXmlJob.run(source, _linkedStyles, cancelled: cancelled);

  static Future<List<String>> _linkedStyles(String source) async {
    final links = <String>[];
    final budget = _Budget();
    await for (final batch in _guard(source, budget).transform(
      XmlEventDecoder(
        entityMapping: const XmlDefaultEntityMapping.html(),
        validateDocument: true,
        validateNesting: true,
        validateNamespace: true,
      ),
    )) {
      for (final e in batch) {
        if (e is XmlStartElementEvent && e.localName == 'link') {
          final attrs = {for (final a in e.attributes) a.name: a.value};
          if ((attrs['rel'] ?? '')
                  .split(RegExp(r'[ \t\r\n]+'))
                  .contains('stylesheet') &&
              attrs['href'] != null) {
            links.add(attrs['href']!);
          }
          if (links.length > 5000) {
            throw const BookFailure(BookError.limitExceeded);
          }
        }
      }
    }
    return links;
  }

  /// Shared lexical preflight for bounded package metadata, before XML allocation.
  static Future<int> validateMetadataXml(String source) async {
    if (utf8.encode(source).length > EpubLimits.metadataDocumentBytes) {
      throw const BookFailure(BookError.limitExceeded);
    }
    final budget = _Budget();
    await for (final _ in _guard(source, budget).transform(
      XmlEventDecoder(
        entityMapping: const XmlDefaultEntityMapping.html(),
        validateDocument: true,
        validateNesting: true,
        validateNamespace: true,
      ),
    )) {
      budget.check();
    }
    return budget.elements;
  }

  static Future<ProjectionResult> projectString({
    required ContentKey key,
    required int chapterOrdinal,
    required String xhtml,
    List<String> localStyles = const [],
  }) async {
    return start(
      key: key,
      chapterOrdinal: chapterOrdinal,
      xhtml: xhtml,
      localStyles: localStyles,
    ).result;
  }

  static ProjectionJob start({
    required ContentKey key,
    required int chapterOrdinal,
    required String xhtml,
    List<String> localStyles = const [],
  }) {
    if (chapterOrdinal < 0 || xhtml.length > EpubLimits.entryBytes) {
      throw const BookFailure(BookError.limitExceeded);
    }
    return ProjectionJob._(key, chapterOrdinal, xhtml, localStyles);
  }
}

class ProjectionJob {
  ProjectionJob._(
    ContentKey key,
    int chapter,
    String source,
    List<String> styles,
  ) {
    _timer = Timer(EpubLimits.analysisDeadline, () {
      _stop(BookError.deadlineExceeded);
    });
    _responses.listen((Object? response) {
      if (_stopping || _completion.isCompleted) return;
      if (response is ProjectionResult) {
        _completion.complete(response);
        _close();
      } else {
        _completion.completeError(
          BookFailure(
            response is BookError ? response : BookError.invalidContent,
          ),
        );
        _close();
      }
    });
    _errors.listen((Object? _) {
      if (!_stopping && !_completion.isCompleted) {
        _completion.completeError(const BookFailure(BookError.invalidContent));
        _close();
      }
    });
    Isolate.spawn(
      _runProjection,
      [_responses.sendPort, key, chapter, source, styles],
      onError: _errors.sendPort,
      errorsAreFatal: true,
    ).then(
      (worker) {
        if (_completion.isCompleted) {
          worker.kill(priority: Isolate.immediate);
        } else {
          _worker = worker;
        }
      },
      onError: (Object _) {
        if (!_completion.isCompleted && !_stopping) {
          _completion.completeError(
            const BookFailure(BookError.invalidContent),
          );
          _close();
        }
      },
    );
  }
  final _completion = Completer<ProjectionResult>();
  final _responses = ReceivePort(), _errors = ReceivePort();
  late final Timer _timer;
  Isolate? _worker;
  bool _stopping = false;
  Future<void>? _stopFuture;
  Future<ProjectionResult> get result => _completion.future;
  Future<void> cancel() => _stop(BookError.cancelled);
  Future<void> _stop(BookError reason) {
    if (_completion.isCompleted) return Future.value();
    if (_stopFuture != null) return _stopFuture!;
    _stopping = true;
    _timer.cancel();
    return _stopFuture = Future<void>.delayed(EpubLimits.cancellationGrace, () {
      _worker?.kill(priority: Isolate.immediate);
      if (!_completion.isCompleted) {
        _completion.completeError(BookFailure(reason));
      }
      _close();
    });
  }

  void _close() {
    _timer.cancel();
    _worker?.kill(priority: Isolate.immediate);
    _responses.close();
    _errors.close();
  }
}

Future<void> _runProjection(List<Object> args) async {
  final port = args[0] as SendPort;
  try {
    port.send(
      await _project(
        args[1] as ContentKey,
        args[2] as int,
        args[3] as String,
        args[4] as List<String>,
      ),
    );
  } on BookFailure catch (error) {
    port.send(error.code);
  } catch (_) {
    port.send(BookError.invalidContent);
  }
}

class _Budget {
  final clock = Stopwatch()..start();
  int elements = 0;
  void check() {
    if (clock.elapsed > EpubLimits.analysisDeadline) {
      throw const BookFailure(BookError.deadlineExceeded);
    }
  }
}

/// Guard emits only bounded text chunks or complete validated markup tokens.
/// No entity, external subset, attribute or deep stack reaches the XML allocator first.
Stream<String> _guard(String source, _Budget budget) async* {
  final text = StringBuffer(), token = StringBuffer(), entity = StringBuffer();
  final cdataText = StringBuffer();
  final cdataTail = <String>[];
  var cdata = false;
  var markup = false, quote = '', prefix = '', tail = '', entityOpen = false;
  var markupBytes = 0, sourceBytes = 0, depth = 0, count = 0;
  const mapping = XmlDefaultEntityMapping.html();
  String literal(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  void validateToken(String value) {
    if (value.startsWith('<!DOCTYPE')) {
      final declaration = value.replaceAll(RegExp(r'\s+'), ' ');
      final simple = RegExp(r'^<!DOCTYPE html\s*>$').hasMatch(declaration);
      final xhtml = RegExp(
        r'^<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1\.0 (Strict|Transitional|Frameset)//EN" "https?://www\.w3\.org/TR/xhtml1/DTD/xhtml1-(strict|transitional|frameset)\.dtd"\s*>$',
      ).hasMatch(declaration);
      final xhtml11 = RegExp(
        r'^<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1\.1//EN" "https?://www\.w3\.org/TR/xhtml11/DTD/xhtml11\.dtd"\s*>$',
      ).hasMatch(declaration);
      final ncx = RegExp(
        r'^<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "https?://www\.daisy\.org/z3986/2005/ncx-2005-1\.dtd"\s*>$',
      ).hasMatch(declaration);
      if (!simple && !xhtml && !xhtml11 && !ncx) {
        throw const BookFailure(BookError.unsupportedContent);
      }
      return;
    }
    if (value.startsWith('<!--') ||
        value.startsWith('<![CDATA[') ||
        value.startsWith('<?')) {
      return;
    }
    if (value.startsWith('<!')) {
      throw const BookFailure(BookError.invalidContent);
    }
    if (value.startsWith('</')) {
      depth--;
    } else {
      final attrs = RegExp(r'''[^\s=<>]+\s*=\s*(["'])([\s\S]*?)\1''')
          .allMatches(value)
          .toList();
      if (attrs.length > EpubLimits.attributes ||
          attrs.any(
            (a) => utf8.encode(a[2]!).length > EpubLimits.attributeBytes,
          )) {
        throw const BookFailure(BookError.limitExceeded);
      }
      if (!value.endsWith('/>')) depth++;
      if (++budget.elements > EpubLimits.xmlElements) {
        throw const BookFailure(BookError.limitExceeded);
      }
    }
    if (depth < 0) throw const BookFailure(BookError.invalidContent);
    if (depth > EpubLimits.xmlDepth) {
      throw const BookFailure(BookError.limitExceeded);
    }
  }

  for (final rune in _xmlRunes(source)) {
    if (++count % 1024 == 0) budget.check();
    final c = String.fromCharCode(rune);
    final bytes = rune <= 127
        ? 1
        : rune <= 2047
        ? 2
        : rune <= 65535
        ? 3
        : 4;
    sourceBytes += bytes;
    if (sourceBytes > EpubLimits.entryBytes) {
      throw const BookFailure(BookError.limitExceeded);
    }
    if (cdata) {
      cdataTail.add(c);
      if (cdataTail.length == 3 &&
          cdataTail[0] == ']' &&
          cdataTail[1] == ']' &&
          cdataTail[2] == '>') {
        cdata = false;
        cdataTail.clear();
        if (cdataText.isNotEmpty) {
          yield literal(cdataText.toString());
          cdataText.clear();
        }
      } else {
        while (cdataTail.length > 2) {
          cdataText.write(cdataTail.removeAt(0));
        }
        if (cdataText.length >= 16384) {
          yield literal(cdataText.toString());
          cdataText.clear();
        }
      }
      continue;
    }
    if (!markup && c == '<') {
      if (entityOpen) throw const BookFailure(BookError.invalidContent);
      if (text.isNotEmpty) {
        yield text.toString();
        text.clear();
      }
      markup = true;
      markupBytes = 0;
      prefix = '';
      tail = '';
      quote = '';
    }
    if (markup) {
      markupBytes += bytes;
      if (markupBytes > EpubLimits.markupBytes) {
        throw const BookFailure(BookError.limitExceeded);
      }
      token.write(c);
      if (prefix.length < 10) prefix += c;
      if (prefix == '<![CDATA[') {
        if (depth == 0) throw const BookFailure(BookError.invalidContent);
        cdata = true;
        markup = false;
        token.clear();
        prefix = '';
        tail = '';
        continue;
      }
      tail = (tail + c);
      if (tail.length > 3) tail = tail.substring(tail.length - 3);
      final special =
          prefix.startsWith('<!--') || prefix.startsWith('<![CDATA[');
      if (prefix.startsWith('<!DOCTYPE') && c == '[') {
        throw const BookFailure(BookError.unsupportedContent);
      }
      if (!special && (c == '"' || c == "'")) {
        quote = quote == c
            ? ''
            : quote.isEmpty
            ? c
            : quote;
      }
      final end = prefix.startsWith('<!--')
          ? tail == '-->'
          : prefix.startsWith('<![CDATA[')
          ? tail == ']]>'
          : prefix.startsWith('<?')
          ? tail.endsWith('?>')
          : c == '>' && quote.isEmpty;
      if (end) {
        final value = token.toString();
        token.clear();
        markup = false;
        validateToken(value);
        // Validate references in attributes before mapping. Comments/CDATA are literal.
        if (!special) _checkEntities(value);
        yield value;
      }
    } else {
      if (entityOpen) {
        if (c == ';') {
          final name = entity.toString();
          entity.clear();
          entityOpen = false;
          if (!_validEntity(name, mapping)) {
            throw const BookFailure(BookError.invalidContent);
          }
        } else {
          entity.write(c);
          if (entity.length > EpubLimits.markupBytes) {
            throw const BookFailure(BookError.limitExceeded);
          }
        }
      } else if (c == '&') {
        entityOpen = true;
      }
      text.write(c);
      if (text.length >= 16384 && !entityOpen) {
        yield text.toString();
        text.clear();
      }
    }
  }
  if (markup || cdata || entityOpen || depth != 0) {
    throw const BookFailure(BookError.invalidContent);
  }
  if (text.isNotEmpty) yield text.toString();
}

bool _validEntity(String name, XmlDefaultEntityMapping mapping) {
  if (name.startsWith('#')) {
    if (!RegExp(r'^#(?:[0-9]+|x[0-9a-fA-F]+)$').hasMatch(name)) return false;
    final hex = name.length > 2 && (name[1] == 'x' || name[1] == 'X');
    final value = int.tryParse(
      name.substring(hex ? 2 : 1),
      radix: hex ? 16 : 10,
    );
    if (value == null || !_xmlScalar(value)) return false;
  }
  final value = mapping.decodeEntity(name);
  if (value == null) return false;
  for (final r in value.runes) {
    if (!(r == 9 ||
        r == 10 ||
        r == 13 ||
        r >= 32 && r <= 0xd7ff ||
        r >= 0xe000 && r <= 0xfffd ||
        r >= 0x10000 && r <= 0x10ffff)) {
      return false;
    }
  }
  return true;
}

bool _xmlScalar(int value) =>
    value == 9 ||
    value == 10 ||
    value == 13 ||
    value >= 32 && value <= 0xd7ff ||
    value >= 0xe000 && value <= 0xfffd ||
    value >= 0x10000 && value <= 0x10ffff;

Iterable<int> _xmlRunes(String source) sync* {
  for (var i = 0; i < source.length; i++) {
    var value = source.codeUnitAt(i);
    if (value >= 0xd800 && value <= 0xdbff) {
      if (++i >= source.length) {
        throw const BookFailure(BookError.invalidContent);
      }
      final low = source.codeUnitAt(i);
      if (low < 0xdc00 || low > 0xdfff) {
        throw const BookFailure(BookError.invalidContent);
      }
      value = 0x10000 + ((value - 0xd800) << 10) + (low - 0xdc00);
    }
    if (!_xmlScalar(value)) throw const BookFailure(BookError.invalidContent);
    yield value;
  }
}

void _checkEntities(String text) {
  var start = text.indexOf('&');
  while (start >= 0) {
    final end = text.indexOf(';', start + 1);
    if (end < 0 ||
        !_validEntity(
          text.substring(start + 1, end),
          const XmlDefaultEntityMapping.html(),
        )) {
      throw const BookFailure(BookError.invalidContent);
    }
    start = text.indexOf('&', end + 1);
  }
}
