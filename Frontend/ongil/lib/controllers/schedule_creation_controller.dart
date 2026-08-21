import 'package:flutter/material.dart';

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

  // 숙소(2단계)는 당일치기면 고를 수 없으므로 선택 없이도 통과시킴.
  bool get canGoNext {
    if (currentStep == 2) return true;
    return (selectedPlacesByStep[currentStep] ?? []).isNotEmpty;
  }

  /// 선택을 전부 비우고 1단계로 되돌림(지역을 새로 검색했을 때).
  void reset() {
    currentStep = 1;
    errorMessage = null;
    for (final list in selectedPlacesByStep.values) {
      list.clear();
    }
    notifyListeners();
  }

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

  // 스케줄 생성은 ai_schedule_working.dart의 ScheduleApiService.createSchedule()에서 처리함.
}