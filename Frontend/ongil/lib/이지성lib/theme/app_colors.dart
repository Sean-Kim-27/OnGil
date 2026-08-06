import 'package:flutter/material.dart';

/// 온길 디자인 시스템 - 컬러 토큰
class AppColors {
  AppColors._();

  /// 용도값 브랜드(포인트 아이콘)
  static const brand = Color(0xFFEAA952);

  /// 브랜드 연한 배경
  static const brandLight = Color(0xFFF3D8AC);

  /// 액센트 (CTA·활성 상태)
  static const accent = Color(0xFFC85A32);

  /// 액센트 연한 배경
  static const accentLight = Color(0xFFF1D3C4);

  /// 화면 배경
  static const background = Color(0xFFFAF6F0);

  /// 카드 배경 (배경보다 살짝 밝게)
  static const cardBackground = Color(0xFFFFFDF8);

  /// 본문 텍스트
  static const text = Color(0xFF332A24);

  /// 보조 텍스트 (라벨/캡션은 항상 이 색으로 위계 구분)
  static const textSecondary = Color(0xFF8C7A68);

  /// 기본 선 (테두리, 거의 안 보이는 헤어라인)
  static const line = Color(0xFFEADFC9);

  /// 강조 선 (선택/활성 상태 테두리)
  static const lineAccent = Color(0xFFDFCBA6);

  /// 라벨/아이콘에 쓰이는 무드톤 강조색 (WELCOME BACK, THEN&NOW, 바로가기 아이콘 등)
  static const brandMuted = Color(0xFFC39B6B);

  /// '지도 살펴보기' 바로가기 카드 배경 (연한 그린 톤)
  static const mapTint = Color(0xFFEBF3E8);

  /// '지도 살펴보기' 카드 테두리
  static final mapTintBorder = Colors.green.withOpacity(0.15);

  /// 메인 카드 · '스케줄 보러가기' 카드 테두리
  static final warmCardBorder = Colors.orange.withOpacity(0.15);
}
