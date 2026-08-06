import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_card.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/memory_photo.dart';
import '../widgets/top_header.dart';
import '../widgets/main_feature_card.dart';
import '../widgets/quick_action_cards.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 2; // '홈' 탭이 기본 선택

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: Column(
            children: [
              const SizedBox(height: 6),
              const TopHeader(),
              const SizedBox(height: AppSpacing.sectionGap),
              const _GreetingSection(),
              const SizedBox(height: AppSpacing.sectionGap),
              const MainFeatureCard(),
              const SizedBox(height: AppSpacing.cardGap),
              const QuickActionCards(),
              const SizedBox(height: AppSpacing.sectionGap),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('최근 기록된 기억', style: AppTextStyles.cardTitle),
                  Text(
                    '더보기',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const _RecentMemoryTile(
                title: '탄금대 · 충주',
                subtitle: '모교 앞 골목',
                meta: '2주 전 방문',
              ),
              const SizedBox(height: AppSpacing.cardGap),
              const _RecentMemoryTile(
                title: '1998년 기억',
                subtitle: '초등학교 앞 문구점 자리',
                meta: '충주 · 대소원면',
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      floatingActionButton: AppFab(
        onPressed: () {
          // TODO: 새 추억/일정 추가 플로우 연결 예정
        },
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
      ),
    );
  }
}

/// 인사말 영역: WELCOME BACK 라벨 + 히어로 타이틀 (신규 시안: 가운데 정렬)
class _GreetingSection extends StatelessWidget {
  const _GreetingSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'WELCOME BACK',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.brandMuted,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '도현님, 오늘도\n추억 속을 걸어보세요',
          textAlign: TextAlign.center,
          style: AppTextStyles.heroGreeting,
        ),
      ],
    );
  }
}

class _RecentMemoryTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String meta;

  const _RecentMemoryTile({
    required this.title,
    required this.subtitle,
    required this.meta,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const MemoryPhoto(size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.cardTitle),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          Text(meta, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}
