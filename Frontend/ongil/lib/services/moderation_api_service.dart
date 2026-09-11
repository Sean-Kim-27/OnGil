import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/moderation.dart';
import 'api_config.dart';
import 'auth_service.dart';

/// 신고·차단 백엔드 연동.
///
/// Google Play는 공개되는 사용자 생성 콘텐츠가 있는 앱에 신고·차단 기능을
/// 요구한다. 이 서비스가 그 두 가지를 담당한다.
///
/// 에러 처리 모양은 `GuestbookApiService`와 맞춰둠.

enum ModerationErrorKind {
  network,
  timeout,
  unauthorized,
  notFound,
  badRequest,

  /// 이미 신고했거나 이미 차단한 경우.
  conflict,
  server,
  parse,
}

class ModerationApiException implements Exception {
  final ModerationErrorKind kind;
  final int? statusCode;
  final String? detail;

  const ModerationApiException(this.kind, {this.statusCode, this.detail});

  String get userMessage {
    switch (kind) {
      case ModerationErrorKind.network:
        return '인터넷 연결을 확인해주세요.';
      case ModerationErrorKind.timeout:
        return '서버 응답이 늦어지고 있어요. 잠시 후 다시 시도해주세요.';
      case ModerationErrorKind.unauthorized:
        return '로그인이 만료됐어요. 다시 로그인해주세요.';
      case ModerationErrorKind.notFound:
        return '대상을 찾을 수 없어요. 이미 삭제됐을 수 있어요.';
      case ModerationErrorKind.badRequest:
        return '요청 형식이 올바르지 않아요.';
      case ModerationErrorKind.conflict:
        return '이미 처리된 요청이에요.';
      case ModerationErrorKind.server:
        return '서버에 문제가 생겼어요. 잠시 후 다시 시도해주세요.';
      case ModerationErrorKind.parse:
        return '서버 응답을 이해하지 못했어요.';
    }
  }

  bool get isRetryable =>
      kind == ModerationErrorKind.network ||
      kind == ModerationErrorKind.timeout ||
      kind == ModerationErrorKind.server;

  @override
  String toString() =>
      'ModerationApiException($kind, status=$statusCode, detail=$detail)';
}

class ModerationApiService {
  ModerationApiService._();

  static const Duration _timeout = Duration(seconds: 15);

  /// 서버 스키마상 신고 상세 설명 최대 길이.
  static const int maxDetailLength = 500;

  // -------------------------------------------------------------------------
  // 공용 요청 처리
  // -------------------------------------------------------------------------

  static Future<T> _send<T>(
    String label,
    Future<http.Response> Function() request,
    T Function(http.Response response) onSuccess,
  ) async {
    http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      debugPrint('⏱️ [$label] 타임아웃');
      throw const ModerationApiException(ModerationErrorKind.timeout);
    } on SocketException catch (e) {
      debugPrint('📡 [$label] 네트워크 실패: $e');
      throw const ModerationApiException(ModerationErrorKind.network);
    } on http.ClientException catch (e) {
      debugPrint('📡 [$label] 네트워크 실패: $e');
      throw const ModerationApiException(ModerationErrorKind.network);
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return onSuccess(response);
    }

    final body = _safeBody(response);
    debugPrint('❌ [$label] HTTP $status: $body');

    final ModerationErrorKind kind;
    if (status == 401 || status == 403) {
      kind = ModerationErrorKind.unauthorized;
    } else if (status == 404) {
      kind = ModerationErrorKind.notFound;
    } else if (status == 409) {
      kind = ModerationErrorKind.conflict;
    } else if (status == 400 || status == 422) {
      kind = ModerationErrorKind.badRequest;
    } else {
      kind = ModerationErrorKind.server;
    }

    throw ModerationApiException(kind, statusCode: status, detail: body);
  }

  static String _safeBody(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      return response.body;
    }
  }

  static Map<String, dynamic> _asObject(String label, http.Response response) {
    try {
      final data = jsonDecode(_safeBody(response));
      if (data is Map<String, dynamic>) return data;
      debugPrint('🧩 [$label] 객체가 아닌 응답: $data');
    } catch (e) {
      debugPrint('🧩 [$label] JSON 파싱 실패: $e');
    }
    throw const ModerationApiException(ModerationErrorKind.parse);
  }

  // -------------------------------------------------------------------------
  // 신고
  // -------------------------------------------------------------------------

  /// POST /api/v1/guestbooks/{guestbook_id}/reports
  ///
  /// [details]는 선택이고 500자를 넘으면 잘라서 보낸다.
  static Future<GuestbookReport> reportGuestbook({
    required int guestbookId,
    required ReportReason reason,
    String? details,
  }) {
    final url = ApiConfig.uri('/guestbooks/$guestbookId/reports');

    String? trimmed = details?.trim();
    if (trimmed != null && trimmed.isEmpty) trimmed = null;
    if (trimmed != null && trimmed.length > maxDetailLength) {
      debugPrint('✂️ [reportGuestbook] 500자 초과라 잘라서 보냄');
      trimmed = trimmed.substring(0, maxDetailLength);
    }

    debugPrint('📤 [reportGuestbook] POST $url (${reason.wire})');

    return _send(
      'reportGuestbook',
      () => AuthService.instance.authorizedPost(
        url,
        body: jsonEncode({
          'reason': reason.wire,
          if (trimmed != null) 'details': trimmed,
        }),
      ),
      (res) => GuestbookReport.fromJson(_asObject('reportGuestbook', res)),
    );
  }

  // -------------------------------------------------------------------------
  // 차단
  // -------------------------------------------------------------------------

  /// PUT /api/v1/user-blocks/{blocked_user_id} — 서버가 중복 요청을 안전 처리함.
  static Future<UserBlock> blockUser(int userId) {
    final url = ApiConfig.uri('/user-blocks/$userId');
    debugPrint('📤 [blockUser] PUT $url');
    return _send(
      'blockUser',
      () => AuthService.instance.authorizedPut(url),
      (res) => UserBlock.fromJson(_asObject('blockUser', res)),
    );
  }

  /// DELETE /api/v1/user-blocks/{blocked_user_id} — 204. 중복 요청 안전.
  static Future<void> unblockUser(int userId) {
    final url = ApiConfig.uri('/user-blocks/$userId');
    debugPrint('📤 [unblockUser] DELETE $url');
    return _send(
      'unblockUser',
      () => AuthService.instance.authorizedDelete(url),
      (_) {},
    );
  }

  /// GET /api/v1/user-blocks — 내가 차단한 사용자 목록.
  static Future<List<UserBlock>> fetchBlockedUsers() {
    final url = ApiConfig.uri('/user-blocks');
    return _send(
      'fetchBlockedUsers',
      () => AuthService.instance.authorizedGet(url),
      (res) {
        final data = jsonDecode(_safeBody(res));

        final List list;
        if (data is List) {
          list = data;
        } else if (data is Map && data['items'] is List) {
          list = data['items'] as List;
        } else {
          debugPrint('🧩 [fetchBlockedUsers] 배열이 아닌 응답: $data');
          throw const ModerationApiException(ModerationErrorKind.parse);
        }

        return list
            .whereType<Map<String, dynamic>>()
            .map(UserBlock.fromJson)
            .toList();
      },
    );
  }
}
