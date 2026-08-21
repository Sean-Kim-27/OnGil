import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class AppAuthProfile {
  final String provider;
  final String providerId;
  final String? email;
  final String? nickname;
  final String? photoUrl;
  final bool isNewUser;

  const AppAuthProfile({
    required this.provider,
    required this.providerId,
    this.email,
    this.nickname,
    this.photoUrl,
    this.isNewUser = true,
  });
}

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
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _googleInitialized = false;

  static const String _defaultHost = '';

  String get _apiBase {
    var host = dotenv.env['BASE_URL'] ?? _defaultHost;
    if (host.isEmpty) host = _defaultHost;
    if (host.endsWith('/')) host = host.substring(0, host.length - 1);
    return host.endsWith('/api/v1') ? host : '$host/api/v1';
  }

  Future<void> initializeGoogle({String? clientId, String? serverClientId}) async {
    if (_googleInitialized) return;
    await _google.initialize(clientId: clientId, serverClientId: serverClientId);
    _googleInitialized = true;
  }

  // ---------------------------------------------------------------- 카카오

  Future<AppAuthProfile> signInWithKakao() async {
    final OAuthToken token = await _obtainKakaoToken();
    final payload = await _sendTokenToBackend(provider: 'kakao', token: token.accessToken);

    final User user = await UserApi.instance.me();
    return AppAuthProfile(
      provider: 'kakao',
      providerId: user.id.toString(),
      email: user.kakaoAccount?.email,
      nickname: user.kakaoAccount?.profile?.nickname,
      photoUrl: user.kakaoAccount?.profile?.thumbnailImageUrl,
      isNewUser: _readIsNewUser(payload),
    );
  }

  Future<OAuthToken> _obtainKakaoToken() async {
    if (await isKakaoTalkInstalled()) {
      try {
        return await UserApi.instance.loginWithKakaoTalk();
      } catch (error, stack) {
        // 사용자가 카카오톡 화면에서 직접 취소한 경우에는 웹 로그인으로 넘기지 않는다.
        if (_isKakaoCancel(error)) {
          throw AuthException('로그인을 취소했어요.', isUserCancel: true);
        }
        _log('카카오톡 로그인 실패 → 카카오계정으로 재시도', error, stack);
      }
    }

    try {
      return await UserApi.instance.loginWithKakaoAccount();
    } catch (error, stack) {
      if (_isKakaoCancel(error)) {
        throw AuthException('로그인을 취소했어요.', isUserCancel: true);
      }
      _log('카카오계정 로그인 실패', error, stack);
      throw AuthException(_describeKakaoError(error));
    }
  }

  bool _isKakaoCancel(Object error) {
    if (error is PlatformException && error.code == 'CANCELED') return true;
    // SDK 버전에 따라 예외 타입이 달라져 문자열로도 확인한다.
    final text = error.toString().toLowerCase();
    return text.contains('cancel') || text.contains('access_denied') || text.contains('accessdenied');
  }

  String _describeKakaoError(Object error) {
    final text = error.toString();

    if (text.contains('KOE101') || text.contains('misconfigured')) {
      return '카카오 앱 설정이 맞지 않아요.\n키 해시와 패키지명이 등록되어 있는지 확인해주세요.';
    }
    if (text.contains('KOE006')) {
      return '등록되지 않은 Redirect URI 입니다.\n카카오 디벨로퍼스에서 kakao{네이티브앱키}://oauth 를 등록해주세요.';
    }
    if (text.contains('KOE205') || text.contains('KOE203')) {
      return '동의 항목 설정이 맞지 않아요.\n카카오 로그인 동의항목을 확인해주세요.';
    }
    if (text.contains('KOE320')) {
      return '인증 코드가 만료됐어요. 다시 시도해주세요.';
    }
    if (error is KakaoClientException) {
      return '네트워크 상태를 확인한 뒤 다시 시도해주세요.';
    }
    return kDebugMode ? '카카오 로그인에 실패했어요.\n$text' : '카카오 로그인에 실패했어요.';
  }

  // ---------------------------------------------------------------- 구글

  Future<AppAuthProfile> signInWithGoogle() async {
    if (!_google.supportsAuthenticate()) {
      throw AuthException('이 기기에서는 구글 로그인을 지원하지 않아요.');
    }

    final account = await _obtainGoogleAccount();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw AuthException('구글 인증 정보를 가져오지 못했어요.');
    }

    final payload = await _sendTokenToBackend(provider: 'google', token: idToken);

    return AppAuthProfile(
      provider: 'google',
      providerId: account.id,
      email: account.email,
      nickname: account.displayName,
      photoUrl: account.photoUrl,
      isNewUser: _readIsNewUser(payload),
    );
  }

  Future<GoogleSignInAccount> _obtainGoogleAccount() async {
    final completer = Completer<GoogleSignInAccount?>();
    late final StreamSubscription<GoogleSignInAuthenticationEvent> sub;

    sub = _google.authenticationEvents.listen(
      (event) {
        final user = switch (event) {
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

    final account = await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => null,
    );
    if (account == null) throw AuthException('구글 로그인에 실패했어요.');
    return account;
  }

  // ---------------------------------------------------------------- 백엔드 연동

  Future<Map<String, dynamic>> _sendTokenToBackend({
    required String provider,
    required String token,
  }) async {
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$_apiBase/auth/social-login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'provider': provider, 'token': token}),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw AuthException('서버 응답이 없어요. 잠시 후 다시 시도해주세요.');
    } catch (e) {
      throw AuthException('서버와 통신하지 못했어요. 인터넷 연결을 확인해주세요.');
    }

    _log('social-login status=${response.statusCode}');

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw AuthException('온길 서버 연동에 실패했어요. (${response.statusCode})');
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw AuthException('서버 응답을 해석하지 못했어요.');
    }

    final accessToken = _readString(data, const ['access_token', 'accessToken']);
    final refreshToken = _readString(data, const ['refresh_token', 'refreshToken']);

    if (accessToken == null || accessToken.isEmpty) {
      throw AuthException('로그인 응답에서 토큰을 찾지 못했어요.');
    }

    await _storage.write(key: 'accessToken', value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: 'refreshToken', value: refreshToken);
    }
    return data;
  }

  /// 응답이 평면 구조든 `data`로 한 번 감싼 구조든 모두 읽는다.
  String? _readString(Map<String, dynamic> data, List<String> keys) {
    final nested = data['data'];
    for (final key in keys) {
      final value = data[key] ?? (nested is Map ? nested[key] : null);
      if (value is String) return value;
    }
    return null;
  }

  bool _readIsNewUser(Map<String, dynamic> data) {
    final nested = data['data'];
    for (final key in const ['is_new_user', 'isNewUser', 'isNew', 'newUser']) {
      final value = data[key] ?? (nested is Map ? nested[key] : null);
      if (value is bool) return value;
    }
    return true;
  }

  // ---------------------------------------------------------------- 세션

  Future<String?> getOnGilAccessToken() => _storage.read(key: 'accessToken');

  Future<bool> hasSession() async {
    final token = await getOnGilAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> saveUserProfile({String? nickname, String? photoUrl}) async {
    if (nickname != null) await _storage.write(key: 'nickname', value: nickname);
    if (photoUrl != null) await _storage.write(key: 'photoUrl', value: photoUrl);
  }

  Future<String?> getNickname() => _storage.read(key: 'nickname');

  Future<String?> getPhotoUrl() => _storage.read(key: 'photoUrl');

  Future<void> logout() async {
    try {
      await UserApi.instance.logout();
    } catch (e) {
      _log('카카오 로그아웃 무시 가능한 오류', e);
    }
    try {
      await _google.signOut();
    } catch (e) {
      _log('구글 로그아웃 무시 가능한 오류', e);
    }
    await _storage.deleteAll();
  }

  Future<void> deleteAccount() async {
    try {
      await UserApi.instance.unlink();
    } catch (e) {
      _log('카카오 연결 끊기 실패', e);
    }
    try {
      await _google.disconnect();
    } catch (e) {
      _log('구글 연결 끊기 실패', e);
    }
    await logout();
  }

  Future<void> forceLogout() async {
    await logout();
    rootNavigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  // ---------------------------------------------------------------- 인증 HTTP

  Future<Map<String, String>> _authHeaders() async {
    final token = await getOnGilAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _handleUnauthorized(http.Response response) async {
    if (response.statusCode == 401) await forceLogout();
  }

  Future<http.Response> authorizedGet(Uri url) async {
    final response = await http.get(url, headers: await _authHeaders());
    await _handleUnauthorized(response);
    return response;
  }

  Future<http.Response> authorizedPost(Uri url, {Object? body}) async {
    final response = await http.post(url, headers: await _authHeaders(), body: body);
    await _handleUnauthorized(response);
    return response;
  }

  Future<http.Response> authorizedDelete(Uri url) async {
    final response = await http.delete(url, headers: await _authHeaders());
    await _handleUnauthorized(response);
    return response;
  }

  void _log(String message, [Object? error, StackTrace? stack]) {
    if (!kDebugMode) return;
    debugPrint('[Auth] $message${error == null ? '' : ' :: $error'}');
    if (stack != null) debugPrintStack(stackTrace: stack);
  }
}
