import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'package:flutter/foundation.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/place_select_screen.dart';
import 'screens/schedule_detail_screen.dart';
import 'screens/schedule_list_screen.dart';
import 'screens/signup_screen.dart';
import 'services/auth_service.dart';
import 'services/place_service.dart';
import 'theme/app_theme.dart';
import 'widgets/mobile_frame.dart';

/// 모든 키는 .env 에서 읽어온다. (.env 는 .gitignore 대상)
/// 새로 클론한 사람은 .env.example 을 .env 로 복사한 뒤 값을 채워 넣어야 한다.
///
/// - KAKAO_NATIVE_APP_KEY : AndroidManifest 의 scheme("kakao" + 이 값)과 반드시 일치
/// - KAKAO_JS_APP_KEY     : 지도 렌더링용 JavaScript 키
/// - GOOGLE_SERVER_CLIENT_ID : 구글 로그인 서버 클라이언트 ID
String _requireEnv(String key) {
  final value = dotenv.env[key];
  if (value == null || value.isEmpty) {
    throw StateError(
      '.env 에 $key 가 없습니다. .env.example 을 .env 로 복사한 뒤 값을 채워주세요.',
    );
  }
  return value;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // isOptional 을 끈다: .env 가 없으면 조용히 넘어가는 대신 즉시 알려준다.
  await dotenv.load(fileName: '.env');

  final kakaoNativeAppKey = _requireEnv('KAKAO_NATIVE_APP_KEY');
  final kakaoJsAppKey = _requireEnv('KAKAO_JS_APP_KEY');
  final googleServerClientId = _requireEnv('GOOGLE_SERVER_CLIENT_ID');

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  KakaoSdk.init(nativeAppKey: kakaoNativeAppKey);
  AuthRepository.initialize(appKey: kakaoJsAppKey);
  await AuthService.instance.initializeGoogle(serverClientId: googleServerClientId);

  if (kDebugMode) {
    // 이 값을 카카오 디벨로퍼스 > 플랫폼 > Android > 키 해시에 등록해야 로그인이 성공한다.
    debugPrint('[Kakao] key hash = ${await KakaoSdk.origin}');
  }

  final loggedIn = await AuthService.instance.hasSession();

  runApp(OngilApp(initialRoute: loggedIn ? '/home' : '/login'));
}

class OngilApp extends StatelessWidget {
  final String initialRoute;

  const OngilApp({super.key, this.initialRoute = '/login'});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '온길',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: rootNavigatorKey,
      initialRoute: initialRoute,
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignUpScreen(),
        '/home': (_) => const HomeScreen(),
        '/schedule_list': (_) => const ScheduleListScreen(),
        '/place_select': (context) => PlaceSelectScreen(
              searchResult:
                  ModalRoute.of(context)!.settings.arguments as NearbySearchResult?,
            ),
        '/schedule_detail': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          final id = args is int ? args : int.tryParse('$args');
          if (id == null) {
            throw ArgumentError('/schedule_detail 라우트에 int scheduleId가 필요합니다 (받은 값: $args)');
          }
          return ScheduleDetailScreen(scheduleId: id);
        },
      },
      builder: (context, child) {
        return ResponsiveMobileFrame(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
