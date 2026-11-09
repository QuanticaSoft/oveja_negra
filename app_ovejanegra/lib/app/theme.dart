import 'package:flutter/material.dart';

/// Identidad OVEJA_NEGRA: negro, blanco y naranja; minimalista y legible.
class AppColors {
  AppColors._();

  static const black = Color(0xFF111111);
  static const orange = Color(0xFFFF7A00);
  static const white = Color(0xFFFFFFFF);
  static const grey = Color(0xFF8A8A8A);
  static const surface = Color(0xFFF6F6F6);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.orange,
    // Texto negro sobre naranja: más contraste que blanco sobre naranja.
    onPrimary: AppColors.black,
    secondary: AppColors.black,
    onSecondary: AppColors.white,
    surface: AppColors.white,
    onSurface: AppColors.black,
    error: Color(0xFFC62828),
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, scaffoldBackgroundColor: AppColors.surface);
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.black,
      foregroundColor: AppColors.white,
      elevation: 0,
      centerTitle: false,
    ),
    drawerTheme: const DrawerThemeData(width: 280, backgroundColor: AppColors.black),
    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: AppColors.black,
      indicatorColor: AppColors.orange,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected) ? AppColors.black : AppColors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? AppColors.black : AppColors.white),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    cardTheme: CardThemeData(
      color: AppColors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE6E6E6))),
    ),
  );
}
