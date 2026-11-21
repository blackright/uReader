import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Paints measured selection rectangles behind text without changing its metrics.
/// No live region or per-word accessibility announcement is introduced.
class WordHighlightOverlay extends StatelessWidget {
  const WordHighlightOverlay({
    super.key,
    required this.paragraphKey,
    required this.words,
    required this.paragraphs,
    required this.child,
  });
  final GlobalKey paragraphKey;
  final List<TextRange> words, paragraphs;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _HighlightPainter(
        paragraphKey,
        words,
        paragraphs,
        colors.primary.withValues(alpha: .27),
        colors.onSurface.withValues(alpha: .06),
      ),
      child: child,
    );
  }
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter(
    this.key,
    this.words,
    this.paragraphs,
    this.wordColor,
    this.paragraphColor,
  );
  final GlobalKey key;
  final List<TextRange> words, paragraphs;
  final Color wordColor, paragraphColor;
  void _paint(
    Canvas canvas,
    RenderParagraph paragraph,
    List<TextRange> ranges,
    Color color,
  ) {
    final paint = Paint()..color = color;
    for (final range in ranges) {
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      )) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(box.toRect(), const Radius.circular(2)),
          paint,
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paragraph = key.currentContext?.findRenderObject();
    if (paragraph is! RenderParagraph || !paragraph.hasSize) return;
    _paint(canvas, paragraph, paragraphs, paragraphColor);
    _paint(canvas, paragraph, words, wordColor);
  }

  @override
  bool shouldRepaint(_HighlightPainter old) => true;
}
