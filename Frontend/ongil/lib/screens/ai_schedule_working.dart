import 'dart:async'; // Timer를 사용하기 위해 필요!
import 'package:flutter/material.dart';
import 'schedule_detail_screen.dart';
import '../services/schedule_api_service.dart';
import '../models/schedule.dart';
import '../services/place_service.dart';

/// 일정 정보 입력 값을 받아 스케줄 생성 API를 호출하는 로딩 화면.
class AiScheduleWorking extends StatefulWidget {
  final List<RecommendedPlace> places;
  final PlaceAnchor anchor;
  final String title;
  final String mobilityMode;
  final int searchRadius;
  final String tripType;
  final String companionType;
  final int companionCount;
  final DateTime startDateTime;
  final DateTime endDateTime;

  const AiScheduleWorking({
    super.key,
    required this.places,
    required this.anchor,
    required this.title,
    required this.mobilityMode,
    required this.searchRadius,
    required this.tripType,
    required this.companionType,
    required this.companionCount,
    required this.startDateTime,
    required this.endDateTime,
  });

  @override
  State<AiScheduleWorking> createState() => _AiScheduleWorkingState();
}

class _AiScheduleWorkingState extends State<AiScheduleWorking> {
  // 응답을 기다리는 동안 순환시킬 문구.
  final List<String> _loadingTexts = [
    '선택한 장소들을 살펴보는 중...',
    '이동 경로를 계산하는 중이에요',
    '하루 일정으로 정리하고 있어요',
    '거의 다 됐어요...',
  ];

  int _currentIndex = 0;
  Timer? _timer;
  bool _hasError = false;
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (timer) {
      if (!mounted) return;
      setState(() {
        if (_currentIndex < _loadingTexts.length - 1) {
          _currentIndex++;
        }
      });
    });
    _createSchedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _createSchedule() async {
    if (widget.places.isEmpty) {
      _fail('선택된 장소가 없어요. 이전 화면으로 돌아가서 장소를 선택해주세요.');
      return;
    }

    try {
      final ScheduleDetail created = await ScheduleApiService.createSchedule(
        places: widget.places,
        anchor: widget.anchor,
        title: widget.title,
        mobilityMode: widget.mobilityMode,
        searchRadius: widget.searchRadius,
        tripType: widget.tripType,
        companionType: widget.companionType,
        companionCount: widget.companionCount,
        startDateTime: widget.startDateTime,
        endDateTime: widget.endDateTime,
      );

      // SchedulerResponse는 id 필드(int)로 내려옴 ('schedule_id' 아님).
      if (created.id == 0) {
        throw const ScheduleApiException(
          ScheduleApiErrorKind.parse,
          detail: '생성 응답에 id가 없음',
        );
      }

      await ScheduleApiService.saveLastScheduleId(created.id);

      _timer?.cancel();
      if (!mounted) return;
      // 방금 받은 상세를 넘겨 같은 데이터를 다시 조회하지 않게 함.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ScheduleDetailScreen(
            scheduleId: created.id,
            initialDetail: created,
            // 생성 플로우가 pushReplacement로 쌓여 있어, 상세에서 홈으로 나갈 길을 열어줌.
            justCreated: true,
          ),
        ),
      );
    } on ScheduleApiException catch (e) {
      debugPrint('❌ [AiScheduleWorking] createSchedule 실패: $e');
      _fail(_toFriendlyMessage(e));
    } catch (e, st) {
      debugPrint('💥 [AiScheduleWorking] 예상 못 한 오류: $e\n$st');
      _fail('스케줄을 만들지 못했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  void _fail(String message) {
    _timer?.cancel();
    if (!mounted) return;
    setState(() {
      _hasError = true;
      _errorDetail = message;
    });
  }

  String _toFriendlyMessage(ScheduleApiException e) {
    // 서버 원문은 로그로만 남기고 화면에는 원인별 안내 문구만 보여줌.
    if (e.kind == ScheduleApiErrorKind.badRequest) {
      return '${e.userMessage}\n(콘솔 로그에서 상세 원인을 확인해주세요)';
    }
    return e.userMessage;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8DFD1), // 시안에 맞춰 약간 따뜻한 크림톤 조율
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 세로 여백(24*2)을 빼야 내용이 짧을 때 불필요한 스크롤이 안 생김.
            final minHeight = (constraints.maxHeight - 48).clamp(0.0, double.infinity);

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          _hasError ? '스케줄을 만들지 못했어요' : '당신의 추억 속\n골목을 걷고 있어요',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFC85A32), // 온길 주황색
                            height: 1.3,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      if (_hasError) ...[
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            _errorDetail ?? '잠시 후 다시 시도해주세요.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF332A24),
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFC85A32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('이전으로 돌아가기', style: TextStyle(color: Colors.white)),
                        ),
                      ] else
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 600), // 전환 속도 (0.6초)
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            final offsetAnimation = Tween<Offset>(
                              begin: const Offset(0.0, 0.5), // 약간 아래에서 시작
                              end: Offset.zero,
                            ).animate(animation);

                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: offsetAnimation,
                                child: child,
                              ),
                            );
                          },
                          // 키는 AnimatedSwitcher의 직속 자식에 있어야 전환이 감지됨.
                          child: SizedBox(
                            key: ValueKey<int>(_currentIndex),
                            width: double.infinity,
                            child: Text(
                              _loadingTexts[_currentIndex],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF332A24), // 짙은 워시드 다크그레이
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
