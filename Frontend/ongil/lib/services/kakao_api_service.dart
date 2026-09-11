import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

/// 카카오 REST API 호출.
///
/// TODO(보안): REST 키가 `.env`에 있고, 그 파일이 에셋으로 APK에 통째로 들어간다.
/// APK 압축만 풀면 키가 노출돼 쿼터 도용이 가능하다. 코드 난독화로는 못 막는다.
/// 백엔드에 아래 프록시가 생기면 그쪽을 거치도록 바꾸고 키를 재발급할 것.
///   GET /api/v1/kakao/search/keyword?query=&x=&y=&radius=
///   GET /api/v1/kakao/directions?origin_lng=&origin_lat=&dest_lng=&dest_lat=
class KakaoApiService {
  static String get _restApiKey => dotenv.env['KAKAO_REST_API_KEY'] ?? '';

  /// 🛣️ 구간별 카카오 모빌리티 길찾기 경로 좌표(LatLng) 조회
  static Future<List<LatLng>> fetchRoutePoints(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      'https://apis-navi.kakaomobility.com/v1/directions'
      '?origin=${origin.longitude},${origin.latitude}'
      '&destination=${destination.longitude},${destination.latitude}'
      '&priority=RECOMMEND',
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'KakaoAK $_restApiKey',
        },
      );

      debugPrint('📩 [길찾기 API 응답 코드]: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'];

        if (routes != null && routes.isNotEmpty && routes[0]['result_code'] == 0) {
          final List<LatLng> pathPoints = [];
          final sections = routes[0]['sections'];

          for (var section in sections) {
            for (var road in section['roads']) {
              List dynamicVertexes = road['vertexes'];
              for (int v = 0; v < dynamicVertexes.length; v += 2) {
                double lng = (dynamicVertexes[v] as num).toDouble();
                double lat = (dynamicVertexes[v + 1] as num).toDouble();
                pathPoints.add(LatLng(lat, lng));
              }
            }
          }
          debugPrint('✅ [길찾기 성공] 추출된 좌표: ${pathPoints.length}개');
          return pathPoints;
        } else {
          debugPrint('⚠️ [길찾기 실패] result_code: ${routes?[0]?['result_code']}');
        }
      } else {
        debugPrint('❌ [길찾기 API 에러]: ${response.body}');
      }
    } catch (e) {
      debugPrint('💥 [길찾기 예외 발생]: $e');
    }

    return [];
  }

  /// 장소 이름과 좌표로 카카오 상세 정보를 조회.
  static Future<Map<String, dynamic>?> fetchPlaceDetail(
    String placeName,
    LatLng latLng,
  ) async {
    final url = Uri.parse(
      'https://dapi.kakao.com/v2/local/search/keyword.json'
      '?query=${Uri.encodeComponent(placeName)}'
      '&x=${latLng.longitude}&y=${latLng.latitude}&radius=100',
    );

    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'KakaoAK $_restApiKey'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List documents = data['documents'];

        if (documents.isNotEmpty) {
          return documents.first as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('💥 카카오 장소 상세 API 호출 예외: $e');
    }

    return null;
  }
}
