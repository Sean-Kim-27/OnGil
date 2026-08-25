import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 서버 주소를 한 곳에서만 만든다.
///
/// 예전에는 서비스마다 BASE_URL을 따로 손질했는데, PlaceService만 `/api/v1`이
/// 이미 붙어 있는 경우를 처리하지 않아서 `.env`를 어떻게 적느냐에 따라
/// `/api/v1/api/v1/places/nearby` 같은 주소가 만들어졌다.
class ApiConfig {
  ApiConfig._();

  /// `https://host` 든 `https://host/api/v1/` 든 같은 결과가 나온다.
  static String get baseUrl {
    var host = (dotenv.env['BASE_URL'] ?? '').trim();
    while (host.endsWith('/')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.isEmpty) return '';
    return host.endsWith('/api/v1') ? host : '$host/api/v1';
  }

  /// `path`는 슬래시로 시작하든 안 하든 됨. 예: `uri('/schedulers')`
  static Uri uri(String path, [Map<String, dynamic>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final base = Uri.parse('$baseUrl$normalized');
    if (query == null || query.isEmpty) return base;
    return base.replace(
      queryParameters: query.map((k, v) => MapEntry(k, '$v')),
    );
  }
}
