import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sipon/services/sipon_api_client.dart';
import 'package:sipon/services/sipon_api_config.dart';
import 'package:sipon/services/sipon_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = SiponApiConfig(baseUrl: 'https://api.example.test');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SiponApiClient.clearSession();
  });

  tearDown(SiponApiClient.clearSession);

  test('Apple 登录向匿名接口发送完整凭据并保存会话', () async {
    final apiClient = SiponApiClient(
      config: config,
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/auth/apple/login');
        expect(request.headers['authorization'], isNull);
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), {
          'identityToken': 'identity-token',
          'authorizationCode': 'authorization-code',
          'displayName': 'Sipon User',
        });
        return http.Response(
          jsonEncode({
            'data': {
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'user': {'id': 1},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final authService = SiponAuthService(apiClient: apiClient);

    await authService.loginWithApple(
      identityToken: 'identity-token',
      authorizationCode: ' authorization-code ',
      displayName: ' Sipon User ',
    );

    expect(authService.session?.accessToken, 'access-token');
    expect(authService.session?.refreshToken, 'refresh-token');
    expect(authService.session?.user, {'id': 1});
  });

  test('Apple 登录保留后端状态、错误码、消息和请求 ID', () async {
    final apiClient = SiponApiClient(
      config: config,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'APPLE_AUDIENCE_NOT_ALLOWED',
            'message': 'Apple token audience is not allowed',
            'requestId': 'request-123',
          }),
          401,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final authService = SiponAuthService(apiClient: apiClient);

    await expectLater(
      authService.loginWithApple(identityToken: 'identity-token'),
      throwsA(
        isA<SiponApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having(
              (error) => error.code,
              'code',
              'APPLE_AUDIENCE_NOT_ALLOWED',
            )
            .having(
              (error) => error.message,
              'message',
              'Apple token audience is not allowed',
            )
            .having((error) => error.requestId, 'requestId', 'request-123'),
      ),
    );
  });
}
