import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class ScheduleApiService {
  // 🐛 버그 수정: api_service.dart의 ApiService._baseUrl과 같은 이유로 404가 나던
  // 부분(자세한 설명은 그쪽 주석 참고). 다른 서비스들과 같은 백엔드/버전 프리픽스
  // (/api/v1)를 기본값으로 쓰도록 통일함.
  static const String _defaultHost = 'https://api.seankim428.site';

  static String get _baseUrl {
    var host = dotenv.env['BASE_URL'] ?? _defaultHost;
    if (host.isEmpty) host = _defaultHost;
    if (host.endsWith('/')) host = host.substring(0, host.length - 1);
    return host.endsWith('/api/v1') ? host : '$host/api/v1';
  }

  /// 📅 일정 상세 정보 백엔드 API 조회
  static Future<Map<String, dynamic>?> fetchScheduleDetail(int scheduleId) async {
    final url = Uri.parse('$_baseUrl/schedulers/$scheduleId');

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['AUTH_TOKEN']}',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        // UTF-8 디코딩으로 한글 깨짐 방지
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        debugPrint('❌ 일정 상세 조회 에러 (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('💥 일정 상세 API 통신 예외: $e');
    }

    return null;
  }
}