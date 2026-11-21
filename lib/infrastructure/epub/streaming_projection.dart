part of 'epub_projection_worker.dart';

const _blockTags = {
  'p',
  'pre',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'td',
  'th',
  'blockquote',
};
const _containers = {
  'html',
  'body',
  'div',
  'section',
  'article',
  'main',
  'aside',
  'header',
  'footer',
  'nav',
  'ul',
  'ol',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
};
const _excluded = {
  'head',
  'style',
  'script',
  'iframe',
  'object',
  'embed',
  'audio',
  'video',
  'svg',
  'math',
  'template',
};

class _Frame {
  _Frame(
    this.element,
    this.visibility,
    this.excluded,
    this.note,
    this.pre,
    this.strong,
    this.emphasis,
    this.link,
    this.kind,
  );
  final CssElement element;
  final ComputedVisibility visibility;
  final bool excluded, note, pre, strong, emphasis;
  final String? link;
  final BookBlockKind kind;
  bool get visible => !excluded && !visibility.displayOff && visibility.visible;
  bool get boundary =>
      _blockTags.contains(element.tag) || _containers.contains(element.tag);
}

class _Span {
  _Span(this.start, this.end, this.strong, this.emphasis, this.link);
  final int start;
  int end;
  final bool strong, emphasis;
  final String? link;
}

class _ProjectionSink {
  _ProjectionSink(this.key, this.chapter, this.budget);
  final ContentKey key;
  final int chapter;
  final _Budget budget;
  final blocks = <BookBlock>[];
  final anchors = <String, BookLocator>{};
  final images = <String, String>{};
  final warnings = <String>{};
  final pendingAnchors = <String>[];
  _CanonicalBlock? current;
  int structural = 0, units = 0;
  void anchor(String name) {
    if (current != null) {
      current!.anchor(name);
    } else {
      pendingAnchors.add(name);
    }
  }

  void bind(String name, BookBlock block, int offset) {
    if (anchors.containsKey(name)) {
      warnings.add('duplicateAnchor');
      return;
    }
    anchors[name] = BookLocator(
      key: key,
      chapterId: block.chapterId,
      blockId: block.id,
      offsetUtf16: offset,
    );
  }

  void text(String text, _Frame frame, {bool br = false}) {
    if (!frame.visible) return;
    if (current != null &&
        (current!.frame.note != frame.note ||
            current!.frame.kind != frame.kind)) {
      finish();
    }
    current ??= _CanonicalBlock(this, frame);
    if (pendingAnchors.isNotEmpty) {
      for (final name in pendingAnchors) {
        current!.anchor(name);
      }
      pendingAnchors.clear();
    }
    current!.add(text, frame, br: br);
  }

  void finish() {
    final value = current;
    current = null;
    if (value != null) {
      if (value.buffer.isEmpty && value.slice == 0) {
        pendingAnchors.addAll(value.localAnchors.map((a) => a.$1));
      } else {
        value.flush(finalSlice: true);
      }
    }
  }

  void push(BookBlock block) {
    if (blocks.length >= EpubLimits.blocks) {
      throw const BookFailure(BookError.limitExceeded);
    }
    blocks.add(block);
  }

  void image(_Frame frame) {
    finish();
    final source = frame.element.attributes['src'] ?? '';
    final uri = Uri.tryParse(source);
    final local =
        source.isNotEmpty &&
        uri != null &&
        !uri.hasScheme &&
        !uri.hasAuthority &&
        !source.contains('\\');
    final resource = 'image-${images.length}';
    if (local) {
      images[resource] = source;
    } else {
      warnings.add('remoteImageRemoved');
    }
    final block = BookBlock(
      key: key,
      chapterId: 'c$chapter',
      id: 'c$chapter-b${structural++}-s0',
      ordinal: blocks.length,
      kind: BookBlockKind.image,
      text: '',
      speechEligible: false,
      resourceId: local ? resource : null,
      alternative: frame.element.attributes['alt'],
    );
    push(block);
    for (final name in pendingAnchors) {
      bind(name, block, 0);
    }
    pendingAnchors.clear();
  }

  ProjectionResult result(SafeCss css) {
    finish();
    if (blocks.isNotEmpty) {
      for (final name in pendingAnchors) {
        bind(name, blocks.last, blocks.last.text.length);
      }
    }
    warnings.addAll(css.warnings);
    return ProjectionResult(blocks, anchors, warnings, images, {
      'elements': budget.elements,
      'cssBytes': css.byteCount,
      'selectors': css.selectorCount,
      'evaluations': css.evaluationCount,
    });
  }
}

class _CanonicalBlock {
  _CanonicalBlock(this.owner, this.frame);
  final _ProjectionSink owner;
  final _Frame frame;
  final buffer = StringBuffer();
  final spans = <_Span>[];
  final localAnchors = <(String, int)>[];
  int? number;
  int slice = 0;
  bool pendingSpace = false, previousCr = false;
  String last = '';
  void anchor(String name) => localAnchors.add((name, buffer.length));
  void append(String c, _Frame style) {
    if (owner.units + c.length > EpubLimits.canonicalUnits) {
      throw const BookFailure(BookError.limitExceeded);
    }
    if (buffer.length + c.length > EpubLimits.blockUnits) {
      flush(finalSlice: false);
    }
    number ??= owner.structural++;
    final start = buffer.length;
    buffer.write(c);
    last = c;
    owner.units += c.length;
    if (style.strong || style.emphasis || style.link != null) {
      if (spans.isNotEmpty &&
          spans.last.end == start &&
          spans.last.strong == style.strong &&
          spans.last.emphasis == style.emphasis &&
          spans.last.link == style.link) {
        spans.last.end = buffer.length;
      } else {
        if (spans.length >= EpubLimits.inlinePerBlock) {
          throw const BookFailure(BookError.limitExceeded);
        }
        spans.add(
          _Span(start, buffer.length, style.strong, style.emphasis, style.link),
        );
      }
    }
  }

  void add(String text, _Frame style, {bool br = false}) {
    var count = 0;
    for (final rune in text.runes) {
      if (++count % 1024 == 0) owner.budget.check();
      final c = String.fromCharCode(rune);
      if (br) {
        pendingSpace = false;
        append('\n', style);
        previousCr = false;
        continue;
      }
      if (frame.pre) {
        if (c == '\n' && previousCr) {
          previousCr = false;
          continue;
        }
        previousCr = c == '\r';
        append(c == '\r' ? '\n' : c, style);
        continue;
      }
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        pendingSpace = true;
        continue;
      }
      if (pendingSpace && (buffer.isNotEmpty || slice > 0) && last != '\n') {
        append(' ', style);
      }
      pendingSpace = false;
      append(c, style);
    }
  }

  void flush({required bool finalSlice}) {
    if (buffer.isEmpty) return;
    final inline = <BookInline>[];
    for (final span in spans) {
      BookLink? link;
      if (span.link != null) {
        try {
          link = BookLink(span.link!, span.start, span.end);
        } on BookFailure {
          owner.warnings.add('unsafeLinkRemoved');
        }
      }
      inline.add(
        BookInline(
          startUtf16: span.start,
          endUtf16: span.end,
          strong: span.strong,
          emphasis: span.emphasis,
          link: link,
        ),
      );
    }
    final block = BookBlock(
      key: owner.key,
      chapterId: 'c${owner.chapter}',
      id: 'c${owner.chapter}-b$number-s${slice++}',
      ordinal: owner.blocks.length,
      kind: frame.kind,
      text: buffer.toString(),
      speechEligible: !frame.note,
      inline: inline,
    );
    owner.push(block);
    final deferred = <(String, int)>[];
    for (final anchor in localAnchors) {
      if (anchor.$2 == buffer.length && !finalSlice) {
        deferred.add((anchor.$1, 0));
      } else {
        owner.bind(anchor.$1, block, anchor.$2);
      }
    }
    localAnchors
      ..clear()
      ..addAll(deferred);
    buffer.clear();
    spans.clear();
  }
}

Stream<List<XmlEvent>> _events(String source, _Budget budget) =>
    _guard(source, budget).transform(
      XmlEventDecoder(
        entityMapping: const XmlDefaultEntityMapping.html(),
        validateDocument: true,
        validateNesting: true,
        validateNamespace: true,
      ),
    );

Future<ProjectionResult> _project(
  ContentKey key,
  int chapter,
  String source,
  List<String> localStyles,
) async {
  final budget = _Budget();
  final css = SafeCss();
  try {
    for (final style in localStyles) {
      css.add(style);
    }
    // First pass gathers bounded sheets, including body styles that affect earlier nodes.
    // No XHTML DOM is retained; only the current sheet and parser ancestor stack exist.
    StringBuffer? style;
    await for (final batch in _events(source, budget)) {
      for (final event in batch) {
        budget.check();
        if (event is XmlStartElementEvent) {
          if (style != null) throw const BookFailure(BookError.invalidContent);
          if (event.localName.toLowerCase() == 'style' &&
              !event.isSelfClosing) {
            style = StringBuffer();
          }
        } else if (event is XmlEndElementEvent &&
            event.localName.toLowerCase() == 'style') {
          if (style != null) css.add(style.toString());
          style = null;
        } else if (style != null &&
            (event is XmlTextEvent || event is XmlCDATAEvent)) {
          final value = event is XmlTextEvent
              ? event.value
              : (event as XmlCDATAEvent).value;
          if (style.length + value.length > EpubLimits.cssSheetBytes) {
            throw const BookFailure(BookError.limitExceeded);
          }
          style.write(value);
        }
      }
    }
    // The element quota describes this source's logical elements, not twice that
    // count because of the two passes. The same deadline covers both passes.
    budget.elements = 0;
    final sink = _ProjectionSink(key, chapter, budget);
    final stack = <_Frame>[
      _Frame(
        CssElement('root', {}, null),
        const ComputedVisibility(),
        false,
        false,
        false,
        false,
        false,
        null,
        BookBlockKind.paragraph,
      ),
    ];
    await for (final batch in _events(source, budget)) {
      for (final event in batch) {
        budget.check();
        if (event is XmlStartElementEvent) {
          final tag = event.localName.toLowerCase(), parent = stack.last;
          final attributes = {
            for (final a in event.attributes) a.name: a.value,
          };
          final element = CssElement(
            tag,
            attributes,
            stack.length == 1 ? null : parent.element,
          );
          final excluded = parent.excluded || _excluded.contains(tag);
          final state = excluded || parent.visibility.displayOff
              ? ComputedVisibility(
                  displayOff: true,
                  visible: parent.visibility.visible,
                )
              : css.compute(element, parent.visibility);
          var semanticType = '';
          for (final attribute in attributes.entries) {
            if (!attribute.key.endsWith(':type')) continue;
            final prefix = attribute.key.substring(0, attribute.key.length - 5);
            var namespace = attributes['xmlns:$prefix'];
            if (namespace == null) {
              for (final ancestor in stack.reversed) {
                namespace = ancestor.element.attributes['xmlns:$prefix'];
                if (namespace != null) break;
              }
            }
            if (namespace == 'http://www.idpf.org/2007/ops') {
              semanticType = attribute.value;
            }
          }
          final note =
              parent.note ||
              semanticType
                  .split(RegExp(r'[ \t\r\n]+'))
                  .any(['footnote', 'endnote'].contains) ||
              ['doc-footnote', 'doc-endnote'].contains(attributes['role']);
          var kind = parent.kind;
          if (tag == 'pre') {
            kind = BookBlockKind.preformatted;
          } else if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
            kind = BookBlockKind.heading;
          } else if (tag == 'li') {
            kind = BookBlockKind.listItem;
          } else if (tag == 'blockquote') {
            kind = BookBlockKind.quote;
          } else if (tag == 'td' || tag == 'th') {
            kind = BookBlockKind.tableCell;
          } else if (tag == 'p' &&
              ![
                BookBlockKind.listItem,
                BookBlockKind.quote,
                BookBlockKind.preformatted,
              ].contains(kind)) {
            kind = BookBlockKind.paragraph;
          }
          final frame = _Frame(
            element,
            state,
            excluded,
            note,
            parent.pre || tag == 'pre',
            parent.strong || tag == 'strong' || tag == 'b',
            parent.emphasis || tag == 'em' || tag == 'i',
            tag == 'a' ? attributes['href'] : parent.link,
            kind,
          );
          if (!excluded && !state.displayOff) {
            if (frame.boundary) sink.finish();
            if (frame.visible && attributes['id'] != null) {
              sink.anchor(attributes['id']!);
            }
            if (tag == 'br') sink.text('\n', frame, br: true);
            if (tag == 'img' && frame.visible) sink.image(frame);
          }
          if (!event.isSelfClosing) stack.add(frame);
        } else if (event is XmlEndElementEvent) {
          final frame = stack.removeLast();
          if (frame.boundary &&
              !frame.excluded &&
              !frame.visibility.displayOff) {
            sink.finish();
          }
        } else if (event is XmlTextEvent) {
          sink.text(event.value, stack.last);
        } else if (event is XmlCDATAEvent) {
          sink.text(event.value, stack.last);
        }
      }
    }
    return sink.result(css);
  } on BookFailure {
    rethrow;
  } catch (_) {
    throw const BookFailure(BookError.invalidContent);
  }
}
