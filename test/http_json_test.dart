import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:htbiz/services/http_json.dart';

void main() {
  late HttpServer server;
  late Completer<void> releaseSlowRequest;

  setUp(() async {
    releaseSlowRequest = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/slow') {
        await releaseSlowRequest.future;
      }
      if (request.uri.path == '/unavailable') {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
    });
  });

  tearDown(() async {
    if (!releaseSlowRequest.isCompleted) releaseSlowRequest.complete();
    await server.close(force: true);
  });

  Uri endpoint(String path) =>
      Uri.parse('http://127.0.0.1:${server.port}$path');

  test('decodes successful JSON responses', () async {
    final result = await HttpJson.get(endpoint('/ok')) as Map<String, dynamic>;
    expect(result['ok'], isTrue);
  });

  test('rejects non-success HTTP responses', () async {
    await expectLater(
      HttpJson.get(endpoint('/unavailable')),
      throwsA(isA<HttpException>()),
    );
  });

  test('times out stalled requests and closes the client', () async {
    await expectLater(
      HttpJson.get(endpoint('/slow'),
          timeout: const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>()),
    );
  });
}
