import 'package:flutter/material.dart';

/// The ONLY place colors are defined. Muted, low-stimulation palette.
class BoloTheme {
  static const background = Color(0xFFF6F4EF);
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFD8D3C8);
  static const cardPressed = Color(0xFFE8E4DA);
  static const text = Color(0xFF4A4A44);
  static const tabActive = Color(0xFFA8BCA1);
  static const tabInactive = Color(0xFFE3E0D8);
}

ThemeData boloThemeData() => ThemeData(
      scaffoldBackgroundColor: BoloTheme.background,
      colorScheme: ColorScheme.fromSeed(
          seedColor: BoloTheme.tabActive, surface: BoloTheme.background),
      splashFactory: NoSplash.splashFactory, // no ripple animations
      useMaterial3: true,
    );
