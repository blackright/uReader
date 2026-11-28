import 'package:flutter/material.dart';

/// Shared book/voice silhouette, also supplied as an Android vector drawable.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _Mark()),
    ),
  );
}

class _Mark extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 108, size.height / 108);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 108, 108),
        const Radius.circular(26),
      ),
      Paint()..color = const Color(0xFF183F35),
    );
    final pages = Path()
      ..moveTo(24, 30)
      ..quadraticBezierTo(40, 26, 51, 36)
      ..lineTo(51, 78)
      ..quadraticBezierTo(39, 68, 24, 72)
      ..close()
      ..moveTo(57, 36)
      ..quadraticBezierTo(69, 26, 84, 30)
      ..lineTo(84, 72)
      ..quadraticBezierTo(69, 68, 57, 78)
      ..close();
    canvas.drawPath(pages, Paint()..color = const Color(0xFFF7F3EA));
    final ink = Paint()
      ..color = const Color(0xFFCDA96D)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final bar in [
      (34.0, 48.0, 57.0),
      (41.0, 43.0, 62.0),
      (67.0, 43.0, 62.0),
      (74.0, 48.0, 57.0),
    ]) {
      canvas.drawLine(Offset(bar.$1, bar.$2), Offset(bar.$1, bar.$3), ink);
    }
  }

  @override
  bool shouldRepaint(_Mark oldDelegate) => false;
}

class BrandedSplash extends StatelessWidget {
  const BrandedSplash({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xFFF7F3EA),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(size: 108),
              SizedBox(height: 28),
              Text(
                'uReader',
                style: TextStyle(
                  fontSize: 36,
                  fontFamily: 'serif',
                  color: Color(0xFF183F35),
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Le plaisir de lire. La liberté d’écouter.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF365B4B)),
              ),
              SizedBox(height: 36),
              SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  semanticsLabel: 'Ouverture de votre bibliothèque',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
