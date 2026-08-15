import 'package:flutter/material.dart';
import '../controllers/schedule_list_controller.dart';

class ScheduleListScreen extends StatefulWidget {
  const ScheduleListScreen({super.key});

  @override
  State<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends State<ScheduleListScreen> {
  final ScheduleListController _controller = ScheduleListController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {});
    });
    // 화면에 들어올 때 API에서 스케줄 목록 불러오기
    _controller.fetchSchedules();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // API에서 내려오는 데이터 아이콘 처리 보조 함수
  IconData _getScheduleIcon(String? iconType) {
    switch (iconType) {
      case 'school':
        return Icons.school_outlined;
      case 'building':
        return Icons.account_balance_outlined;
      case 'home':
        return Icons.home_outlined;
      default:
        return Icons.map_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFC85A32);
    const bgColor = Color(0xFFFAF7F2);
    const cardBgColor = Colors.white;
    const iconBoxBg = Color(0xFFEADBCE);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // 1. 상단 타이틀 & 헤더 영역
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '스케줄',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFEBE4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.tune,
                          color: Color(0xFF2C2825),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '추억 좌표를 기준으로 완성된 여정들',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8A827A),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. API 데이터 연동 리스트 영역
            Expanded(
              child: _controller.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: primaryColor),
                    )
                  : _controller.schedules.isEmpty
                      ? Center(
                          child: _controller.errorMessage != null
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _controller.errorMessage!,
                                      style: const TextStyle(color: Color(0xFF8A827A)),
                                    ),
                                    const SizedBox(height: 12),
                                    TextButton(
                                      onPressed: () => _controller.fetchSchedules(),
                                      child: const Text(
                                        '다시 시도',
                                        style: TextStyle(
                                          color: primaryColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : const Text(
                                  '아직 저장된 스케줄이 없어요.',
                                  style: TextStyle(color: Color(0xFF8A827A)),
                                ),
                        )
                      : RefreshIndicator(
                          color: primaryColor,
                          onRefresh: () => _controller.fetchSchedules(),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: _controller.schedules.length,
                            itemBuilder: (context, index) {
                              final item = _controller.schedules[index];

                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: cardBgColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFEFEBE4)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.02),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    // 아이콘 박스
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: iconBoxBg,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Icon(
                                        _getScheduleIcon(item['icon_type']),
                                        color: const Color(0xFF8A827A),
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 16),

                                    // API에서 가져온 정보 세팅
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['title'] ?? '제목 없음',
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
                                                Icons.calendar_month_outlined,
                                                size: 14,
                                                color: Color(0xFF8A827A),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                item['mobility_mode'] ?? '이동 수단 정보 없음',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Color(0xFF8A827A),
                                                ),
                                              ),
                                              if (item['trip_type'] != null) ...[
                                                const SizedBox(width: 6),
                                                Text(
                                                  item['trip_type'] ?? '',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFFE2A84B),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    const Icon(
                                      Icons.chevron_right,
                                      color: Color(0xFFACACAC),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
            ),

            // 3. 하단 버튼
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/place_select');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add, color: Colors.white, size: 20),
                      SizedBox(width: 6),
                      Text(
                        '새로운 스케줄 만들기',
                        style: TextStyle(
                          fontSize: 16,
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