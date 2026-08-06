import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// 홈 화면 상단 바: 로고 + 검색/설정 아이콘
class TopHeader extends StatelessWidget {
  const TopHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '온길',
          style: AppTextStyles.logo.copyWith(fontSize: 28, color: AppColors.accent),
        ),
        const Row(
          children: [
            Icon(Icons.search, size: 26, color: AppColors.text),
            SizedBox(width: 12),
            Icon(Icons.settings_outlined, size: 26, color: AppColors.text),
          ],
        ),
      ],
    );
  }
}
