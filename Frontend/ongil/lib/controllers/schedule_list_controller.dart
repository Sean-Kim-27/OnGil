import 'package:flutter/foundation.dart';
import '../models/schedule.dart';
import '../services/schedule_api_service.dart';

/// 여정 목록 화면 상태.
class ScheduleListController extends ChangeNotifier {
  List<ScheduleSummary> schedules = [];
  bool isLoading = false;
  ScheduleApiException? error;

  bool _disposed = false;

  bool get hasError => error != null;
  bool get isEmpty => !isLoading && !hasError && schedules.isEmpty;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 목록 새로고침. [silent]면 스피너 없이 갱신.
  Future<void> fetchSchedules({bool silent = false}) async {
    if (!silent) {
      isLoading = true;
      error = null;
      _notify();
    }

    try {
      schedules = await ScheduleApiService.fetchSchedules();
      error = null;
    } on ScheduleApiException catch (e) {
      // 조용한 새로고침 실패 시엔 보던 목록을 그대로 유지.
      if (!silent || schedules.isEmpty) {
        error = e;
      }
    } catch (e, st) {
      debugPrint('💥 [ScheduleListController] 예상 못 한 오류: $e\n$st');
      error = const ScheduleApiException(ScheduleApiErrorKind.parse);
    } finally {
      isLoading = false;
      _notify();
    }
  }

  /// 여정 삭제. 낙관적으로 먼저 지우고, 서버가 실패하면 되돌림.
  Future<bool> deleteSchedule(int scheduleId) async {
    final index = schedules.indexWhere((s) => s.id == scheduleId);
    if (index == -1) return false;

    final removed = schedules[index];
    schedules = List.of(schedules)..removeAt(index);
    error = null;
    _notify();

    try {
      await ScheduleApiService.deleteSchedule(scheduleId);
      // 지도 탭이 지운 여정을 계속 조회하지 않도록 캐시된 id도 정리.
      await ScheduleApiService.clearLastScheduleIdIf(scheduleId);
      return true;
    } on ScheduleApiException catch (e) {
      // 404는 이미 삭제된 것이므로 되돌리지 않음.
      if (e.kind == ScheduleApiErrorKind.notFound) {
        await ScheduleApiService.clearLastScheduleIdIf(scheduleId);
        return true;
      }
      schedules = List.of(schedules)..insert(index, removed);
      error = e;
      _notify();
      return false;
    }
  }
}
