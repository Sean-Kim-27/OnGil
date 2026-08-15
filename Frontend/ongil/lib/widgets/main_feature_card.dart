import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import 'memory_photo.dart';

/// 홈 화면 메인 카드: '그때와 지금' 추억 하이라이트.
/// tag/title/subtitle을 안 넘기면 아직 검색 전 상태의 기본 문구가 나타남  -
/// 검색으로 대표 장소가 정해지면 그 값을 넘겨서 실제 내용으로 바꿔서 나타나게함
class MainFeatureCard extends StatelessWidget {
  final String? tag;
  final String? title;
  final String? subtitle;
  final ImageProvider? image;
  final VoidCallback? onTap;

  const MainFeatureCard({
    super.key,
    this.tag,
    this.title,
    this.subtitle,
    this.image,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            _PhotoHeader(tag: tag ?? '충주 · 1998', image: image),
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
                    title ?? '그 골목, 지금은\n어떤 모습일까요',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.heroCopy,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle ?? '초등학교 앞 문구점 자리를 다시 찾아가는 길',
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
      ),
    );
  }
}

class _PhotoHeader extends StatelessWidget {
  final String tag;
  final ImageProvider? image;
  const _PhotoHeader({required this.tag, this.image});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MemoryPhotoHero(
          image: image,
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                tag,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
