import 'package:flutter/material.dart';
import 'schedule_list_screen.dart';

// 나중에 API/DB에서 넘어올 일정 아이템 모델
class ScheduleTimelineItem {
  final String timeCategory; // 예: "오전 09:00 · 숙소"
  final String title;        // 예: "충주 한옥스테이"
  final String location;     // 예: "칠금동 · 도보 6분"
  final String tag;          // 예: "체크인"
  final IconData icon;

  ScheduleTimelineItem({
    required this.timeCategory,
    required this.title,
    required this.location,
    required this.tag,
    required this.icon,
  });
}

class ScheduleDetailScreen extends StatelessWidget {
  const ScheduleDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFC85A32);
    const bgColor = Color(0xFFFAF7F2);

    // 나중에 DB에서 들어올 결과 데이터 스켈레톤 리스트
    final List<ScheduleTimelineItem> timelineItems = [
      ScheduleTimelineItem(
        timeCategory: '오전 09:00 · 숙소',
        title: '충주 한옥스테이',
        location: '칠금동 · 도보 6분',
        tag: '체크인',
        icon: Icons.nightlight_round_outlined,
      ),
      ScheduleTimelineItem(
        timeCategory: '오전 11:00 · 관광지',
        title: '탄금대',
        location: '칠금동 산1-1',
        tag: '추억 반경 3km',
        icon: Icons.account_balance_outlined,
      ),
      ScheduleTimelineItem(
        timeCategory: '오후 14:00 · 카페',
        title: '구도심 골목카페',
        location: '성내동 12-3',
        tag: '현지 인기',
        icon: Icons.coffee_outlined,
      ),
      ScheduleTimelineItem(
        timeCategory: '저녁 18:00 · 식당',
        title: '충주 손칼국수',
        location: '성내동 8-1',
        tag: '저녁 추천',
        icon: Icons.ramen_dining_outlined,
      ),
    ];

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // 1. 상단 앱바 (뒤로가기, 타이틀, 수정 아이콘)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF2C2825)),
                    onPressed: () => Navigator.pop(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ScheduleListScreen(),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '충주 초등학교 여정',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C2825),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Color(0xFF2C2825), size: 22),
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            // 2. 점선 연도 칩
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: primaryColor,
                  width: 1.2,
                  style: BorderStyle.solid, // Flutter 기본 Border는 점선 미지원이라 깔끔한 선 처리
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.location_on_outlined, size: 14, color: primaryColor),
                  SizedBox(width: 4),
                  Text(
                    '1998년 · 초등학교 시절',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. 타임라인 리스트 영역
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                itemCount: timelineItems.length,
                itemBuilder: (context, index) {
                  final item = timelineItems[index];
                  final isLast = index == timelineItems.length - 1;

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // [왼쪽] 수직 타임라인 (점 + 세로 구분선)
                        Column(
                          children: [
                            const SizedBox(height: 4),
                            // 노란색 지점 도트
                            Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE2A84B),
                                shape: BoxShape.circle,
                              ),
                            ),
                            // 세로 점선/실선 연결선
                            if (!isLast)
                              Expanded(
                                child: Container(
                                  width: 1.5,
                                  color: const Color(0xFFE4DCD3),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 16),

                        // [오른쪽] 시간 정보 + 카테고리 카드
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 시간 및 카테고리 텍스트
                                Center(
                                  child: Text(
                                    item.timeCategory,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF8A827A),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // 장소 카드
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFEFEBE4)),
                                  ),
                                  child: Row(
                                    children: [
                                      // 아이콘 박스
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEADBCE).withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Icon(item.icon, color: const Color(0xFF8C7A6B), size: 26),
                                      ),
                                      const SizedBox(width: 16),

                                      // 상세 정보
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF2C2825),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              item.location,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF8A827A),
                                              ),
                                            ),
                                            const SizedBox(height: 8),

                                            // 연주황 칩 태그
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF9EAE1),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                item.tag,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: primaryColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // 4. 하단 버튼 영역 (공유하기 / 일정 편집하기)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: bgColor,
                border: Border(top: BorderSide(color: Color(0xFFEFEBE4))),
              ),
              child: Row(
                children: [
                  // 공유하기 버튼
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.share_outlined, size: 18, color: Color(0xFF2C2825)),
                      label: const Text(
                        '공유하기',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C2825),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFDDD7CD)),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 일정 편집하기 버튼
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.edit, size: 18, color: Colors.white),
                      label: const Text(
                        '일정 편집하기',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: primaryColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}