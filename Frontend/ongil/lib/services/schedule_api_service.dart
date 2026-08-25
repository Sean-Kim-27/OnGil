import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/schedule.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'place_service.dart';

/// 스케줄(여정) 관련 백엔드 연동 단일 진입점.

enum ScheduleApiErrorKind {
  /// 인터넷이 끊겼거나 서버에 닿지 못함
  network,

  /// 서버가 제한 시간 안에 응답하지 않음
  timeout,

  /// 토큰 만료·무효 (AuthService가 로그인 화면으로 보냄)
  unauthorized,

  /// 요청한 스케줄이 없음(삭제됐거나 남의 것)
  notFound,

  /// 요청 형식이 서버 명세와 안 맞음 (422 등)
  badRequest,

  /// 서버 내부 오류
  server,

  /// 200이지만 본문이 예상한 JSON 형태가 아님
  parse,
}

class ScheduleApiException implements Exception {
  final ScheduleApiErrorKind kind;
  final int? statusCode;

  /// 서버 원본 메시지. 화면에 띄우지 않고 로그용으로만 씀.
  final String? detail;

  const ScheduleApiException(this.kind, {this.statusCode, this.detail});

  /// 사용자에게 보여줄 문구.
  String get userMessage {
    switch (kind) {
      case ScheduleApiErrorKind.network:
        return '인터넷 연결을 확인해주세요.';
      case ScheduleApiErrorKind.timeout:
        return '서버 응답이 늦어지고 있어요. 잠시 후 다시 시도해주세요.';
      case ScheduleApiErrorKind.unauthorized:
        return '로그인이 만료됐어요. 다시 로그인해주세요.';
      case ScheduleApiErrorKind.notFound:
        return '이 여정을 찾을 수 없어요. 삭제됐을 수 있어요.';
      case ScheduleApiErrorKind.badRequest:
        return '요청 내용이 서버와 맞지 않아요.';
      case ScheduleApiErrorKind.server:
        return '서버에 문제가 생겼어요. 잠시 후 다시 시도해주세요.';
      case ScheduleApiErrorKind.parse:
        return '서버 응답을 이해하지 못했어요.';
    }
  }

  /// 재시도 버튼을 보여주기
  bool get isRetryable =>
      kind == ScheduleApiErrorKind.network ||
      kind == ScheduleApiErrorKind.timeout ||
      kind == ScheduleApiErrorKind.server;

  @override
  String toString() =>
      'ScheduleApiException($kind, status=$statusCode, detail=$detail)';
}

class ScheduleApiService {
  ScheduleApiService._();

  static const Duration _timeout = Duration(seconds: 15);

  static const _storage = FlutterSecureStorage();
  static const _lastScheduleIdKey = 'last_schedule_id';

  static String get _baseUrl => ApiConfig.baseUrl;

  // -------------------------------------------------------------------------
  // 공용 요청 처리
  // -------------------------------------------------------------------------

  /// 네트워크 예외와 상태 코드를 ScheduleApiException으로 정규화해서 돌려줌.
  static Future<T> _send<T>(
    String label,
    Future<http.Response> Function() request,
    T Function(http.Response response) onSuccess,
  ) async {
    http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      debugPrint('⏱️ [$label] 타임아웃 (${_timeout.inSeconds}s)');
      throw const ScheduleApiException(ScheduleApiErrorKind.timeout);
    } on SocketException catch (e) {
      debugPrint('📡 [$label] 네트워크 실패: $e');
      throw const ScheduleApiException(ScheduleApiErrorKind.network);
    } on http.ClientException catch (e) {
      debugPrint('📡 [$label] 네트워크 실패: $e');
      throw const ScheduleApiException(ScheduleApiErrorKind.network);
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return onSuccess(response);
    }

    final body = _safeBody(response);
    debugPrint('❌ [$label] HTTP $status: $body');

    final ScheduleApiErrorKind kind;
    if (status == 401 || status == 403) {
      kind = ScheduleApiErrorKind.unauthorized;
    } else if (status == 404) {
      kind = ScheduleApiErrorKind.notFound;
    } else if (status == 400 || status == 422) {
      kind = ScheduleApiErrorKind.badRequest;
    } else {
      kind = ScheduleApiErrorKind.server;
    }

    throw ScheduleApiException(kind, statusCode: status, detail: body);
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
      throw const ScheduleApiException(ScheduleApiErrorKind.parse);
    }
  }

  // -------------------------------------------------------------------------
  // 조회
  // -------------------------------------------------------------------------

  /// GET /api/v1/schedulers — 내 여정 목록
  static Future<List<ScheduleSummary>> fetchSchedules() {
    final url = Uri.parse('$_baseUrl/schedulers');
    return _send('fetchSchedules', () => AuthService.instance.authorizedGet(url), (res) {
      final data = _decode('fetchSchedules', res);

      final List list;
      if (data is List) {
        list = data;
      } else if (data is Map && data['items'] is List) {
        list = data['items'] as List;
      } else if (data is Map && data['results'] is List) {
        list = data['results'] as List;
      } else {
        debugPrint('🧩 [fetchSchedules] 배열이 아닌 응답: $data');
        throw const ScheduleApiException(ScheduleApiErrorKind.parse);
      }

      return list
          .whereType<Map<String, dynamic>>()
          .map(ScheduleSummary.fromJson)
          .toList();
    });
  }

  /// GET /api/v1/schedulers/{id} — 여정 상세
  static Future<ScheduleDetail> fetchScheduleDetail(int scheduleId) {
    final url = Uri.parse('$_baseUrl/schedulers/$scheduleId');
    return _send('fetchScheduleDetail', () => AuthService.instance.authorizedGet(url), (res) {
      final data = _decode('fetchScheduleDetail', res);
      if (data is! Map<String, dynamic>) {
        debugPrint('🧩 [fetchScheduleDetail] 객체가 아닌 응답: $data');
        throw const ScheduleApiException(ScheduleApiErrorKind.parse);
      }
      return ScheduleDetail.fromJson(data);
    });
  }

  // -------------------------------------------------------------------------
  // 생성 / 삭제
  // -------------------------------------------------------------------------

  /// POST /api/v1/schedulers
  ///
  /// 스펙상 places[]의 각 항목은 SchedulerPlaceCreateRequest 이고
  /// `required: ["place", "visit_order"]` 다. 즉 장소 값은 `place` 안에 넣어야 하고
  /// 방문 순서는 **프론트가 정해서** 보내야 한다. 서버가 자동 배정해주지 않는다.
  static Future<ScheduleDetail> createSchedule({
    required List<RecommendedPlace> places,
    required PlaceAnchor anchor,
    required String title,
    required String mobilityMode,
    required int searchRadius,
    required String tripType,
    required String companionType,
    required int companionCount,
    required DateTime startDateTime,
    required DateTime endDateTime,
  }) {
    // 422를 받고 역추적하지 않도록 필수값을 여기서 먼저 막음.
    for (final p in places) {
      if (p.contentId == null || p.contentId!.isEmpty) {
        throw ScheduleApiException(
          ScheduleApiErrorKind.badRequest,
          detail: '"${p.title}"에 content_id가 없음 (GET /places/nearby 응답 확인 필요)',
        );
      }
      if (!p.hasCoordinates) {
        throw ScheduleApiException(
          ScheduleApiErrorKind.badRequest,
          detail: '"${p.title}"에 좌표가 없음',
        );
      }
    }
    if (anchor.latitude == null || anchor.longitude == null) {
      throw const ScheduleApiException(
        ScheduleApiErrorKind.badRequest,
        detail: '기준 장소(anchor)에 좌표가 없음',
      );
    }
    if (places.isEmpty) {
      throw const ScheduleApiException(
        ScheduleApiErrorKind.badRequest,
        detail: 'places가 비어 있음 (서버 minItems: 1)',
      );
    }

    final url = Uri.parse('$_baseUrl/schedulers');
    final requestBody = {
      'title': title,
      'mobility_mode': mobilityMode,
      'search_radius': searchRadius, // SearchRadiusKm: 3 또는 5만 허용
      'trip_type': tripType,
      'memory_place': {
        'name': anchor.title,
        'address': anchor.address,
        'latitude': anchor.latitude,
        'longitude': anchor.longitude,
      },
      'places': buildPlacesPayload(
        places,
        dayCount: dayCountOf(startDateTime, endDateTime),
      ),
      'companion_type': companionType,
      'companion_count': companionCount,
      'start_datetime': startDateTime.toUtc().toIso8601String(),
      'end_datetime': endDateTime.toUtc().toIso8601String(),
    };

    debugPrint('📤 [createSchedule] POST $url');
    return _send(
      'createSchedule',
      () => AuthService.instance.authorizedPost(url, body: jsonEncode(requestBody)),
      (res) {
        final data = _decode('createSchedule', res);
        if (data is! Map<String, dynamic>) {
          throw const ScheduleApiException(ScheduleApiErrorKind.parse);
        }
        return ScheduleDetail.fromJson(data);
      },
    );
  }

  /// 시작·종료 날짜로 며칠짜리 여정인지 계산. 최소 1일.
  static int dayCountOf(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final nights = e.difference(s).inDays;
    return nights > 0 ? nights + 1 : 1;
  }

  /// 사용자가 고른 순서를 그대로 방문 순서로 쓰고, 일수에 맞춰 날짜별로 나눈다.
  ///
  /// - `visit_order`는 **일차별로 1부터** 다시 시작한다 (스펙: "해당 일차의 방문 순서").
  /// - 숙소는 그날의 마지막 순서로 밀어둔다. 자고 나서 다음 일정이 오는 게 자연스러움.
  /// - 좌표 기반 최단경로 재정렬은 아직 안 함. 필요하면 여기만 바꾸면 된다.
  static List<Map<String, dynamic>> buildPlacesPayload(
    List<RecommendedPlace> places, {
    int dayCount = 1,
  }) {
    final days = dayCount < 1 ? 1 : dayCount;

    // 일차별로 고르게 나눔. 앞쪽 날에 한 곳씩 더 배치.
    final perDay = <List<RecommendedPlace>>[for (var i = 0; i < days; i++) []];
    final base = places.length ~/ days;
    final remainder = places.length % days;

    var cursor = 0;
    for (var d = 0; d < days; d++) {
      final take = base + (d < remainder ? 1 : 0);
      perDay[d] = places.sublist(cursor, cursor + take);
      cursor += take;
    }

    final payload = <Map<String, dynamic>>[];
    for (var d = 0; d < days; d++) {
      final dayPlaces = [...perDay[d]];
      // 숙소를 그날 맨 뒤로.
      dayPlaces.sort((a, b) {
        final aStay = a.rawCategory == 'accommodation' ? 1 : 0;
        final bStay = b.rawCategory == 'accommodation' ? 1 : 0;
        return aStay.compareTo(bStay);
      });

      for (var i = 0; i < dayPlaces.length; i++) {
        final p = dayPlaces[i];
        payload.add({
          'place': {
            'content_id': p.contentId,
            'title': p.title,
            // 한글 category는 되돌릴 수 없어 원본 영문값을 그대로 보냄.
            'category': p.rawCategory,
            'latitude': p.latitude,
            'longitude': p.longitude,
            if (p.imageUrl != null) 'image_url': p.imageUrl,
            if (p.kakaoPlaceId != null) 'kakao_place_id': p.kakaoPlaceId,
            if (p.placeUrl != null) 'place_url': p.placeUrl,
          },
          'day_no': d + 1,
          'visit_order': i + 1,
          // time_slot은 보내지 않는다(nullable). 서버가 채워주는지 확인 필요.
        });
      }
    }
    return payload;
  }

  /// DELETE /api/v1/schedulers/{id} → 204 No Content
  static Future<void> deleteSchedule(int scheduleId) {
    final url = Uri.parse('$_baseUrl/schedulers/$scheduleId');
    return _send<void>(
      'deleteSchedule',
      () => AuthService.instance.authorizedDelete(url),
      (_) {},
    );
  }

  // -------------------------------------------------------------------------
  // 마지막으로 만든 스케줄 (지도 탭이 자동으로 그려줄 대상)
  // -------------------------------------------------------------------------

  static Future<void> saveLastScheduleId(int scheduleId) =>
      _storage.write(key: _lastScheduleIdKey, value: '$scheduleId');

  static Future<int?> getLastScheduleId() async {
    final raw = await _storage.read(key: _lastScheduleIdKey);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  /// 삭제한 게 마지막 스케줄이었다면 저장해둔 id도 같이 지움.
  static Future<void> clearLastScheduleIdIf(int scheduleId) async {
    if (await getLastScheduleId() == scheduleId) {
      await _storage.delete(key: _lastScheduleIdKey);
    }
  }
}
