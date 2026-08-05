import 'package:flutter/material.dart';
import '../widgets/top_header.dart';
import '../widgets/main_feature_card.dart';
import '../widgets/quick_action_cards.dart';
import 'Ai_schedule_working.dart';
import 'Schedule_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 2; // 기본 탭: 홈(2번)

  // 1. 各 탭에 보여줄 화면 리스트
  List<Widget> get _pages => [
        const Center(child: Text('지도 화면')),          // 0번 탭
        const ScheduleListScreen(),                   // 1번 탭 (⭐ 스케줄 화면!)
        _buildHomeContent(),                          // 2번 탭 (기존 홈 메인)
        const Center(child: Text('방명록 화면')),        // 3번 탭
        const Center(child: Text('설정 화면')),          // 4번 탭
      ];

  static const Color primaryColor = Color(0xFFC85A32); // 온길 시그니처 테라코타 오렌지
  static const Color bgColor = Color(0xFFFAF7F2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F2),
      
      // ⭐ 현재 선택된 탭에 맞춰 화면을 띄워줌! (하단 바는 고정 유지)
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _pages[_selectedIndex],
        ),
      ),

      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // 기존 홈 화면 내용 (독립 위젯 함수로 정리)
  Widget _buildHomeContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const TopHeader(),
          const SizedBox(height: 20),
          const _GreetingSection(),
          const SizedBox(height: 24),
          const MainFeatureCard(),
          const SizedBox(height: 16),
          
          // 퀵 액션 카드에서 스케줄 누르면 로딩 띄우기 예시
          QuickActionCards(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // 하단 네비게이션 바 클릭 로직
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEFEBE4), width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) async {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed, // 탭 5개 이상일 때 모양 유지
        backgroundColor: bgColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey[500],
        selectedFontSize: 11,
        unselectedFontSize: 11,
        elevation: 0,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: '지도',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.alt_route_outlined),
            activeIcon: Icon(Icons.alt_route),
            label: '스케줄',
          ),
          BottomNavigationBarItem(
            icon: Column(
              children: [
                const Icon(Icons.home_outlined),
                if (_selectedIndex == 2)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            activeIcon: const Icon(Icons.home_filled, color: primaryColor),
            label: '홈',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            activeIcon: Icon(Icons.menu_book),
            label: '방명록',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}

// 환영 문구 영역만 작게 분리한 위젯
class _GreetingSection extends StatelessWidget {
  const _GreetingSection();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: const [
          Text(
            'WELCOME BACK',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFC39B6B),
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '도현님, 오늘도\n추억 속을 걸어보세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: Color(0xFF2C2825),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
