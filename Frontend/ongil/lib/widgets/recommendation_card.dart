import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import 'memory_photo.dart';

/// 홈 화면 '추천리스트' 카드. 메인 피처 카드와 같은 형태(사진+배지+텍스트)를 가로 스크롤용으로 줄인 버전으로 나타냄
class RecommendationCard extends StatelessWidget {
  final String tag;
  final String title;
  final String subtitle;
  final Color accentColor;
  final double width;
  final double height;
  final ImageProvider? image;
  final VoidCallback? onTap;

  const RecommendationCard({
    super.key,
    required this.tag,
    required this.title,
    required this.subtitle,
    this.accentColor = AppColors.accent,
    this.width = 208,
    this.height = 222,
    this.image,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.cardHero),
          border: Border.all(color: accentColor.withValues(alpha: 0.18)),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MemoryPhotoHero(
                    image: image,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.cardHero)),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: accentColor, width: 1.1),
                      ),
                      child: Text(
                        tag,
                        style: AppTextStyles.caption.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.cardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
