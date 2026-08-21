import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// 영문 카테고리 값을 아이콘/한글 라벨로 옮기는 표.
/// 모르는 값은 넘겨짚지 않고 기본 핀 아이콘 + 원본 문자열을 그대로 씀.
const _categoryIcons = <String, IconData>{
  'tourist_attraction': Icons.photo_camera_outlined,
  'attraction': Icons.photo_camera_outlined,
  'cultural_facility': Icons.account_balance_outlined,
  'festival': Icons.celebration_outlined,
  'leisure': Icons.hiking_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'restaurant': Icons.restaurant_outlined,
  'food': Icons.restaurant_outlined,
  'cafe': Icons.local_cafe_outlined,
  'accommodation': Icons.hotel_outlined,
  'lodging': Icons.hotel_outlined,
  'school': Icons.school_outlined,
  'course': Icons.alt_route_outlined,
};

const _categoryLabels = <String, String>{
  'tourist_attraction': '관광',
  'attraction': '관광',
  'cultural_facility': '문화시설',
  'festival': '축제',
  'leisure': '레저',
  'shopping': '쇼핑',
  'restaurant': '음식점',
  'food': '음식점',
  'cafe': '카페',
  'accommodation': '숙박',
  'lodging': '숙박',
  'school': '학교',
  'course': '코스',
};

IconData categoryIcon(String? rawCategory) =>
    _categoryIcons[(rawCategory ?? '').toLowerCase()] ?? Icons.place_outlined;

String categoryLabel(String? rawCategory) {
  final raw = (rawCategory ?? '').trim();
  if (raw.isEmpty) return '';
  return _categoryLabels[raw.toLowerCase()] ?? raw;
}

/// 타임라인/썸네일 자리에 쓰는 카테고리 아이콘 박스.
class CategoryIconBox extends StatelessWidget {
  final String? category;

  /// 방문 순서. 주면 박스 좌상단에 작게 얹음.
  final int? order;

  final double size;

  const CategoryIconBox({
    super.key,
    this.category,
    this.order,
    this.size = AppIconSize.categoryBox,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.brandLight,
        borderRadius: BorderRadius.circular(AppRadius.thumbnail),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            categoryIcon(category),
            size: AppIconSize.categoryIcon,
            color: AppColors.brandMuted,
          ),
          if (order != null)
            Positioned(
              top: 4,
              left: 6,
              child: Text('$order', style: AppTextStyles.caption.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              )),
            ),
        ],
      ),
    );
  }
}
