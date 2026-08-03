import 'package:flutter/material.dart';
import '../widgets/top_header.dart';
import '../widgets/main_feature_card.dart';
import '../widgets/quick_action_cards.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 현재 선택된 하단 탭 인덱스 (0: 지도, 1: 스케줄, 2: 홈, 3: 방명록, 4: 설정)
  int _selectedIndex = 2; 

  // 테마 색상 상수로 정의
  static const Color primaryColor = Color(0xFFC85A32); // 온길 주황색
  static const Color bgColor = Color(0xFFFAF7F2);      // 크림 배경색

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      
      // 1. 메인 컨텐츠 영역 (스크롤 가능하게 SingleChildScrollView로 감쌈)
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: const [
                TopHeader(),             // 1) 상단 로고 & 아이콘
                SizedBox(height: 20),
                _GreetingSection(),      // 2) 환영 문구 (아래 분리)
                SizedBox(height: 24),
                MainFeatureCard(),       // 3) 메인 추억 카드
                SizedBox(height: 16),
                QuickActionCards(),      // 4) 하단 퀵 링크 2개
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),

      // 2. 우측 하단 주황색 플러스(+) 플로팅 버튼
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 8.0, right: 8.0),
        child: FloatingActionButton(
          onPressed: () {
            print('플러스 버튼 클릭됨!');
          },
          backgroundColor: primaryColor,
          elevation: 4,
          shape: const CircleBorder(), // 완전한 동그라미 모양
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),

      // 3. 하단 5개 탭 네비게이션 바
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // 하단 네비게이션 바 생성 함수
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEFEBE4), width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index; // 탭 클릭 시 상태 변경 & 화면 새로고침!
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
