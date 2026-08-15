import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

/// 추천 리스트 화면 상단 카드 캐러셀 한 장. 페이지 안에서 한 번에 하나만 보이도록함
/// 화면 폭 전체를 채움. 사진이 없으면 카테고리 아이콘을 그라디언트 위에 보여줌.
class RecommendationHeroCard extends StatelessWidget {
  final String title;
  final String address;
  final IconData placeholderIcon;
  final ImageProvider? image;
  final String badgeLabel;
  final VoidCallback? onTap;

  const RecommendationHeroCard({
    super.key,
    required this.title,
    required this.address,
    this.placeholderIcon = Icons.place_outlined,
    this.image,
    this.badgeLabel = '추천',
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
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: image == null
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppColors.brand, AppColors.accent],
                            )
                          : null,
                      image: image != null
                          ? DecorationImage(image: image!, fit: BoxFit.cover, onError: (_, __) {})
                          : null,
                    ),
                    child: image == null
                        ? Center(
                            child: Icon(
                              placeholderIcon,
                              size: 52,
                              color: AppColors.cardBackground.withOpacity(0.85),
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        badgeLabel,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.cardBackground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              child: Column(
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_on_outlined, size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          address,
                          style: AppTextStyles.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
