import 'package:flutter/material.dart';
import '../models/schedule.dart';
import '../widgets/category_icon_box.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import '../controllers/map_controller.dart';
import '../widgets/place_detail_bottom_sheet.dart';
import '../constants/app_color.dart';
import '../services/place_service.dart';

class MapScreen extends StatefulWidget {
  /// 홈에서 검색한 결과. 지도 검색창에서 다시 검색하면 그쪽이 우선함.
  final NearbySearchResult? searchResult;

  /// 이 여정의 경로를 그려달라는 요청.
  final int? focusScheduleId;

  const MapScreen({super.key, this.searchResult, this.focusScheduleId});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _controller = MapController();
  final TextEditingController _searchController = TextEditingController();

  /// 스케줄 생성의 기준. 지도 검색 결과가 있으면 그것, 없으면 홈 결과.
  NearbySearchResult? get _activeSearchResult =>
      _controller.nearbyResult ?? widget.searchResult;

  void _showPlaceDetailBottomSheet(
    BuildContext context,
    String placeName,
    LatLng latLng,
  ) {
    _controller.fetchPlaceDetail(placeName, latLng);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PlaceDetailBottomSheet(
        controller: _controller,
        defaultPlaceName: placeName,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // 경로 재생은 타이머로 자주 알림을 보내므로, 화면이 사라진 뒤 호출되지 않게 막는다.
      if (!mounted) return;
      setState(() {});
    });
    final anchorTitle = widget.searchResult?.anchor.title;
    if (anchorTitle != null && anchorTitle.isNotEmpty) {
      _searchController.text = anchorTitle;
    }
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 화면이 이미 떠 있는 상태에서 대상 여정만 바뀌어도 다시 그려줌.
    final focusId = widget.focusScheduleId;
    if (focusId != null && focusId != oldWidget.focusScheduleId) {
      // didUpdateWidget은 빌드 중에 불리므로 setState를 다음 프레임으로 미룸.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.fetchAndDrawSchedule(focusId);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  static bool _hasCoords(NearbySearchResult r) =>
      r.anchor.latitude != null && r.anchor.longitude != null;

  /// 지도 준비 직후 표시 대상 결정: 요청받은 경로 > 검색한 지역 > 마지막 여정.
  Future<void> _bootstrapMap() async {
    final focusId = widget.focusScheduleId;
    if (focusId != null) {
      await _controller.fetchAndDrawSchedule(focusId);
      return;
    }

    // 지도 검색이 홈 검색에 덮이지 않게 더 나중에 검색한 쪽을 기준으로 삼음.
    NearbySearchResult? best;
    final fromHome = widget.searchResult;
    if (fromHome != null && _hasCoords(fromHome)) best = fromHome;

    final cached = MapController.lastMapSearch;
    if (cached != null &&
        _hasCoords(cached) &&
        (best == null || cached.fetchedAt.isAfter(best.fetchedAt))) {
      best = cached;
    }

    if (best != null) {
      _controller.applyNearbyResult(best);
      final title = best.anchor.title;
      if (title.isNotEmpty) _searchController.text = title;
      await _controller.refreshSavedScheduleFlag();
      return;
    }

    await _controller.fetchAndDrawLastSchedule();
  }

  void _startScheduling() {
    Navigator.pushNamed(
      context,
      '/place_select',
      arguments: _activeSearchResult,
    );
  }

  Future<void> _showLastSchedule() async {
    final found = await _controller.fetchAndDrawLastSchedule();
    if (!mounted || found) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('아직 만든 여정이 없어요. 먼저 스케줄을 만들어보세요')),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFC85A32);
    final searchResult = _activeSearchResult;
    final hasRoute = _controller.scheduleList.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          KakaoMap(
            onMapCreated: (controller) {
              _controller.setMapController(controller);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _bootstrapMap();
              });
            },
            center: _controller.currentCenter,
            markers: _controller.markers.toList(),
            polylines: _controller.polylines.toList(),
            onMarkerTap: (markerId, latLng, zoomLevel) {
              _controller.panTo(latLng);

              // 마커 종류에 맞춰 이름을 찾음.
              _controller.onMarkerTapped(markerId);
              final placeName = _controller.resolveMarkerTitle(markerId);

              _showPlaceDetailBottomSheet(context, placeName, latLng);
            },
          ),

          // 여정 경로 재생 컨트롤
          if (_controller.hasPlayback)
            Positioned(
              left: 16,
              right: 16,
              bottom: 120,
              child: _RoutePlaybackBar(controller: _controller),
            ),

          // 상단 검색바 & 위치 뱃지
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12.0,
                  horizontal: 16.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.search,
                                  color: Color(0xFF8A827A),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    textInputAction: TextInputAction.search,
                                    onSubmitted: (value) {
                                      _controller.searchAndMoveLocation(value);
                                    },
                                    decoration: const InputDecoration(
                                      hintText: '지역을 검색해주세요',
                                      hintStyle: TextStyle(
                                        color: Color(0xFFACACAC),
                                        fontSize: 14,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                if (_controller.isSearchingNearby)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: primaryColor,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          height: 48,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              _buildTransportBtn('차', primaryColor),
                              _buildTransportBtn('도보', primaryColor),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  color: primaryColor,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _controller.selectedLocationName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2C2825),
                                    ),
                                  ),
                                ),
                                const Text(
                                  ' 일대',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF8A827A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (hasRoute) ...[
                          const SizedBox(width: 8),
                          _InfoPill(
                            icon: Icons.route_outlined,
                            label: '여정 경로 ${_controller.scheduleList.length}곳',
                          ),
                        ] else if (searchResult != null &&
                            searchResult.places.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _InfoPill(
                            icon: Icons.place_outlined,
                            label: '추천 ${searchResult.places.length}곳',
                          ),
                        ],
                      ],
                    ),

                    if (_controller.searchMessage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _controller.searchMessage!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8A827A),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          _buildMapOverlay(),

          // 마커 터치 시 뜨는 장소 상세 카드
          if (_controller.selectedScheduleItem != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 80,
              child: _buildPlaceDetailCard(_controller.selectedScheduleItem!),
            ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _startScheduling,
                      icon: const Icon(Icons.route_outlined, color: Colors.white),
                      label: Text(
                        searchResult != null && searchResult.places.isNotEmpty
                            ? '${searchResult.anchor.title} 기준 스케줄링'
                            : '스케줄링 시작하기',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ),
                ),
                // 경로가 없고 저장된 여정이 있으면 다시 볼 수 있게 해줌.
                if (!hasRoute && _controller.hasSavedSchedule) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 54,
                    width: 54,
                    child: ElevatedButton(
                      onPressed: _showLastSchedule,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 4,
                      ),
                      child: const Icon(Icons.timeline, color: primaryColor),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceDetailCard(SchedulePlace item) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (item.imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                item.imageUrl,
                width: 70,
                height: 70,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 70,
                  height: 70,
                  color: Colors.grey[200],
                  child: const Icon(
                    Icons.image_not_supported,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '방문 순서 ${item.visitOrder}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC85A32),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C2825),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (categoryLabel(item.category).isNotEmpty)
                  Text(
                    categoryLabel(item.category),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A827A),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            onPressed: () {
              _controller.clearSelectedPlace();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTransportBtn(String label, Color activeColor) {
    final isSelected = _controller.transportType == label;
    return GestureDetector(
      onTap: () {
        _controller.setTransportType(label);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : const Color(0xFF8A827A),
          ),
        ),
      ),
    );
  }

  Widget _buildMapOverlay() {
    if (_controller.isLoadingSchedule) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    // 검색 결과가 떠 있으면 안내 카드가 지도를 가리지 않게 숨김.
    final hasSearchMarkers = (_activeSearchResult?.places.isNotEmpty ?? false);
    if (hasSearchMarkers) return const SizedBox.shrink();

    if (_controller.scheduleList.isEmpty && !_controller.isLoadingPlaceDetail) {
      final hasTriedBefore = _controller.lastAttemptedScheduleId != null;
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: AppColors.cardShadow,
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasTriedBefore ? Icons.location_off_outlined : Icons.route_outlined,
                size: 48,
                color: AppColors.textIcon,
              ),
              const SizedBox(height: 12),
              Text(
                _controller.scheduleError?.userMessage ??
                    (hasTriedBefore
                        ? '이 여정에는 지도에 표시할 장소가 없어요.'
                        : '아직 만든 스케줄이 없어요.'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hasTriedBefore
                    ? '위 검색창에서 지역을 검색하면 그 근처로 새 스케줄을 만들 수 있어요'
                    : '위 검색창에서 가고 싶은 지역을 검색한 뒤\n"스케줄링 시작하기"를 눌러보세요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              if (hasTriedBefore) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _controller.fetchAndDrawLastSchedule(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '다시 시도',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 지도 상단의 작은 정보 알약.
class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFC85A32).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// 지도 위에 뜨는 여정 경로 재생 컨트롤.
///
/// 재생을 누르면 저장한 방문 순서대로 지도를 따라 움직이며 보여준다.
class _RoutePlaybackBar extends StatelessWidget {
  final MapController controller;

  const _RoutePlaybackBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFC85A32);

    final label = controller.playbackLabel;
    final total = controller.scheduleList.length;
    final current = controller.playbackStopIndex + 1;
    final finished = !controller.isPlayingRoute && controller.playbackProgress >= 1.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      controller.isPlayingRoute || controller.playbackProgress > 0
                          ? '$current / $total번째 장소'
                          : '여정 경로 따라가기',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8A827A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label ?? '경로를 재생해보세요',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: controller.isDwelling
                            ? primaryColor
                            : const Color(0xFF2C2825),
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.playbackProgress > 0)
                IconButton(
                  tooltip: '처음부터',
                  onPressed: controller.restartRoutePlayback,
                  icon: const Icon(Icons.replay, size: 20, color: Color(0xFF8A827A)),
                ),
              GestureDetector(
                onTap: () {
                  if (controller.isPlayingRoute) {
                    controller.pauseRoutePlayback();
                  } else if (finished) {
                    controller.restartRoutePlayback();
                  } else {
                    controller.startRoutePlayback();
                  }
                },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    controller.isPlayingRoute
                        ? Icons.pause
                        : (finished ? Icons.replay : Icons.play_arrow),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: controller.playbackProgress,
              minHeight: 4,
              backgroundColor: const Color(0xFFEFEBE4),
              valueColor: const AlwaysStoppedAnimation<Color>(primaryColor),
            ),
          ),
        ],
      ),
    );
  }
}
