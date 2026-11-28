import 'package:flutter/material.dart';

import '../domain/reader_experience.dart';

class ReadingHighlight extends ThemeExtension<ReadingHighlight> {
  const ReadingHighlight(this.color);
  final Color color;

  static Color resolve(HighlightColor choice) => switch (choice) {
    HighlightColor.yellow => const Color(0xFFFFC107),
    HighlightColor.green => const Color(0xFF66BB6A),
    HighlightColor.blue => const Color(0xFF42A5F5),
    HighlightColor.pink => const Color(0xFFEC407A),
    HighlightColor.purple => const Color(0xFFAB47BC),
  };

  @override
  ReadingHighlight copyWith({Color? color}) =>
      ReadingHighlight(color ?? this.color);

  @override
  ReadingHighlight lerp(covariant ReadingHighlight? other, double t) =>
      ReadingHighlight(Color.lerp(color, other?.color ?? color, t)!);
}
