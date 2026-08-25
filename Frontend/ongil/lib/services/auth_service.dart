import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'api_config.dart';

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

  /// 진행 중인 토큰 갱신. 여러 요청이 동시에 401을 받아도 갱신은 한 번만 돈다.
  Future<bool>? _refreshInFlight;

  String get _apiBase => ApiConfig.baseUrl;

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

    final saved = await _saveTokens(data);
    if (!saved) {
      throw AuthException('로그인 응답에서 토큰을 찾지 못했어요.');
    }
    return data;
  }

  /// social-login / refresh 응답에서 토큰 3종(access, refresh, 만료시각)을 저장.
  Future<bool> _saveTokens(Map<String, dynamic> data) async {
    final accessToken = _readString(data, const ['access_token', 'accessToken']);
    final refreshToken = _readString(data, const ['refresh_token', 'refreshToken']);
    if (accessToken == null || accessToken.isEmpty) return false;

    await _storage.write(key: 'accessToken', value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: 'refreshToken', value: refreshToken);
    }

    // expires_in(초)을 만료 시각으로 바꿔 둔다. 만료 직전에 미리 갱신하려고 60초 뺌.
    final nested = data['data'];
    final rawExpires = data['expires_in'] ?? (nested is Map ? nested['expires_in'] : null);
    final expiresIn = rawExpires is num ? rawExpires.toInt() : int.tryParse('$rawExpires');
    if (expiresIn != null && expiresIn > 0) {
      final expiresAt = DateTime.now().add(Duration(seconds: expiresIn - 60));
      await _storage.write(
        key: 'accessTokenExpiresAt',
        value: expiresAt.toIso8601String(),
      );
    }
    return true;
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

  Future<String?> getRefreshToken() => _storage.read(key: 'refreshToken');

  Future<bool> hasSession() async {
    final token = await getOnGilAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// 저장해둔 만료 시각이 지났는지. 시각을 모르면 false(=요청 보내보고 401로 판단).
  Future<bool> _isAccessTokenExpired() async {
    final raw = await _storage.read(key: 'accessTokenExpiresAt');
    final expiresAt = DateTime.tryParse(raw ?? '');
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt);
  }

  /// POST /api/v1/auth/refresh 로 액세스 토큰을 새로 받는다.
  ///
  /// 여러 요청이 동시에 401을 받아도 갱신은 한 번만 돌게 in-flight를 공유한다.
  Future<bool> _refreshSession() {
    final running = _refreshInFlight;
    if (running != null) return running;

    final future = _doRefresh();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      _log('refresh 토큰이 없어 갱신 불가');
      return false;
    }

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$_apiBase/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': refreshToken}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      // 네트워크 문제로 실패한 거면 로그아웃시키지 않는 게 맞다.
      _log('refresh 요청 실패(네트워크)', e);
      return false;
    }

    if (response.statusCode != 200) {
      _log('refresh 실패 status=${response.statusCode}');
      return false;
    }

    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return await _saveTokens(data);
    } catch (e) {
      _log('refresh 응답 해석 실패', e);
      return false;
    }
  }

  Future<void> saveUserProfile({String? nickname, String? photoUrl}) async {
    if (nickname != null) await _storage.write(key: 'nickname', value: nickname);
    if (photoUrl != null) await _storage.write(key: 'photoUrl', value: photoUrl);
  }

  Future<String?> getNickname() => _storage.read(key: 'nickname');

  Future<String?> getPhotoUrl() => _storage.read(key: 'photoUrl');

  Future<void> logout() async {
    // 서버에 리프레시 토큰을 무효화해달라고 먼저 알린다.
    // (예전엔 이 호출이 아예 없어서 로그아웃해도 서버 세션이 살아 있었다.)
    await _revokeSessionOnServer();

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

  /// POST /api/v1/auth/logout → 204. 실패해도 로컬 로그아웃은 그대로 진행한다.
  Future<void> _revokeSessionOnServer() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse('$_apiBase/auth/logout'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': refreshToken}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      _log('서버 로그아웃 실패(로컬 로그아웃은 계속 진행)', e);
    }
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

  bool _forceLogoutRunning = false;

  /// 토큰이 완전히 죽었을 때만 호출. 동시에 여러 요청이 실패해도 한 번만 돈다.
  Future<void> forceLogout() async {
    if (_forceLogoutRunning) return;
    _forceLogoutRunning = true;
    try {
      await logout();
      rootNavigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/login', (route) => false);
    } finally {
      _forceLogoutRunning = false;
    }
  }

  // ---------------------------------------------------------------- 인증 HTTP

  Future<Map<String, String>> _authHeaders() async {
    final token = await getOnGilAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// 인증이 필요한 요청의 공통 경로.
  ///
  /// 예전에는 401을 받으면 곧바로 로그인 화면으로 튕겼다. 서버가 access token에
  /// 만료(expires_in)를 주고 /auth/refresh 도 있는데 앱이 안 쓰고 있어서,
  /// 토큰 수명이 지나는 순간 사용자가 아무것도 못 하고 로그아웃됐다.
  /// 이제는 만료가 예상되면 먼저 갱신하고, 그래도 401이면 한 번 갱신 후 재시도한다.
  Future<http.Response> _authorized(
    Future<http.Response> Function() send,
  ) async {
    if (await _isAccessTokenExpired()) {
      await _refreshSession();
    }

    var response = await send();
    if (response.statusCode != 401) return response;

    final refreshed = await _refreshSession();
    if (!refreshed) {
      // 갱신 자체가 안 되는 상황(리프레시 만료/무효)이면 세션을 정리한다.
      await forceLogout();
      return response;
    }

    response = await send();
    if (response.statusCode == 401) await forceLogout();
    return response;
  }

  Future<http.Response> authorizedGet(Uri url) =>
      _authorized(() async => http.get(url, headers: await _authHeaders()));

  Future<http.Response> authorizedPost(Uri url, {Object? body}) =>
      _authorized(() async => http.post(url, headers: await _authHeaders(), body: body));

  Future<http.Response> authorizedPut(Uri url, {Object? body}) =>
      _authorized(() async => http.put(url, headers: await _authHeaders(), body: body));

  Future<http.Response> authorizedDelete(Uri url) =>
      _authorized(() async => http.delete(url, headers: await _authHeaders()));

  /// 파일 업로드용. Content-Type은 http 패키지가 boundary와 함께 직접 채우므로
  /// _authHeaders()를 쓰지 않고 Authorization만 얹는다.
  ///
  /// MultipartFile은 스트림이라 한 번 보내면 재사용할 수 없다. 그래서 요청 객체를
  /// 매번 새로 만들 수 있도록 파일 목록이 아니라 '파일을 만드는 함수'를 받는다.
  Future<http.Response> authorizedMultipartPost(
    Uri url, {
    Map<String, String> fields = const {},
    required Future<List<http.MultipartFile>> Function() buildFiles,
  }) {
    return _authorized(() async {
      final token = await getOnGilAccessToken();
      final request = http.MultipartRequest('POST', url);
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.fields.addAll(fields);
      request.files.addAll(await buildFiles());
      return http.Response.fromStream(await request.send());
    });
  }

  void _log(String message, [Object? error, StackTrace? stack]) {
    if (!kDebugMode) return;
    debugPrint('[Auth] $message${error == null ? '' : ' :: $error'}');
    if (stack != null) debugPrintStack(stackTrace: stack);
  }
}
