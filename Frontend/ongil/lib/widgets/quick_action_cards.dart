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
<<<<<<< HEAD
        // 1. 왼쪽: 지도 살펴보기 카드 (절반 차지)
        Expanded(
          child: Container(
            height: 110,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEBF3E8), // 은은한 연두빛 배경
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween, // 아이콘 상단, 텍스트 하단 배치
              children: [
                const Icon(Icons.map_outlined, color: Color(0xFFC39B6B), size: 26),
                Row(
                  children: const [
                    Text(
                      '지도 살펴보기',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C2825),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: Color(0xFF2C2825)),
                  ],
                ),
              ],
            ),
          ),
        ),
    
        const SizedBox(width: 12), // 카드 사이의 가로 간격
    
        // 2. 오른쪽: 스케줄 보러가기 카드 (절반 차지)
        Expanded(
          child: Container(
            height: 110,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Icon(Icons.alt_route_rounded, color: Color(0xFFC39B6B), size: 26),
                Text(
                  '스케줄 보러가기',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C2825),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
=======
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
>>>>>>> 181b2e02e01fc09c9df58fdd7b41b573330de210
    );
  }
}
