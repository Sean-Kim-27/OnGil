import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ScheduleCreationController extends ChangeNotifier {
  int currentStep = 1; // 1: 명소, 2: 숙소, 3: 카페, 4: 식당
  bool isLoading = false;
  String? errorMessage;

  final Map<int, String> stepTitles = {
    1: '가고 싶은 명소',
    2: '머물고 싶은 숙소',
    3: '쉬어가고 싶은 카페',
    4: '맛보고 싶은 식당',
  };

  final Map<int, List<String>> selectedPlacesByStep = {
    1: [],
    2: [],
    3: [],
    4: [],
  };

  List<String> get currentStepSelectedIds => selectedPlacesByStep[currentStep] ?? [];

  // 현재 스텝에서 최소 1개 이상 선택되었는지 체크하는 getter
  bool get canGoNext => (selectedPlacesByStep[currentStep] ?? []).isNotEmpty;

  // 장소 선택 / 해제 토글
  void togglePlaceSelection(String placeId) {
    final list = selectedPlacesByStep[currentStep] ?? [];
    if (list.contains(placeId)) {
      list.remove(placeId);
    } else {
      list.add(placeId);
    }
    notifyListeners();
  }

  // 다음 스텝으로 진행
  bool nextStep() {
    if (!canGoNext) {
      errorMessage = '장소를 최소 1개 이상 선택해 주세요!';
      notifyListeners();
      return false;
    }

    errorMessage = null;
    if (currentStep < 4) {
      currentStep++;
      notifyListeners();
      return true;
    }
    return false;
  }

  // 이전 스텝으로 이동
  bool previousStep() {
    errorMessage = null;
    if (currentStep > 1) {
      currentStep--;
      notifyListeners();
      return true;
    }
    return false;
  }

  List<String> get getAllSelectedPlaceIds {
    final List<String> allIds = [];
    selectedPlacesByStep.values.forEach(allIds.addAll);
    return allIds;
  }

  Future<Map<String, dynamic>?> submitSchedule() async {
    isLoading = true;
    notifyListeners();

    try {
      final result = await ApiService.createSchedule(getAllSelectedPlaceIds);
      isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      isLoading = false;
      errorMessage = '생성 중 오류가 발생했습니다.';
      notifyListeners();
      return null;
    }
  }
}