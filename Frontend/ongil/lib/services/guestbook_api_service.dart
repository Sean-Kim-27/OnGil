import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/guestbook.dart';
import 'api_config.dart';
import 'auth_service.dart';

/// 방명록/아카이브 백엔드 연동 단일 진입점.
///
/// 기존 `GuestbookService`(기기 로컬 저장)를 대체함.
/// 에러 처리 모양은 `ScheduleApiService`와 맞춰둠.

enum GuestbookApiErrorKind {
  network,
  timeout,
  unauthorized,

  /// 방명록이나 장소가 없음. 조회에서는 '아직 안 씀'으로 취급.
  notFound,

  /// 422 등 요청 형식 불일치. 100자 초과, 잘못된 연도 등도 여기로 옴.
  badRequest,

  /// 이미 올린 사진을 또 올렸거나, 지금 사진 없이 그때 사진을 올린 경우.
  conflict,

  server,
  parse,
}

class GuestbookApiException implements Exception {
  final GuestbookApiErrorKind kind;
  final int? statusCode;

  /// 서버 원본 메시지. 로그용.
  final String? detail;

  const GuestbookApiException(this.kind, {this.statusCode, this.detail});

  String get userMessage {
    switch (kind) {
      case GuestbookApiErrorKind.network:
        return '인터넷 연결을 확인해주세요.';
      case GuestbookApiErrorKind.timeout:
        return '서버 응답이 늦어지고 있어요. 잠시 후 다시 시도해주세요.';
      case GuestbookApiErrorKind.unauthorized:
        return '로그인이 만료됐어요. 다시 로그인해주세요.';
      case GuestbookApiErrorKind.notFound:
        return '방명록을 찾을 수 없어요.';
      case GuestbookApiErrorKind.badRequest:
        return '입력한 내용이 서버와 맞지 않아요. 글자 수와 연도를 확인해주세요.';
      case GuestbookApiErrorKind.conflict:
        return '이미 올린 사진이에요. 사진 교체는 아직 지원되지 않아요.';
      case GuestbookApiErrorKind.server:
        return '서버에 문제가 생겼어요. 잠시 후 다시 시도해주세요.';
      case GuestbookApiErrorKind.parse:
        return '서버 응답을 이해하지 못했어요.';
    }
  }

  bool get isRetryable =>
      kind == GuestbookApiErrorKind.network ||
      kind == GuestbookApiErrorKind.timeout ||
      kind == GuestbookApiErrorKind.server;

  @override
  String toString() =>
      'GuestbookApiException($kind, status=$statusCode, detail=$detail)';
}

class GuestbookApiService {
  GuestbookApiService._();

  static const Duration _timeout = Duration(seconds: 15);

  /// 사진은 용량이 커서 넉넉히 잡음.
  static const Duration _uploadTimeout = Duration(seconds: 60);

  static String get _baseUrl => ApiConfig.baseUrl;

  // -------------------------------------------------------------------------
  // 공용 요청 처리
  // -------------------------------------------------------------------------

  static Future<T> _send<T>(
    String label,
    Future<http.Response> Function() request,
    T Function(http.Response response) onSuccess, {
    Duration timeout = _timeout,
  }) async {
    http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      debugPrint('⏱️ [$label] 타임아웃 (${timeout.inSeconds}s)');
      throw const GuestbookApiException(GuestbookApiErrorKind.timeout);
    } on SocketException catch (e) {
      debugPrint('📡 [$label] 네트워크 실패: $e');
      throw const GuestbookApiException(GuestbookApiErrorKind.network);
    } on http.ClientException catch (e) {
      debugPrint('📡 [$label] 네트워크 실패: $e');
      throw const GuestbookApiException(GuestbookApiErrorKind.network);
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return onSuccess(response);
    }

    final body = _safeBody(response);
    debugPrint('❌ [$label] HTTP $status: $body');

    final GuestbookApiErrorKind kind;
    if (status == 401 || status == 403) {
      kind = GuestbookApiErrorKind.unauthorized;
    } else if (status == 404) {
      kind = GuestbookApiErrorKind.notFound;
    } else if (status == 409) {
      kind = GuestbookApiErrorKind.conflict;
    } else if (status == 400 || status == 422) {
      // 사진 순서/중복 제약도 400으로 올 수 있어 본문으로 한 번 더 갈라봄.
      kind = _looksLikePhotoConflict(body)
          ? GuestbookApiErrorKind.conflict
          : GuestbookApiErrorKind.badRequest;
    } else {
      kind = GuestbookApiErrorKind.server;
    }

    throw GuestbookApiException(kind, statusCode: status, detail: body);
  }

  /// 사진 제약(중복 업로드 / 현재 사진 선행 조건) 위반으로 보이는 본문인지.
  static bool _looksLikePhotoConflict(String body) {
    final text = body.toLowerCase();
    return text.contains('already') ||
        text.contains('exists') ||
        text.contains('duplicate') ||
        text.contains('current photo') ||
        body.contains('이미') ||
        body.contains('먼저');
  }

  static String _safeBody(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      return response.body;
    }
  }

  static dynamic _decode(String label, http.Response response) {
    try {
      return jsonDecode(_safeBody(response));
    } catch (e) {
      debugPrint('🧩 [$label] JSON 파싱 실패: $e');
      throw const GuestbookApiException(GuestbookApiErrorKind.parse);
    }
  }

  static Map<String, dynamic> _asObject(String label, http.Response response) {
    final data = _decode(label, response);
    if (data is! Map<String, dynamic>) {
      debugPrint('🧩 [$label] 객체가 아닌 응답: $data');
      throw const GuestbookApiException(GuestbookApiErrorKind.parse);
    }
    return data;
  }

  // -------------------------------------------------------------------------
  // 조회
  // -------------------------------------------------------------------------

  /// GET /api/v1/guestbooks — 내 방명록 전체 목록
  static Future<List<Guestbook>> fetchMyGuestbooks() {
    final url = Uri.parse('$_baseUrl/guestbooks');
    return _send('fetchMyGuestbooks', () => AuthService.instance.authorizedGet(url),
        (res) {
      final data = _decode('fetchMyGuestbooks', res);

      final List list;
      if (data is List) {
        list = data;
      } else if (data is Map && data['items'] is List) {
        list = data['items'] as List;
      } else {
        debugPrint('🧩 [fetchMyGuestbooks] 배열이 아닌 응답: $data');
        throw const GuestbookApiException(GuestbookApiErrorKind.parse);
      }

      return list
          .whereType<Map<String, dynamic>>()
          .map(Guestbook.fromJson)
          .toList();
    });
  }

  /// GET /api/v1/guestbooks/places/{place_id} — 특정 장소 방명록
  ///
  /// 아직 아무것도 안 남긴 장소면 404가 오므로 null로 돌려줌.
  static Future<Guestbook?> fetchGuestbook(int placeId) async {
    final url = Uri.parse('$_baseUrl/guestbooks/places/$placeId');
    try {
      return await _send(
        'fetchGuestbook',
        () => AuthService.instance.authorizedGet(url),
        (res) => Guestbook.fromJson(_asObject('fetchGuestbook', res)),
      );
    } on GuestbookApiException catch (e) {
      if (e.kind == GuestbookApiErrorKind.notFound) return null;
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // 작성 / 수정
  // -------------------------------------------------------------------------

  /// PUT /api/v1/guestbooks/places/{place_id} — 텍스트 작성·수정
  ///
  /// [content]가 null이면 글만 지운다(사진은 서버에 그대로 남음).
  /// 서버 제약이 100자라 넘치면 요청 전에 잘라 보냄.
  static Future<Guestbook> saveContent(int placeId, String? content) {
    final url = Uri.parse('$_baseUrl/guestbooks/places/$placeId');

    String? trimmed = content?.trim();
    if (trimmed != null && trimmed.isEmpty) trimmed = null;
    if (trimmed != null && trimmed.length > maxContentLength) {
      debugPrint('✂️ [saveContent] 100자 초과라 잘라서 보냄 (${trimmed.length}자)');
      trimmed = trimmed.substring(0, maxContentLength);
    }

    debugPrint('📤 [saveContent] PUT $url');
    return _send(
      'saveContent',
      () => AuthService.instance
          .authorizedPut(url, body: jsonEncode({'content': trimmed})),
      (res) => Guestbook.fromJson(_asObject('saveContent', res)),
    );
  }

  /// POST /api/v1/guestbooks/places/{place_id}/photos — 사진 업로드(멀티파트)
  ///
  /// 서버 제약 두 가지를 그대로 따름.
  /// - 스팟당 CURRENT 1장, PAST 1장 (교체·삭제 엔드포인트 없음)
  /// - PAST는 CURRENT가 먼저 올라가 있어야 함
  static Future<ArchivePhoto> uploadPhoto({
    required int placeId,
    required ArchivePhotoType type,
    required String filePath,
    int? takenYear,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw GuestbookApiException(
        GuestbookApiErrorKind.badRequest,
        detail: '업로드할 파일이 없음: $filePath',
      );
    }

    // taken_year는 PAST에만 의미가 있고 서버 최소값이 1900.
    int? year;
    if (type == ArchivePhotoType.past && takenYear != null) {
      if (takenYear >= 1900 && takenYear <= DateTime.now().year) {
        year = takenYear;
      } else {
        debugPrint('⚠️ [uploadPhoto] 범위를 벗어난 taken_year($takenYear)라 빼고 보냄');
      }
    }

    final url = Uri.parse('$_baseUrl/guestbooks/places/$placeId/photos');
    final filename =
        '${type.wire.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    debugPrint('📤 [uploadPhoto] POST $url (${type.wire}, year=$year)');

    return _send(
      'uploadPhoto',
      () => AuthService.instance.authorizedMultipartPost(
        url,
        fields: {
          'photo_type': type.wire,
          if (year != null) 'taken_year': '$year',
        },
        // 401 후 재시도할 때 요청을 다시 만들어야 해서 파일도 매번 새로 연다.
        // MultipartFile은 스트림이라 한 번 보내면 재사용할 수 없음.
        buildFiles: () async => [
          await http.MultipartFile.fromPath('image', filePath, filename: filename),
        ],
      ),
      (res) => ArchivePhoto.fromJson(_asObject('uploadPhoto', res)),
      timeout: _uploadTimeout,
    );
  }

  /// 서버 스키마상 방명록 텍스트 최대 길이.
  static const int maxContentLength = 100;
}
