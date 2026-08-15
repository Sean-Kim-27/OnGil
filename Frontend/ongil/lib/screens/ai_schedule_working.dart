import 'dart:async'; // Timer를 사용하기 위해 필요
import 'package:flutter/material.dart';
import 'schedule_detail_screen.dart';
import '../services/api_service.dart';
import '../services/place_service.dart';

class AiScheduleWorking extends StatefulWidget {
  const AiScheduleWorking({super.key});

  @override
  State<AiScheduleWorking> createState() => _AiScheduleWorkingState();
}

class _AiScheduleWorkingState extends State<AiScheduleWorking> {
  // 1. 순차적으로 보여줄 문구 리스트 (실제 API 응답을 기다리는 동안 보여주는 연출용)
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
  bool _requestStarted = false; // didChangeDependencies가 여러 번 불려도 요청은 한 번만

  @override
  void initState() {
    super.initState();
    // 문구는 실제 응답 여부와 무관하게 계속 순환 연출만 함 (마지막 문구에서 대기).
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (timer) {
      if (!mounted) return;
      setState(() {
        if (_currentIndex < _loadingTexts.length - 1) {
          _currentIndex++;
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestStarted) return;
    _requestStarted = true;

    // place_select_screen.dart에서 넘겨준 실제 선택 장소들(RecommendedPlace 리스트).
    final args = ModalRoute.of(context)?.settings.arguments;
    final places = args is List<RecommendedPlace> ? args : const <RecommendedPlace>[];
    _createSchedule(places);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _createSchedule(List<RecommendedPlace> places) async {
    if (places.isEmpty) {
      _timer?.cancel();
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorDetail = '선택된 장소가 없어요. 이전 화면으로 돌아가서 장소를 선택해주세요.';
      });
      return;
    }

    try {
      final result = await ApiService.createSchedule(places);
      final scheduleId = (result['schedule_id'] ?? result['id'])?.toString();
      if (scheduleId == null || scheduleId.isEmpty) {
        throw Exception('응답에 schedule_id가 없어요: $result');
      }

      await ApiService.saveLastScheduleId(scheduleId);

      _timer?.cancel();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ScheduleDetailScreen(scheduleId: scheduleId),
        ),
      );
    } catch (e) {
      _timer?.cancel();
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorDetail = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8DFD1), // 시안에 맞춰 약간 따뜻한 크림톤 조율
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // [상단 고정 주황색 타이틀]
              Text(
                _hasError ? '스케줄을 만들지 못했어요' : '당신의 추억 속\n골목을 걷고 있어요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFC85A32), // 온길 주황색
                  height: 1.3,
                ),
              ),

              const SizedBox(height: 32),

              if (_hasError) ...[
                Text(
                  _errorDetail ?? '잠시 후 다시 시도해주세요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF332A24),
                    height: 1.4,
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
                // [하단 슬라이드 전환 서브 문구]
                // AnimatedSwitcher가 글자가 바뀔 때 스스륵(Fade+Slide) 연출을 해줌
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600), // 전환 속도 (0.6초)
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    // 아래에서 위로 살짝 올라오는 슬라이드 + 페이드 효과
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
                  // ValueKey를 쥐여줘야 글자가 바뀌었음을 인식하고 애니메이션 실행
                  child: Text(
                    _loadingTexts[_currentIndex],
                    key: ValueKey<int>(_currentIndex),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF332A24), 
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
