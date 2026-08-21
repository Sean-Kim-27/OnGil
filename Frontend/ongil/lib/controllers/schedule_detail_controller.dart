import 'package:flutter/foundation.dart';
import '../models/schedule.dart';
import '../services/schedule_api_service.dart';

/// 여정 상세 화면 상태.
class ScheduleDetailController extends ChangeNotifier {
  ScheduleDetail? detail;
  bool isLoading = false;
  ScheduleApiException? error;

  bool _disposed = false;

  bool get hasError => error != null;

  /// 통신은 성공했는데 장소가 하나도 없는 상태(에러와 구분).
  bool get isEmpty => !isLoading && !hasError && (detail?.places.isEmpty ?? false);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load(int scheduleId) async {
    isLoading = true;
    error = null;
    _notify();

    try {
      detail = await ScheduleApiService.fetchScheduleDetail(scheduleId);
    } on ScheduleApiException catch (e) {
      error = e;
    } catch (e, st) {
      debugPrint('💥 [ScheduleDetailController] 예상 못 한 오류: $e\n$st');
      error = const ScheduleApiException(ScheduleApiErrorKind.parse);
    } finally {
      isLoading = false;
      _notify();
    }
  }

  /// 이미 상세를 들고 있으면 재조회 없이 그대로 씀.
  void seed(ScheduleDetail value) {
    detail = value;
    isLoading = false;
    error = null;
    _notify();
  }
}
