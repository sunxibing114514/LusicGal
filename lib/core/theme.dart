import 'package:flutter/material.dart';

/// Material 3 主题（明 / 暗），品牌种子色：星云紫。
class LusicTheme {
  LusicTheme._();

  static const Color seed = Color(0xFF7C5CFF);

  /// 书库卡片渐变（明）。
  static const List<Color> coverGradientLight = [
    Color(0xFFEDE7FF),
    Color(0xFFD5CCFF),
  ];

  /// 书库卡片渐变（暗）。
  static const List<Color> coverGradientDark = [
    Color(0xFF2A2350),
    Color(0xFF161232),
  ];

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(centerTitle: true),
    );
  }
}
