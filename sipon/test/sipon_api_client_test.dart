import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sipon/services/sipon_api_client.dart';
import 'package:sipon/services/sipon_api_config.dart';

void main() {
  const config = SiponApiConfig(baseUrl: 'https://api.example.test');

  tearDown(SiponApiClient.clearSession);

  test('发送 JSON 请求时附带 Bearer token 与查询参数', () async {
    SiponApiClient.setSessionAccessToken('access-token');
    final client = SiponApiClient(
      config: config,
      httpClient: MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/users/me');
        expect(request.url.queryParameters, {'locale': 'zh-CN'});
        expect(request.headers['authorization'], 'Bearer access-token');
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), {'displayName': 'Sipon'});
        return http.Response('{"id": 1}', 200);
      }),
    );

    expect(
      await client.patchJson(
        '/api/users/me',
        body: {'displayName': 'Sipon'},
        queryParameters: {'locale': 'zh-CN'},
      ),
      {'id': 1},
    );
  });

  test('401 时只刷新一次并使用新令牌重试请求', () async {
    var requestCount = 0;
    var refreshCount = 0;
    SiponApiClient.setSessionAccessToken(
      'expired-token',
      refresher: () async {
        refreshCount++;
        SiponApiClient.setSessionAccessToken('fresh-token');
        return 'fresh-token';
      },
    );
    final client = SiponApiClient(
      config: config,
      httpClient: MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          expect(request.headers['authorization'], 'Bearer expired-token');
          return http.Response('{"code":"UNAUTHENTICATED"}', 401);
        }
        expect(request.headers['authorization'], 'Bearer fresh-token');
        return http.Response('{"ok":true}', 200);
      }),
    );

    expect(await client.getJson('/api/users/me'), {'ok': true});
    expect(refreshCount, 1);
    expect(requestCount, 2);
  });

  test('错误响应保留服务端错误详情和请求 ID', () async {
    final client = SiponApiClient(
      config: config,
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            '{"code":"VALIDATION_ERROR","message":"参数不合法","path":"/api/bars","requestId":"body-id"}',
          ),
          400,
          headers: {'x-request-id': 'header-id'},
        ),
      ),
    );

    await expectLater(
      client.getJson('/api/bars'),
      throwsA(
        isA<SiponApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)
            .having((error) => error.code, 'code', 'VALIDATION_ERROR')
            .having((error) => error.message, 'message', '参数不合法')
            .having((error) => error.path, 'path', '/api/bars')
            .having((error) => error.requestId, 'requestId', 'body-id'),
      ),
    );
  });
}
