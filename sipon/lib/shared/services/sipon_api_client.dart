import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// 受登录保护的上传内容用于 Flutter 图片组件时所需的请求头。
  /// 不在日志中输出 token。
  static Map<String, String> get imageRequestHeaders {
    final token = _sharedSessionAccessToken;
    return token == null || token.isEmpty
        ? const <String, String>{}
        : <String, String>{'Authorization': 'Bearer $token'};
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

    return _decode(response, debugEndpoint: _debugEndpoint('POST', path));
  }

  Future<dynamic> postUnauthenticatedJson(String path, {Object? body}) async {
    final response = await _send('POST', path, body: body, includeAuth: false);

    return _decode(response, debugEndpoint: _debugEndpoint('POST', path));
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
    Map<String, Object?> queryParameters = const {},
  }) async {
    final request = http.MultipartRequest(
      'POST',
      config.uri(path, queryParameters),
    );
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

    final debugEndpoint = _debugEndpoint('POST', path);
    var response = await _sendRequest(request, attempt: 1);
    if (response.statusCode == 401 &&
        await _refreshSession(debugEndpoint: debugEndpoint)) {
      final retry = http.MultipartRequest(
        'POST',
        config.uri(path, queryParameters),
      );
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
      response = await _sendRequest(retry, attempt: 2);
    }
    return _decode(response, debugEndpoint: debugEndpoint);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    Map<String, Object?> queryParameters = const {},
    bool includeAuth = true,
    bool acceptJson = true,
  }) async {
    final debugEndpoint = _debugEndpoint(method, path);
    var attempt = 0;
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
      return _sendRequest(request, attempt: ++attempt);
    }

    var response = await sendOnce();
    if (response.statusCode == 401 && !includeAuth) {
      _debugLog(debugEndpoint, 'refresh unavailable includeAuth=false');
    }
    if (!includeAuth ||
        response.statusCode != 401 ||
        !await _refreshSession(debugEndpoint: debugEndpoint)) {
      return response;
    }
    return sendOnce();
  }

  Future<http.Response> _sendRequest(
    http.BaseRequest request, {
    required int attempt,
  }) async {
    final endpoint = _debugEndpoint(request.method, request.url.path);
    if (endpoint == null) {
      return http.Response.fromStream(
        await _httpClient.send(request).timeout(config.timeout),
      ).timeout(config.timeout);
    }

    final stopwatch = Stopwatch()..start();
    var stage = 'send';
    _debugLog(
      endpoint,
      'attempt=$attempt stage=$stage '
      'hasAuthorization=${request.headers.containsKey('Authorization')} '
      'hasSessionRefresher=${_sharedSessionRefresher != null} '
      'timeoutMs=${config.timeout.inMilliseconds}',
    );
    try {
      final streamed = await _httpClient.send(request).timeout(config.timeout);
      stage = 'read';
      _debugLog(
        endpoint,
        'attempt=$attempt stage=$stage status=${streamed.statusCode} '
        'elapsedMs=${stopwatch.elapsedMilliseconds} '
        'contentType=${streamed.headers['content-type']} '
        'requestId=${streamed.headers['x-request-id']}',
      );
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(config.timeout);
      _debugLog(
        endpoint,
        'attempt=$attempt stage=complete status=${response.statusCode} '
        'elapsedMs=${stopwatch.elapsedMilliseconds} '
        'responseBytes=${response.bodyBytes.length} '
        'contentType=${response.headers['content-type']} '
        'requestId=${response.headers['x-request-id']}',
      );
      return response;
    } catch (error, stack) {
      _debugLog(
        endpoint,
        'attempt=$attempt stage=$stage elapsedMs=${stopwatch.elapsedMilliseconds} '
        'exceptionType=${error.runtimeType}',
        stack: stack,
      );
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  static String? _debugEndpoint(String method, String path) {
    if (!kDebugMode || method != 'POST') return null;
    final parsedPath = Uri.tryParse(path)?.path;
    final endpoint = parsedPath?.startsWith('/') == true
        ? parsedPath
        : '/$parsedPath';
    return endpoint == '/api/uploads' || endpoint == '/api/poi-submissions'
        ? endpoint
        : null;
  }

  static void _debugLog(String? endpoint, String message, {StackTrace? stack}) {
    if (!kDebugMode || endpoint == null) return;
    debugPrint('[VenueAPI] POST $endpoint $message');
    if (stack != null) {
      debugPrintStack(
        stackTrace: stack,
        label: '[VenueAPI] POST $endpoint stack',
      );
    }
  }

  static Future<bool> _refreshSession({String? debugEndpoint}) async {
    _debugLog(debugEndpoint, 'refresh start status=401');
    final refresher = _sharedSessionRefresher;
    if (refresher == null || _sharedSessionAccessToken == null) {
      _debugLog(
        debugEndpoint,
        'refresh unavailable hasSessionRefresher=${refresher != null} '
        'hasSessionAccessToken=${_sharedSessionAccessToken != null}',
      );
      return false;
    }
    try {
      _debugLog(debugEndpoint, 'refresh shared=${_refreshingSession != null}');
      final pending = _refreshingSession ??= refresher();
      try {
        final accessToken = await pending;
        final refreshed = accessToken?.trim().isNotEmpty == true;
        _debugLog(debugEndpoint, 'refresh result=$refreshed');
        return refreshed;
      } finally {
        if (identical(_refreshingSession, pending)) {
          _refreshingSession = null;
        }
      }
    } catch (error, stack) {
      _debugLog(
        debugEndpoint,
        'refresh exceptionType=${error.runtimeType}',
        stack: stack,
      );
      rethrow;
    }
  }

  dynamic _decode(http.Response response, {String? debugEndpoint}) {
    _throwForError(response, debugEndpoint: debugEndpoint);
    final body = _bodyText(response);

    if (body.trim().isEmpty) {
      _debugLog(debugEndpoint, 'decode empty response');
      return null;
    }

    return _decodeJson(body, debugEndpoint: debugEndpoint);
  }

  dynamic _decodeJson(String body, {String? debugEndpoint}) {
    try {
      final value = jsonDecode(body);
      _debugLog(debugEndpoint, 'decode success jsonType=${value.runtimeType}');
      return value;
    } catch (error, stack) {
      _debugLog(
        debugEndpoint,
        'decode failure exceptionType=${error.runtimeType}',
        stack: stack,
      );
      rethrow;
    }
  }

  void _throwForError(http.Response response, {String? debugEndpoint}) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final body = _bodyText(response);
    final payload = _tryDecodeObject(body, debugEndpoint: debugEndpoint);
    final error = SiponApiException(
      statusCode: response.statusCode,
      code: payload?['code']?.toString(),
      message:
          payload?['message']?.toString() ??
          (body.isEmpty ? response.reasonPhrase : body),
      path: payload?['path']?.toString(),
      requestId:
          payload?['requestId']?.toString() ?? response.headers['x-request-id'],
    );
    _debugLog(
      debugEndpoint,
      'apiError status=${error.statusCode} code=${error.code} '
      'requestId=${error.requestId}',
    );
    throw error;
  }

  Map<String, dynamic>? _tryDecodeObject(String body, {String? debugEndpoint}) {
    if (body.trim().isEmpty) {
      _debugLog(debugEndpoint, 'decode empty response');
      return null;
    }
    try {
      final value = _decodeJson(body, debugEndpoint: debugEndpoint);
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
