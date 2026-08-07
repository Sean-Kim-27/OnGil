import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import 'memory_photo.dart';

/// 홈 화면 메인 카드: '그때와 지금' 추억 하이라이트.
/// 상단은 사진(플레이스홀더는 그라디언트) + 위치·연도 배지, 하단은 타이틀/설명과 비교 링크.
class MainFeatureCard extends StatelessWidget {
  const MainFeatureCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.cardHero),
        border: Border.all(color: AppColors.warmCardBorder),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PhotoHeader(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'THEN & NOW',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.brandMuted,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '그 골목, 지금은\n어떤 모습일까요',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.heroCopy,
                ),
                const SizedBox(height: 8),
                Text(
                  '초등학교 앞 문구점 자리를 다시 찾아가는 길',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '그때와 지금 비교해보기',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward, size: 16, color: AppColors.accent),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoHeader extends StatelessWidget {
  const _PhotoHeader();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MemoryPhotoHero(
          height: 200,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.cardHero)),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.cardBackground.withOpacity(0.6),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.accent, width: 1.2),
            ),
            child: Text(
              '충주 · 1998',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
