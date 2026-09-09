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
  static String? _sharedSessionAccessToken;
  static SiponSessionRefresher? _sharedSessionRefresher;
  static Future<String?>? _refreshingSession;

  static void setSessionAccessToken(
    String? accessToken, {
    SiponSessionRefresher? refresher,
  }) {
    final normalized = accessToken?.trim();
    _sharedSessionAccessToken = normalized?.isNotEmpty == true
        ? normalized
        : null;
    _sharedSessionRefresher = _sharedSessionAccessToken == null
        ? null
        : refresher;
  }

  static void clearSession() {
    _sharedSessionAccessToken = null;
    _sharedSessionRefresher = null;
  }

  Future<dynamic> getJson(
    String path, {
    Map<String, Object?> queryParameters = const {},
  }) async {
    final response = await _send('GET', path, queryParameters: queryParameters);

    return _decode(response);
  }

  Future<dynamic> postJson(
    String path, {
    Object? body,
    Map<String, Object?> queryParameters = const {},
  }) async {
    final response = await _send(
      'POST',
      path,
      body: body,
      queryParameters: queryParameters,
    );

    return _decode(response);
  }

  Future<dynamic> postUnauthenticatedJson(String path, {Object? body}) async {
    final response = await _send('POST', path, body: body, includeAuth: false);

    return _decode(response);
  }

  Future<dynamic> putJson(
    String path, {
    Object? body,
    Map<String, Object?> queryParameters = const {},
  }) async {
    final response = await _send(
      'PUT',
      path,
      body: body,
      queryParameters: queryParameters,
    );

    return _decode(response);
  }

  Future<dynamic> patchJson(
    String path, {
    Object? body,
    Map<String, Object?> queryParameters = const {},
  }) async {
    final response = await _send(
      'PATCH',
      path,
      body: body,
      queryParameters: queryParameters,
    );

    return _decode(response);
  }

  Future<dynamic> deleteJson(
    String path, {
    Object? body,
    Map<String, Object?> queryParameters = const {},
  }) async {
    final response = await _send(
      'DELETE',
      path,
      body: body,
      queryParameters: queryParameters,
    );

    return _decode(response);
  }

  Future<List<int>> getBytes(String path) async {
    final response = await _send('GET', path, acceptJson: false);
    _throwForError(response);
    return response.bodyBytes;
  }

  Future<dynamic> postMultipart(
    String path, {
    required List<int> fileBytes,
    required String filename,
    required String mimeType,
    Map<String, String> fields = const {},
  }) async {
    final request = http.MultipartRequest('POST', config.uri(path));
    request.headers.addAll(
      config.headers(accessTokenOverride: _sharedSessionAccessToken),
    );
    request.fields.addAll(fields);
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: filename,
        contentType: http.MediaType.parse(mimeType),
      ),
    );

    var response = await http.Response.fromStream(
      await _httpClient.send(request).timeout(config.timeout),
    ).timeout(config.timeout);
    if (response.statusCode == 401 && await _refreshSession()) {
      final retry = http.MultipartRequest('POST', config.uri(path));
      retry.headers.addAll(
        config.headers(accessTokenOverride: _sharedSessionAccessToken),
      );
      retry.fields.addAll(fields);
      retry.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: filename,
          contentType: http.MediaType.parse(mimeType),
        ),
      );
      response = await http.Response.fromStream(
        await _httpClient.send(retry).timeout(config.timeout),
      ).timeout(config.timeout);
    }
    return _decode(response);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    Map<String, Object?> queryParameters = const {},
    bool includeAuth = true,
    bool acceptJson = true,
  }) async {
    Future<http.Response> sendOnce() async {
      final request = http.Request(method, config.uri(path, queryParameters));
      request.headers.addAll(
        config.headers(
          jsonBody: body != null,
          includeAuth: includeAuth,
          accessTokenOverride: _sharedSessionAccessToken,
        ),
      );
      if (!acceptJson) {
        request.headers['Accept'] = '*/*';
      }
      if (body != null) {
        request.body = jsonEncode(body);
      }
      return http.Response.fromStream(
        await _httpClient.send(request).timeout(config.timeout),
      ).timeout(config.timeout);
    }

    var response = await sendOnce();
    if (!includeAuth ||
        response.statusCode != 401 ||
        !await _refreshSession()) {
      return response;
    }
    return sendOnce();
  }

  static Future<bool> _refreshSession() async {
    final refresher = _sharedSessionRefresher;
    if (refresher == null || _sharedSessionAccessToken == null) return false;
    final pending = _refreshingSession ??= refresher();
    try {
      final accessToken = await pending;
      return accessToken?.trim().isNotEmpty == true;
    } finally {
      if (identical(_refreshingSession, pending)) {
        _refreshingSession = null;
      }
    }
  }

  dynamic _decode(http.Response response) {
    _throwForError(response);
    final body = _bodyText(response);

    if (body.trim().isEmpty) {
      return null;
    }

    return jsonDecode(body);
  }

  void _throwForError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final body = _bodyText(response);
    final payload = _tryDecodeObject(body);
    throw SiponApiException(
      statusCode: response.statusCode,
      code: payload?['code']?.toString(),
      message:
          payload?['message']?.toString() ??
          (body.isEmpty ? response.reasonPhrase : body),
      path: payload?['path']?.toString(),
      requestId:
          payload?['requestId']?.toString() ?? response.headers['x-request-id'],
    );
  }

  Map<String, dynamic>? _tryDecodeObject(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final value = jsonDecode(body);
      return value is Map ? value.cast<String, dynamic>() : null;
    } on FormatException {
      return null;
    }
  }

  String _bodyText(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);
}

typedef SiponSessionRefresher = Future<String?> Function();

class SiponApiException implements Exception {
  const SiponApiException({
    required this.statusCode,
    required this.message,
    this.code,
    this.path,
    this.requestId,
  });

  final int statusCode;
  final String? message;
  final String? code;
  final String? path;
  final String? requestId;

  @override
  String toString() {
    final detail = message?.trim();
    if (detail == null || detail.isEmpty) {
      return 'HTTP $statusCode';
    }

    final errorCode = code?.trim();
    return errorCode == null || errorCode.isEmpty
        ? 'HTTP $statusCode: $detail'
        : '$errorCode (HTTP $statusCode): $detail';
  }
}
