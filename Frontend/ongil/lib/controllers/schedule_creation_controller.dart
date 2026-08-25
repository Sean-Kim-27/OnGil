import 'package:flutter/material.dart';

/// 4단계 장소 선택 상태.
///
/// 선택은 RecommendedPlace.selectionKey(= content_id 기반)로 기억한다.
/// 예전에는 장소 '이름'으로 기억해서, 이름이 같은 장소가 둘 있으면 하나만 골라도
/// 둘 다 선택된 것으로 잡혔다.
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

  /// 단계별 선택 키. 리스트라서 사용자가 누른 순서가 그대로 남는다.
  final Map<int, List<String>> selectedPlacesByStep = {
    1: [],
    2: [],
    3: [],
    4: [],
  };

  List<String> get currentStepSelectedKeys => selectedPlacesByStep[currentStep] ?? [];

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
  void togglePlaceSelection(String selectionKey) {
    final list = selectedPlacesByStep[currentStep] ?? [];
    if (list.contains(selectionKey)) {
      list.remove(selectionKey);
    } else {
      list.add(selectionKey);
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

  /// 1단계 → 4단계 순서로, 각 단계 안에서는 누른 순서대로.
  /// 이 순서가 그대로 서버의 visit_order가 되므로 순서를 흐트러뜨리면 안 된다.
  List<String> get allSelectedKeys {
    final keys = <String>[];
    final seen = <String>{};
    for (final step in const [1, 2, 3, 4]) {
      for (final key in selectedPlacesByStep[step] ?? const <String>[]) {
        if (seen.add(key)) keys.add(key);
      }
    }
    return keys;
  }

  // 스케줄 생성은 ai_schedule_working.dart의 ScheduleApiService.createSchedule()에서 처리함.
}