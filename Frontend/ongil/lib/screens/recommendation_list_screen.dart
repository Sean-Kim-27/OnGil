import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/category_selector.dart';
import '../widgets/recommendation_hero_card.dart';
import '../widgets/recommendation_list_row.dart';
import '../widgets/page_dots_indicator.dart';
import '../widgets/kakao_webview_screen.dart';
import '../services/place_service.dart';

/// 추천 리스트 화면. 위쪽 카드(PageView) + 카테고리 필터 + 목록.
class RecommendationListScreen extends StatefulWidget {
  final NearbySearchResult? searchResult;

  const RecommendationListScreen({super.key, this.searchResult});

  @override
  State<RecommendationListScreen> createState() => _RecommendationListScreenState();
}

class _RecommendationListScreenState extends State<RecommendationListScreen> {
  int _categoryIndex = 0;
  int _pageIndex = 0;
  final _pageController = PageController();
  final _scrollController = ScrollController();

  // 실제 검색 결과가 없을 때 보여줄 예시 데이터.
  static const _fallback = [
    RecommendedPlace(title: '구도심 골목카페', address: '충주시 성내동 12-3', category: '카페'),
    RecommendedPlace(title: '신발원', address: '대소원면 대소원로 62', category: '음식'),
    RecommendedPlace(title: '스완양분식', address: '대소원면 중앙로 7', category: '음식'),
    RecommendedPlace(title: '충주 손칼국수', address: '성내동 8-1', category: '음식'),
    RecommendedPlace(title: '탄금대', address: '칠금동 산1', category: '관광'),
    RecommendedPlace(title: '충주 관아공원', address: '성내동 205', category: '관광'),
    RecommendedPlace(title: '숲속 게스트하우스', address: '수안보면 온천리 3', category: '숙박'),
    RecommendedPlace(title: '충주 특산품 판매점', address: '성내동 45', category: '관광'),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  IconData _categoryIcon(String category) {
    final match = CategorySelector.items.where((c) => c.label == category);
    return match.isNotEmpty ? match.first.icon : Icons.place_outlined;
  }

  /// 목록에서 장소를 탭하면 위쪽 카드를 그 장소로 옮기고 맨 위로 스크롤.
  void _focusHero(RecommendedPlace place, List<RecommendedPlace> heroItems) {
    final index = heroItems.indexOf(place);
    if (index == -1) return;

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final realPlaces = widget.searchResult?.places ?? [];
    final heroItems = realPlaces.isNotEmpty ? realPlaces : _fallback;

    final selectedCategory = CategorySelector.items[_categoryIndex].label;
    final listItems = heroItems.where((p) => p.category == selectedCategory).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppBackTopBar(title: '추천 리스트'),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
                children: [
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 290,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: heroItems.length,
                      onPageChanged: (i) => setState(() => _pageIndex = i),
                      itemBuilder: (context, i) {
                        final item = heroItems[i];
                        return RecommendationHeroCard(
                          title: item.title,
                          address: item.address,
                          placeholderIcon: _categoryIcon(item.category),
                          image: item.imageUrl != null ? NetworkImage(item.imageUrl!) : null,
                          onTap: () => openKakaoPlaceDetail(
                            context,
                            title: item.title,
                            latitude: item.latitude,
                            longitude: item.longitude,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  PageDotsIndicator(count: heroItems.length, currentIndex: _pageIndex),
                  const SizedBox(height: AppSpacing.sectionGap),
                  CategorySelector(
                    selectedIndex: _categoryIndex,
                    onChanged: (i) => setState(() => _categoryIndex = i),
                  ),
                  const SizedBox(height: AppSpacing.sectionGap),
                  if (listItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '이 카테고리에는 아직 추천 장소가 없어요',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    for (final item in listItems) ...[
                      RecommendationListRow(
                        title: item.title,
                        address: item.address,
                        icon: _categoryIcon(item.category),
                        onTap: () => _focusHero(item, heroItems),
                      ),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
