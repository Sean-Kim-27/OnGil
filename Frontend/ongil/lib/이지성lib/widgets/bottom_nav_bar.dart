import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 하단 5탭 네비게이션. 탭마다 선택/비선택 아이콘을 따로 둬서 선택 상태가
/// 또렷하게 보이도록 함 (신규 홈 화면 시안 기준).
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    (icon: Icons.map_outlined, activeIcon: Icons.map, label: '지도'),
    (icon: Icons.alt_route_outlined, activeIcon: Icons.alt_route, label: '스케줄'),
    (icon: Icons.home_outlined, activeIcon: Icons.home_filled, label: '홈'),
    (icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book, label: '방명록'),
    (icon: Icons.settings_outlined, activeIcon: Icons.settings, label: '설정'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(top: BorderSide(color: AppColors.line, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.cardBackground,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textSecondary,
        iconSize: AppIconSize.bottomTab,
        selectedLabelStyle: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 9.5,
          fontWeight: FontWeight.w500,
        ),
        elevation: 0,
        items: [
          for (final item in _items)
            BottomNavigationBarItem(
              icon: Icon(item.icon),
              activeIcon: Icon(item.activeIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

/// 홈 화면 우하단 FAB (+ 새 추억/일정 추가). 그림자를 은은하게 준 몇 안 되는 요소.
class AppFab extends StatelessWidget {
  final VoidCallback onPressed;
  const AppFab({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const Icon(Icons.add, color: AppColors.cardBackground),
        ),
      ),
    );
  }
}
