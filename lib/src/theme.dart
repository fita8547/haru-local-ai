import 'package:flutter/material.dart';

ThemeData buildHaruTheme() {
  const ink = Color(0xFF18201D);
  const mint = Color(0xFFBDECCF);
  const canvas = Color(0xFFF6F8F5);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF247A50),
    brightness: Brightness.light,
    surface: canvas,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(primary: const Color(0xFF176B45)),
    scaffoldBackgroundColor: canvas,
    fontFamilyFallback: const ['Apple SD Gothic Neo', 'Noto Sans KR'],
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: ink,
        fontSize: 32,
        height: 1.16,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: ink, height: 1.5),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: mint,
      height: 72,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE4E9E5)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFE5EAE6)),
      ),
    ),
  );
}
