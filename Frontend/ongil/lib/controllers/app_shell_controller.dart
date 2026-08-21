import 'package:flutter/material.dart';

/// 홈 셸(하단 탭)에게 "이 탭을 열어달라"고 요청하는 통로.
class HomeTabIntent {
  /// 0:지도 1:스케줄 2:홈 3:방명록
  final int tabIndex;

  /// 지도 탭에서 그려줄 여정 id. 없으면 기존 상태 유지.
  final int? focusScheduleId;

  const HomeTabIntent({required this.tabIndex, this.focusScheduleId});
}

class AppShellController extends ChangeNotifier {
  AppShellController._();
  static final AppShellController instance = AppShellController._();

  HomeTabIntent? _pending;

  /// 홈 셸이 한 번 소비하면 비워짐(같은 요청이 두 번 적용되지 않게).
  HomeTabIntent? consumePending() {
    final intent = _pending;
    _pending = null;
    return intent;
  }

  void request(HomeTabIntent intent) {
    _pending = intent;
    notifyListeners();
  }

  /// 쌓인 화면을 닫고 홈 셸로 돌아가며 원하는 탭을 열어줌.
  void openHomeTab(
    BuildContext context, {
    required int tabIndex,
    int? focusScheduleId,
  }) {
    request(HomeTabIntent(tabIndex: tabIndex, focusScheduleId: focusScheduleId));
    Navigator.of(context).popUntil(
      (route) => route.settings.name == '/home' || route.isFirst,
    );
  }
}
