import '../../domain/word_alignment.dart';
import 'word_highlight_overlay.dart';

import 'package:flutter/rendering.dart';

import '../../domain/word_selection.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../../domain/paragraph_index.dart';
import '../../domain/pagination.dart';
import 'book_image_view.dart';

class MeasuredLine {
  const MeasuredLine(this.start, this.end, this.top, this.height);
  final int start, end;
  final double top, height;
}

class MeasuredReaderBlock {
  MeasuredReaderBlock(
    this.lines,
    this.height, {
    this.atomic = false,
    this.prefix = 0,
  });
  final List<MeasuredLine> lines;
  final double height, prefix;
  final bool atomic;
}

/// A layout instance is immutable. Measuring and rendering use precisely these inputs.
class ReaderLayout {
  ReaderLayout({
    required this.width,
    required this.height,
    this.fontScale = 1,
    this.lineHeight = 1.5,
    this.textScaler = TextScaler.noScaling,
    this.color = Colors.black,
    this.fontFamily = 'serif',
    this.fontRevision = 'unresolved',
    this.locale = const Locale('fr'),
    this.direction = TextDirection.ltr,
    this.margins = 20,
    this.viewInsets = EdgeInsets.zero,
  }) {
    if (!width.isFinite ||
        !height.isFinite ||
        width <= 20 ||
        height <= 0 ||
        !fontScale.isFinite ||
        fontScale <= 0 ||
        !lineHeight.isFinite ||
        lineHeight < 1 ||
        !margins.isFinite ||
        margins < 0) {
      throw const PaginationFailure(PaginationError.viewportTooSmall);
    }
  }
  final double width, height, fontScale, lineHeight, margins;
  final TextScaler textScaler;
  final Color color;
  final String fontFamily, fontRevision;
  final Locale locale;
  final TextDirection direction;
  final EdgeInsets viewInsets;
  LayoutFingerprint fingerprint(String sourceHash, int projectionVersion) =>
      _fingerprint(sourceHash, projectionVersion);

  /// Unidentified fallback fonts must never reuse an index from another session.
  LayoutFingerprint fingerprintForSession(
    String sourceHash,
    int projectionVersion,
    String sessionScope,
  ) {
    if (sessionScope.length < 16) {
      throw const PaginationFailure(PaginationError.invalidIndex);
    }
    return _fingerprint(
      sourceHash,
      projectionVersion,
      sessionScope: sessionScope,
    );
  }

  LayoutFingerprint _fingerprint(
    String sourceHash,
    int projectionVersion, {
    String? sessionScope,
  }) {
    if ((fontRevision == 'unresolved' || fontRevision.isEmpty) &&
        sessionScope == null) {
      throw const PaginationFailure(PaginationError.invalidIndex);
    }
    return LayoutFingerprint.of({
      'layoutVersion': 3,
      'sessionScope': ?sessionScope,
      'sourceHash': sourceHash,
      'projectionVersion': projectionVersion,
      'width': width,
      'height': height,
      'fontScale': fontScale,
      'lineHeight': lineHeight,
      'fontFamily': fontFamily,
      'fontRevision': fontRevision,
      'locale': locale.toLanguageTag(),
      'direction': direction.name,
      'margins': margins,
      'insets': [
        viewInsets.left,
        viewInsets.top,
        viewInsets.right,
        viewInsets.bottom,
      ],
      'scaledFontSizes': [
        for (final n in [12.0, 18.0, 22.0]) textScaler.scale(n * fontScale),
      ],
    });
  }

  bool validBoundary(String text, int offset) =>
      ParagraphIndex().validTextBoundary(text, offset);
  TextStyle style(BookBlock b) => TextStyle(
    fontFamily: b.kind == BookBlockKind.preformatted ? 'monospace' : fontFamily,
    fontSize: (b.kind == BookBlockKind.heading ? 22 : 18) * fontScale,
    height: lineHeight,
    fontWeight: b.kind == BookBlockKind.heading
        ? FontWeight.bold
        : FontWeight.normal,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );
  TextStyle get labelStyle => TextStyle(
    fontFamily: fontFamily,
    fontSize: 12 * fontScale,
    height: lineHeight,
    color: color,
  );
  double gutter(BookBlock b) =>
      b.kind == BookBlockKind.listItem ? textScaler.scale(18 * fontScale) : 0;
  double get horizontalPadding => 8;
  double textWidth(BookBlock b) =>
      width -
      horizontalPadding -
      (b.kind == BookBlockKind.quote ? 3 : 0) -
      gutter(b);
  static List<TextSpan> spans(
    BookBlock b, {
    GestureRecognizer? Function(BookLink)? recognizer,
  }) {
    final points = <int>{
      0,
      b.text.length,
      for (final i in b.inline) ...[i.startUtf16, i.endUtf16],
    }.toList()..sort();
    return [
      for (var i = 0; i + 1 < points.length; i++)
        _span(b, points[i], points[i + 1], recognizer),
    ];
  }

  static TextSpan _span(
    BookBlock b,
    int start,
    int end,
    GestureRecognizer? Function(BookLink)? recognizer,
  ) {
    final inline = b.inline
        .where((s) => s.startUtf16 <= start && s.endUtf16 >= end)
        .toList();
    final link = inline.where((i) => i.link != null).firstOrNull?.link;
    return TextSpan(
      text: b.text.substring(start, end),
      style: TextStyle(
        fontWeight: inline.any((s) => s.strong) ? FontWeight.bold : null,
        fontStyle: inline.any((s) => s.emphasis) ? FontStyle.italic : null,
        decoration: link == null ? null : TextDecoration.underline,
      ),
      recognizer: link == null ? null : recognizer?.call(link),
    );
  }

  static List<TextSpan> contextSpans(
    BookBlock b,
    PageTextContext? context, {
    GestureRecognizer? Function(BookBlock, BookLink)? recognizer,
  }) => [
    for (final source in context?.blocks ?? [b])
      ...spans(source, recognizer: (link) => recognizer?.call(source, link)),
  ];

  TextPainter painter(
    BookBlock b, {
    bool note = false,
    PageTextContext? context,
  }) => TextPainter(
    text: note
        ? TextSpan(text: 'Consulter la note', style: style(b))
        : TextSpan(style: style(b), children: contextSpans(b, context)),
    textDirection: direction,
    textScaler: textScaler,
    locale: locale,
    textHeightBehavior: const TextHeightBehavior(
      applyHeightToFirstAscent: true,
      applyHeightToLastDescent: true,
    ),
  );
  double tableLabelHeight(BookBlock b) {
    if (b.kind != BookBlockKind.tableCell) return 0;
    final p = TextPainter(
      text: TextSpan(text: 'Cellule de tableau', style: labelStyle),
      textDirection: direction,
      textScaler: textScaler,
      locale: locale,
    )..layout(maxWidth: textWidth(b));
    final result = p.height + 4;
    p.dispose();
    return result;
  }

  MeasuredReaderBlock measure(BookBlock b) {
    if (b.kind == BookBlockKind.image) {
      return MeasuredReaderBlock([], math.min(240.0, height), atomic: true);
    }
    final note = b.isIdentifiedNote;
    final p = painter(b, note: note)..layout(maxWidth: textWidth(b));
    try {
      if (note) {
        return MeasuredReaderBlock(
          [],
          math.max(48, p.height + 16),
          atomic: true,
        );
      }
      return MeasuredReaderBlock(
        _lines(b.text, p).toList(),
        p.height,
        prefix: tableLabelHeight(b),
      );
    } finally {
      p.dispose();
    }
  }

  /// Full scroll fragments need the same shaped height, but no per-line index.
  MeasuredReaderBlock measureWholeBlock(BookBlock b) {
    if (b.kind == BookBlockKind.image || b.isIdentifiedNote) return measure(b);
    final p = painter(b)..layout(maxWidth: textWidth(b));
    try {
      return MeasuredReaderBlock(
        const [],
        p.height > 0 ? p.height : p.preferredLineHeight,
        prefix: tableLabelHeight(b),
      );
    } finally {
      p.dispose();
    }
  }

  /// Shapes on the UI isolate, then yields while resolving line boundaries.
  /// A native shaping call itself cannot be preempted; its cost is reported too.
  Future<MeasuredReaderBlock> measureCooperatively(
    BookBlock b, {
    PageTextContext? context,
    required bool Function() cancelled,
    required void Function(int) onBatch,
  }) async {
    final watch = Stopwatch()..start();
    void check() {
      if (cancelled()) {
        throw const PaginationFailure(PaginationError.cancelled);
      }
    }

    check();
    if (b.kind == BookBlockKind.image || b.isIdentifiedNote) {
      final result = measure(b);
      onBatch(watch.elapsedMicroseconds);
      check();
      return result;
    }
    final p = painter(b, context: context)..layout(maxWidth: textWidth(b));
    try {
      final lines = <MeasuredLine>[];
      for (final line in _lines(context?.text ?? b.text, p)) {
        check();
        lines.add(line);
        if (watch.elapsedMicroseconds >= 8000) {
          onBatch(watch.elapsedMicroseconds);
          watch.stop();
          await Future<void>.delayed(Duration.zero);
          check();
          watch
            ..reset()
            ..start();
        }
      }
      final result = MeasuredReaderBlock(
        lines,
        p.height,
        prefix: tableLabelHeight(b),
      );
      onBatch(watch.elapsedMicroseconds);
      check();
      return result;
    } finally {
      p.dispose();
    }
  }

  Iterable<MeasuredLine> _lines(String text, TextPainter p) sync* {
    final metrics = p.computeLineMetrics();
    if (metrics.isEmpty) {
      yield MeasuredLine(0, 0, 0, p.preferredLineHeight);
      return;
    }
    final boundaries = <int>{0};
    var boundary = 0;
    for (final cluster in text.characters) {
      boundary += cluster.length;
      boundaries.add(boundary);
    }
    var start = 0, top = 0.0;
    // A terminal newline creates an extra visual line with no source units.
    // Keep its height with the preceding line so it cannot become a second
    // page boundary at EOF or duplicate the source endpoint.
    final terminalBlank =
        metrics.length > 1 &&
        metrics.last.width == 0 &&
        RegExp(r'[\n\r\u2028\u2029]$').hasMatch(text);
    final count = metrics.length - (terminalBlank ? 1 : 0);
    for (var i = 0; i < count; i++) {
      var end = text.length, bottom = p.height;
      if (i + 1 < count) {
        final next = metrics[i + 1];
        final pos = p.getPositionForOffset(
          Offset(0, next.baseline - next.ascent / 2),
        );
        end = p.getLineBoundary(pos).start;
        while (end > 0 && !boundaries.contains(end)) {
          end--;
        }
        if (end <= start) {
          throw const PaginationFailure(PaginationError.invalidIndex);
        }
        bottom = next.baseline - next.ascent;
      }
      yield MeasuredLine(start, end, top, bottom - top);
      start = end;
      top = bottom;
    }
  }
}

/// Clip the original shaped paragraph; do not reshape substrings at page boundaries.
class ReaderFragmentView extends StatefulWidget {
  const ReaderFragmentView({
    super.key,
    required this.layout,
    required this.fragment,
    required this.onLink,
    required this.onNote,
    this.images,
    this.textKey,
    this.onParagraph,
    this.onWord,
    this.heardPassageId,
    this.heardSpan,
    this.heardParagraph = false,
  });
  final String? heardPassageId;
  final SourceSpan? heardSpan;
  final bool heardParagraph;
  final ReaderLayout layout;
  final PageFragment fragment;
  final void Function(BookBlock, String) onLink;
  final ValueChanged<BookBlock> onNote;
  final BookImageDecoder? images;
  final GlobalKey? textKey;
  final ValueChanged<BookLocator>? onParagraph;
  final ValueChanged<WordSelection>? onWord;
  @override
  State<ReaderFragmentView> createState() => _ReaderFragmentViewState();
}

class _ReaderFragmentViewState extends State<ReaderFragmentView> {
  final _recognizers = <TapGestureRecognizer>[];
  final _wordTextKey = GlobalKey();
  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final f = widget.fragment, b = f.block, l = widget.layout;
    if (f.coverageOnly) return const SizedBox.shrink();
    Widget result;
    if (b.kind == BookBlockKind.image) {
      result = BookImageView(
        block: b,
        decoder: widget.images,
        viewportHeight: f.height,
      );
    } else if (b.isIdentifiedNote) {
      result = TextButton(
        onPressed: () => widget.onNote(b),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          'Consulter la note',
          style: l.style(b),
          textScaler: l.textScaler,
        ),
      );
    } else {
      final rich = RichText(
        key: widget.textKey ?? _wordTextKey,
        text: TextSpan(
          style: l.style(b),
          children: ReaderLayout.contextSpans(
            b,
            f.context,
            recognizer: (source, link) {
              final r = TapGestureRecognizer()
                ..onTap = () => widget.onLink(source, link.target);
              _recognizers.add(r);
              return r;
            },
          ),
        ),
        textDirection: l.direction,
        textScaler: l.textScaler,
        locale: l.locale,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: true,
          applyHeightToLastDescent: true,
        ),
      );
      final wordRanges = <TextRange>[], paragraphRanges = <TextRange>[];
      var textBase = 0;
      for (final source in f.context?.blocks ?? [b]) {
        if (source.id == widget.heardPassageId && widget.heardParagraph) {
          paragraphRanges.add(
            TextRange(start: textBase, end: textBase + source.text.length),
          );
        }
        if (source.id == widget.heardPassageId && widget.heardSpan != null) {
          final span = widget.heardSpan!;
          if (span.start >= 0 &&
              span.end <= source.text.length &&
              validUtf16Offset(source.text, span.start) &&
              validUtf16Offset(source.text, span.end)) {
            wordRanges.add(
              TextRange(start: textBase + span.start, end: textBase + span.end),
            );
            paragraphRanges.add(
              TextRange(start: textBase, end: textBase + source.text.length),
            );
          }
        }
        textBase += source.text.length;
      }
      final highlighted = WordHighlightOverlay(
        paragraphKey: widget.textKey ?? _wordTextKey,
        words: wordRanges,
        paragraphs: paragraphRanges,
        child: rich,
      );
      final actions = <CustomSemanticsAction, VoidCallback>{
        if (widget.onParagraph != null && b.speechEligible)
          const CustomSemanticsAction(label: 'Choisir ce paragraphe'): () =>
              widget.onParagraph!(f.locator),
      };
      var sourceBase = 0;
      for (final source in f.context?.blocks ?? [b]) {
        for (final inline in source.inline) {
          final link = inline.link;
          if (link != null &&
              inline.endUtf16 + sourceBase >
                  (f.context == null ? f.startUtf16 : f.contextStart) &&
              inline.startUtf16 + sourceBase <
                  (f.context == null ? f.endUtf16 : f.contextEnd)) {
            actions[CustomSemanticsAction(
              label:
                  'Ouvrir le lien : ${source.text.substring(inline.startUtf16, inline.endUtf16)}',
            )] = () =>
                widget.onLink(source, link.target);
          }
        }
        sourceBase += source.text.length;
      }
      final clipped = ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minHeight: f.fullTextHeight,
          maxHeight: f.fullTextHeight,
          minWidth: l.textWidth(b),
          maxWidth: l.textWidth(b),
          child: Transform.translate(
            offset: Offset(0, -f.clipTop),
            child: SizedBox(
              height: f.fullTextHeight,
              width: l.textWidth(b),
              child: widget.onWord == null || !b.speechEligible
                  ? highlighted
                  : GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onLongPressStart: (details) {
                        final paragraph = (widget.textKey ?? _wordTextKey)
                            .currentContext
                            ?.findRenderObject();
                        if (paragraph is! RenderParagraph) return;
                        final point = paragraph.globalToLocal(
                          details.globalPosition,
                        );
                        final offset = paragraph
                            .getPositionForOffset(point)
                            .offset;
                        final blocks = f.context?.blocks ?? [b];
                        final word = WordSelection.at(blocks, offset);
                        if (word == null) {
                          widget.onParagraph?.call(f.locator);
                          return;
                        }
                        var base = 0;
                        for (final block in blocks) {
                          if (block.id == word.start.blockId) break;
                          base += block.text.length;
                        }
                        final boxes = paragraph.getBoxesForSelection(
                          TextSelection(
                            baseOffset: base + word.start.offsetUtf16,
                            extentOffset:
                                base +
                                word.start.offsetUtf16 +
                                word.text.length,
                          ),
                        );
                        if (boxes.any(
                          (box) => box.toRect().inflate(1).contains(point),
                        )) {
                          widget.onWord!(word);
                        } else {
                          widget.onParagraph?.call(f.locator);
                        }
                      },
                      child: highlighted,
                    ),
            ),
          ),
        ),
      );
      result = Semantics(
        container: true,
        header: b.kind == BookBlockKind.heading,
        label: f.context == null
            ? b.text.substring(f.startUtf16, f.endUtf16)
            : f.context!.text.substring(f.contextStart, f.contextEnd),
        customSemanticsActions: actions,
        child: ExcludeSemantics(
          child: Container(
            decoration: b.kind == BookBlockKind.quote
                ? BoxDecoration(
                    border: Border(left: BorderSide(color: l.color, width: 3)),
                  )
                : null,
            padding: EdgeInsets.only(
              left: 4,
              right: 4,
              top: f.leading - (f.startsParagraph ? l.tableLabelHeight(b) : 0),
              bottom: f.trailing,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (f.startsParagraph && b.kind == BookBlockKind.tableCell)
                  SizedBox(
                    height: l.tableLabelHeight(b),
                    child: Text(
                      'Cellule de tableau',
                      style: l.labelStyle,
                      textScaler: l.textScaler,
                    ),
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (b.kind == BookBlockKind.listItem)
                        SizedBox(
                          width: l.gutter(b),
                          child: f.startsParagraph
                              ? Text(
                                  '•',
                                  style: l.style(b),
                                  textScaler: l.textScaler,
                                )
                              : null,
                        ),
                      Expanded(child: clipped),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return SizedBox(
      key: ValueKey(f.identity),
      width: l.width,
      height: f.height,
      child:
          widget.onWord != null ||
              widget.onParagraph == null ||
              !b.speechEligible
          ? result
          : GestureDetector(
              onLongPress: () => widget.onParagraph!(f.locator),
              child: result,
            ),
    );
  }
}
