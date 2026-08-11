import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 👈 추가

// 전체 스크린 파일들 import
import 'screens/schedule_list_screen.dart';
import 'screens/place_select_screen.dart';
import 'screens/ai_schedule_working.dart';
import 'screens/schedule_detail_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  debugPrint('앱 시작!'); // 앱 시작 시 콘솔에 로그 찍기
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  // 상단 상태바 투명화 설정
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  AuthRepository.initialize(appKey: '89ffb7fc95646374f10f4e7b942677ed'); // 카카오맵 플러그인 초기화
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '온길',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFAF7F2),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC85A32),
          primary: const Color(0xFFC85A32),
        ),
        useMaterial3: true,
      ),
      // 1. 앱을 켜면 제일 먼저 홈 화면이 떠!
      home: const HomeScreen(),
      
      // 2. 앱 내 전체 화면 이동 경로(Route) 정의
      routes: {
        '/schedule_list': (context) => const ScheduleListScreen(),
        '/place_select': (context) => const PlaceSelectScreen(),
        '/ai_working': (context) => const AiScheduleWorking(),
        '/schedule_detail': (context) => ScheduleDetailScreen(scheduleId: ModalRoute.of(context)!.settings.arguments as String),
      },
    );
  }
}