import 'package:flutter/material.dart';
import '../controllers/schedule_creation_controller.dart';
import '../services/place_service.dart';
import 'schedule_info_screen.dart';

class PlaceSelectScreen extends StatefulWidget {
  /// 홈/지도에서 넘어온 검색 결과. 없으면 마지막 검색 주소로 불러옴.
  final NearbySearchResult? searchResult;

  const PlaceSelectScreen({super.key, this.searchResult});

  @override
  State<PlaceSelectScreen> createState() => _PlaceSelectScreenState();
}

class _PlaceSelectScreenState extends State<PlaceSelectScreen> {
  static const primaryColor = Color(0xFFC85A32);
  static const bgColor = Color(0xFFFAF7F2);

  final ScheduleCreationController _controller = ScheduleCreationController();

  // 선택 단계(1~4)를 PlaceService의 카테고리 라벨에 매핑.
  static const Map<int, String> _stepToCategory = {
    1: '관광',
    2: '숙박',
    3: '카페',
    4: '음식',
  };

  late List<RecommendedPlace> _places;
  PlaceAnchor? _anchor;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isSearching = false;

  List<RecommendedPlace> get _allPlaces => _places;

  List<RecommendedPlace> get _currentStepPlaces {
    final category = _stepToCategory[_controller.currentStep];
    return _allPlaces.where((p) => p.category == category).toList();
  }

  int get _selectedCount => _controller.getAllSelectedPlaceIds.length;

  @override
  void initState() {
    super.initState();
    _places = widget.searchResult?.places ?? [];
    _anchor = widget.searchResult?.anchor;
    if (_anchor != null && _anchor!.title.isNotEmpty) {
      _searchCtrl.text = _anchor!.title;
    }
    _controller.addListener(() {
      setState(() {});
    });
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

  /// 지역을 검색해 선택 목록과 스케줄 기준을 통째로 바꿈.
  Future<void> _search(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSearching = true);
    await PlaceService.instance.saveLastAddress(trimmed);
    final result = await PlaceService.instance.fetchNearbyPlaces(trimmed);
    if (!mounted) return;

    final previousAnchor = _anchor?.title;
    setState(() {
      _places = result?.places ?? [];
      _anchor = result?.anchor;
      _isSearching = false;
    });

    // 이전 지역에서 고른 장소는 목록에 없으므로 선택을 비움.
    if (result != null && previousAnchor != result.anchor.title) {
      _controller.reset();
    }

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

  Future<void> _goToInfoScreen() async {
    // 선택한 제목들을 실제 RecommendedPlace 객체로 되찾아 넘김.
    final selectedTitles = _controller.getAllSelectedPlaceIds.toSet();
    final selectedPlaces =
        _allPlaces.where((p) => selectedTitles.contains(p.title)).toList();

    final anchor = _anchor;
    if (anchor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('추억의 장소 정보가 없어요. 위에서 동네를 다시 검색해주세요'),
        ),
      );
      return;
    }

    if (selectedPlaces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('스케줄에 담을 장소를 한 곳 이상 선택해주세요')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduleInfoScreen(
          places: selectedPlaces,
          anchor: anchor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _controller.currentStep / 4,
                      backgroundColor: const Color(0xFFEFEBE4),
                      valueColor: const AlwaysStoppedAnimation<Color>(primaryColor),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${_controller.stepTitles[_controller.currentStep]}를\n선택해주세요',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C2825),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 이 화면 안에서 바로 지역을 바꿔 검색할 수 있는 검색창.
                  _SearchField(
                    controller: _searchCtrl,
                    onSubmitted: _search,
                    isSearching: _isSearching,
                  ),
                  if (_isSearching) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(
                      minHeight: 2,
                      color: primaryColor,
                      backgroundColor: Color(0xFFEFEBE4),
                    ),
                  ],
                  if (_anchor != null) ...[
                    const SizedBox(height: 10),
                    _AnchorBadge(
                      anchorTitle: _anchor!.title,
                      totalCount: _allPlaces.length,
                      selectedCount: _selectedCount,
                    ),
                  ],
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

            Expanded(
              child: _allPlaces.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.search_off_rounded,
                      title: '가고 싶은 동네를 검색해주세요',
                      subtitle: '위 검색창에 동네·역·학교 이름을 넣으면\n그 근처 실제 추천 장소가 여기 떠요',
                    )
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

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_controller.currentStep < 4) {
                      _controller.nextStep();
                      return;
                    }
                    if (!_controller.canGoNext) {
                      _controller.nextStep(); // 에러 메시지 띄우기용
                      return;
                    }
                    await _goToInfoScreen();
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

/// 지역 검색창.
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final bool isSearching;

  const _SearchField({
    required this.controller,
    required this.onSubmitted,
    required this.isSearching,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEFEBE4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 20, color: Color(0xFF8A827A)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              style: const TextStyle(fontSize: 14, color: Color(0xFF2C2825)),
              decoration: const InputDecoration(
                hintText: '동네, 역, 학교 이름으로 검색',
                hintStyle: TextStyle(color: Color(0xFFACACAC), fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (isSearching)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFC85A32),
              ),
            )
          else
            GestureDetector(
              onTap: () => onSubmitted(controller.text),
              child: const Text(
                '검색',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFC85A32),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 어떤 지역 기준으로 몇 곳 골랐는지 알려주는 뱃지.
class _AnchorBadge extends StatelessWidget {
  final String anchorTitle;
  final int totalCount;
  final int selectedCount;

  const _AnchorBadge({
    required this.anchorTitle,
    required this.totalCount,
    required this.selectedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFC85A32).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC85A32).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.my_location, size: 15, color: Color(0xFFC85A32)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$anchorTitle 기준 · 추천 $totalCount곳',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFC85A32),
              ),
            ),
          ),
          if (selectedCount > 0)
            Text(
              '선택 $selectedCount곳',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A827A),
              ),
            ),
        ],
      ),
    );
  }
}
