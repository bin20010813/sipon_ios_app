import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sipon_api_client.dart';

class SiponAuthService {
  SiponAuthService({SiponApiClient? apiClient})
    : _apiClient = apiClient ?? SiponApiClient();

  static const _sessionKey = 'sipon_auth_session';
  static const _legacyAccessTokenKey = 'sipon_access_token';
  static final SiponAuthService instance = SiponAuthService();

  final SiponApiClient _apiClient;
  SiponAuthSession? _session;
  Future<SiponAuthSession?>? _refreshing;

  SiponAuthSession? get session => _session;

  Future<bool> restoreSession() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_sessionKey);
    final restored = SiponAuthSession.tryParse(saved);
    if (restored != null) {
      _setSession(restored);
      if (restored.accessTokenExpiresSoon) {
        return (await _refreshSession()) != null;
      }
      try {
        await _apiClient.getJson('/api/auth/me');
        return true;
      } on SiponApiException catch (error) {
        if (error.statusCode != 401) rethrow;
        await _clearSession(preferences);
        return false;
      }
    }

    // 兼容只保存了 access token 的历史安装；该会话不具备刷新能力。
    final legacyToken = preferences.getString(_legacyAccessTokenKey)?.trim();
    if (legacyToken == null || legacyToken.isEmpty) return false;
    SiponApiClient.setSessionAccessToken(legacyToken);
    try {
      await _apiClient.getJson('/api/auth/me');
      return true;
    } on SiponApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      await preferences.remove(_legacyAccessTokenKey);
      SiponApiClient.clearSession();
      return false;
    }
  }

  Future<void> login({required String username, required String password}) =>
      _authenticate('/api/auth/login', {
        'username': username,
        'password': password,
      });

  Future<void> register({
    required String username,
    required String password,
    String? displayName,
  }) => _authenticate('/api/auth/register', {
    'username': username,
    'password': password,
    if (displayName?.trim().isNotEmpty == true)
      'displayName': displayName!.trim(),
  });

  Future<void> requestPhoneCode(String phone) async {
    await _apiClient.postUnauthenticatedJson(
      '/api/auth/phone/code',
      body: {'phone': phone},
    );
  }

  Future<void> loginWithPhoneCode({
    required String phone,
    required String code,
    String? displayName,
  }) => _authenticate('/api/auth/phone/login', {
    'phone': phone,
    'code': code,
    if (displayName?.trim().isNotEmpty == true)
      'displayName': displayName!.trim(),
  });

  Future<dynamic> healthCheck() => _apiClient.getJson('/api/health');

  Future<void> logout() async {
    final refreshToken = _session?.refreshToken;
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _apiClient.postUnauthenticatedJson(
          '/api/auth/logout',
          body: {'refreshToken': refreshToken},
        );
      }
    } finally {
      await _clearSession();
    }
  }

  Future<void> _authenticate(String path, Map<String, Object?> body) async {
    final response = await _apiClient.postUnauthenticatedJson(path, body: body);
    final session = SiponAuthSession.fromResponse(response);
    await _persistSession(session);
  }

  Future<String?> _refreshAccessToken() async {
    final refreshed = await _refreshSession();
    return refreshed?.accessToken;
  }

  Future<SiponAuthSession?> _refreshSession() {
    return _refreshing ??= _performRefresh().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<SiponAuthSession?> _performRefresh() async {
    final refreshToken = _session?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return null;
    try {
      final response = await _apiClient.postUnauthenticatedJson(
        '/api/auth/refresh',
        body: {'refreshToken': refreshToken},
      );
      final session = SiponAuthSession.fromResponse(response);
      await _persistSession(session);
      return session;
    } on SiponApiException catch (error) {
      if (error.statusCode == 400 || error.statusCode == 401) {
        await _clearSession();
        return null;
      }
      rethrow;
    }
  }

  Future<void> _persistSession(SiponAuthSession session) async {
    final preferences = await SharedPreferences.getInstance();
    // 单个序列化记录避免轮换 refresh token 时出现不一致的键值组合。
    await preferences.setString(_sessionKey, jsonEncode(session.toJson()));
    await preferences.remove(_legacyAccessTokenKey);
    _setSession(session);
  }

  void _setSession(SiponAuthSession session) {
    _session = session;
    SiponApiClient.setSessionAccessToken(
      session.accessToken,
      refresher: _refreshAccessToken,
    );
  }

  Future<void> _clearSession([SharedPreferences? preferences]) async {
    _session = null;
    SiponApiClient.clearSession();
    final store = preferences ?? await SharedPreferences.getInstance();
    await Future.wait([
      store.remove(_sessionKey),
      store.remove(_legacyAccessTokenKey),
    ]);
  }
}

class SiponAuthSession {
  const SiponAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.refreshExpiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime? expiresAt;
  final DateTime? refreshExpiresAt;
  final Map<String, dynamic> user;

  bool get accessTokenExpiresSoon {
    final expiry = expiresAt;
    return expiry != null &&
        !expiry.isAfter(
          DateTime.now().toUtc().add(const Duration(seconds: 30)),
        );
  }

  factory SiponAuthSession.fromResponse(dynamic response) {
    final raw = response is Map && response['data'] is Map
        ? response['data'] as Map
        : response;
    if (raw is! Map) {
      throw const SiponAuthException('认证接口响应格式无效。');
    }
    final accessToken = raw['accessToken']?.toString().trim();
    final refreshToken = raw['refreshToken']?.toString().trim();
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      throw const SiponAuthException('认证接口响应中未包含完整令牌。');
    }
    return SiponAuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: _parseDate(raw['expiresAt']),
      refreshExpiresAt: _parseDate(raw['refreshExpiresAt']),
      user: raw['user'] is Map
          ? (raw['user'] as Map).cast<String, dynamic>()
          : const {},
    );
  }

  static SiponAuthSession? tryParse(String? source) {
    if (source == null || source.trim().isEmpty) return null;
    try {
      final value = jsonDecode(source);
      if (value is! Map) return null;
      return SiponAuthSession.fromResponse(value);
    } on FormatException {
      return null;
    } on SiponAuthException {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    if (refreshExpiresAt != null)
      'refreshExpiresAt': refreshExpiresAt!.toIso8601String(),
    'user': user,
  };
}

DateTime? _parseDate(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toUtc();

class SiponAuthException implements Exception {
  const SiponAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
