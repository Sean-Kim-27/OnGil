import 'package:flutter/material.dart';

class ScheduleListScreen extends StatelessWidget {
  const ScheduleListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F2), // 크림 배경색
      body: SafeArea(
        child: Column(
          children: [
            // 1. 상단 헤더 (타이틀 + 오른쪽 동그란 필터 버튼)
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '스케줄',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC85A32), // 온길 주황색
                  ),
                ),
                // 필터 버튼
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFEBE4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.filter_list,
                    color: Color(0xFF2C2825),
                    size: 20,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            // 2. 서브 타이틀
            const Text(
              '추억 좌표를 기준으로 완성된 여정들',
              style: TextStyle(fontSize: 14, color: Color(0xFF8A827A)),
            ),

            const SizedBox(height: 24),

            // 3. 스케줄 카드 리스트 (스크롤 가능)
            Expanded(
              child: ListView(
                children: const [
                  _ScheduleCard(
                    icon: Icons.school_outlined,
                    title: '충주 · 초등학교 근처',
                    duration: '하루 일정 · 4곳',
                    year: '1998년',
                  ),
                  SizedBox(height: 16),
                  _ScheduleCard(
                    icon: Icons.account_balance_outlined,
                    title: '탄금대 · 옛 동네',
                    duration: '하루 일정 · 5곳',
                  ),
                  SizedBox(height: 16),
                  _ScheduleCard(
                    icon: Icons.home_outlined,
                    title: '옛 자취방 골목',
                    duration: '하루 일정 · 3곳',
                  ),
                ],
              ),
            ),

            // 4. 하단 "+ 새로운 스케줄 만들기" 버튼
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC85A32),
                    elevation: 3,
                    shadowColor: const Color(0xFFC85A32).withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        '새로운 스케줄 만들기',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
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

// 📦 카드 하나를 담당하는 재사용 위젯
class _ScheduleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String duration;
  final String? year; // 연도는 선택사항(nullable)

  const _ScheduleCard({
    required this.icon,
    required this.title,
    required this.duration,
    this.year,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEFEBE4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // 왼쪽 아이콘 상자
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFEADBCE).withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF8C7A6B), size: 28),
          ),
          const SizedBox(width: 16),

          // 중앙 텍스트 영역
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C2825),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 12,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      duration,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (year != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        year!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFC85A32),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // 오른쪽 화살표
          const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        ],
      ),
    );
  }
}
