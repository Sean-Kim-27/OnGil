import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

/// 구글/카카오 어느 쪽으로 로그인했든, 앱 나머지 부분에서는 이 모델 하나만 보고 쓰면 되도록 통일한 프로필.
class AppAuthProfile {
  final String provider; // 'google' | 'kakao'
  final String providerId;
  final String? email;
  final String? nickname;
  final String? photoUrl;

  const AppAuthProfile({
    required this.provider,
    required this.providerId,
    this.email,
    this.nickname,
    this.photoUrl,
  });
}

/// 로그인 실패/취소를 구분해서 던지는 예외.
class AuthException implements Exception {
  final String message;
  final bool isUserCancel;
  AuthException(this.message, {this.isUserCancel = false});
  @override
  String toString() => message;
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final GoogleSignIn _google = GoogleSignIn.instance;
  bool _googleInitialized = false;

  final _storage = const FlutterSecureStorage();

  // 백엔드 API 주소
  final String _backendUrl =
      'https://api.seankim428.site/api/v1/auth/social-login';

  /// clientId / serverClientId는 구글 클라우드 콘솔에서 만든 OAuth 클라이언트
  Future<void> initializeGoogle({
    String? clientId,
    String? serverClientId,
  }) async {
    if (_googleInitialized) return;
    await _google.initialize(
      clientId: clientId,
      serverClientId: serverClientId,
    );
    _googleInitialized = true;
  }

  Future<AppAuthProfile> signInWithGoogle() async {
    if (!_google.supportsAuthenticate()) {
      throw AuthException('이 플랫폼에서는 구글 로그인 버튼을 직접 지원하지 않아요.');
    }

    late final GoogleSignInAccount account;
    try {
      account = await _google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw AuthException(
          '구글 로그인을 완료하지 못했습니다. 계정 선택을 취소했거나 '
          'Android OAuth의 패키지명/SHA-1 설정이 일치하지 않습니다.',
        );
      }
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError ||
          e.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw AuthException(
          '구글 로그인 설정을 확인해주세요. (${e.description ?? e.code.name})',
        );
      }
      throw AuthException('구글 로그인에 실패했습니다. (${e.description ?? e.code.name})');
    }

    // Google은 ID token 전송
    final GoogleSignInAuthentication auth = account.authentication;
    final String? idToken = auth.idToken;

    if (idToken == null) {
      throw AuthException('구글 인증 정보를 가져오지 못했습니다.');
    }

    await _sendTokenToBackend(provider: 'google', token: idToken);

    return AppAuthProfile(
      provider: 'google',
      providerId: account.id,
      email: account.email,
      nickname: account.displayName,
    );
  }

  Future<AppAuthProfile> signInWithKakao() async {
    try {
      final bool talkInstalled = await isKakaoTalkInstalled();

      OAuthToken oauthToken;

      if (talkInstalled) {
        try {
          oauthToken = await UserApi.instance.loginWithKakaoTalk();
        } catch (_) {
          // 카카오톡으로 로그인 실패/취소 시 카카오계정 로그인으로 폴백
          oauthToken = await UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        oauthToken = await UserApi.instance.loginWithKakaoAccount();
      }

      // Kakao는 실제 OnGil 앱의 access token 전송
      final String accessToken = oauthToken.accessToken;

      await _sendTokenToBackend(provider: 'kakao', token: accessToken);

      final User user = await UserApi.instance.me();
      return AppAuthProfile(
        provider: 'kakao',
        providerId: user.id.toString(),
        email: user.kakaoAccount?.email,
        nickname: user.kakaoAccount?.profile?.nickname,
        photoUrl: user.kakaoAccount?.profile?.thumbnailImageUrl,
      );
    } catch (e) {
      // 서버 전송 중 발생한 에러 화면에 뜨도록
      if (e is AuthException) rethrow;
      throw AuthException('카카오 로그인에 실패했어요.');
    }
  }

  // 백엔드로 토큰을 보내 온길 자체 토큰을 받고, 시큐어 스토리지에 저장
  Future<void> _sendTokenToBackend({
    required String provider,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'provider': provider, 'token': token}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        // TODO: 아래 두 키 이름은 백엔드 API 명세서 기준으로, 실제 응답 필드명과 다르면 맞춰서 수정해야함.
        final String onGilAccessToken = data['access_token'];
        final String onGilRefreshToken = data['refresh_token'];

        // Secure Storage에 저장 (절대 print()로 찍지 않기)
        await _storage.write(key: 'accessToken', value: onGilAccessToken);
        await _storage.write(key: 'refreshToken', value: onGilRefreshToken);
      } else {
        throw AuthException(
          '온길 서버 연동에 실패했습니다. (Error: ${response.statusCode})',
        );
      }
    } catch (e) {
      throw AuthException('서버와의 통신에 실패했습니다. 인터넷 연결을 확인해주세요.');
    }
  }

  // 추후 앱 내 다른 화면에서 온길 토큰이 필요할 때 꺼내 쓰는 용도
  Future<String?> getOnGilAccessToken() async {
    return await _storage.read(key: 'accessToken');
  }
}
