import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ScheduleDetailController extends ChangeNotifier {
  Map<String, dynamic>? scheduleDetail;
  bool isLoading = false;
  String? errorMessage;

  Future<void> loadScheduleDetail(String scheduleId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      scheduleDetail = await ApiService.fetchScheduleDetail(scheduleId);
      isLoading = false;
      notifyListeners();
    } catch (e) {
      isLoading = false;
      errorMessage = '스케줄 상세 정보를 불러올 수 없어요.';
      notifyListeners();
    }
  }
}