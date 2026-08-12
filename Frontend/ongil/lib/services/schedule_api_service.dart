import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class ScheduleApiService {
  static String get _baseUrl =>
      dotenv.env['BASE_URL'] ?? '백엔드 URL이 설정되지 않았습니다.';

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