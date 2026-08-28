import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

/// 토큰 만료 시 BuildContext 없이 로그인 화면으로 이동시키기 위한 전역 네비게이터 키.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

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
  final String _backendUrl = 'https://api.seankim428.site/api/v1/auth/social-login';
  final String _meUrl = 'https://api.seankim428.site/api/v1/auth/me';

  /// clientId / serverClientId는 구글 클라우드 콘솔에서 만든 OAuth 클라이언트
  Future<void> initializeGoogle({String? clientId, String? serverClientId}) async {
    if (_googleInitialized) return;
    await _google.initialize(clientId: clientId, serverClientId: serverClientId);
    _googleInitialized = true;
  }

  Future<AppAuthProfile> signInWithGoogle() async {
    if (!_google.supportsAuthenticate()) {
      throw AuthException('이 플랫폼에서는 구글 로그인 버튼을 직접 지원하지 않아요.');
    }

    final Completer<GoogleSignInAccount?> completer = Completer<GoogleSignInAccount?>();
    late final StreamSubscription<GoogleSignInAuthenticationEvent> sub;
    sub = _google.authenticationEvents.listen(
      (GoogleSignInAuthenticationEvent event) {
        final GoogleSignInAccount? user = switch (event) {
          GoogleSignInAuthenticationEventSignIn() => event.user,
          GoogleSignInAuthenticationEventSignOut() => null,
        };
        if (!completer.isCompleted) completer.complete(user);
        sub.cancel();
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
        sub.cancel();
      },
    );

    try {
      await _google.authenticate();
    } on GoogleSignInException catch (e) {
      await sub.cancel();
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw AuthException('로그인을 취소했어요.', isUserCancel: true);
      }
      throw AuthException('구글 로그인에 실패했어요. (${e.code})');
    }

    final GoogleSignInAccount? account = await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => null,
    );
    if (account == null) {
      throw AuthException('구글 로그인에 실패했어요.');
    }

    // Google은 ID token 전송
    final GoogleSignInAuthentication auth = await account.authentication;
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
  Future<void> _sendTokenToBackend({required String provider, required String token}) async {
    late final http.Response response;
    try {
      response = await http.post(
        Uri.parse(_backendUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'provider': provider,
          'token': token,
        }),
      );
    } catch (e) {
      // 여기 catch는 진짜 네트워크 문제(연결 안 됨, 타임아웃 등)일 때만 탐.
      throw AuthException('서버와의 통신에 실패했습니다. 인터넷 연결을 확인해주세요.');
    }

    // 🔍 디버깅용: 실제 서버 응답을 콘솔에 그대로 찍음. flutter run 콘솔에서
    // 이 로그로 실제 필드명이 뭔지 바로 확인 가능함 (로그인 안 넘어갈 때 여기부터 확인).
    debugPrint('🔑 [social-login] status=${response.statusCode} body=${response.body}');

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw AuthException('온길 서버 연동에 실패했습니다. (Error: ${response.statusCode})');
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw AuthException('서버 응답을 해석하지 못했어요. (JSON 형식이 예상과 달라요)');
    }

    // TODO: 백엔드 API 명세서 확인되면 이 목록은 정리해도 됨. 지금은 snake_case/
    // camelCase, data로 한 번 감싸진 경우까지 최대한 시도해서 원인 파악을 돕는 용도.
    final nested = data['data'];
    final String? onGilAccessToken = (data['access_token'] ?? data['accessToken'] ?? (nested is Map ? (nested['access_token'] ?? nested['accessToken']) : null)) as String?;
    final String? onGilRefreshToken = (data['refresh_token'] ?? data['refreshToken'] ?? (nested is Map ? (nested['refresh_token'] ?? nested['refreshToken']) : null)) as String?;

    if (onGilAccessToken == null || onGilAccessToken.isEmpty) {
      // 응답 자체는 성공(200)했는데 토큰 필드를 못 찾은 경우 - 실제 응답 내용을
      // 그대로 보여줘서 정확한 필드명을 바로 알 수 있게 함.
      throw AuthException('로그인 응답에서 토큰을 찾지 못했어요.\n서버 응답: ${response.body}');
    }

    // Secure Storage에 저장 (절대 print()로 찍지 않기)
    await _storage.write(key: 'accessToken', value: onGilAccessToken);
    if (onGilRefreshToken != null && onGilRefreshToken.isNotEmpty) {
      await _storage.write(key: 'refreshToken', value: onGilRefreshToken);
    }

    final dynamic userPayload = data['user'] ??
        (nested is Map ? nested['user'] : null);
    if (userPayload is Map && userPayload['id'] != null) {
      await _storage.write(key: 'userId', value: userPayload['id'].toString());
    }
  }

  // 추후 앱 내 다른 화면에서 온길 토큰이 필요할 때 꺼내 쓰는 용도
  Future<String?> getOnGilAccessToken() async {
    return await _storage.read(key: 'accessToken');
  }

  /// 현재 온길 사용자 ID. 예전 로그인 세션처럼 로컬에 ID가 없으면 /auth/me에서 보충한다.
  Future<int?> getCurrentUserId() async {
    final stored = await _storage.read(key: 'userId');
    final storedId = int.tryParse(stored ?? '');
    if (storedId != null) return storedId;

    final response = await authorizedGet(Uri.parse(_meUrl));
    if (response.statusCode != 200) return null;
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final id = data is Map<String, dynamic> ? data['id'] as int? : null;
      if (id != null) {
        await _storage.write(key: 'userId', value: id.toString());
      }
      return id;
    } catch (_) {
      return null;
    }
  }

  /// 회원가입 화면에서 확정한 닉네임·프로필 사진을 로컬에 저장.
  /// TODO: 백엔드 프로필 등록·수정 API 명세가 나오면 authorizedPost 등으로 서버에도 반영 필요.
  Future<void> saveUserProfile({String? nickname, String? photoUrl}) async {
    if (nickname != null) {
      await _storage.write(key: 'nickname', value: nickname);
    }
    if (photoUrl != null) {
      await _storage.write(key: 'photoUrl', value: photoUrl);
    }
  }

  Future<String?> getNickname() async {
    return await _storage.read(key: 'nickname');
  }

  Future<String?> getPhotoUrl() async {
    return await _storage.read(key: 'photoUrl');
  }

  /// 온길 access token이 남아있는지로 로그인 세션 여부를 판단.
  Future<bool> hasSession() async {
    final token = await getOnGilAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// 로그아웃: 저장해둔 토큰/닉네임/프로필 사진 등 로컬 정보를 전부 지움.
  Future<void> logout() async {
    await _storage.deleteAll();
  }

  /// 회원탈퇴.
  /// TODO: 백엔드 회원탈퇴 API 명세가 정해지면 서버에 탈퇴 요청을 먼저 보내도록 교체해야 함.
  Future<void> deleteAccount() async {
    await logout();
  }

  /// 세션이 끊겼을 때 로컬 토큰을 지우고 로그인 화면으로 강제 이동시킴.
  Future<void> forceLogout() async {
    await logout();
    rootNavigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  // 인증이 필요한 API용 공용 헬퍼. 401 응답이 오면 자동으로 forceLogout() 처리함.
  Future<Map<String, String>> _authHeaders() async {
    final token = await getOnGilAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _handleUnauthorized(http.Response response) async {
    if (response.statusCode == 401) {
      await forceLogout();
    }
  }

  Future<http.Response> authorizedGet(Uri url) async {
    final response = await http.get(url, headers: await _authHeaders());
    await _handleUnauthorized(response);
    return response;
  }

  Future<http.Response> authorizedPost(Uri url, {Object? body}) async {
    final response = await http.post(
      url,
      headers: await _authHeaders(),
      body: body,
    );
    await _handleUnauthorized(response);
    return response;
  }

  Future<http.Response> authorizedPut(Uri url, {Object? body}) async {
    final response = await http.put(
      url,
      headers: await _authHeaders(),
      body: body,
    );
    await _handleUnauthorized(response);
    return response;
  }

  Future<http.Response> authorizedDelete(Uri url) async {
    final response = await http.delete(url, headers: await _authHeaders());
    await _handleUnauthorized(response);
    return response;
  }
}
