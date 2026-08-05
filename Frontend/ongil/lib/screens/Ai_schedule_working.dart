import 'dart:async'; // Timer를 사용하기 위해 필요!
import 'package:flutter/material.dart';
import 'schedule_detail_screen.dart';

class AiScheduleWorking extends StatefulWidget {
  const AiScheduleWorking({super.key});

  @override
  State<AiScheduleWorking> createState() => _AiScheduleWorkingState();
}

class _AiScheduleWorkingState extends State<AiScheduleWorking> {
  // 1. 순차적으로 보여줄 문구 리스트
  final List<String> _loadingTexts = [
    '충주시 대소원면 반경 5km를 살펴보는 중...',
    '그때 그 골목 주변 맛집을 찾고 있어요',
    '숙소와 이동 경로를 계산하는 중이에요',
    '하루 일정으로 정리하고 있어요',
  ];

  int _currentIndex = 0; // 현재 보여줄 문구의 인덱스
  Timer? _timer;         // 타이머 객체

  @override
  void initState() {
    super.initState();
    // 2. 화면이 켜지면 3초마다 인덱스를 바꿔주는 타이머 가동!
    _timer = Timer.periodic(const Duration(milliseconds: 3000), (timer) {
      setState(() {
        // 리스트 끝에 도달하면 마지막 문구 유지 (원하면 % 연산으로 반복도 가능)
        if (_currentIndex < _loadingTexts.length - 1) {
          _currentIndex++;
        } else {
          _timer?.cancel(); // 다 돌면 타이머 종료 (나중에 여기서 다음 화면으로 이동!)
          _redirectToResultScreen();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // 화면이 닫힐 때 타이머 메모리 해제!
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8DFD1), // 시안에 맞춰 약간 따뜻한 크림톤 조율
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // [상단 고정 주황색 타이틀]
            const Text(
              '당신의 추억 속\n골목을 걷고 있어요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFFC85A32), // 온길 주황색
                height: 1.3,
              ),
            ),

            const SizedBox(height: 32),

            // [하단 슬라이드 전환 서브 문구]
            // AnimatedSwitcher가 글자가 바뀔 때 스스륵(Fade+Slide) 연출을 해줌!
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
              // ValueKey를 쥐여줘야 글자가 바뀌었음을 인식하고 애니메이션을 돌려!
              child: Text(
                _loadingTexts[_currentIndex],
                key: ValueKey<int>(_currentIndex),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF332A24), // 짙은 워시드 다크그레이
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _redirectToResultScreen() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      // ⭐ 로딩 끝나면 AI가 완성한 타임라인 상세 화면으로 이동!
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const ScheduleDetailScreen(),
        ),
      );
    });
  }
}