import 'package:shared_preferences/shared_preferences.dart';

import 'sipon_api_client.dart';

class SiponAuthService {
  SiponAuthService({SiponApiClient? apiClient})
    : _apiClient = apiClient ?? SiponApiClient();

  static const _accessTokenKey = 'sipon_access_token';
  static final SiponAuthService instance = SiponAuthService();

  final SiponApiClient _apiClient;

  Future<bool> restoreSession() async {
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString(_accessTokenKey)?.trim();
    if (token == null || token.isEmpty) return false;
    SiponApiClient.setSessionAccessToken(token);
    return true;
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final response = await _apiClient.postUnauthenticatedJson(
      '/api/auth/login',
      body: {'username': username, 'password': password},
    );
    await _saveAccessToken(response);
  }

  Future<void> logout() async {
    SiponApiClient.setSessionAccessToken(null);
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_accessTokenKey);
  }

  Future<void> register({
    required String username,
    required String password,
  }) async {
    final response = await _apiClient.postUnauthenticatedJson(
      '/api/auth/register',
      body: {
        'username': username,
        'password': password,
        'displayName': username,
      },
    );
    await _saveAccessToken(response);
  }

  Future<void> _saveAccessToken(dynamic response) async {
    final token = _readAccessToken(response);
    if (token == null) {
      throw const SiponAuthException('接口响应中未包含 accessToken。');
    }
    SiponApiClient.setSessionAccessToken(token);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_accessTokenKey, token);
  }

  String? _readAccessToken(dynamic response) {
    if (response is! Map) return null;
    final directToken = response['accessToken']?.toString().trim();
    if (directToken != null && directToken.isNotEmpty) return directToken;
    final data = response['data'];
    if (data is Map) {
      final token = data['accessToken']?.toString().trim();
      if (token != null && token.isNotEmpty) return token;
    }
    return null;
  }
}

class SiponAuthException implements Exception {
  const SiponAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
