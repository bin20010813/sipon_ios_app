class SiponApiConfig {
  const SiponApiConfig({
    this.baseUrl = const String.fromEnvironment(
      'SIPON_API_BASE_URL',
      defaultValue: 'http://106.53.119.216:8081',
    ),
    this.accessToken = const String.fromEnvironment('SIPON_ACCESS_TOKEN'),
    this.adminToken = const String.fromEnvironment('SIPON_ADMIN_TOKEN'),
    this.loginUsername = const String.fromEnvironment(
      'SIPON_LOGIN_USERNAME',
      defaultValue: 'apifox_user',
    ),
    this.loginPassword = const String.fromEnvironment(
      'SIPON_LOGIN_PASSWORD',
      defaultValue: 'password123',
    ),
    this.timeout = const Duration(seconds: 12),
  });

  static const SiponApiConfig instance = SiponApiConfig();

  final String baseUrl;
  final String accessToken;
  final String adminToken;
  final String loginUsername;
  final String loginPassword;
  final Duration timeout;

  bool get canLogin =>
      loginUsername.trim().isNotEmpty && loginPassword.trim().isNotEmpty;

  Uri uri(String path, [Map<String, Object?> queryParameters = const {}]) {
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$normalizedBaseUrl$normalizedPath');
    final query = <String, String>{};

    for (final entry in queryParameters.entries) {
      final value = entry.value;
      if (value != null) {
        query[entry.key] = value.toString();
      }
    }

    return uri.replace(queryParameters: query.isEmpty ? null : query);
  }

  Map<String, String> headers({
    bool jsonBody = false,
    bool includeAuth = true,
    bool includeAdminToken = false,
    String? accessTokenOverride,
  }) {
    final headers = <String, String>{'Accept': 'application/json'};
    final bearerToken = (accessTokenOverride ?? accessToken).trim();
    final appAdminToken = adminToken.trim();

    if (jsonBody) {
      headers['Content-Type'] = 'application/json';
    }
    if (includeAuth && bearerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearerToken';
    }
    if (includeAdminToken && appAdminToken.isNotEmpty) {
      headers['X-Admin-Token'] = appAdminToken;
    }

    return headers;
  }
}
