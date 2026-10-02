import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sipon/shared/services/sipon_api_client.dart';
import 'package:sipon/shared/services/sipon_api_config.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';

void main() {
  const config = SiponApiConfig(baseUrl: 'https://api.example.test');

  tearDown(SiponApiClient.clearSession);

  test(
    'feed request sends all server filters and preserves page shape',
    () async {
      SiponApiClient.setSessionAccessToken('token');
      final service = SiponApiService(
        apiClient: SiponApiClient(
          config: config,
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/feed/check-ins');
            expect(request.url.queryParameters, {
              'city': '佛山',
              'keyword': '特调',
              'barSubtype': 'cocktail_bar',
              'scope': 'following',
              'sort': 'popular',
              'limit': '20',
              'offset': '20',
            });
            expect(request.headers['authorization'], 'Bearer token');
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'items': [
                    {'id': 100, 'barId': 12, 'barName': '示例酒吧'},
                  ],
                  'limit': 20,
                  'offset': 20,
                  'hasMore': true,
                }),
              ),
              200,
            );
          }),
        ),
      );

      final response = await service.getCheckInFeed(
        city: '佛山',
        keyword: '特调',
        barSubtype: 'cocktail_bar',
        scope: 'following',
        sort: 'popular',
        page: const SiponPage(limit: 20, offset: 20),
      );
      expect(response['hasMore'], isTrue);
      expect(response['items'], hasLength(1));
    },
  );

  test('like and unlike accept 204 without a JSON body', () async {
    final methods = <String>[];
    final service = SiponApiService(
      apiClient: SiponApiClient(
        config: config,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/check-ins/100/reaction');
          methods.add(request.method);
          if (request.method == 'PUT') {
            expect(jsonDecode(request.body), {'reaction': 'like'});
          }
          return http.Response('', 204);
        }),
      ),
    );

    await service.setCheckInReaction(100, 'like');
    await service.setCheckInReaction(100, null);
    expect(methods, ['PUT', 'DELETE']);
  });

  test('comments use paged GET, POST and empty DELETE', () async {
    final methods = <String>[];
    final service = SiponApiService(
      apiClient: SiponApiClient(
        config: config,
        httpClient: MockClient((request) async {
          expect(request.url.path, startsWith('/api/check-ins/100/comments'));
          methods.add(request.method);
          if (request.method == 'GET') {
            expect(request.url.queryParameters, {'limit': '20', 'offset': '20'});
            return http.Response(
              jsonEncode({'items': [], 'limit': 20, 'offset': 20, 'hasMore': false}),
              200,
            );
          }
          if (request.method == 'POST') {
            expect(jsonDecode(request.body), {'content': '很好喝'});
            return http.Response(
              jsonEncode({'id': 7, 'moderationStatus': 'pending'}),
              201,
            );
          }
          expect(request.url.path, '/api/check-ins/100/comments/7');
          return http.Response('', 204);
        }),
      ),
    );
    final page = await service.getCheckInComments(
      100,
      page: const SiponPage(limit: 20, offset: 20),
    );
    expect(page['hasMore'], false);
    final created = await service.createCheckInComment(100, '很好喝');
    expect(created['moderationStatus'], 'pending');
    await service.deleteCheckInComment(100, 7);
    expect(methods, ['GET', 'POST', 'DELETE']);
  });
}
