import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import '../models/schedule_item.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import '../services/kakao_api_service.dart';
import '../services/schedule_api_service.dart';

class MapController extends ChangeNotifier {
  Map<String, dynamic>? selectedPlaceDetail;
  bool isLoadingPlaceDetail = false;
  final Map<int, Uint8List> _markerBitmapCache = {};

  KakaoMapController? _kakaoMapController;

  LatLng currentCenter = LatLng(37.5776, 126.9768);
  String selectedLocationName = '경복궁'; // 기준 위치 이름
  String transportType = '도보';

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  List<ScheduleItem> scheduleList = [];

  ScheduleItem? selectedScheduleItem; // 💡 선택된 장소 정보 (바텀시트용)

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true; // 💡 파괴 상태 플래그 설정
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      // 💡 살아있을 때만 리스너 알림!
      super.notifyListeners();
    }
  }

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

  // 💡 카메라 중심 이동 헬퍼 메서드 추가
  void panTo(LatLng latLng) {
    _kakaoMapController?.setCenter(latLng);
  }

  // 🔍 마커 클릭 시 카카오 상세 정보 가져오기
  Future<void> fetchPlaceDetail(String placeName, LatLng latLng) async {
    isLoadingPlaceDetail = true;
    selectedPlaceDetail = null;
    notifyListeners();

    // 💡 서비스 클래스로 깔끔하게 호출
    final result = await KakaoApiService.fetchPlaceDetail(placeName, latLng);

    if (result != null) {
      selectedPlaceDetail = result;
    } else {
      selectedPlaceDetail = {
        'place_name': placeName,
        'address_name': '주소 정보 없음',
      };
    }

    isLoadingPlaceDetail = false;
    notifyListeners();
  }

  // 🎨 Flutter 위젯을 커스텀 마커 이미지(Uint8List)로 변환
  Future<Uint8List> _createCustomMarkerBitmap(int order) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(pictureRecorder);
    const double size = 90.0; // 마커 크기

    if (_markerBitmapCache.containsKey(order)) {
      return _markerBitmapCache[order]!; // 이미 만든 마커면 재사용!
    }

    // 1. 그림자 그리기
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(const Offset(size / 2, size / 2 + 2), 22, shadowPaint);

    // 2. 테두리 (흰색 배경)
    final Paint whiteBorderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(size / 2, size / 2), 22, whiteBorderPaint);

    // 3. 메인 주황색 원 (#C85A32)
    final Paint mainCirclePaint = Paint()..color = const Color(0xFFC85A32);
    canvas.drawCircle(const Offset(size / 2, size / 2), 18, mainCirclePaint);

    // 4. 숫자 텍스트 그리기
    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    textPainter.text = TextSpan(
      text: '$order',
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    // 5. 이미지 추출
    final ui.Image image = await pictureRecorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    final Uint8List bytes = byteData!.buffer.asUint8List();

    _markerBitmapCache[order] = bytes; // 캐시에 저장
    return bytes;
  }

  // 📡 실제 백엔드 스케줄 API 연동 및 자동 그리기
  Future<void> fetchAndDrawSchedule(int scheduleId) async {
    final data = await ScheduleApiService.fetchScheduleDetail(scheduleId);

    if (data == null) {
      debugPrint('⚠️ 일정 데이터를 불러오지 못했습니다.');
      notifyListeners();
      return;
    }

    if (data['memory_place'] != null && data['memory_place']['name'] != null) {
      selectedLocationName = data['memory_place']['name'];
    } else {
      selectedLocationName = data['title'] ?? '알 수 없는 위치';
    }

    transportType = (data['mobility_mode'] == 'WALK') ? '도보' : '차';

    final List<dynamic> placesJson = data['places'] ?? [];
    scheduleList =
        placesJson.map((item) => ScheduleItem.fromJson(item)).toList()
          ..sort((a, b) => a.visitOrder.compareTo(b.visitOrder));

    if (scheduleList.isNotEmpty) {
      List<LatLng> points = scheduleList
          .map((item) => LatLng(item.latitude, item.longitude))
          .toList();
      await drawScheduleRoute(points);
    }
  }

  // 🚗 길찾기 경로 및 마커 생성
  Future<void> drawScheduleRoute(List<LatLng> schedulePoints) async {
    if (schedulePoints.isEmpty) return;

    // 1. 마커 생성 (기존 비트맵 캐시 로직 동일)
    final List<Marker> customMarkers = [];
    for (int i = 0; i < schedulePoints.length; i++) {
      final orderNumber = i + 1;
      final markerBytes = await _createCustomMarkerBitmap(orderNumber);

      customMarkers.add(
        Marker(
          markerId: 'schedule_$i',
          latLng: schedulePoints[i],
          markerImageSrc: Uri.dataFromBytes(
            markerBytes,
            mimeType: 'image/png',
          ).toString(),
          width: 45,
          height: 45,
        ),
      );
    }
    markers = customMarkers.toSet();

    // 2. 💡 서비스 클래스를 활용한 구간별 길찾기 경로 생성
    List<LatLng> fullPathCoordinates = [];
    for (int i = 0; i < schedulePoints.length - 1; i++) {
      final routePoints = await KakaoApiService.fetchRoutePoints(
        schedulePoints[i],
        schedulePoints[i + 1],
      );
      fullPathCoordinates.addAll(routePoints);
    }

    final finalPoints = fullPathCoordinates.isNotEmpty
        ? fullPathCoordinates
        : schedulePoints;

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
