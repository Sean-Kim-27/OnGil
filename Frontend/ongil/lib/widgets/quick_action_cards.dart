import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// 홈 화면 하단 바로가기 카드 2개: 지도 / 스케줄
class QuickActionCards extends StatelessWidget {
  final VoidCallback? onMapTap;
  final VoidCallback? onScheduleTap;

  const QuickActionCards({super.key, this.onMapTap, this.onScheduleTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            icon: Icons.map_outlined,
            label: '지도 살펴보기',
            background: AppColors.mapTint,
            borderColor: AppColors.mapTintBorder,
            onTap: onMapTap,
          ),
        ),
        const SizedBox(width: AppSpacing.cardGap),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.alt_route_rounded,
            label: '스케줄 보러가기',
            background: AppColors.cardBackground,
            borderColor: AppColors.warmCardBorder,
            onTap: onScheduleTap,
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color borderColor;
  final VoidCallback? onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.background,
    required this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.cardMedium),
      child: Container(
        height: 110,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.cardMedium),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 26, color: AppColors.brandMuted),
            Row(
              children: [
                Text(label, style: AppTextStyles.cardTitle),
                const Icon(Icons.chevron_right, size: 16, color: AppColors.text),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
