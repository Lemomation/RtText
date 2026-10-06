import 'package:flutter/material.dart';

/// Dark-first Material 3 theme: deep charcoal surfaces with a configurable
/// accent (teal by default).
abstract final class AppTheme {
  static const seed = Color(0xFF2DD4BF);

  static const background = Color(0xFF0B0F14);
  static const surface = Color(0xFF11161D);
  static const surfaceHigh = Color(0xFF1A212B);

  static ThemeData dark({Color seed = AppTheme.seed}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(surface: surface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        height: 68,
        indicatorColor: scheme.primary.withValues(alpha: 0.25),
      ),
      cardTheme: const CardThemeData(color: surface),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
    );
  }
}
