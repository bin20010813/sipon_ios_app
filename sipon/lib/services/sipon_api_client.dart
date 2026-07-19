import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sipon_api_config.dart';

class SiponApiClient {
  SiponApiClient({
    this.config = SiponApiConfig.instance,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final SiponApiConfig config;
  final http.Client _httpClient;
  String? _sessionAccessToken;

  Future<dynamic> getJson(
    String path, {
    Map<String, Object?> queryParameters = const {},
  }) async {
    final response = await _sendWithAuthRetry(
      () => _httpClient.get(
        config.uri(path, queryParameters),
        headers: config.headers(accessTokenOverride: _sessionAccessToken),
      ),
    );

    return _decode(response);
  }

  Future<dynamic> postJson(
    String path, {
    Object? body,
    Map<String, Object?> queryParameters = const {},
  }) async {
    final response = await _sendWithAuthRetry(
      () => _httpClient.post(
        config.uri(path, queryParameters),
        headers: config.headers(
          jsonBody: true,
          accessTokenOverride: _sessionAccessToken,
        ),
        body: body == null ? null : jsonEncode(body),
      ),
    );

    return _decode(response);
  }

  Future<dynamic> postAdminJson(
    String path, {
    Object? body,
    Map<String, Object?> queryParameters = const {},
  }) async {
    final response = await _httpClient
        .post(
          config.uri(path, queryParameters),
          headers: config.headers(
            jsonBody: true,
            includeAuth: false,
            includeAdminToken: true,
          ),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(config.timeout);

    return _decode(response);
  }

  Future<http.Response> _sendWithAuthRetry(
    Future<http.Response> Function() send,
  ) async {
    var response = await send().timeout(config.timeout);
    if (response.statusCode != 401 || !config.canLogin) {
      return response;
    }

    _sessionAccessToken = await _login();
    response = await send().timeout(config.timeout);

    return response;
  }

  Future<String?> _login() async {
    final response = await _httpClient
        .post(
          config.uri('/api/auth/login'),
          headers: config.headers(
            jsonBody: true,
            includeAuth: false,
            includeAdminToken: false,
          ),
          body: jsonEncode({
            'username': config.loginUsername,
            'password': config.loginPassword,
          }),
        )
        .timeout(config.timeout);
    final json = _decode(response);

    if (json is Map) {
      final accessToken = json['accessToken']?.toString().trim();
      if (accessToken != null && accessToken.isNotEmpty) {
        return accessToken;
      }
    }

    return null;
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SiponApiException(
        statusCode: response.statusCode,
        message: response.body.isEmpty ? response.reasonPhrase : response.body,
      );
    }

    if (response.body.trim().isEmpty) {
      return null;
    }

    return jsonDecode(response.body);
  }
}

class SiponApiException implements Exception {
  const SiponApiException({required this.statusCode, required this.message});

  final int statusCode;
  final String? message;

  @override
  String toString() {
    final detail = message?.trim();
    if (detail == null || detail.isEmpty) {
      return 'HTTP $statusCode';
    }

    return 'HTTP $statusCode: $detail';
  }
}
