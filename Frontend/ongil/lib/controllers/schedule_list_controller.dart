import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ScheduleListController extends ChangeNotifier {
  List<dynamic> schedules = [];
  bool isLoading = false;
  String? errorMessage;

  // 1. 내 스케줄 목록 불러오기 (GET)
  Future<void> fetchSchedules() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final data = await ApiService.fetchSchedules(); // 기존 ApiService 연결
      schedules = data;
      isLoading = false;
      notifyListeners();
    } catch (e) {
      isLoading = false;
      errorMessage = '스케줄 목록을 불러오는 데 실패했어요.';
<<<<<<< HEAD
      // notifyListeners();
=======
      // 🐛 버그 수정: notifyListeners()가 주석 처리돼 있어서 실패해도 화면이
      // isLoading=true인 채로 멈춰있었음 (로딩 스피너가 영원히 안 사라짐).
      notifyListeners();
>>>>>>> 181b2e02e01fc09c9df58fdd7b41b573330de210
    }
  }

  // 2. 스케줄 삭제 (DELETE)
  Future<void> deleteSchedule(String scheduleId) async {
    try {
      // 화면 UI에서 먼저 바로 지워줘서 반응 속도 업!
      schedules.removeWhere((item) => item['id'] == scheduleId);
      notifyListeners();

      // 백엔드 삭제 API 호출
      await ApiService.deleteSchedule(scheduleId);
    } catch (e) {
      errorMessage = '삭제에 실패했어요. 다시 시도해 주세요.';
      notifyListeners();
      fetchSchedules(); // 에러 시 데이터 원복
    }
  }

  // 3. 즐겨찾기(고정) 토글
  void toggleFavorite(String scheduleId) {
    final index = schedules.indexWhere((item) => item['id'] == scheduleId);
    if (index != -1) {
      schedules[index]['is_favorite'] = !(schedules[index]['is_favorite'] ?? false);
      notifyListeners();
      // 백엔드 업데이트 API 호출 필요 시 여기에 연결
    }
  }
}