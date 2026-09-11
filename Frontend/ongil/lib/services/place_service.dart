import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_service.dart';

const Map<String, String> _categoryLabelMap = {
  'restaurant': '음식',
  'cafe': '카페',
  'accommodation': '숙박',
  'shopping': '관광',
  'tourist_attraction': '관광',
  'cultural_facility': '관광',
  'festival': '관광',
  'travel_course': '관광',
  'leisure_sports': '관광',
  'other': '관광',
};

const Map<String, String> _categoryTagMap = {
  'restaurant': '음식점',
  'cafe': '카페',
  'accommodation': '숙박',
  'tourist_attraction': '관광지',
  'cultural_facility': '문화시설',
  'festival': '축제',
  'travel_course': '여행코스',
  'leisure_sports': '레저스포츠',
  'shopping': '쇼핑',
  'other': '기타',
};

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

class PlaceAnchor {
  final String title;
  final String? address;
  final double? latitude;
  final double? longitude;

  const PlaceAnchor({
    required this.title,
    this.address,
    this.latitude,
    this.longitude,
  });

  factory PlaceAnchor.fromJson(Map<String, dynamic> json) => PlaceAnchor(
        title: json['title'] as String? ?? '',
        address: (json['address'] as String?) ?? (json['address_detail'] as String?),
        latitude: _toDouble(json['latitude'] ?? json['lat'] ?? json['y']),
        longitude: _toDouble(json['longitude'] ?? json['lng'] ?? json['lon'] ?? json['x']),
      );
}

class RecommendedPlace {
  final String title;
  final String address;
  final String category; // 화면 표시/필터용 한글 라벨 (관광/숙박/카페/음식)
  // 스케줄 생성 요청엔 한글 category가 아니라 이 원본 영문값을 써야 함.
  final String rawCategory;
  final List<String> tags;
  final int distanceM;
  final double? latitude;
  final double? longitude;
  
  final String? imageUrl;
  final String? kakaoPlaceId;
  final String? placeUrl;
  // 스케줄 생성 요청의 places[].content_id에 필요. 응답에 없으면 null.
  final String? contentId;

  const RecommendedPlace({
    required this.title,
    required this.address,
    required this.category,
    this.rawCategory = 'other',
    this.tags = const [],
    this.distanceM = 0,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.kakaoPlaceId,
    this.placeUrl,
    this.contentId,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  /// 장소 선택을 기억할 때 쓰는 안정적인 키.
  ///
  /// 예전에는 title로 선택을 관리했는데, 같은 이름의 장소가 둘 이상이면
  /// 하나만 골라도 전부 선택된 것으로 잡혔다. content_id가 정답이고,
  /// 혹시 없을 때만 좌표를 섞어 대체 키를 만든다.
  String get selectionKey {
    final id = contentId;
    if (id != null && id.isNotEmpty) return 'cid:$id';
    return 'xy:$title@$latitude,$longitude';
  }

  factory RecommendedPlace.fromJson(Map<String, dynamic> json) {
    final rawCategory = json['category'] as String? ?? 'other';
    final relatedCategory = json['related_category'] as String?;

    return RecommendedPlace(
      title: json['title'] as String? ?? '이름 없음',
      address: (json['address'] as String?) ?? (json['address_detail'] as String?) ?? '',
      category: _categoryLabelMap[rawCategory] ?? '관광',
      rawCategory: rawCategory,
      tags: [
        _categoryTagMap[rawCategory] ?? '기타',
        if (relatedCategory != null && relatedCategory.isNotEmpty) relatedCategory,
      ],
      distanceM: (json['distance_m'] as num?)?.toInt() ?? 0,
      latitude: _toDouble(json['latitude'] ?? json['lat'] ?? json['y']),
      longitude: _toDouble(json['longitude'] ?? json['lng'] ?? json['lon'] ?? json['x']),
      
      imageUrl: (json['image_url'] as String?) ?? (json['thumbnail_url'] as String?),
      // nearby 응답(NearbyPlace)에는 id도 kakao_place_id도 없다.
      // 카카오 장소 id는 /places/kakao-links/resolve 로 따로 받아야 함.
      kakaoPlaceId: json['kakao_place_id'] as String?,
      placeUrl: (json['place_url'] as String?) ?? (json['url'] as String?),
      contentId: (json['content_id'])?.toString(),
    );
  }
}

class KakaoDetailUrlException implements Exception {
  final String message;
  final bool notFound;
  KakaoDetailUrlException(this.message, {this.notFound = false});

  @override
  String toString() => message;
}

class NearbySearchResult {
  final PlaceAnchor anchor;
  final List<RecommendedPlace> places;

  /// 지도 화면이 '더 최근에 검색한 쪽'을 고르는 데 씀.
  final DateTime fetchedAt;

  NearbySearchResult({
    required this.anchor,
    required this.places,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  ImageProvider? get heroImage {
    for (final p in places) {
      if (p.imageUrl != null) return NetworkImage(p.imageUrl!);
    }
    return null;
  }
}

class PlaceService {
  PlaceService._();
  static final PlaceService instance = PlaceService._();

  final _storage = const FlutterSecureStorage();

  // 예전에는 여기서만 BASE_URL을 따로 손질했다. .env에 `/api/v1`까지 적혀 있으면
  // `/api/v1/api/v1/places/nearby`가 만들어져 전부 404였다. ApiConfig로 통일.
  static String get _nearbyUrl => '${ApiConfig.baseUrl}/places/nearby';
  static String get _kakaoLinksResolveUrl =>
      '${ApiConfig.baseUrl}/places/kakao-links/resolve';

  /// 서버 SearchRadiusMeters enum은 3000 / 5000 두 값만 받는다.
  /// clamp(3000, 5000)만 하면 4000 같은 값이 그대로 통과해 422가 났다.
  static int _snapRadius(int radiusM) => radiusM <= 4000 ? 3000 : 5000;

  Future<void> saveLastAddress(String address) async {
    await _storage.write(key: 'lastSearchedAddress', value: address);
  }

  Future<String?> getLastAddress() async {
    return _storage.read(key: 'lastSearchedAddress');
  }

  Future<NearbySearchResult?> fetchNearbyPlaces(
    String query, {
    int radiusM = 5000,
  }) async {
    final uri = Uri.parse(_nearbyUrl).replace(queryParameters: {
      'query': query,
      'radius_m': _snapRadius(radiusM).toString(),
    });

     try {
      debugPrint('[Nearby] GET $uri');
      final response = await AuthService.instance.authorizedGet(uri);
      debugPrint('[Nearby] status=${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('[Nearby] body=${utf8.decode(response.bodyBytes)}');
        return null;
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final anchor = PlaceAnchor.fromJson(data['anchor'] as Map<String, dynamic>);
      final places = (data['places'] as List<dynamic>? ?? [])
          .map((e) => RecommendedPlace.fromJson(e as Map<String, dynamic>))
          .toList();

      debugPrint('[Nearby] anchor=${anchor.title} places=${places.length}');
      return NearbySearchResult(anchor: anchor, places: places);
    } catch (e, st) {
      debugPrint('[Nearby] 예외: $e\n$st');
      return null;
    }
  }

  Future<String> fetchKakaoDetailUrl({
    required String title,
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(_kakaoLinksResolveUrl);

    late final http.Response response;
    try {
      response = await AuthService.instance.authorizedPost(
        uri,
        body: jsonEncode({
          'title': title,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );
    } catch (_) {
      throw KakaoDetailUrlException('인터넷 연결을 확인해주세요.');
    }

    if (response.statusCode == 200) {
      Map<String, dynamic> data;
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {
        throw KakaoDetailUrlException('상세 페이지 응답을 해석하지 못했어요.');
      }
      final url = data['place_url'] as String?;
      if (url == null || url.isEmpty) {
        throw KakaoDetailUrlException('상세 페이지 주소를 받지 못했어요.');
      }
      return url;
    }

    // 상세 페이지가 없는 장소(숙박·축제에 흔함)를 대비한 방어 분기.
    if (response.statusCode == 404) {
      throw KakaoDetailUrlException(
        "'$title'에 일치하는 카카오 장소 상세 페이지를 찾지 못했습니다.",
        notFound: true,
      );
    }

    if (response.statusCode == 422) {
      // detail은 문자열이 아니라 ValidationError 배열임.
      String message = '요청 형식이 서버와 맞지 않아요.';
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final detail = data['detail'];
        if (detail is List && detail.isNotEmpty && detail.first is Map) {
          final msg = (detail.first as Map)['msg'];
          if (msg is String && msg.isNotEmpty) message = msg;
        }
      } catch (_) {}
      throw KakaoDetailUrlException(message);
    }

    throw KakaoDetailUrlException('상세 페이지를 불러오지 못했어요. (Error: ${response.statusCode})');
  }
}