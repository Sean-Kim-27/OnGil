import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import '../models/schedule_model.dart';

class MapController extends ChangeNotifier {
  KakaoMapController? _kakaoMapController;

  LatLng currentCenter = LatLng(37.5776, 126.9768);
  String selectedLocationName = '경복궁'; // 기준 위치 이름
  String transportType = '도보';

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  List<ScheduleItem> scheduleList = [];

  ScheduleItem? selectedScheduleItem; // 💡 선택된 장소 정보 (바텀시트용)

  void setMapController(KakaoMapController controller) {
    _kakaoMapController = controller;
  }

  void setTransportType(String type) {
    transportType = type;
    notifyListeners();
  }

  void selectPlace(ScheduleItem item) {
    selectedScheduleItem = item;
    notifyListeners();
  }

  void clearSelectedPlace() {
    selectedScheduleItem = null;
    notifyListeners();
  }

  // 📡 실제 백엔드 스케줄 API 연동 및 자동 그리기
  Future<void> fetchAndDrawSchedule(int scheduleId) async {
    debugPrint('🚀 [1] fetchAndDrawSchedule 시작 (ID: $scheduleId)');

    final baseUrl = dotenv.env['BASE_URL'] ?? 'https://api.yourdomain.com';
    final url = Uri.parse('$baseUrl/schedulers/$scheduleId');

    debugPrint('token: ${dotenv.env['AUTH_TOKEN']}'); // 토큰 확인용 로그

    try {
      debugPrint('📡 [2] 백엔드 요청 보냄: $url');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['AUTH_TOKEN'] ?? ''}',
        },
      );

      debugPrint('📩 [3] 백엔드 응답 코드: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data['memory_place'] != null &&
            data['memory_place']['name'] != null) {
          selectedLocationName = data['memory_place']['name'];
        } else {
          selectedLocationName = data['title'] ?? '알 수 없는 위치';
        }

        transportType = (data['mobility_mode'] == 'WALK') ? '도보' : '차';

        final List<dynamic> placesJson = data['places'] ?? [];
        scheduleList =
            placesJson.map((item) => ScheduleItem.fromJson(item)).toList()
              ..sort((a, b) => a.visitOrder.compareTo(b.visitOrder));

        debugPrint('📍 [4] 파싱된 장소 개수: ${scheduleList.length}개');

        if (scheduleList.isNotEmpty) {
          List<LatLng> points = scheduleList
              .map((item) => LatLng(item.latitude, item.longitude))
              .toList();

          debugPrint('🚗 [5] drawScheduleRoute 실행 전 (좌표 ${points.length}개)');
          await drawScheduleRoute(points);
          debugPrint('✨ [6] drawScheduleRoute 완료!');
        } else {
          debugPrint('⚠️ [경고] scheduleList가 비어있습니다.');
        }
      } else {
        debugPrint('❌ 백엔드 API 에러 응답: ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('💥 [예외 발생]: $e');
      debugPrint('🔍 [스택트레이스]: $stackTrace');
    }
  }

  // 🚗 길찾기 경로 및 마커 생성
  Future<void> drawScheduleRoute(List<LatLng> schedulePoints) async {
    if (schedulePoints.isEmpty) {
      debugPrint('⚠️ [drawScheduleRoute] 넘겨받은 좌표가 없어!');
      return;
    }

    debugPrint('🏁 [drawScheduleRoute] 시작! 포인트 개수: ${schedulePoints.length}');

    // 1. 마커 생성
    markers = schedulePoints.asMap().entries.map((entry) {
      int idx = entry.key;
      return Marker(markerId: 'schedule_$idx', latLng: entry.value);
    }).toSet();
    debugPrint('📍 마커 ${markers.length}개 생성 완료');

    List<LatLng> fullPathCoordinates = [];

    // 2. 구간별 카카오 길찾기 API 호출
    for (int i = 0; i < schedulePoints.length - 1; i++) {
      final origin = schedulePoints[i];
      final destination = schedulePoints[i + 1];

      final url = Uri.parse(
        'https://apis-navi.kakaomobility.com/v1/directions'
        '?origin=${origin.longitude},${origin.latitude}'
        '&destination=${destination.longitude},${destination.latitude}'
        '&priority=RECOMMEND',
      );

      debugPrint('🛣️ [$i 구간] 길찾기 요청: $url');

      try {
        final response = await http.get(
          url,
          headers: {
            'Authorization': 'KakaoAK ${dotenv.env['KAKAO_REST_API_KEY']}',
          },
        );

        debugPrint('📩 [$i 구간] 응답 코드: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final routes = data['routes'];

          if (routes != null &&
              routes.isNotEmpty &&
              routes[0]['result_code'] == 0) {
            final sections = routes[0]['sections'];
            for (var section in sections) {
              for (var road in section['roads']) {
                List dynamicVertexes = road['vertexes'];
                for (int v = 0; v < dynamicVertexes.length; v += 2) {
                  double lng = (dynamicVertexes[v] as num).toDouble();
                  double lat = (dynamicVertexes[v + 1] as num).toDouble();
                  fullPathCoordinates.add(LatLng(lat, lng));
                }
              }
            }
            debugPrint(
              '✅ [$i 구간] 도로 좌표 추출 성공! 현재 총 좌표: ${fullPathCoordinates.length}개',
            );
          } else {
            debugPrint(
              '⚠️ [$i 구간] routes 결과 없음 또는 result_code 이상: ${routes?[0]?['result_code']}',
            );
          }
        } else {
          debugPrint('❌ [$i 구간] 카카오 길찾기 API 에러 응답: ${response.body}');
        }
      } catch (e) {
        debugPrint('💥 [$i 구간] 카카오 길찾기 API 호출 중 예외: $e');
      }
    }

    // 도로 좌표를 못 받아오면 직선 좌표라도 넣어서 예외 처리
    final finalPoints = fullPathCoordinates.isNotEmpty
        ? fullPathCoordinates
        : schedulePoints;

    debugPrint('🎨 최종 폴리라인에 그려질 좌표 총 개수: ${finalPoints.length}개');

    polylines = {
      Polyline(
        polylineId: 'schedule_path_${DateTime.now().millisecondsSinceEpoch}',
        points: finalPoints,
        strokeColor: const Color(0xFFC85A32),
        strokeWidth: 6,
        strokeOpacity: 0.9,
      ),
    };

    fitBounds(schedulePoints);
    notifyListeners();
  }

  // 🔍 카카오 REST API를 직접 호출하는 키워드 검색
  Future<void> searchAndMoveLocation(String keyword) async {
    if (keyword.isEmpty) return;

    final url = Uri.parse(
      'https://dapi.kakao.com/v2/local/search/keyword.json?query=${Uri.encodeComponent(keyword)}',
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'KakaoAK ${dotenv.env['KAKAO_REST_API_KEY']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List documents = data['documents'];

        if (documents.isNotEmpty) {
          polylines.clear(); // 기존 경로 선 제거

          final firstPlace = documents.first;
          final double lat = double.parse(firstPlace['y']);
          final double lng = double.parse(firstPlace['x']);
          final LatLng searchedLatLng = LatLng(lat, lng);

          currentCenter = searchedLatLng;
          selectedLocationName = firstPlace['place_name'];

          // 검색 결과 장소들에 마커 추가
          markers = documents.map((place) {
            return Marker(
              markerId: place['id'],
              latLng: LatLng(
                double.parse(place['y']),
                double.parse(place['x']),
              ),
            );
          }).toSet();

          // 지도 카메라 이동
          _kakaoMapController?.setCenter(searchedLatLng);
          notifyListeners();
        }
      } else {
        debugPrint('검색 실패 코드: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('위치 검색 오류: $e');
    }
  }

  // 📐 카메라 영역 자동 맞춤 계산 (중심점 및 레벨 조절)
  void fitBounds(List<LatLng> points) {
    if (points.isEmpty || _kakaoMapController == null) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // 1. 중심점 계산 및 이동
    currentCenter = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    _kakaoMapController?.setCenter(currentCenter);

    // 2. 좌표간 거리에 따른 적절한 지도 레벨(확대/축소) 계산
    double latDiff = (maxLat - minLat).abs();
    double lngDiff = (maxLng - minLng).abs();
    double maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    int level = 3; // 기본 레벨
    if (maxDiff > 0.5) {
      level = 8;
    } else if (maxDiff > 0.2) {
      level = 7;
    } else if (maxDiff > 0.1) {
      level = 6;
    } else if (maxDiff > 0.05) {
      level = 5;
    } else if (maxDiff > 0.02) {
      level = 4;
    } else {
      level = 3;
    }

    _kakaoMapController?.setLevel(level);
  }

  // 📍 마커 터치 처리
  void onMarkerTapped(String markerId) {
    if (markerId.startsWith('schedule_')) {
      final indexStr = markerId.replaceFirst('schedule_', '');
      final index = int.tryParse(indexStr);
      if (index != null && index < scheduleList.length) {
        selectPlace(scheduleList[index]);
      }
    }
  }
}
