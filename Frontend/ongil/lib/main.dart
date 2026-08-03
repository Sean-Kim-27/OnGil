import 'package:flutter/material.dart';
// 1. 방금 만든 home_screen.dart 파일을 가져오기 (import)
import './screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      // 우측 상단에 뜨는 'DEBUG' 띠 숨기기
      debugShowCheckedModeBanner: false,
      title: '온길',
      
      // 2. 앱이 실행될 때 가장 먼저 보여줄 첫 화면(home)으로 HomeScreen을 지정!
      home: HomeScreen(),
    );
  }
}
