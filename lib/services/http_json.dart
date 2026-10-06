import 'dart:convert';
import 'dart:io';

/// Small bounded GET helper for third-party JSON APIs.
///
/// Always closes its socket pool, including when parsing or a request fails.
class HttpJson {
  HttpJson._();

  static const Duration requestTimeout = Duration(seconds: 15);

  static Future<dynamic> get(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = requestTimeout,
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      headers.forEach((name, value) => request.headers.set(name, value));

      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Request failed with status ${response.statusCode}',
          uri: uri,
        );
      }

      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }
}
