import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// 온길 디자인 시스템 - 타이포그래피 토큰

/// 폰트 사용 규칙 (스펙 그대로):
/// - Gowun Batang(세리프)  → 로고, 화면 히어로 타이틀, 히어로 카피에만 사용
/// - Pretendard Variable   → 나머지 UI 전체 (본문, 카드 제목, 캡션, 버튼 등)
///
/// flutter:
///   fonts:
///     - family: Pretendard
///       fonts:
///         - asset: assets/fonts/PretendardVariable.ttf
class AppTextStyles {
  AppTextStyles._();

  static const _body = 'Pretendard';

  // ---------- Gowun Batang (세리프) : 로고 / 히어로 전용 ----------

  /// 로고 워드마크 21px
  static TextStyle logo = GoogleFonts.gowunBatang(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
    letterSpacing: -0.2,
  );

  /// 홈 인사말 (세리프 타이틀) 20px
  static TextStyle heroGreeting = GoogleFonts.gowunBatang(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
    height: 1.45,
  );

  /// 히어로 카피 (예: "그 골목, 지금은 어떤 모습일까요") 17px
  static TextStyle heroCopy = GoogleFonts.gowunBatang(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
    height: 1.5,
  );

  /// 역할/화면 타이틀 (작은 헤더) 16.5~17px
  static const screenTitle = TextStyle(
    fontFamily: _body,
    fontSize: 16.5,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
    letterSpacing: -0.2,
  );

  /// 카드 제목 13.5~15.5px
  static const cardTitle = TextStyle(
    fontFamily: _body,
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );

  /// 본문 / 설명 11~12.5px (기본값 12.5px)
  static const body = TextStyle(
    fontFamily: _body,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: AppColors.text,
    height: 1.4,
  );

  static const bodySmall = TextStyle(
    fontFamily: _body,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  /// 캡션 / 태그 / 보조정보 9.5~10.5px - 항상 보조 텍스트 색
  static const caption = TextStyle(
    fontFamily: _body,
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  /// 상태바 시간 12px
  static const statusBarTime = TextStyle(
    fontFamily: _body,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );

  /// 버튼 라벨
  static const button = TextStyle(
    fontFamily: _body,
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
    color: AppColors.cardBackground,
  );

  /// 인풋 필드 텍스트
  static const input = TextStyle(
    fontFamily: _body,
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    color: AppColors.text,
  );

  /// 인풋 힌트
  static const inputHint = TextStyle(
    fontFamily: _body,
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
}
