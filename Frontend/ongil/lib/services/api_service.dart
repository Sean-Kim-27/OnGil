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
      headers: {'Authorization': 'Bearer $authToken'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data;
    } else {
      throw Exception('데이터 로드 실패');
    }
  }

  // 3. 더미 스케줄 삭제 (DELETE)
  static Future<bool> deleteSchedule(String scheduleId) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return true;
  }

  // 기존 ApiService 클래스 내부에 추가
  static Future<Map<String, dynamic>> fetchScheduleDetail(
    String scheduleId,
  ) async {
    final response = await http.get(
      Uri.parse('${dotenv.env['BASE_URL']}/schedulers/$scheduleId'),
      headers: {'Authorization': 'Bearer $authToken'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data["places"];
    } else {
      throw Exception('데이터 로드 실패');
    }
  }
}
