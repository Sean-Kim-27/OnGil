import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// 백엔드 PlaceCategory enum → 온길 카테고리 라벨(CategorySelector와 맞춤).
/// 카페/식당/관광/숙박으로 나눔
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

/// 카드 배지에 보여줄 더 자세한 라벨.
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

/// 백엔드 응답의 위경도 필드명이 latitude/longitude, lat/lng, x/y(카카오 방식) 중
/// 무엇이든 최대한 읽어내기 위한 헬퍼. 숫자든 문자열이든 다 허용.
double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// 검색 기준이 된 장소. GET /places/nearby 응답의 anchor를 옮겨 담음.
class PlaceAnchor {
  final String title;
  final String? address;
  final double? latitude;
  final double? longitude;

  const PlaceAnchor({required this.title, this.address, this.latitude, this.longitude});

  factory PlaceAnchor.fromJson(Map<String, dynamic> json) => PlaceAnchor(
        title: json['title'] as String? ?? '',
        address: json['address'] as String?,
        latitude: _toDouble(json['latitude'] ?? json['lat'] ?? json['y']),
        longitude: _toDouble(json['longitude'] ?? json['lng'] ?? json['lon'] ?? json['x']),
      );
}

/// 주변에서 찾은 추천 장소 하나.
class RecommendedPlace {
  final String title;
  final String address;
  final String category; // 음식/ 관광 / 숙박 / 카페/  - CategorySelector 라벨과 맞춤
  final List<String> tags;
  final String? imageUrl;
  final int distanceM;
  final double? latitude;
  final double? longitude;

  const RecommendedPlace({
    required this.title,
    required this.address,
    required this.category,
    this.tags = const [],
    this.imageUrl,
    this.distanceM = 0,
    this.latitude,
    this.longitude,
  });

  /// 카카오 상세 URL 조회 API를 부를 수 있는 상태인지 (위경도가 있어야 가능).
  bool get hasCoordinates => latitude != null && longitude != null;

  factory RecommendedPlace.fromJson(Map<String, dynamic> json) {
    final rawCategory = json['category'] as String? ?? 'other';
    final relatedCategory = json['related_category'] as String?;

    return RecommendedPlace(
      title: json['title'] as String? ?? '이름 없음',
      address: (json['address'] as String?) ?? (json['address_detail'] as String?) ?? '',
      category: _categoryLabelMap[rawCategory] ?? '관광',
      tags: [
        _categoryTagMap[rawCategory] ?? '기타',
        if (relatedCategory != null && relatedCategory.isNotEmpty) relatedCategory,
      ],
      imageUrl: (json['image_url'] as String?) ?? (json['thumbnail_url'] as String?),
      distanceM: (json['distance_m'] as num?)?.toInt() ?? 0,
      latitude: _toDouble(json['latitude'] ?? json['lat'] ?? json['y']),
      longitude: _toDouble(json['longitude'] ?? json['lng'] ?? json['lon'] ?? json['x']),
    );
  }
}

/// 카카오 상세 페이지 URL을 못 받아왔을 때(네트워크 오류, 404 등) 던지는 예외.
/// [notFound]가 true면 "카카오맵에 이 장소 자체가 없는" 404 상황 (숙박/축제 등에서 흔함) →
/// 화면에서는 에러 취급하지 말고 "카카오맵에서 검색해보라"는 안내로 처리하면 됨.
class KakaoDetailUrlException implements Exception {
  final String message;
  final bool notFound;
  KakaoDetailUrlException(this.message, {this.notFound = false});

  @override
  String toString() => message;
}

/// GET /api/v1/places/nearby 응답 전체(검색 기준 장소 + 근처 추천 목록).
class NearbySearchResult {
  final PlaceAnchor anchor;
  final List<RecommendedPlace> places;

  const NearbySearchResult({required this.anchor, required this.places});

  /// 추천리스트 카드용 이미지: places 중 image_url이 있는 첫 장소.
  ImageProvider? get heroImage {
    for (final p in places) {
      if (p.imageUrl != null) return NetworkImage(p.imageUrl!);
    }
    return null;
  }
}

/// 홈 화면 검색창에서 입력한 주소를 저장하고, 그 주소 기준 근처 추천 장소를 가져오는 서비스.
class PlaceService {
  PlaceService._();
  static final PlaceService instance = PlaceService._();

  final _storage = const FlutterSecureStorage();
  static const _nearbyUrl = 'https://api.seankim428.site/api/v1/places/nearby';

  // TODO(지성): 정확한 경로/파라미터명은 https://api.seankim428.site/docs 에서 최종 확인 필요!
  // Swagger 문서 페이지가 JS로 그려지는 SPA라서 내가 직접 못 열어보고, nearby 엔드포인트
  // 네이밍 규칙(복수형 리소스 + 케밥케이스)을 따라 추정만 해둔 값이야.
  // Swagger에서 "Try it out"으로 찍힌 실제 요청 URL(또는 curl)만 캡처해서 보내주면
  // 이 한 줄만 고쳐서 바로 맞출 수 있어.
  static const _kakaoDetailUrlEndpoint = 'https://api.seankim428.site/api/v1/places/kakao-detail-url';

  Future<void> saveLastAddress(String address) async {
    await _storage.write(key: 'lastSearchedAddress', value: address);
  }

  Future<String?> getLastAddress() async {
    return _storage.read(key: 'lastSearchedAddress');
  }

  /// 기준 장소명(학교·아파트·관광지 등) 기준 근처 추천 장소 조회.
  /// 실패(네트워크 오류, 로그인 만료 등)하면 null.
  Future<NearbySearchResult?> fetchNearbyPlaces(
    String query, {
    int radiusM = 5000,
  }) async {
    final clampedRadius = radiusM.clamp(3000, 5000).toInt();
    final uri = Uri.parse(_nearbyUrl).replace(queryParameters: {
      'query': query,
      'radius_m': clampedRadius.toString(),
    });

    try {
      final response = await AuthService.instance.authorizedGet(uri);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final anchor = PlaceAnchor.fromJson(data['anchor'] as Map<String, dynamic>);
      final places = (data['places'] as List<dynamic>? ?? [])
          .map((e) => RecommendedPlace.fromJson(e as Map<String, dynamic>))
          .toList();

      return NearbySearchResult(anchor: anchor, places: places);
    } catch (_) {
      return null;
    }
  }

  /// nearby 응답에서 받은 title/latitude/longitude로 카카오 장소 상세 페이지 URL을 조회함.
  /// 성공하면 URL 문자열, 실패하면 [KakaoDetailUrlException]을 던짐.
  ///
  /// 숙박·축제처럼 카카오맵에 상세 페이지 자체가 없는 장소는 서버가 404로 응답하는데,
  /// 이 경우 [KakaoDetailUrlException.notFound]가 true로 옴 → 에러 팝업이 아니라
  /// "카카오맵에서 검색해보세요" 안내로 처리해야 함 (호출하는 쪽에서 분기).
  Future<String> fetchKakaoDetailUrl({
    required String title,
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(_kakaoDetailUrlEndpoint).replace(queryParameters: {
      'title': title,
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
    });

    late final http.Response response;
    try {
      response = await AuthService.instance.authorizedGet(uri);
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
      // 응답 필드명도 문서 확인 전이라 흔히 쓰이는 이름들을 순서대로 시도함.
      final url = (data['url'] ??
          data['detail_url'] ??
          data['place_url'] ??
          data['kakao_url'] ??
          data['kakao_place_url']) as String?;
      if (url == null || url.isEmpty) {
        throw KakaoDetailUrlException('상세 페이지 주소를 받지 못했어요.');
      }
      return url;
    }

    if (response.statusCode == 404) {
      String message = "'$title'에 일치하는 카카오 장소 상세 페이지를 찾지 못했습니다.";
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        message = (data['detail'] as String?) ?? message;
      } catch (_) {
        // 응답 파싱 실패해도 기본 메시지로 진행
      }
      throw KakaoDetailUrlException(message, notFound: true);
    }

    throw KakaoDetailUrlException('상세 페이지를 불러오지 못했어요. (Error: ${response.statusCode})');
  }
}
