import 'package:flutter/material.dart';

class AppColors {
  // 브랜드 메인 컬러
  static const Color primary = Color(0xFFC85A32);
  static final Color primaryLight = const Color(0xFFC85A32).withOpacity(0.1);

  // 배경 및 중립 색상
  static const Color background = Colors.white;
  static const Color cardShadow = Colors.black12;
  static final Color dragHandle = Colors.grey[300]!;

  // 텍스트 컬러
  static const Color textPrimary = Color(0xFF222222);
  static final Color textSecondary = Colors.grey[700]!;
  static const Color textIcon = Colors.grey;
}