import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Pretendard',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary500,
        primary: AppColors.primary500,
        onPrimary: AppColors.gray900,
        surface: AppColors.grayWhite,
        onSurface: AppColors.textPrimary,
        error: AppColors.error01,
      ),
      textTheme: const TextTheme(
        displayLarge: AppTypography.heading01,
        displayMedium: AppTypography.heading02,
        displaySmall: AppTypography.heading03,
        headlineMedium: AppTypography.heading04,
        titleLarge: AppTypography.subtitle01,
        titleMedium: AppTypography.subtitle02,
        titleSmall: AppTypography.subtitle03,
        bodyLarge: AppTypography.body01,
        bodyMedium: AppTypography.body02,
        labelLarge: AppTypography.button03,
        labelMedium: AppTypography.button05,
        bodySmall: AppTypography.caption02,
        labelSmall: AppTypography.caption03,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: AppTypography.heading04,
      ),
    );
  }
}
