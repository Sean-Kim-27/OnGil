import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import '../controllers/map_controller.dart';
import '../models/schedule_item.dart';
// import 'package:url_launcher/url_launcher.dart';
import '../widgets/place_detail_bottom_sheet.dart';
import '../constants/app_color.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _controller = MapController();
  final TextEditingController _searchController = TextEditingController();

  // 🔽 하단에서 올라오는 장소 상세 바텀시트
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
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFC85A32);

    return Scaffold(
      body: Stack(
        children: [
          // 1. [배경] 카카오 지도 (마커 클릭 이벤트 추가)
          KakaoMap(
            onMapCreated: (controller) {
              _controller.setMapController(controller);
              _controller.fetchAndDrawSchedule(1);
            },
            center: _controller.currentCenter,
            markers: _controller.markers.toList(),
            polylines: _controller.polylines.toList(),
            onMarkerTap: (markerId, latLng, zoomLevel) {
              // 💡 1. 터치한 마커 위치로 카메라 중심을 부드럽게 이동!
              _controller.panTo(latLng);

              // 2. 장소 이름 찾기
              int index =
                  int.tryParse(markerId.replaceAll('schedule_', '')) ?? 0;
              String placeName = '선택한 장소';
              if (index < _controller.scheduleList.length) {
                placeName = _controller.scheduleList[index].title;
              }

              // 3. 바텀시트 띄우기
              _showPlaceDetailBottomSheet(context, placeName, latLng);
            },
          ),

          // 2. [상단] 검색바 & 위치 뱃지 ("경복궁 일대"로 자동 변경됨)
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

                    // 위치 표시 뱃지 (memory_place.name 반영)
                    Container(
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
                          Text(
                            '${_controller.selectedLocationName} ',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2C2825),
                            ),
                          ),
                          const Text(
                            '일대',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8A827A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. [하단] 선택된 장소 상세 카드 (마커 터치 시 노출)
          if (_controller.selectedScheduleItem != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 80,
              child: _buildPlaceDetailCard(_controller.selectedScheduleItem!),
            ),

          // 4. [하단] 스케줄링 시작하기 버튼
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, '/place_select');
                },
                icon: const Icon(Icons.route_outlined, color: Colors.white),
                label: const Text(
                  '스케줄링 시작하기',
                  style: TextStyle(
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
        ],
      ),
    );
  }

  // 하단 상세 카드 위젯
  Widget _buildPlaceDetailCard(ScheduleItem item) {
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
                if (item.category.isNotEmpty)
                  Text(
                    item.category,
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
    if (_controller.scheduleList.isEmpty && !_controller.isLoadingPlaceDetail) {
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
              const Icon(
                Icons.location_off_outlined,
                size: 48,
                color: AppColors.textIcon,
              ),
              const SizedBox(height: 12),
              const Text(
                '일정 장소 정보를 불러올 수 없습니다.',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _controller.fetchAndDrawSchedule(1),
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
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
