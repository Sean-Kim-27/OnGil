import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_dimens.dart';
import 'app_text_styles.dart';

/// 컴포넌트 톤 규칙:
/// - 버튼은 화면당 강한 CTA(액센트) 1개만, 나머지는 아웃라인/고스트
/// - 그림자는 거의 안 씀. CTA 버튼과 FAB에만 은은하게(블러 크게)
class AppShadows {
  AppShadows._();

  static List<BoxShadow> cta = [
    BoxShadow(
      color: AppColors.accent.withOpacity(0.28),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> fab = [
    BoxShadow(
      color: AppColors.accent.withOpacity(0.35),
      blurRadius: 20,
      offset: const Offset(0, 10),
    ),
  ];

  /// 홈 화면 메인 피처 카드에 쓰이는 아주 은은한 그림자 
  static List<BoxShadow> card = [
    BoxShadow(
      color: Colors.black.withOpacity(0.03),
      blurRadius: 15,
      offset: const Offset(0, 6),
    ),
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData light = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Pretendard',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      primary: AppColors.accent,
      secondary: AppColors.brand,
      surface: AppColors.cardBackground,
      background: AppColors.background,
    ),
    textTheme: const TextTheme(
      bodyMedium: AppTextStyles.body,
      bodySmall: AppTextStyles.bodySmall,
      labelSmall: AppTextStyles.caption,
      titleMedium: AppTextStyles.cardTitle,
      titleLarge: AppTextStyles.screenTitle,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardBackground,
      hintStyle: AppTextStyles.inputHint,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding + 3,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.line, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.line, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.accent, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.cardBackground,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: AppTextStyles.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.line, width: 1),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: AppTextStyles.button.copyWith(color: AppColors.text),
      ),
    ),
  );
}
