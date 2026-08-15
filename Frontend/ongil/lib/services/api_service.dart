<<<<<<< HEAD
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 👈 추가

class ApiService {
  static String authToken = "${dotenv.env['AUTH_TOKEN']}"; // 인증 토큰 (필요 시)

  // 1. 더미 AI 스케줄 생성 요청 (POST)
  static Future<Map<String, dynamic>> createSchedule(
    List<String> placeIds,
  ) async {
    // 2초 네트워크 통신 지연 흉내
    await Future.delayed(const Duration(seconds: 2));

    return {
      "status": "success",
      "schedule_id": "sched_101",
      "title": "충주 감성 당일치기 코스",
      "selected_places_count": placeIds.length,
      "places": placeIds,
    };
  }

  // 2. 더미 내 스케줄 목록 조회 (GET)
  static Future<List<dynamic>> fetchSchedules() async {
    final response = await http.get(
      Uri.parse('${dotenv.env['BASE_URL']}/schedulers'),
=======
// ℹ️ controllers/schedule_list_controller.dart, schedule_creation_controller.dart,
// schedule_detail_controller.dart, screens/ai_schedule_working.dart에서 씀.
// 목록/상세 조회, 스케줄 생성까지 real 백엔드(api.seankim428.site/api/v1)를 침.
// .env의 BASE_URL은 선택 사항 - 안 채워져 있으면 다른 서비스들과 같은 기본 호스트를
// 씀(아래 _baseUrl 참고). AUTH_TOKEN은 로그인 연동 전까지 임시로 여전히 .env에서
// 채워야 함(.env.example 참고).
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'place_service.dart';

class ApiService {
  static String get authToken => dotenv.env['AUTH_TOKEN'] ?? '';

  // 🐛 버그 수정 (404 "스케줄 생성 실패: {"detail":"Not Found"}"):
  // 여기 있던 `dotenv.env['BASE_URL'] ?? ''`는 .env의 BASE_URL 뒤에 바로
  // '/schedulers'를 붙여도 되는(=이미 버전 프리픽스까지 포함된) 값이라고 가정하고
  // 있었음. 근데 AuthService(_backendUrl)랑 PlaceService(_nearbyUrl 등)가 실제로
  // 쓰고 있는 백엔드는 전부 https://api.seankim428.site/api/v1/... 형태라서,
  // BASE_URL에 가장 자연스러운 값인 도메인만("https://api.seankim428.site") 넣어뒀다면
  // 실제 요청은 버전 프리픽스 없는 '.../schedulers'로 나가서 존재하지 않는 경로 →
  // 404가 났던 것으로 보임. 다른 서비스들과 동일한 백엔드/버전 프리픽스를 기본값으로
  // 쓰고, .env의 BASE_URL은 "호스트"로만 취급해서 뒤에 /api/v1이 없으면 붙이고
  // 이미 있으면(예전처럼 완전한 값을 넣어둔 경우) 중복으로 안 붙게 함.
  static const String _defaultHost = 'https://api.seankim428.site';

  static String get _baseUrl {
    var host = dotenv.env['BASE_URL'] ?? _defaultHost;
    if (host.isEmpty) host = _defaultHost;
    if (host.endsWith('/')) host = host.substring(0, host.length - 1);
    return host.endsWith('/api/v1') ? host : '$host/api/v1';
  }

  static const _storage = FlutterSecureStorage();
  static const _lastScheduleIdKey = 'last_schedule_id';

  // ⚠️ 실제 백엔드로 POST 시도하도록 바꿈. 다만 요청/응답 형태(필드명)는
  // Swagger 문서를 직접 못 열어봐서 GET /schedulers, GET /schedulers/{id}랑
  // 같은 패턴(복수형 리소스)을 따라 추정한 거야. 응답에서 schedule_id를 못 찾으면
  // 'id' 필드도 같이 시도하게 해뒀는데, 그래도 안 맞으면 실제 요청 바디/응답 캡처해서
  // 보내주면 바로 맞춰줄게.
  static Future<Map<String, dynamic>> createSchedule(
    List<RecommendedPlace> places,
  ) async {
    final url = Uri.parse('$_baseUrl/schedulers');
    debugPrint('📤 [createSchedule] POST $url'); // 이 URL이 실제로 맞는지 콘솔에서 바로 확인 가능
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({
        'places': places
            .map((p) => {
                  'title': p.title,
                  'category': p.category,
                  'address': p.address,
                  'latitude': p.latitude,
                  'longitude': p.longitude,
                })
            .toList(),
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data is Map<String, dynamic> ? data : {'raw': data};
    } else {
      throw Exception('스케줄 생성 실패 (${response.statusCode}): ${response.body}');
    }
  }

  // 방금 만든(또는 마지막으로 본) 스케줄 id를 기기에 저장/조회함.
  // 지도 탭이 "가장 최근 스케줄"의 경로를 자동으로 그려줄 때 씀.
  static Future<void> saveLastScheduleId(String scheduleId) async {
    await _storage.write(key: _lastScheduleIdKey, value: scheduleId);
  }

  static Future<String?> getLastScheduleId() async {
    return _storage.read(key: _lastScheduleIdKey);
  }

  // 내 스케줄 목록 조회 (GET)
  static Future<List<dynamic>> fetchSchedules() async {
    final url = Uri.parse('$_baseUrl/schedulers');
    debugPrint('📥 [fetchSchedules] GET $url');
    final response = await http.get(
      url,
>>>>>>> 181b2e02e01fc09c9df58fdd7b41b573330de210
      headers: {'Authorization': 'Bearer $authToken'},
    );

    if (response.statusCode == 200) {
<<<<<<< HEAD
      final data = jsonDecode(response.body);
=======
      final data = jsonDecode(utf8.decode(response.bodyBytes));
>>>>>>> 181b2e02e01fc09c9df58fdd7b41b573330de210
      return data;
    } else {
      throw Exception('데이터 로드 실패');
    }
  }

<<<<<<< HEAD
  // 3. 더미 스케줄 삭제 (DELETE)
=======
  // 스케줄 삭제 (DELETE) — 아직 더미. 실제 연동 필요하면 알려주세요.
>>>>>>> 181b2e02e01fc09c9df58fdd7b41b573330de210
  static Future<bool> deleteSchedule(String scheduleId) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return true;
  }

<<<<<<< HEAD
  // 기존 ApiService 클래스 내부에 추가
=======
>>>>>>> 181b2e02e01fc09c9df58fdd7b41b573330de210
  static Future<Map<String, dynamic>> fetchScheduleDetail(
    String scheduleId,
  ) async {
    final response = await http.get(
<<<<<<< HEAD
      Uri.parse('${dotenv.env['BASE_URL']}/schedulers/$scheduleId'),
=======
      Uri.parse('$_baseUrl/schedulers/$scheduleId'),
>>>>>>> 181b2e02e01fc09c9df58fdd7b41b573330de210
      headers: {'Authorization': 'Bearer $authToken'},
    );

    if (response.statusCode == 200) {
<<<<<<< HEAD
      final data = jsonDecode(response.body);
      return data["places"];
=======
      // 🐛 버그 수정: 원래 data["places"]만 반환해서 title/subtitle/timeline이
      // 다 날아가고 있었음. ScheduleDetailScreen은 전체 객체를 기대함.
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data;
>>>>>>> 181b2e02e01fc09c9df58fdd7b41b573330de210
    } else {
      throw Exception('데이터 로드 실패');
    }
  }
}
