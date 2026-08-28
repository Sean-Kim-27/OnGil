// 프로젝트 기본 생성 템플릿(MyApp / counter 테스트)을 실제 앱에 맞게 교체한 버전.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ongil/main.dart';
import 'package:ongil/screens/login_screen.dart';

void main() {
  testWidgets('앱이 예외 없이 빌드되고 첫 화면으로 로그인 화면이 뜬다', (WidgetTester tester) async {
    await tester.pumpWidget(const OngilApp());
    await tester.pump();

    // initialRoute가 '/login' 이므로 LoginScreen이 렌더링되어야 한다.
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('로그인 화면에 소셜 로그인 버튼 영역이 존재한다', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );
    await tester.pump();


    expect(find.textContaining('카카오'), findsWidgets);
  });
}
