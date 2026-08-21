import 'package:flutter/foundation.dart';

/// 스케줄(여정) 도메인 모델. 서버 응답 파싱을 한곳에 모아둠.

// ---------------------------------------------------------------------------
// 공용 파서
// ---------------------------------------------------------------------------

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String? _toStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? _toDateTime(dynamic v) {
  final s = _toStringOrNull(v);
  if (s == null) return null;
  return DateTime.tryParse(s)?.toLocal();
}

/// 모델이 모르는 응답 필드를 디버그 빌드에서만 찍어줌.
void _reportUnknownKeys(String modelName, Map<String, dynamic> json, Set<String> known) {
  if (!kDebugMode) return;
  final unknown = json.keys.where((k) => !known.contains(k)).toList();
  if (unknown.isNotEmpty) {
    debugPrint('ℹ️ [$modelName] 모델이 아직 안 쓰는 응답 필드: ${unknown.join(', ')}');
  }
}

// ---------------------------------------------------------------------------
// 라벨 변환 (서버 enum → 화면 문구)
// ---------------------------------------------------------------------------

/// 모르는 값은 한글로 넘겨짚지 않고 영문 원본을 그대로 보여줌.
String _labelOr(String? raw, Map<String, String> table) {
  if (raw == null) return '';
  return table[raw.toUpperCase()] ?? raw;
}

const _mobilityLabels = {
  'WALK': '도보',
  'CAR': '차량',
  'DRIVE': '차량',
  'PUBLIC': '대중교통',
  'TRANSIT': '대중교통',
};

const _tripTypeLabels = {
  'DAY_TRIP': '당일치기',
  'OVERNIGHT': '숙박',
};

const _companionLabels = {
  'ALONE': '혼자',
  'SOLO': '혼자',
  'COUPLE': '연인',
  'FAMILY': '가족',
  'FRIEND': '친구',
  'FRIENDS': '친구',
};

// ---------------------------------------------------------------------------
// 추억의 장소 (여정의 기준점)
// ---------------------------------------------------------------------------

class MemoryPlace {
  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;

  const MemoryPlace({
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  factory MemoryPlace.fromJson(Map<String, dynamic> json) {
    _reportUnknownKeys('MemoryPlace', json, const {
      'id', 'name', 'address', 'address_detail', 'latitude', 'longitude',
      'created_at', 'updated_at',
    });
    return MemoryPlace(
      name: _toStringOrNull(json['name']) ?? '',
      address: _toStringOrNull(json['address']) ?? _toStringOrNull(json['address_detail']),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
    );
  }
}

// ---------------------------------------------------------------------------
// 여정에 포함된 장소 한 곳
// ---------------------------------------------------------------------------

/// `GET /schedulers/{id}`의 places[] 한 항목.
class SchedulePlace {
  final int id;
  final int visitOrder;

  /// 며칠째인지. 서버가 안 보낼 수 있어 nullable.
  final int? dayNo;

  /// 서버가 배정한 시간대. 없으면 화면에서 시간 자리를 그리지 않음.
  final String? timeSlot;

  final String title;
  final String category;
  final String imageUrl;
  final double? latitude;
  final double? longitude;
  final String? placeUrl;
  final String? kakaoPlaceId;

  const SchedulePlace({
    required this.id,
    required this.visitOrder,
    this.dayNo,
    this.timeSlot,
    required this.title,
    this.category = '',
    this.imageUrl = '',
    this.latitude,
    this.longitude,
    this.placeUrl,
    this.kakaoPlaceId,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  factory SchedulePlace.fromJson(Map<String, dynamic> json) {
    _reportUnknownKeys('SchedulePlace', json, const {
      'id', 'visit_order', 'day_no', 'time_slot', 'place', 'place_id',
      'created_at', 'updated_at', 'memo',
    });

    // 정식 위치는 중첩 place 객체. 평탄화해서 오면 최상위에서 읽음.
    final nested = json['place'];
    final Map<String, dynamic> place;
    if (nested is Map<String, dynamic>) {
      place = nested;
    } else {
      place = json;
      if (kDebugMode) {
        debugPrint('⚠️ [SchedulePlace] 중첩 place 객체가 없어 최상위에서 읽음. 응답 스키마 확인 필요.');
      }
    }

    return SchedulePlace(
      id: _toInt(json['id']) ?? 0,
      visitOrder: _toInt(json['visit_order']) ?? 0,
      dayNo: _toInt(json['day_no']),
      timeSlot: _toStringOrNull(json['time_slot']),
      title: _toStringOrNull(place['title']) ?? _toStringOrNull(place['name']) ?? '이름 없는 장소',
      category: _toStringOrNull(place['category']) ?? '',
      imageUrl: _toStringOrNull(place['image_url']) ?? '',
      latitude: _toDouble(place['latitude']),
      longitude: _toDouble(place['longitude']),
      placeUrl: _toStringOrNull(place['place_url']),
      kakaoPlaceId: _toStringOrNull(place['kakao_place_id']),
    );
  }
}

/// 하루 단위로 묶은 방문 장소들. 당일치기면 1개만 나옴.
class ScheduleDay {
  final int dayNo;
  final List<SchedulePlace> places;

  const ScheduleDay({required this.dayNo, required this.places});
}

// ---------------------------------------------------------------------------
// 목록용 요약
// ---------------------------------------------------------------------------

class ScheduleSummary {
  final int id;
  final String title;
  final String? mobilityMode;
  final String? tripType;
  final DateTime? startDateTime;
  final DateTime? endDateTime;
  final int placeCount;

  const ScheduleSummary({
    required this.id,
    required this.title,
    this.mobilityMode,
    this.tripType,
    this.startDateTime,
    this.endDateTime,
    this.placeCount = 0,
  });

  String get mobilityLabel => _labelOr(mobilityMode, _mobilityLabels);
  String get tripTypeLabel => _labelOr(tripType, _tripTypeLabels);

  /// '2026.08.19' 또는 '2026.08.19 ~ 08.21'. 날짜가 없으면 빈 문자열.
  String get dateLabel => formatDateRange(startDateTime, endDateTime);

  factory ScheduleSummary.fromJson(Map<String, dynamic> json) {
    _reportUnknownKeys('ScheduleSummary', json, const {
      'id', 'title', 'mobility_mode', 'trip_type', 'search_radius',
      'companion_type', 'companion_count', 'start_datetime', 'end_datetime',
      'memory_place', 'places', 'created_at', 'updated_at', 'user_id',
    });

    final places = json['places'];
    return ScheduleSummary(
      id: _toInt(json['id']) ?? 0,
      title: _toStringOrNull(json['title']) ?? '제목 없는 여정',
      mobilityMode: _toStringOrNull(json['mobility_mode']),
      tripType: _toStringOrNull(json['trip_type']),
      startDateTime: _toDateTime(json['start_datetime']),
      endDateTime: _toDateTime(json['end_datetime']),
      placeCount: places is List ? places.length : 0,
    );
  }
}

// ---------------------------------------------------------------------------
// 상세
// ---------------------------------------------------------------------------

class ScheduleDetail {
  final int id;
  final String title;
  final String? mobilityMode;
  final String? tripType;
  final int? searchRadius;
  final String? companionType;
  final int? companionCount;
  final DateTime? startDateTime;
  final DateTime? endDateTime;
  final MemoryPlace? memoryPlace;
  final List<SchedulePlace> places;

  const ScheduleDetail({
    required this.id,
    required this.title,
    this.mobilityMode,
    this.tripType,
    this.searchRadius,
    this.companionType,
    this.companionCount,
    this.startDateTime,
    this.endDateTime,
    this.memoryPlace,
    this.places = const [],
  });

  String get mobilityLabel => _labelOr(mobilityMode, _mobilityLabels);
  String get tripTypeLabel => _labelOr(tripType, _tripTypeLabels);
  String get companionLabel => _labelOr(companionType, _companionLabels);
  String get dateLabel => formatDateRange(startDateTime, endDateTime);

  bool get isWalking => (mobilityMode ?? '').toUpperCase() == 'WALK';

  /// 기준 장소 · 날짜 · 동행 중 값이 있는 것만 골라 조합한 부제.
  String get subtitle {
    final parts = <String>[
      if (memoryPlace != null && memoryPlace!.name.isNotEmpty) '${memoryPlace!.name} 기준',
      if (dateLabel.isNotEmpty) dateLabel,
      if (companionLabel.isNotEmpty)
        companionCount != null && companionCount! > 1
            ? '$companionLabel $companionCount명'
            : companionLabel,
    ];
    return parts.join(' · ');
  }

  /// day_no로 묶고 visit_order로 정렬. day_no가 없으면 전부 1일차.
  List<ScheduleDay> get days {
    if (places.isEmpty) return const [];

    final grouped = <int, List<SchedulePlace>>{};
    for (final p in places) {
      grouped.putIfAbsent(p.dayNo ?? 1, () => []).add(p);
    }

    final dayNos = grouped.keys.toList()..sort();
    return [
      for (final d in dayNos)
        ScheduleDay(
          dayNo: d,
          places: grouped[d]!..sort((a, b) => a.visitOrder.compareTo(b.visitOrder)),
        ),
    ];
  }

  /// 지도에 그릴 수 있는(좌표가 있는) 장소만 방문 순서대로.
  List<SchedulePlace> get routePlaces =>
      (places.where((p) => p.hasCoordinates).toList()
        ..sort((a, b) => a.visitOrder.compareTo(b.visitOrder)));

  factory ScheduleDetail.fromJson(Map<String, dynamic> json) {
    _reportUnknownKeys('ScheduleDetail', json, const {
      'id', 'title', 'mobility_mode', 'trip_type', 'search_radius',
      'companion_type', 'companion_count', 'start_datetime', 'end_datetime',
      'memory_place', 'places', 'created_at', 'updated_at', 'user_id',
    });

    final rawPlaces = json['places'];
    final memoryPlace = json['memory_place'];

    if (kDebugMode && rawPlaces is! List) {
      debugPrint('⚠️ [ScheduleDetail] places 배열이 응답에 없음 (키: ${json.keys.join(', ')})');
    }

    return ScheduleDetail(
      id: _toInt(json['id']) ?? 0,
      title: _toStringOrNull(json['title']) ?? '제목 없는 여정',
      mobilityMode: _toStringOrNull(json['mobility_mode']),
      tripType: _toStringOrNull(json['trip_type']),
      searchRadius: _toInt(json['search_radius']),
      companionType: _toStringOrNull(json['companion_type']),
      companionCount: _toInt(json['companion_count']),
      startDateTime: _toDateTime(json['start_datetime']),
      endDateTime: _toDateTime(json['end_datetime']),
      memoryPlace: memoryPlace is Map<String, dynamic> ? MemoryPlace.fromJson(memoryPlace) : null,
      places: rawPlaces is List
          ? rawPlaces
              .whereType<Map<String, dynamic>>()
              .map(SchedulePlace.fromJson)
              .toList()
          : const [],
    );
  }
}

// ---------------------------------------------------------------------------

/// intl 패키지 없이 쓰는 짧은 날짜 표기.
String formatDateRange(DateTime? start, DateTime? end) {
  String ymd(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  String md(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  if (start == null) return '';
  if (end == null) return ymd(start);
  final sameDay = start.year == end.year && start.month == end.month && start.day == end.day;
  return sameDay ? ymd(start) : '${ymd(start)} ~ ${md(end)}';
}
