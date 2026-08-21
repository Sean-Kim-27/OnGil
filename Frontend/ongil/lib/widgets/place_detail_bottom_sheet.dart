import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/map_controller.dart';

class PlaceDetailBottomSheet extends StatelessWidget {
  final MapController controller;
  final String defaultPlaceName;

  const PlaceDetailBottomSheet({
    super.key,
    required this.controller,
    required this.defaultPlaceName,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final detail = controller.selectedPlaceDetail;
        final isLoading = controller.isLoadingPlaceDetail;

        return Container(
          height: MediaQuery.of(context).size.height * 0.35,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 드래그 핸들바
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              if (isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFC85A32),
                    ),
                  ),
                )
              else ...[
                // 장소명
                Text(
                  detail?['place_name'] ?? defaultPlaceName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // 카테고리
                if (detail?['category_group_name'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC85A32).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      detail!['category_group_name'],
                      style: const TextStyle(
                        color: Color(0xFFC85A32),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),

                // 주소
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        detail?['road_address_name'] ?? detail?['address_name'] ?? '주소 정보 없음',
                        style: TextStyle(color: Colors.grey[700], fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 전화번호
                if (detail?['phone'] != null && (detail!['phone'] as String).isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 18, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        detail['phone'] as String,
                        style: TextStyle(color: Colors.grey[700], fontSize: 14),
                      ),
                    ],
                  ),

                const Spacer(),

                // 카카오맵 상세페이지 열기 버튼
                if (detail?['place_url'] != null)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final Uri url = Uri.parse(detail!['place_url']);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        } else {
                          debugPrint('카카오맵 URL을 열 수 없습니다: $url');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC85A32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '카카오맵에서 상세 보기',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}