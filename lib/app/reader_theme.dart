import 'package:flutter/material.dart';

/// Shared application chrome. Book typography is measured by ReaderLayout.
abstract final class ReaderVisualTheme {
  static ThemeData theme({bool dark = false}) {
    final paper = Color(dark ? 0xFF171C19 : 0xFFF7F3EA);
    final ink = Color(dark ? 0xFFEFEDE5 : 0xFF252C27);
    final accent = Color(dark ? 0xFFB8D8C4 : 0xFF365B4B);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          surface: paper,
          onSurface: ink,
          primary: accent,
          onPrimary: dark ? const Color(0xFF171C19) : Colors.white,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: paper,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: DividerThemeData(color: ink.withValues(alpha: .12)),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: accent.withValues(alpha: .12),
      ),
    );
  }
}
