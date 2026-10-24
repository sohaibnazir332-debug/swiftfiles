import 'package:flutter/material.dart';

/// Poori app ke rang yahin se control hote hain.
/// Rang badalna ho to sirf yahan badlein.
class AppColors {
  static const sky = Color(0xFF4DB6F5); // soothing light blue (primary)
  static const skyDark = Color(0xFF1E88E5); // buttons / text accent
  static const skySoft = Color(0xFFE3F2FD); // soft tint backgrounds
  static const bg = Color(0xFFF4F9FF); // page background
  static const ink = Color(0xFF1B2B3A); // main text
  static const muted = Color(0xFF7A8CA0); // secondary text
  static const danger = Color(0xFFEF5350);
  static const success = Color(0xFF26A69A);
}

class AppTheme {
  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.sky,
      brightness: Brightness.light,
    );
    final scheme = base.copyWith(
      primary: AppColors.skyDark,
      secondary: AppColors.sky,
      surface: Colors.white,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.skyDark,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.skyDark,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.skyDark,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.sky,
        linearTrackColor: Colors.transparent,
      ),
    );
  }
}
