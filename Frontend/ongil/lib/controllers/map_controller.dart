import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import '../models/schedule.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import '../services/kakao_api_service.dart';
import '../services/place_service.dart';
import '../services/schedule_api_service.dart';

class MapController extends ChangeNotifier {
  Map<String, dynamic>? selectedPlaceDetail;
  bool isLoadingPlaceDetail = false;
  final Map<int, Uint8List> _markerBitmapCache = {};

  KakaoMapController? _kakaoMapController;

  LatLng currentCenter = LatLng(37.5776, 126.9768);
  String selectedLocationName = '경복궁'; // 기준 위치 이름
  String transportType = '도보';
  bool isLoadingSchedule = false;
  /// null이면 아직 조회를 시도한 적 없음(온보딩 안내), 값이 있으면 시도했었음.
  String? lastAttemptedScheduleId;

  /// 마지막 조회가 왜 실패했는지. 화면이 원인별 안내를 띄우는 데 씀.
  ScheduleApiException? scheduleError;

  /// 지도에서 마지막으로 검색한 주변 추천 결과. 있으면 스케줄 생성의 기준이 됨.
  NearbySearchResult? nearbyResult;

  /// 탭을 옮겼다 돌아와도 검색해둔 지역을 잃지 않게 하는 캐시.
  static NearbySearchResult? lastMapSearch;

  bool isSearchingNearby = false;

  /// 검색 결과에 대해 사용자에게 알려줄 짧은 안내.
  String? searchMessage;

  /// 저장된 스케줄이 있는지(= '최근 여정 경로 보기' 노출 여부).
  bool hasSavedSchedule = false;

  /// 현재 지도에 경로가 그려진 스케줄 id.
  int? drawnScheduleId;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  List<SchedulePlace> scheduleList = [];

  // ---------------------------------------------------------------------------
  // 경로 재생 (지도 위에서 여정을 따라 움직이며 보여주기)
  // ---------------------------------------------------------------------------

  /// 재생에 쓸 전체 경로 좌표. 차량이면 도로 경로, 도보면 장소를 직선으로 이은 것.
  List<LatLng> _playbackPath = const [];

  /// _playbackPath에서 각 방문 장소가 놓인 인덱스. 도착 판정에 씀.
  List<int> _stopIndices = const [];

  Timer? _playbackTimer;

  bool isPlayingRoute = false;

  /// 재생이 끝난 뒤에도 컨트롤 바를 유지하기 위한 플래그.
  bool hasPlayback = false;

  /// 0.0 ~ 1.0. 진행 바에 씀.
  double playbackProgress = 0.0;

  /// 지금 향하고 있는(또는 방금 도착한) 장소의 순번. 0부터.
  int playbackStopIndex = 0;

  /// 장소에 도착해 잠시 머무는 중인지. 캡션을 강조하는 데 씀.
  bool isDwelling = false;

  /// 재생 중 화면에 띄울 현재 장소 이름.
  String? get playbackLabel {
    if (scheduleList.isEmpty) return null;
    final i = playbackStopIndex.clamp(0, scheduleList.length - 1);
    return scheduleList[i].title;
  }

  /// 전체 경로에서 지금까지 진행한 좌표 인덱스.
  int _cursor = 0;

  /// 한 프레임에 몇 개의 좌표를 건너뛸지. 경로가 길수록 크게 잡아 총 재생 시간을 맞춘다.
  int _step = 1;

  /// 도착 후 머무는 프레임 수.
  int _dwellFrames = 0;

  /// 프레임 간격. 카카오 지도는 WebView라 너무 촘촘하면 끊긴다.
  static const Duration _frameInterval = Duration(milliseconds: 70);

  /// 전체 재생 목표 시간(대략).
  static const int _targetFrames = 200;

  /// markerId 'nearby_{i}' 를 되짚기 위한 목록 (nearbyResult.places 와 인덱스 동일).
  List<RecommendedPlace> get nearbyPlaces => nearbyResult?.places ?? const [];

  /// 마커를 눌러 선택한 장소(바텀시트용).
  SchedulePlace? selectedScheduleItem;

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  void setMapController(KakaoMapController controller) {
    _kakaoMapController = controller;
  }

  void setTransportType(String type) {
    if (transportType == type) return;
    transportType = type;
    notifyListeners();
    // 도보는 직선, 차량은 도로 경로라 이동수단이 바뀌면 다시 그려야 함.
    if (scheduleList.length > 1) {
      final points = scheduleList
          .map((item) => LatLng(item.latitude!, item.longitude!))
          .toList();
      drawScheduleRoute(points);
    }
  }

  void selectPlace(SchedulePlace item) {
    selectedScheduleItem = item;
    notifyListeners();
  }

  void clearSelectedPlace() {
    selectedScheduleItem = null;
    notifyListeners();
  }

  void panTo(LatLng latLng) {
    _kakaoMapController?.setCenter(latLng);
  }

  /// 이미 확보한 좌표로 지도만 이동(검색 API를 다시 부르지 않음).
  void moveToAnchor(String name, LatLng latLng) {
    currentCenter = latLng;
    selectedLocationName = name;
    _kakaoMapController?.setCenter(latLng);
    notifyListeners();
  }

  /// '최근 여정 경로 보기' 버튼 노출 여부를 갱신.
  Future<void> refreshSavedScheduleFlag() async {
    final id = await ScheduleApiService.getLastScheduleId();
    hasSavedSchedule = id != null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 검색
  // ---------------------------------------------------------------------------

  /// 주변 추천 검색을 먼저 시도하고, 실패하면 카카오 키워드 검색으로 카메라만 옮김.
  Future<void> searchAndMoveLocation(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    isSearchingNearby = true;
    searchMessage = null;
    notifyListeners();

    NearbySearchResult? result;
    try {
      result = await PlaceService.instance.fetchNearbyPlaces(trimmed);
    } catch (e) {
      debugPrint('💥 [MapController] 주변 추천 검색 실패: $e');
    }

    final anchor = result?.anchor;
    final hasAnchorCoords =
        anchor != null && anchor.latitude != null && anchor.longitude != null;

    if (result != null && hasAnchorCoords) {
      await PlaceService.instance.saveLastAddress(trimmed);
      applyNearbyResult(result);
      isSearchingNearby = false;
      if (result.places.isEmpty) {
        searchMessage = "'$trimmed' 근처에서 추천 장소를 찾지 못했어요";
      }
      notifyListeners();
      return;
    }

    final moved = await _searchWithKakao(trimmed);
    isSearchingNearby = false;
    searchMessage = moved
        ? '이 지역의 추천 장소를 불러오지 못했어요. 동네·역·학교 이름으로 다시 검색해보세요'
        : "'$trimmed' 위치를 찾지 못했어요";
    notifyListeners();
  }

  /// 검색 결과를 지도에 반영. 홈에서 넘어온 결과에도 같이 씀.
  void applyNearbyResult(NearbySearchResult result, {bool moveCamera = true}) {
    nearbyResult = result;
    lastMapSearch = result;
    searchMessage = null;

    // 지역이 바뀌었으므로 이전 여정 경로는 지움.
    polylines = {};
    scheduleList = [];
    selectedScheduleItem = null;
    drawnScheduleId = null;
    scheduleError = null;

    final anchor = result.anchor;
    if (anchor.title.isNotEmpty) selectedLocationName = anchor.title;

    final points = <LatLng>[];
    final placeMarkers = <Marker>[];

    if (anchor.latitude != null && anchor.longitude != null) {
      final anchorLatLng = LatLng(anchor.latitude!, anchor.longitude!);
      currentCenter = anchorLatLng;
      points.add(anchorLatLng);
      placeMarkers.add(Marker(markerId: 'anchor', latLng: anchorLatLng));
    }

    for (var i = 0; i < result.places.length; i++) {
      final p = result.places[i];
      if (!p.hasCoordinates) continue;
      final latLng = LatLng(p.latitude!, p.longitude!);
      points.add(latLng);
      // 마커 탭에서 장소를 되찾으려면 인덱스가 result.places와 같아야 함.
      placeMarkers.add(Marker(markerId: 'nearby_$i', latLng: latLng));
    }

    markers = placeMarkers.toSet();

    if (moveCamera) {
      if (points.length > 1) {
        fitBounds(points);
      } else if (points.isNotEmpty) {
        _kakaoMapController?.setCenter(points.first);
        _kakaoMapController?.setLevel(5);
      }
    }

    notifyListeners();
  }

  void clearNearbyResult() {
    nearbyResult = null;
    lastMapSearch = null;
    markers = {};
    searchMessage = null;
    notifyListeners();
  }

  /// 추천 장소를 못 얻었을 때의 폴백 — 카메라만 이동.
  Future<bool> _searchWithKakao(String keyword) async {
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
          polylines = {}; // 기존 경로 선 제거
          scheduleList = [];
          drawnScheduleId = null;

          final firstPlace = documents.first;
          final double lat = double.parse(firstPlace['y']);
          final double lng = double.parse(firstPlace['x']);
          final LatLng searchedLatLng = LatLng(lat, lng);

          currentCenter = searchedLatLng;
          selectedLocationName = firstPlace['place_name'];

          markers = documents.map<Marker>((place) {
            return Marker(
              markerId: 'kakao_${place['id']}',
              latLng: LatLng(
                double.parse(place['y']),
                double.parse(place['x']),
              ),
            );
          }).toSet();

          _kakaoMapController?.setCenter(searchedLatLng);
          return true;
        }
      } else {
        debugPrint('검색 실패 코드: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('위치 검색 오류: $e');
    }
    return false;
  }

  Future<void> fetchPlaceDetail(String placeName, LatLng latLng) async {
    isLoadingPlaceDetail = true;
    selectedPlaceDetail = null;
    notifyListeners();

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

  /// 방문 순서 숫자가 박힌 원형 마커 이미지를 만들어 캐시함.
  Future<Uint8List> _createCustomMarkerBitmap(int order) async {
    if (_markerBitmapCache.containsKey(order)) {
      return _markerBitmapCache[order]!; // 이미 만든 마커면 재사용!
    }

    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(pictureRecorder);
    const double size = 90.0; // 마커 크기

    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(const Offset(size / 2, size / 2 + 2), 22, shadowPaint);

    final Paint whiteBorderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(size / 2, size / 2), 22, whiteBorderPaint);

    final Paint mainCirclePaint = Paint()..color = const Color(0xFFC85A32);
    canvas.drawCircle(const Offset(size / 2, size / 2), 18, mainCirclePaint);

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

  Future<void> fetchAndDrawSchedule(int scheduleId) async {
    isLoadingSchedule = true;
    lastAttemptedScheduleId = '$scheduleId';
    // 이전 마커/경로가 새 여정과 섞이지 않게 먼저 비움.
    polylines = {};
    markers = {};
    selectedScheduleItem = null;
    notifyListeners();

    ScheduleDetail detail;
    try {
      detail = await ScheduleApiService.fetchScheduleDetail(scheduleId);
    } on ScheduleApiException catch (e) {
      debugPrint('⚠️ 일정 데이터를 불러오지 못했습니다: $e');
      scheduleError = e;
      isLoadingSchedule = false;
      notifyListeners();
      return;
    }

    scheduleError = null;
    drawnScheduleId = scheduleId;
    hasSavedSchedule = true;
    final memoryPlace = detail.memoryPlace;
    selectedLocationName =
        (memoryPlace != null && memoryPlace.name.isNotEmpty) ? memoryPlace.name : detail.title;

    transportType = detail.isWalking ? '도보' : '차';

    // 좌표가 없는 장소는 지도에 찍을 수 없으므로 경로에서 제외.
    scheduleList = detail.routePlaces;
    final dropped = detail.places.length - scheduleList.length;
    if (dropped > 0) {
      debugPrint('⚠️ 좌표가 없어 지도에서 제외한 장소 $dropped곳');
    }

    isLoadingSchedule = false;

    if (scheduleList.isNotEmpty) {
      final points = scheduleList
          .map((item) => LatLng(item.latitude!, item.longitude!))
          .toList();
      await drawScheduleRoute(points);
    } else {
      notifyListeners();
    }
  }

  /// 마지막으로 만든 스케줄을 그림. 만든 적이 없으면 false를 돌려줌.
  Future<bool> fetchAndDrawLastSchedule() async {
    final lastId = await ScheduleApiService.getLastScheduleId();
    hasSavedSchedule = lastId != null;
    if (lastId == null) {
      notifyListeners();
      return false;
    }
    await fetchAndDrawSchedule(lastId);
    return true;
  }

  Future<void> drawScheduleRoute(List<LatLng> schedulePoints) async {
    if (schedulePoints.isEmpty) return;

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

    // 카카오 길찾기는 자동차 기준이라, 도보는 직선으로 연결함.
    List<LatLng> fullPathCoordinates = [];
    if (transportType != '도보') {
      for (int i = 0; i < schedulePoints.length - 1; i++) {
        final routePoints = await KakaoApiService.fetchRoutePoints(
          schedulePoints[i],
          schedulePoints[i + 1],
        );
        fullPathCoordinates.addAll(routePoints);
      }
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

    // 경로 재생에 쓸 좌표를 같이 준비해둔다.
    _preparePlayback(schedulePoints, finalPoints);

    fitBounds(schedulePoints);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 경로 재생
  // ---------------------------------------------------------------------------

  /// 재생용 경로와 '각 장소가 경로의 몇 번째 좌표인지'를 미리 계산해둔다.
  ///
  /// 도로 경로(fullPath)는 장소 좌표와 정확히 일치하지 않으므로,
  /// 장소마다 가장 가까운 경로 좌표를 찾아 도착 지점으로 삼는다.
  void _preparePlayback(List<LatLng> stops, List<LatLng> path) {
    stopRoutePlayback(reset: true);

    if (stops.length < 2 || path.length < 2) {
      _playbackPath = const [];
      _stopIndices = const [];
      hasPlayback = false;
      return;
    }

    _playbackPath = path;

    final indices = <int>[];
    var searchFrom = 0;
    for (var s = 0; s < stops.length; s++) {
      if (s == 0) {
        indices.add(0);
        continue;
      }
      if (s == stops.length - 1) {
        indices.add(path.length - 1);
        continue;
      }
      // 경로를 앞에서부터 훑으며 이 장소에 가장 가까운 지점을 찾는다.
      var bestIndex = searchFrom;
      var bestDist = double.infinity;
      for (var i = searchFrom; i < path.length; i++) {
        final d = _squaredDistance(path[i], stops[s]);
        if (d < bestDist) {
          bestDist = d;
          bestIndex = i;
        }
      }
      indices.add(bestIndex);
      searchFrom = bestIndex;
    }

    _stopIndices = indices;
    // 총 재생 시간이 경로 길이와 무관하게 비슷하도록 보폭을 맞춘다.
    _step = (path.length / _targetFrames).ceil().clamp(1, 999);
    hasPlayback = true;
  }

  /// 위경도 차이의 제곱합. 순위 비교에만 쓰므로 실제 거리로 환산하지 않는다.
  double _squaredDistance(LatLng a, LatLng b) {
    final dLat = a.latitude - b.latitude;
    final dLng = a.longitude - b.longitude;
    return dLat * dLat + dLng * dLng;
  }

  /// 여정을 따라 움직이며 보여주기 시작.
  Future<void> startRoutePlayback() async {
    if (!hasPlayback || _playbackPath.length < 2) return;

    // 끝까지 재생한 상태에서 다시 누르면 처음부터.
    if (_cursor >= _playbackPath.length - 1) _cursor = 0;

    isPlayingRoute = true;
    _playbackTimer?.cancel();

    await _renderPlaybackFrame();

    _playbackTimer = Timer.periodic(_frameInterval, (_) async {
      if (_isDisposed) return;

      // 장소에 도착하면 잠깐 머문다.
      if (_dwellFrames > 0) {
        _dwellFrames--;
        if (_dwellFrames == 0) {
          isDwelling = false;
          notifyListeners();
        }
        return;
      }

      _cursor += _step;

      if (_cursor >= _playbackPath.length - 1) {
        _cursor = _playbackPath.length - 1;
        await _renderPlaybackFrame();
        stopRoutePlayback();
        return;
      }

      _updateStopProgress();
      await _renderPlaybackFrame();
    });

    notifyListeners();
  }

  void pauseRoutePlayback() {
    if (!isPlayingRoute) return;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    isPlayingRoute = false;
    notifyListeners();
  }

  /// 재생 중지. [reset]이면 처음 상태로 되돌리고 전체 경로를 다시 그린다.
  void stopRoutePlayback({bool reset = false}) {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    isPlayingRoute = false;
    isDwelling = false;
    _dwellFrames = 0;

    if (reset) {
      _cursor = 0;
      playbackProgress = 0.0;
      playbackStopIndex = 0;
    }
    notifyListeners();
  }

  /// 처음부터 다시.
  Future<void> restartRoutePlayback() async {
    _cursor = 0;
    playbackProgress = 0.0;
    playbackStopIndex = 0;
    await startRoutePlayback();
  }

  /// 현재 커서가 어느 장소를 지났는지 갱신하고, 막 도착했으면 머무름을 건다.
  void _updateStopProgress() {
    for (var i = playbackStopIndex + 1; i < _stopIndices.length; i++) {
      if (_cursor >= _stopIndices[i]) {
        playbackStopIndex = i;
        isDwelling = true;
        // 도착 시 약 0.9초 머무름.
        _dwellFrames = (900 / _frameInterval.inMilliseconds).round();
      } else {
        break;
      }
    }
  }

  /// 한 프레임 그리기: 지나온 경로 + 이동 마커 + 카메라 추적.
  Future<void> _renderPlaybackFrame() async {
    if (_playbackPath.isEmpty) return;

    final index = _cursor.clamp(0, _playbackPath.length - 1);
    final current = _playbackPath[index];
    playbackProgress = index / (_playbackPath.length - 1);

    final traveled = _playbackPath.sublist(0, index + 1);
    final remaining = _playbackPath.sublist(index);

    polylines = {
      // 남은 경로는 흐리게 깔아두고
      if (remaining.length > 1)
        Polyline(
          polylineId: 'playback_remaining',
          points: remaining,
          strokeColor: const Color(0xFFC85A32),
          strokeWidth: 5,
          strokeOpacity: 0.25,
        ),
      // 지나온 경로를 진하게 덮는다
      if (traveled.length > 1)
        Polyline(
          polylineId: 'playback_traveled',
          points: traveled,
          strokeColor: const Color(0xFFC85A32),
          strokeWidth: 6,
          strokeOpacity: 0.95,
        ),
    };

    final moverBytes = await _createMoverMarkerBitmap();
    markers = {
      ...markers.where((m) => m.markerId != 'playback_mover'),
      Marker(
        markerId: 'playback_mover',
        latLng: current,
        markerImageSrc:
            Uri.dataFromBytes(moverBytes, mimeType: 'image/png').toString(),
        width: 46,
        height: 46,
      ),
    };

    currentCenter = current;
    _kakaoMapController?.setCenter(current);

    notifyListeners();
  }

  Uint8List? _moverBitmapCache;

  /// 이동 중임을 나타내는 마커. 순번 마커와 구분되도록 다른 모양으로 그린다.
  Future<Uint8List> _createMoverMarkerBitmap() async {
    final cached = _moverBitmapCache;
    if (cached != null) return cached;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const double size = 92.0;
    const center = Offset(size / 2, size / 2);

    // 바깥 헤일로
    canvas.drawCircle(
      center,
      30,
      Paint()..color = const Color(0xFFC85A32).withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      center,
      22,
      Paint()..color = const Color(0xFFC85A32).withValues(alpha: 0.30),
    );
    // 흰 테두리 + 본체
    canvas.drawCircle(center, 15, Paint()..color = Colors.white);
    canvas.drawCircle(center, 11, Paint()..color = const Color(0xFFC85A32));

    final image = await recorder.endRecording().toImage(
          size.toInt(),
          size.toInt(),
        );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    _moverBitmapCache = bytes;
    return bytes;
  }

  /// 모든 좌표가 화면에 들어오도록 중심과 확대 레벨을 맞춤.
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

    currentCenter = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    _kakaoMapController?.setCenter(currentCenter);

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

  void onMarkerTapped(String markerId) {
    if (markerId.startsWith('schedule_')) {
      final indexStr = markerId.replaceFirst('schedule_', '');
      final index = int.tryParse(indexStr);
      if (index != null && index < scheduleList.length) {
        selectPlace(scheduleList[index]);
      }
    }
  }

  /// 마커 id('schedule_{i}' / 'nearby_{i}' / 'anchor')로 장소 이름을 되찾음.
  String resolveMarkerTitle(String markerId) {
    if (markerId.startsWith('schedule_')) {
      final index = int.tryParse(markerId.replaceFirst('schedule_', ''));
      if (index != null && index >= 0 && index < scheduleList.length) {
        return scheduleList[index].title;
      }
    } else if (markerId.startsWith('nearby_')) {
      final index = int.tryParse(markerId.replaceFirst('nearby_', ''));
      final places = nearbyPlaces;
      if (index != null && index >= 0 && index < places.length) {
        return places[index].title;
      }
    } else if (markerId == 'anchor') {
      return nearbyResult?.anchor.title ?? selectedLocationName;
    }
    return '선택한 장소';
  }
}
