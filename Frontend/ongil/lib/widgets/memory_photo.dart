import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// '추억 사진' 자리. 사진이 없으면 브랜드 그라디언트로 대체.
class MemoryPhoto extends StatelessWidget {
  final double size;
  final double radius;
  final ImageProvider? image;

  const MemoryPhoto({
    super.key,
    this.size = 56,
    this.radius = AppRadius.thumbnail,
    this.image,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: image == null
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.brandLight,
                  AppColors.accentLight,
                  AppColors.brand,
                ],
              )
            : null,
        image: image != null
            ? DecorationImage(image: image!, fit: BoxFit.cover, onError: (_, __) {})
            : null,
      ),
      child: image == null
          ? Center(
              child: Icon(
                Icons.landscape_outlined,
                size: size * 0.32,
                color: AppColors.cardBackground.withValues(alpha: 0.75),
              ),
            )
          : null,
    );
  }
}

/// 풀 와이드 카드 상단용 큰 버전.
class MemoryPhotoHero extends StatelessWidget {
  final ImageProvider? image;
  final double height;
  final BorderRadius borderRadius;

  const MemoryPhotoHero({
    super.key,
    this.image,
    this.height = 150,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.cardLarge)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: image == null
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.brandLight,
                  AppColors.accentLight,
                ],
              )
            : null,
        image: image != null
            ? DecorationImage(image: image!, fit: BoxFit.cover, onError: (_, __) {})
            : null,
      ),
      child: image == null
          ? Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(
                  Icons.image_outlined,
                  size: 20,
                  color: AppColors.cardBackground.withValues(alpha: 0.8),
                ),
              ),
            )
          : null,
    );
  }
}
