import 'package:flutter/material.dart';

import 'app_theme.dart';

abstract final class AuthColors {
  static const accent = AppColors.mint;
  static const background = AppColors.background;
  static const field = AppColors.surface;
  static const text = AppColors.text;
  static const muted = AppColors.muted;
  static const border = AppColors.border;
}

ThemeData buildAuthTheme() {
  final base = buildTheme();
  return base.copyWith(
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: AuthColors.field,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      labelStyle: const TextStyle(color: AuthColors.muted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AuthColors.accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: base.colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: base.colorScheme.error, width: 1.6),
      ),
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AuthColors.accent,
        foregroundColor: AuthColors.background,
        minimumSize: const Size(double.infinity, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        side: const BorderSide(color: AuthColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        minimumSize: const Size(48, 48),
      ),
    ),
  );
}
