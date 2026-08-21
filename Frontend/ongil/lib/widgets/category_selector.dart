import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// 카테고리 한 항목의 라벨/아이콘/색 정의.
class CategoryItem {
  final String label;
  final IconData icon;
  final Color color;
  const CategoryItem({required this.label, required this.icon, required this.color});
}

/// 추천 리스트 화면의 카테고리 필터. 브랜드 골드/액센트 테라코타 두 색을 번갈아 써서
/// (음식·숙박 = 액센트, 관광·카페 = 브랜드) 구분하고, 선택된 항목만 해당 색으로 채워짐.
class CategorySelector extends StatelessWidget {
  static const items = [
    CategoryItem(label: '음식', icon: Icons.restaurant_outlined, color: AppColors.accent),
    CategoryItem(label: '관광', icon: Icons.photo_camera_outlined, color: AppColors.brand),
    CategoryItem(label: '숙박', icon: Icons.hotel_outlined, color: AppColors.accent),
    CategoryItem(label: '카페', icon: Icons.local_cafe_outlined, color: AppColors.brand),
  ];

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const CategorySelector({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i != 0) const SizedBox(width: 8),
          Expanded(
            child: _CategoryChip(
              item: items[i],
              selected: selectedIndex == i,
              onTap: () => onChanged(i),
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final CategoryItem item;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? item.color.withOpacity(0.12) : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? item.color : AppColors.line,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 20, color: selected ? item.color : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(
              item.label,
              style: AppTextStyles.caption.copyWith(
                color: selected ? item.color : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
