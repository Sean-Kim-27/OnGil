import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/schedule_list_screen.dart';
import 'screens/place_select_screen.dart';
import 'screens/ai_schedule_working.dart';
import 'screens/schedule_detail_screen.dart';
import 'services/auth_service.dart';
import 'services/place_service.dart';
import 'widgets/mobile_frame.dart';

/// 카카오 디벨로퍼스 "네이티브 키" (로그인용 SDK)
const String kKakaoNativeAppKey = 'ad2a4b2182c29302796381039856a10c';

/// 카카오 지도 플러그인 앱 키 (지도 렌더링용, 로그인 키와 다름)
const String kKakaoMapAppKey = '89ffb7fc95646374f10f4e7b942677ed';

/// 구글 클라우드 콘솔 "OAuth" 키
const String? kGoogleServerClientId =
    '9411341480-2i2l7fr0vengvod9dauk5gvumstsg23t.apps.googleusercontent.com';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env가 없어도(아직 안 만들었어도) 앱이 죽지 않게 isOptional: true로 로드함.
  // 이러면 지도 길찾기/스케줄 API처럼 dotenv.env[...]를 읽는 코드들이 그냥 null을
  // 받고(각자 정의된 기본값/에러 처리로 흘러감) 앱 시작 자체는 항상 성공함.
  // 실제로 지도·스케줄 기능을 쓰려면 .env.example 참고해서 진짜 .env를 만들어야 함.
  await dotenv.load(fileName: '.env', isOptional: true);

  // 상단 상태바 투명화 (도현님 쪽 디자인 반영)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  KakaoSdk.init(nativeAppKey: kKakaoNativeAppKey);
  AuthRepository.initialize(appKey: kKakaoMapAppKey); // 카카오맵 플러그인(지도 렌더링) 초기화
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
      // 서비스 레이어에서 강제 로그아웃 시 쓰는 키
      navigatorKey: rootNavigatorKey,
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignUpScreen(),
        '/home': (_) => const HomeScreen(),
        // 도현님 스케줄 플로우 (홈 화면 '스케줄'/'지도' 탭 안에서는 직접 push로도 진입 가능)
        '/schedule_list': (_) => const ScheduleListScreen(),
        '/place_select': (context) => PlaceSelectScreen(
              places: ModalRoute.of(context)!.settings.arguments as List<RecommendedPlace>?,
            ),
        '/ai_working': (_) => const AiScheduleWorking(),
        '/schedule_detail': (context) => ScheduleDetailScreen(
              scheduleId: ModalRoute.of(context)!.settings.arguments as String,
            ),
      },
      builder: (context, child) {
        return ResponsiveMobileFrame(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
