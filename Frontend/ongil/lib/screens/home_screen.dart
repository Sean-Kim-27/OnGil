import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/top_header.dart';
import '../widgets/home_search_bar.dart';
import '../widgets/main_feature_card.dart';
import '../widgets/quick_action_cards.dart';
import '../widgets/recommendation_card.dart';
import '../widgets/kakao_webview_screen.dart';
import '../controllers/app_shell_controller.dart';
import '../services/auth_service.dart';
import '../services/place_service.dart';
import 'settings_screen.dart';
import 'recommendation_list_screen.dart';
import 'schedule_list_screen.dart';
import 'map_screen.dart';
import 'guestbook_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 2; // '홈' 탭이 기본 선택 (0:지도 1:스케줄 2:홈 3:방명록 4:설정)
  String? _nickname;

  /// 지도 탭에 그려달라고 넘길 여정 id.
  int? _focusScheduleId;

  /// 방명록 탭을 열 때 어느 하위 탭으로 갈지. 0:방명록 1:아카이브.
  int _guestbookTabIndex = 0;

  final _addressCtrl = TextEditingController();
  bool _isSearching = false;
  NearbySearchResult? _searchResult;

  List<RecommendedPlace> get _places => _searchResult?.places ?? [];

  // 검색 전(또는 검색 결과가 비었을 때) 보여줄 예시 데이터.
  static const _fallbackRecommendations = [
    (
      tag: '충주 · 1998',
      title: '탄금대 · 충주',
      subtitle: '모교 앞 골목',
      accentColor: AppColors.accent,
    ),
    (
      tag: '충주 · 2001',
      title: '대소원면 문구점',
      subtitle: '초등학교 앞 거리',
      accentColor: AppColors.brand,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _checkSession();
    _loadProfile();
    _restoreLastAddress();
    // 다른 화면에서 온 탭 전환 요청을 받아서 처리.
    AppShellController.instance.addListener(_handleShellIntent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleShellIntent());
  }

  @override
  void dispose() {
    AppShellController.instance.removeListener(_handleShellIntent);
    _addressCtrl.dispose();
    super.dispose();
  }

  /// 대기 중인 탭 전환 요청을 한 번만 소비.
  void _handleShellIntent() {
    final intent = AppShellController.instance.consumePending();
    if (intent == null || !mounted) return;
    setState(() {
      _navIndex = intent.tabIndex;
      if (intent.focusScheduleId != null) {
        _focusScheduleId = intent.focusScheduleId;
      }
      if (intent.guestbookTabIndex != null) {
        _guestbookTabIndex = intent.guestbookTabIndex!;
      }
    });
  }

  // 로그인 세션이 없으면 홈 진입 즉시 로그인 화면으로 되돌려보냄.
  Future<void> _checkSession() async {
    final hasSession = await AuthService.instance.hasSession();
    if (!hasSession && mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  Future<void> _loadProfile() async {
    final nickname = await AuthService.instance.getNickname();
    if (mounted) setState(() => _nickname = nickname);
  }

  // 이전에 검색했던 주소가 있으면 검색창에 채워두고 그 기준으로 다시 조회함.
  Future<void> _restoreLastAddress() async {
    final address = await PlaceService.instance.getLastAddress();
    if (address == null || address.isEmpty || !mounted) return;
    _addressCtrl.text = address;
    _searchAddress(address);
  }

  // 주소를 저장하고 그 근처 추천 장소를 가져와 화면에 반영.
  Future<void> _searchAddress(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return;

    setState(() => _isSearching = true);
    await PlaceService.instance.saveLastAddress(trimmed);
    final result = await PlaceService.instance.fetchNearbyPlaces(trimmed);
    if (!mounted) return;

    setState(() {
      _searchResult = result;
      _isSearching = false;
    });

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('검색에 실패했어요. 다시 시도해주세요')),
      );
    } else if (result.places.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("'$trimmed' 근처 추천 장소를 찾지 못했어요")),
      );
    }
  }

  // 설정에서 돌아오면 '홈' 탭으로 되돌리고 프로필을 새로고침.
  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
        .then((_) {
      if (!mounted) return;
      setState(() => _navIndex = 2);
      _loadProfile();
    });
  }

  /// 홈의 '그때와 지금' 카드 → 방명록 탭의 아카이브.
  void _openArchive() {
    setState(() {
      _navIndex = 3;
      _guestbookTabIndex = 1;
    });
  }

  void _openRecommendationList() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecommendationListScreen(searchResult: _searchResult)),
    );
  }

  // 하단 탭에 따라 몸통을 바꿔줌. 홈 검색 결과는 지도 탭에도 넘김.
  Widget _buildTabBody(BuildContext context) {
    switch (_navIndex) {
      case 0:
        return MapScreen(
          searchResult: _searchResult,
          focusScheduleId: _focusScheduleId,
        );
      case 1:
        return const ScheduleListScreen();
      case 3:
        return GuestbookScreen(initialTabIndex: _guestbookTabIndex);
      case 2:
      default:
        return _buildHomeContent(context);
    }
  }

  Widget _buildHomeContent(BuildContext context) {
    final anchor = _searchResult?.anchor;
    // 홈 가로 목록은 거르지 않고 전체를 보여줌(필터는 추천 리스트 화면에서).
    final displayPlaces = _places;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
        ),
        child: Column(
          children: [
            const SizedBox(height: 6),
            TopHeader(onSettingsTap: _openSettings),
            const SizedBox(height: AppSpacing.sectionGap),
            _GreetingSection(nickname: _nickname),
            const SizedBox(height: AppSpacing.sectionGap),
            HomeSearchBar(controller: _addressCtrl, onSubmitted: _searchAddress),
            if (_isSearching) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.accent,
                backgroundColor: AppColors.line,
              ),
            ],
            const SizedBox(height: AppSpacing.sectionGap),
            MainFeatureCard(
              tag: anchor?.title,
              title: anchor != null ? '${anchor.title}, 지금은\n어떤 모습일까요' : null,
              subtitle: anchor != null
                  ? (_places.isNotEmpty
                      ? '반경 5km 안에서 추천 장소 ${_places.length}곳을 찾았어요'
                      : '근처 추천 장소를 찾지 못했어요')
                  : null,
              image: _searchResult?.heroImage,
              onTap: _openArchive,
            ),
            const SizedBox(height: AppSpacing.cardGap),
            QuickActionCards(
              onMapTap: () => setState(() => _navIndex = 0),
              onScheduleTap: () => setState(() => _navIndex = 1),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('추천리스트', style: AppTextStyles.cardTitle),
                GestureDetector(
                  onTap: _openRecommendationList,
                  child: Text(
                    '더보기',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 222,
              child: displayPlaces.isNotEmpty
                  ? ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: displayPlaces.length,
                      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.cardGap),
                      itemBuilder: (context, i) {
                        final place = displayPlaces[i];
                        return RecommendationCard(
                          tag: place.tags.isNotEmpty ? place.tags.first : place.category,
                          title: place.title,
                          subtitle: place.address,
                          accentColor: i.isEven ? AppColors.accent : AppColors.brand,
                          image: place.imageUrl != null ? NetworkImage(place.imageUrl!) : null,
                          onTap: () => openKakaoPlaceDetail(
                            context,
                            title: place.title,
                            latitude: place.latitude,
                            longitude: place.longitude,
                          ),
                        );
                      },
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: _fallbackRecommendations.length,
                      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.cardGap),
                      itemBuilder: (context, i) {
                        final item = _fallbackRecommendations[i];
                        return RecommendationCard(
                          tag: item.tag,
                          title: item.title,
                          subtitle: item.subtitle,
                          accentColor: item.accentColor,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _buildTabBody(context),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 4) {
            // '설정' 탭
            _openSettings();
          } else {
            setState(() {
              // 직접 탭을 누르면 '특정 여정 경로 보기' 요청은 해제.
              _focusScheduleId = null;
              // 하단 탭으로 방명록을 열면 기본 탭(글 목록)에서 시작.
              if (i == 3) _guestbookTabIndex = 0;
              _navIndex = i;
            });
          }
        },
      ),
    );
  }
}

/// 인사말 영역. 닉네임이 없으면 '회원'으로 대체.
class _GreetingSection extends StatelessWidget {
  final String? nickname;
  const _GreetingSection({this.nickname});

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
          '${nickname ?? '회원'}님, 오늘도\n추억 속을 걸어보세요',
          textAlign: TextAlign.center,
          style: AppTextStyles.heroGreeting,
        ),
      ],
    );
  }
}
