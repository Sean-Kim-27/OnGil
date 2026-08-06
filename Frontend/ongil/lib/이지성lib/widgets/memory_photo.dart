import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 프로젝트 전체에서 반복 사용하는 '추억 사진' 모티프.
/// 실제 사진이 없을 때(placeholder) 브랜드 그라디언트 + 풍경 아이콘으로 표시하고,
/// imageProvider가 주어지면 실제 사진을 같은 프레임 안에 채워 넣습니다.
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
            ? DecorationImage(image: image!, fit: BoxFit.cover)
            : null,
      ),
      child: image == null
          ? Center(
              child: Icon(
                Icons.landscape_outlined,
                size: size * 0.32,
                color: AppColors.cardBackground.withOpacity(0.75),
              ),
            )
          : null,
    );
  }
}

/// 홈 화면 히어로용 큰 버전 (풀 와이드 카드 상단 이미지 영역).
/// borderRadius를 지정하지 않으면 카드 전체와 동일한 라운드(기존 동작)로 표시되고,
/// 카드 상단에 딱 붙는 형태로 쓸 때는 위쪽 모서리만 둥근 BorderRadius를 넘겨서 재사용할 수 있습니다.
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
            ? DecorationImage(image: image!, fit: BoxFit.cover)
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
                  color: AppColors.cardBackground.withOpacity(0.8),
                ),
              ),
            )
          : null,
    );
  }
}
