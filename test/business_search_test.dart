import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:htbiz/services/business_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // These service integration tests use only the loopback fixture server.
  // Disable Flutter's blanket HTTP-400 override for this test isolate.
  HttpOverrides.global = null;
  late HttpServer server;
  late SupabaseClient client;
  late BusinessService service;
  late Uri requestUri;
  var requestCount = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    requestCount = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestCount++;
      requestUri = request.uri;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(List.generate(
          3,
          (index) => {
                'id': '$index',
                'name': 'Business $index',
                'category': 'Restaurant',
                'address': 'Haiti',
                'owner_id': 'owner',
                'rating': 0,
                'total_reviews': 0,
                'created_at': '2026-09-01T00:00:00Z',
              })));
      await request.response.close();
    });
    client = SupabaseClient('http://127.0.0.1:${server.port}', 'test-key');
    service = BusinessService(client: client);
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });
  test('search is sent to the database and excludes deleted businesses',
      () async {
    final page = await service.getBusinessPage(
        search: 'Kay%', category: 'restaurant', limit: 2);
    expect(requestUri.queryParameters['name'], r'ilike.%Kay\%%');
    expect(requestUri.queryParameters['deleted_at'], 'is.null');
    expect(requestUri.queryParameters['category'], 'ilike.restaurant');
    expect(page.items.length, 2);
    expect(page.hasMore, isTrue);
  });
  test('pagination preserves search and uses stable ordering', () async {
    await service.getBusinessPage(search: 'shop', offset: 20, limit: 2);
    expect(requestUri.queryParameters['offset'], '20');
    expect(requestUri.queryParameters['limit'], '3');
    expect(requestUri.queryParameters['order'],
        'created_at.desc.nullslast,id.asc.nullslast');
    expect(requestUri.queryParameters['name'], 'ilike.%shop%');
  });
  test('empty favorites do not fetch the whole directory', () async {
    final page = await service.getBusinessPage(businessIds: {});
    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
    expect(requestCount, 0);
  });
}
