import 'dart:async';
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

  test('恢复已保存会话时验证请求超时仍保留登录状态', () async {
    final savedSession = SiponAuthSession(
      accessToken: 'saved-access-token',
      refreshToken: 'saved-refresh-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      refreshExpiresAt: null,
      user: const {'id': 1},
    );
    SharedPreferences.setMockInitialValues({
      'sipon_auth_session': jsonEncode(savedSession.toJson()),
    });
    final apiClient = SiponApiClient(
      config: const SiponApiConfig(
        baseUrl: 'https://api.example.test',
        timeout: Duration(milliseconds: 10),
      ),
      httpClient: MockClient((request) {
        expect(request.url.path, '/api/auth/me');
        return Completer<http.Response>().future;
      }),
    );
    final authService = SiponAuthService(apiClient: apiClient);

    expect(await authService.restoreSession(), isTrue);
    expect(authService.session?.accessToken, 'saved-access-token');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('sipon_auth_session'), isNotNull);
  });

  test('令牌刷新超时仍保留已保存会话', () async {
    final savedSession = SiponAuthSession(
      accessToken: 'expired-access-token',
      refreshToken: 'saved-refresh-token',
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      refreshExpiresAt: null,
      user: const {'id': 1},
    );
    SharedPreferences.setMockInitialValues({
      'sipon_auth_session': jsonEncode(savedSession.toJson()),
    });
    final apiClient = SiponApiClient(
      config: const SiponApiConfig(
        baseUrl: 'https://api.example.test',
        timeout: Duration(milliseconds: 10),
      ),
      httpClient: MockClient((request) {
        expect(request.url.path, '/api/auth/refresh');
        return Completer<http.Response>().future;
      }),
    );
    final authService = SiponAuthService(apiClient: apiClient);

    expect(await authService.restoreSession(), isTrue);
    expect(authService.session?.refreshToken, 'saved-refresh-token');
  });

  test('旧版 access token 验证超时仍可继续启动', () async {
    SharedPreferences.setMockInitialValues({
      'sipon_access_token': 'legacy-access-token',
    });
    final apiClient = SiponApiClient(
      config: const SiponApiConfig(
        baseUrl: 'https://api.example.test',
        timeout: Duration(milliseconds: 10),
      ),
      httpClient: MockClient((request) {
        expect(request.url.path, '/api/auth/me');
        return Completer<http.Response>().future;
      }),
    );
    final authService = SiponAuthService(apiClient: apiClient);

    expect(await authService.restoreSession(), isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('sipon_access_token'), 'legacy-access-token');
  });

  test('服务器确认会话失效时清除已保存会话', () async {
    final savedSession = SiponAuthSession(
      accessToken: 'invalid-access-token',
      refreshToken: 'invalid-refresh-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      refreshExpiresAt: null,
      user: const {'id': 1},
    );
    SharedPreferences.setMockInitialValues({
      'sipon_auth_session': jsonEncode(savedSession.toJson()),
    });
    final apiClient = SiponApiClient(
      config: config,
      httpClient: MockClient((request) async {
        expect(
          request.url.path,
          anyOf('/api/auth/me', '/api/auth/refresh'),
        );
        return http.Response('{"code":"UNAUTHENTICATED"}', 401);
      }),
    );
    final authService = SiponAuthService(apiClient: apiClient);

    expect(await authService.restoreSession(), isFalse);
    expect(authService.session, isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('sipon_auth_session'), isNull);
  });
}
