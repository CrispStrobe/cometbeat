// lib/shared/theme.dart
//
// Kid-friendly Material 3 theme: big touch targets, rounded shapes, high
// contrast. Keep all app-wide styling here.

import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF5E35B1),
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF6F2FF),
    cardTheme: const CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    // Slightly larger type for young readers. englishLike2021 carries the
    // font sizes; blackMountainView alone has null sizes and apply() asserts.
    textTheme: Typography.englishLike2021
        .merge(Typography.blackMountainView)
        .apply(fontSizeFactor: 1.1),
    // Children's motor precision is limited: enforce generous tap targets.
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}
