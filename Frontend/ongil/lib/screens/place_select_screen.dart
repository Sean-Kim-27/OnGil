import 'package:flutter/material.dart';
import '../controllers/schedule_creation_controller.dart';
import '../services/place_service.dart';
import '../widgets/home_search_bar.dart';

class PlaceSelectScreen extends StatefulWidget {
  /// 홈/지도에서 검색해서 얻은 실제 추천 장소들. null이거나 비어있으면
  /// 이 화면 자체에서 바로 검색할 수 있는 검색창을 보여줌(마지막으로 검색했던
  /// 주소가 있으면 자동으로 한 번 더 불러옴). 예전처럼 충주 더미 데이터는 안 씀.
  final List<RecommendedPlace>? places;

  const PlaceSelectScreen({super.key, this.places});

  @override
  State<PlaceSelectScreen> createState() => _PlaceSelectScreenState();
}

class _PlaceSelectScreenState extends State<PlaceSelectScreen> {
  final ScheduleCreationController _controller = ScheduleCreationController();

  // ScheduleCreationController의 스텝(1~4: 명소/숙소/카페/식당)을 PlaceService가
  // 매기는 카테고리 라벨(관광/숙박/카페/음식)에 매핑함.
  static const Map<int, String> _stepToCategory = {
    1: '관광',
    2: '숙박',
    3: '카페',
    4: '음식',
  };

  // 🐛 버그 수정: 예전엔 widget.places를 그대로 읽기만 하는 getter라서, 홈/지도를
  // 거치지 않고(예: 스케줄 탭의 '+ 새로운 스케줄 만들기'처럼 인자 없이) 이 화면에
  // 들어오면 "먼저 검색해주세요" 안내만 보여줄 뿐 정작 이 화면 자체에서는 검색할
  // 방법이 없었음. places를 로컬 state로 바꿔서 이 화면에서 직접 검색해 채울 수
  // 있게 함(홈 화면 검색과 동일한 PlaceService.fetchNearbyPlaces 사용).
  late List<RecommendedPlace> _places;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isSearching = false;

  List<RecommendedPlace> get _allPlaces => _places;

  List<RecommendedPlace> get _currentStepPlaces {
    final category = _stepToCategory[_controller.currentStep];
    return _allPlaces.where((p) => p.category == category).toList();
  }

  @override
  void initState() {
    super.initState();
    _places = widget.places ?? [];
    _controller.addListener(() {
      setState(() {});
    });
    // places 없이 들어온 경우, 홈 화면처럼 마지막으로 검색했던 주소가 있으면
    // 그 기준으로 한 번 더 자동 조회해줌 (완전히 빈 화면으로 시작하지 않도록).
    if (_places.isEmpty) {
      _restoreLastAddress();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _restoreLastAddress() async {
    final address = await PlaceService.instance.getLastAddress();
    if (address == null || address.isEmpty || !mounted) return;
    _searchCtrl.text = address;
    _search(address);
  }

  // 홈 화면(_searchAddress)과 동일한 로직: 주소로 근처 추천 장소를 조회해서
  // 이 화면의 4단계 선택 리스트를 바로 채움.
  Future<void> _search(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return;

    setState(() => _isSearching = true);
    await PlaceService.instance.saveLastAddress(trimmed);
    final result = await PlaceService.instance.fetchNearbyPlaces(trimmed);
    if (!mounted) return;

    setState(() {
      _places = result?.places ?? [];
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

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFC85A32);
    const bgColor = Color(0xFFFAF7F2);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: _controller.currentStep > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF2C2825), size: 20),
                onPressed: () => _controller.previousStep(),
              )
            : IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF2C2825)),
                onPressed: () => Navigator.pop(context),
              ),
        title: Text(
          '${_controller.currentStep}/4 단계',
          style: const TextStyle(
            color: primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 진행바 및 타이틀
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상단 프로그레스 바
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _controller.currentStep / 4,
                      backgroundColor: const Color(0xFFEFEBE4),
                      valueColor: const AlwaysStoppedAnimation<Color>(primaryColor),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${_controller.stepTitles[_controller.currentStep]}를\n선택해주세요',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C2825),
                      height: 1.3,
                    ),
                  ),
                  if (_controller.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _controller.errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),

            // 장소 선택 리스트 영역
            Expanded(
              child: _allPlaces.isEmpty
                  ? _buildSearchEmptyState()
                  : _currentStepPlaces.isEmpty
                      ? _buildEmptyState(
                          icon: Icons.location_off_outlined,
                          title: '이 근처엔 ${_controller.stepTitles[_controller.currentStep]} 추천 장소가 없어요',
                          subtitle: '다음 단계로 넘어가거나 다른 지역으로 다시 검색해보세요',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          itemCount: _currentStepPlaces.length,
                          itemBuilder: (context, index) {
                            final place = _currentStepPlaces[index];
                            final isSelected = _controller.currentStepSelectedIds.contains(place.title);

                            return GestureDetector(
                              onTap: () => _controller.togglePlaceSelection(place.title),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected ? primaryColor : const Color(0xFFEFEBE4),
                                    width: isSelected ? 2 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.03),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            place.title,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF2C2825),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            place.address.isNotEmpty
                                                ? place.address
                                                : (place.tags.isNotEmpty ? place.tags.first : ''),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF8A827A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      isSelected ? Icons.check_circle : Icons.add_circle_outline,
                                      color: isSelected ? primaryColor : const Color(0xFFACACAC),
                                      size: 26,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // 하단 버튼 (4단계 완료 시 바로 ai_schedule_working으로 전환)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_controller.currentStep < 4) {
                      _controller.nextStep();
                    } else {
                      // 4단계 선택 검증
                      if (!_controller.canGoNext) {
                        _controller.nextStep(); // 에러 메시지 띄우기용
                        return;
                      }

                      // 선택한 장소 '제목'들을 실제 RecommendedPlace 객체로 다시 매칭해서
                      // (좌표/카테고리 등 상세 정보까지) AI 로딩 화면으로 통째로 넘겨줌.
                      final selectedTitles = _controller.getAllSelectedPlaceIds.toSet();
                      final selectedPlaces =
                          _allPlaces.where((p) => selectedTitles.contains(p.title)).toList();

                      if (context.mounted) {
                        Navigator.pushReplacementNamed(
                          context,
                          '/ai_working',
                          arguments: selectedPlaces,
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _controller.currentStep == 4 ? 'AI 스케줄 생성하기' : '다음 단계로',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // '먼저 검색해주세요'로 막다른 길이던 화면 대신, 이 화면에서 바로 검색까지
  // 끝낼 수 있게 검색창 + 안내 문구를 함께 보여줌.
  Widget _buildSearchEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          HomeSearchBar(controller: _searchCtrl, onSubmitted: _search),
          if (_isSearching) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(
              minHeight: 2,
              color: Color(0xFFC85A32),
              backgroundColor: Color(0xFFEFEBE4),
            ),
          ],
          Expanded(
            child: _buildEmptyState(
              icon: Icons.search_off_rounded,
              title: '가고 싶은 동네를 검색해주세요',
              subtitle: '동네나 학교 이름으로 검색하면\n근처 실제 추천 장소가 여기 떠요',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: const Color(0xFFACACAC)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C2825),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF8A827A), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
