import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_config.dart';
import 'auth_service.dart';

/// `GET /api/v1/auth/me` — 서버 기준 내 계정 정보.
///
/// 지금까지 앱은 닉네임·프로필을 소셜 제공자에서 받아 로컬에만 저장했다.
/// 신고·차단에는 **서버가 아는 내 user id**가 필요해서(내 글에는 신고 버튼을
/// 띄우지 않으려고) 이 엔드포인트를 처음으로 쓴다.
class AppUser {
  final int id;
  final String provider;
  final String? email;
  final String? nickname;
  final String? profileImageUrl;
  final String status;
  final bool isAdmin;

  const AppUser({
    required this.id,
    required this.provider,
    this.email,
    this.nickname,
    this.profileImageUrl,
    this.status = '',
    this.isAdmin = false,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    String? str(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return AppUser(
      id: (json['id'] is num)
          ? (json['id'] as num).toInt()
          : int.tryParse('${json['id']}') ?? 0,
      provider: str(json['social_provider']) ?? '',
      email: str(json['email']),
      nickname: str(json['nickname']),
      profileImageUrl: str(json['profile_image_url']),
      status: str(json['status']) ?? '',
      isAdmin: json['is_admin'] == true,
    );
  }
}

class UserApiService {
  UserApiService._();

  /// 앱이 살아 있는 동안만 유지하는 캐시. 화면마다 다시 부르지 않으려고 둠.
  static AppUser? _cached;

  static AppUser? get cached => _cached;

  /// 캐시된 내 user id. 아직 안 불러왔으면 null.
  static int? get currentUserId => _cached?.id;

  /// 실패해도 화면이 멈추지 않도록 null을 돌려준다.
  /// (내 id를 모르면 신고 버튼을 조금 더 보여줄 뿐, 기능은 그대로 동작)
  static Future<AppUser?> fetchMe({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) return _cached;

    try {
      final url = ApiConfig.uri('/auth/me');
      final res = await AuthService.instance.authorizedGet(url);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('⚠️ [UserApiService] /auth/me HTTP ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map<String, dynamic>) return null;

      final user = AppUser.fromJson(data);
      _cached = user;

      // 서버에서 프로필을 바꿨을 때 앱에 반영되도록 로컬 값도 맞춰둔다.
      await AuthService.instance.saveUserProfile(
        nickname: user.nickname,
        photoUrl: user.profileImageUrl,
      );
      return user;
    } catch (e) {
      debugPrint('⚠️ [UserApiService] /auth/me 실패: $e');
      return null;
    }
  }

  /// 로그아웃·탈퇴 시 호출.
  static void clearCache() => _cached = null;
}
