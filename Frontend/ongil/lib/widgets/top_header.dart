import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// 홈 화면 상단 바: 로고 + 검색/설정 아이콘. 설정 아이콘을 탭하면 onSettingsTap이 호출됨.
class TopHeader extends StatelessWidget {
  final VoidCallback? onSearchTap;
  final VoidCallback? onSettingsTap;

  const TopHeader({super.key, this.onSearchTap, this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '온길',
          style: AppTextStyles.logo.copyWith(fontSize: 28, color: AppColors.accent),
        ),
        Row(
          children: [
            GestureDetector(
              onTap: onSearchTap,
              child: const Icon(Icons.search, size: 26, color: AppColors.text),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onSettingsTap,
              child: const Icon(Icons.settings_outlined, size: 26, color: AppColors.text),
            ),
          ],
        ),
      ],
    );
  }
}
