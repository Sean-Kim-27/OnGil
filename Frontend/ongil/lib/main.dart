import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'widgets/mobile_frame.dart';

/// 카카오 디벨로퍼스 "네이티브 키"
const String kKakaoNativeAppKey = 'ad2a4b2182c29302796381039856a10c';

/// 구글 클라우드 콘솔 "OAuth" 키
const String? kGoogleServerClientId =
    '9411341480-2i2l7fr0vengvod9dauk5gvumstsg23t.apps.googleusercontent.com';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  KakaoSdk.init(nativeAppKey: kKakaoNativeAppKey);
  await AuthService.instance.initializeGoogle(serverClientId: kGoogleServerClientId);

  runApp(const OngilApp());
}

class OngilApp extends StatelessWidget {
  const OngilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '온길',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignUpScreen(),
        '/home': (_) => const HomeScreen(),
      },
      builder: (context, child) {
        return ResponsiveMobileFrame(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
