import 'package:flutter/material.dart';
import '../controllers/schedule_creation_controller.dart';

class PlaceSelectScreen extends StatefulWidget {
  const PlaceSelectScreen({super.key});

  @override
  State<PlaceSelectScreen> createState() => _PlaceSelectScreenState();
}

class _PlaceSelectScreenState extends State<PlaceSelectScreen> {
  final ScheduleCreationController _controller = ScheduleCreationController();

  // 테스트용 더미 장소 데이터
  final List<Map<String, String>> _dummyPlaces = [
    {'id': 'p1', 'title': '탄금대 공원', 'sub': '충주 대표 명소 · 도보 10분'},
    {'id': 'p2', 'title': '중앙탑 사적공원', 'sub': '시원한 호수뷰 · 산책로'},
    {'id': 'p3', 'title': '활옥동굴', 'sub': '신비로운 동굴 카약 체험'},
    {'id': 'p4', 'title': '수주팔봉', 'sub': '차박과 차크닉의 성지'},
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFC85A32);
    const bgColor = Color(0xFFFAF7F2);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: _controller.currentStep > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF2C2825), size: 20),
                onPressed: () => _controller.previousStep(),
              )
            : IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF2C2825)),
                onPressed: () => Navigator.pop(context),
              ),
        title: Text(
          '${_controller.currentStep}/4 단계',
          style: const TextStyle(
            color: primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 진행바 및 타이틀
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상단 프로그레스 바
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _controller.currentStep / 4,
                      backgroundColor: const Color(0xFFEFEBE4),
                      valueColor: const AlwaysStoppedAnimation<Color>(primaryColor),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${_controller.stepTitles[_controller.currentStep]}를\n선택해주세요',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C2825),
                      height: 1.3,
                    ),
                  ),
                  if (_controller.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _controller.errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),

            // 장소 선택 리스트 영역
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: _dummyPlaces.length,
                itemBuilder: (context, index) {
                  final place = _dummyPlaces[index];
                  final isSelected = _controller.currentStepSelectedIds.contains(place['id']);

                  return GestureDetector(
                    onTap: () => _controller.togglePlaceSelection(place['id']!),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? primaryColor : const Color(0xFFEFEBE4),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  place['title']!,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2C2825),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  place['sub']!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF8A827A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            isSelected ? Icons.check_circle : Icons.add_circle_outline,
                            color: isSelected ? primaryColor : const Color(0xFFACACAC),
                            size: 26,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // 하단 버튼 (4단계 완료 시 바로 ai_schedule_working으로 전환)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_controller.currentStep < 4) {
                      _controller.nextStep();
                    } else {
                      // 4단계 선택 검증
                      if (!_controller.canGoNext) {
                        _controller.nextStep(); // 에러 메시지 띄우기용
                        return;
                      }

                      // 백엔드 요청을 보내면서 'AI 로딩 화면'으로 즉시 전환!
                      final selectedIds = _controller.getAllSelectedPlaceIds;
                      
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(
                          context, 
                          '/ai_working',
                          arguments: selectedIds, // 선택한 장소 데이터 전달
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _controller.currentStep == 4 ? 'AI 스케줄 생성하기' : '다음 단계로',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}