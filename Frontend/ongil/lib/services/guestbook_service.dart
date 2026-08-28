import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/guestbook_entry.dart';
import 'auth_service.dart';

enum GuestbookReportReason {
  spam('SPAM', '스팸·광고'),
  harassment('HARASSMENT', '괴롭힘·모욕'),
  hateSpeech('HATE_SPEECH', '혐오 표현'),
  sexualContent('SEXUAL_CONTENT', '성적 콘텐츠'),
  violence('VIOLENCE', '폭력적 콘텐츠'),
  privacy('PRIVACY', '개인정보 노출'),
  illegal('ILLEGAL', '불법 콘텐츠'),
  other('OTHER', '기타');

  final String apiValue;
  final String label;
  const GuestbookReportReason(this.apiValue, this.label);
}

class GuestbookApiException implements Exception {
  final String message;
  const GuestbookApiException(this.message);

  @override
  String toString() => message;
}

abstract class GuestbookRepository {
  Future<int?> fetchCurrentUserId();
  Future<GuestbookFeed> fetchFeed({int limit = 50, int offset = 0});
  Future<void> reportGuestbook({
    required int guestbookId,
    required GuestbookReportReason reason,
    String? details,
  });
  Future<void> blockUser(int userId);
  Future<void> unblockUser(int userId);
}

class GuestbookService implements GuestbookRepository {
  GuestbookService._();
  static final GuestbookService instance = GuestbookService._();

  static const String _defaultHost = 'https://api.seankim428.site';

  static String get _baseUrl {
    var host = dotenv.env['BASE_URL'] ?? _defaultHost;
    if (host.isEmpty) host = _defaultHost;
    if (host.endsWith('/')) host = host.substring(0, host.length - 1);
    return host.endsWith('/api/v1') ? host : '$host/api/v1';
  }

  static String resolveMediaUrl(String path) {
    final parsed = Uri.tryParse(path);
    if (parsed != null && parsed.hasScheme) return path;
    final host = _baseUrl.replaceFirst(RegExp(r'/api/v1$'), '');
    return path.startsWith('/') ? '$host$path' : '$host/$path';
  }

  @override
  Future<int?> fetchCurrentUserId() {
    return AuthService.instance.getCurrentUserId();
  }

  @override
  Future<GuestbookFeed> fetchFeed({int limit = 50, int offset = 0}) async {
    final uri = Uri.parse('$_baseUrl/guestbooks/feed').replace(
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
    final response = await AuthService.instance.authorizedGet(uri);
    if (response.statusCode != 200) {
      throw GuestbookApiException(
        _errorMessage(response.bodyBytes, '방명록을 불러오지 못했어요.'),
      );
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw const GuestbookApiException('방명록 응답 형식이 올바르지 않아요.');
    }
    return GuestbookFeed.fromJson(data);
  }

  @override
  Future<void> reportGuestbook({
    required int guestbookId,
    required GuestbookReportReason reason,
    String? details,
  }) async {
    final response = await AuthService.instance.authorizedPost(
      Uri.parse('$_baseUrl/guestbooks/$guestbookId/reports'),
      body: jsonEncode({
        'reason': reason.apiValue,
        if (details != null && details.trim().isNotEmpty)
          'details': details.trim(),
      }),
    );
    if (response.statusCode != 201) {
      throw GuestbookApiException(
        _errorMessage(response.bodyBytes, '신고를 접수하지 못했어요.'),
      );
    }
  }

  @override
  Future<void> blockUser(int userId) async {
    final response = await AuthService.instance.authorizedPut(
      Uri.parse('$_baseUrl/user-blocks/$userId'),
    );
    if (response.statusCode != 200) {
      throw GuestbookApiException(
        _errorMessage(response.bodyBytes, '사용자를 차단하지 못했어요.'),
      );
    }
  }

  @override
  Future<void> unblockUser(int userId) async {
    final response = await AuthService.instance.authorizedDelete(
      Uri.parse('$_baseUrl/user-blocks/$userId'),
    );
    if (response.statusCode != 204) {
      throw GuestbookApiException(
        _errorMessage(response.bodyBytes, '차단을 해제하지 못했어요.'),
      );
    }
  }

  static String _errorMessage(List<int> bodyBytes, String fallback) {
    try {
      final data = jsonDecode(utf8.decode(bodyBytes));
      if (data is Map<String, dynamic> && data['detail'] is String) {
        return data['detail'] as String;
      }
    } catch (_) {
      // 서버가 JSON이 아닌 오류를 반환하면 사용자에게 안전한 기본 문구를 보여준다.
    }
    return fallback;
  }
}
