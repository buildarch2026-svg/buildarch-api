import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.surface,
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.primaryContainer,
          onPrimary: Colors.white,
          secondary: AppColors.secondary,
          onSecondary: Colors.white,
          error: AppColors.error,
          onError: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.onSurface,
        ),
      );
}

/// Shadows (Tailwind shadow-sm / shadow-md / shadow-2xl equivalents).
class AppShadows {
  AppShadows._();

  static const sm = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const md = [
    BoxShadow(
        color: Color(0x1A000000),
        blurRadius: 6,
        spreadRadius: -1,
        offset: Offset(0, 4)),
    BoxShadow(
        color: Color(0x1A000000),
        blurRadius: 4,
        spreadRadius: -2,
        offset: Offset(0, 2)),
  ];

  static const xl2 = [
    BoxShadow(
        color: Color(0x40000000),
        blurRadius: 50,
        spreadRadius: -12,
        offset: Offset(0, 25)),
  ];
}
