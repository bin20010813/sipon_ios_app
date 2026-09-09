import 'sipon_api_client.dart';

class SiponPage {
  const SiponPage({this.limit = 20, this.offset = 0})
    : assert(limit >= 1 && limit <= 100),
      assert(offset >= 0);

  final int limit;
  final int offset;

  Map<String, Object> get queryParameters => {'limit': limit, 'offset': offset};
}

class SiponApiService {
  SiponApiService({SiponApiClient? apiClient})
    : _apiClient = apiClient ?? SiponApiClient();

  final SiponApiClient _apiClient;

  // 用户资料与设置
  Future<dynamic> getMyProfile() => _get('/api/users/me');

  Future<dynamic> updateMyProfile(Map<String, Object?> body) =>
      _patchJson('/api/users/me', body: body);

  Future<dynamic> getMyOverview() => _get('/api/users/me/overview');

  Future<dynamic> getMyPreferences() => _get('/api/users/me/preferences');

  Future<dynamic> updateMyPreferences(Map<String, Object?> body) =>
      _patchJson('/api/users/me/preferences', body: body);

  Future<void> changePassword(Map<String, Object?> body) =>
      _putEmpty('/api/users/me/password', body: body);

  Future<List<dynamic>> getMyNotifications({
    SiponPage page = const SiponPage(),
  }) => _getList(
    '/api/users/me/notifications',
    queryParameters: page.queryParameters,
  );

  Future<dynamic> getUnreadNotificationCount() =>
      _get('/api/users/me/notifications/unread-count');

  Future<dynamic> markNotificationsRead(Map<String, Object?> body) =>
      _postJson('/api/users/me/notifications/read', body: body);

  Future<void> upsertDevice({
    required String deviceId,
    required Map<String, Object?> body,
  }) => _putEmpty(
    '/api/users/me/devices/${Uri.encodeComponent(deviceId)}',
    body: body,
  );

  Future<void> deleteDevice(String deviceId) =>
      _deleteEmpty('/api/users/me/devices/${Uri.encodeComponent(deviceId)}');

  Future<dynamic> getMembership() => _get('/api/users/me/membership');

  Future<List<dynamic>> getCoupons() => _getList('/api/users/me/coupons');

  Future<List<dynamic>> getAchievements() =>
      _getList('/api/users/me/achievements');

  // 首页、酒吧与地图
  Future<dynamic> getHome({String? city, num? longitude, num? latitude}) =>
      _get(
        '/api/home',
        queryParameters: {
          'city': city,
          'longitude': longitude,
          'latitude': latitude,
        },
      );

  Future<List<dynamic>> getCities() => _getList('/api/cities');

  Future<List<dynamic>> searchBars({
    String? city,
    String? keyword,
    String? subtype,
    num? minRating,
    SiponPage page = const SiponPage(),
  }) => _getList(
    '/api/bars',
    queryParameters: {
      'city': city,
      'keyword': keyword,
      'subtype': subtype,
      'minRating': minRating,
      ...page.queryParameters,
    },
  );

  Future<dynamic> getBarById(int id) => _get('/api/bars/$id');

  Future<List<dynamic>> getBarMedia(int id) => _getList('/api/bars/$id/media');

  Future<List<dynamic>> getBarHours(int id) => _getList('/api/bars/$id/hours');

  Future<List<dynamic>> getBarDrinks(
    int id, {
    SiponPage page = const SiponPage(),
  }) => _getList('/api/bars/$id/drinks', queryParameters: page.queryParameters);

  Future<List<dynamic>> getBarReviews(
    int id, {
    SiponPage page = const SiponPage(),
  }) =>
      _getList('/api/bars/$id/reviews', queryParameters: page.queryParameters);

  Future<List<dynamic>> getNearbyBars({
    required num longitude,
    required num latitude,
    int? radiusMeters,
    SiponPage page = const SiponPage(),
  }) => _getList(
    '/api/bars/nearby',
    queryParameters: {
      'longitude': longitude,
      'latitude': latitude,
      'radiusMeters': radiusMeters,
      'limit': page.limit,
    },
  );

  Future<dynamic> getMapBars({
    required num west,
    required num south,
    required num east,
    required num north,
    required int zoom,
  }) => _get(
    '/api/bars/map',
    queryParameters: {
      'west': west,
      'south': south,
      'east': east,
      'north': north,
      'zoom': zoom,
    },
  );

  // 打卡与想喝清单
  Future<dynamic> createCheckIn(Map<String, Object?> body) =>
      _postJson('/api/check-ins', body: body);

  Future<dynamic> getCheckIn(int id) => _get('/api/check-ins/$id');

  Future<dynamic> updateCheckIn(int id, Map<String, Object?> body) =>
      _patchJson('/api/check-ins/$id', body: body);

  Future<void> deleteCheckIn(int id) => _deleteEmpty('/api/check-ins/$id');

  Future<List<dynamic>> getMyCheckIns({SiponPage page = const SiponPage()}) =>
      _getList(
        '/api/users/me/check-ins',
        queryParameters: page.queryParameters,
      );

  Future<List<dynamic>> getWishlistBars({SiponPage page = const SiponPage()}) =>
      _getList(
        '/api/users/me/wishlist/bars',
        queryParameters: page.queryParameters,
      );

  Future<void> addWishlistBar(int barId) =>
      _putEmpty('/api/users/me/wishlist/bars/$barId');

  Future<void> removeWishlistBar(int barId) =>
      _deleteEmpty('/api/users/me/wishlist/bars/$barId');

  // 饮酒账本
  Future<dynamic> createDrinkRecord(Map<String, Object?> body) =>
      _postJson('/api/accounting/records', body: body);

  Future<List<dynamic>> getDrinkRecords({
    required String from,
    required String to,
    SiponPage page = const SiponPage(limit: 100),
  }) => _getList(
    '/api/accounting/records',
    queryParameters: {'from': from, 'to': to, ...page.queryParameters},
  );

  Future<dynamic> getDrinkRecord(int id) => _get('/api/accounting/records/$id');

  Future<dynamic> updateDrinkRecord(int id, Map<String, Object?> body) =>
      _putJson('/api/accounting/records/$id', body: body);

  Future<void> deleteDrinkRecord(int id) =>
      _deleteEmpty('/api/accounting/records/$id');

  Future<dynamic> getDrinkAnalytics({
    required String from,
    required String to,
  }) => _get(
    '/api/accounting/analytics',
    queryParameters: {'from': from, 'to': to},
  );

  Future<dynamic> getDrinkBudget(String month) =>
      _get('/api/accounting/budgets/${Uri.encodeComponent(month)}');

  Future<dynamic> setDrinkBudget(String month, Map<String, Object?> body) =>
      _putJson(
        '/api/accounting/budgets/${Uri.encodeComponent(month)}',
        body: body,
      );

  // 酒吧路线
  Future<dynamic> createDrinkingRoute(Map<String, Object?> body) =>
      _postJson('/api/users/me/routes', body: body);

  Future<List<dynamic>> getMyDrinkingRoutes({
    SiponPage page = const SiponPage(),
  }) => _getList('/api/users/me/routes', queryParameters: page.queryParameters);

  Future<dynamic> getDrinkingRoute(int id) => _get('/api/routes/$id');

  Future<dynamic> updateDrinkingRoute(int id, Map<String, Object?> body) =>
      _patchJson('/api/routes/$id', body: body);

  Future<void> deleteDrinkingRoute(int id) => _deleteEmpty('/api/routes/$id');

  // 文件上传、下载与反馈
  Future<dynamic> uploadMedia({
    required List<int> fileBytes,
    required String filename,
    required String mimeType,
    String purpose = 'feedback',
  }) async {
    return _unwrapData(
      await _apiClient.postMultipart(
        '/api/uploads',
        fileBytes: fileBytes,
        filename: filename,
        mimeType: mimeType,
        fields: {'purpose': purpose},
      ),
    );
  }

  Future<List<int>> downloadMedia(String id) async {
    return _apiClient.getBytes(
      '/api/uploads/${Uri.encodeComponent(id)}/content',
    );
  }

  Future<dynamic> createFeedback(Map<String, Object?> body) =>
      _postJson('/api/feedback', body: body);

  Future<List<dynamic>> getMyFeedback({SiponPage page = const SiponPage()}) =>
      _getList('/api/users/me/feedback', queryParameters: page.queryParameters);

  Future<dynamic> _get(
    String path, {
    Map<String, Object?> queryParameters = const {},
  }) async => _unwrapData(
    await _apiClient.getJson(path, queryParameters: queryParameters),
  );

  Future<List<dynamic>> _getList(
    String path, {
    Map<String, Object?> queryParameters = const {},
  }) async => _unwrapList(
    await _apiClient.getJson(path, queryParameters: queryParameters),
  );

  Future<dynamic> _postJson(
    String path, {
    required Map<String, Object?> body,
    Map<String, Object?> queryParameters = const {},
  }) async => _unwrapData(
    await _apiClient.postJson(
      path,
      body: body,
      queryParameters: queryParameters,
    ),
  );

  Future<dynamic> _putJson(
    String path, {
    required Map<String, Object?> body,
  }) async => _unwrapData(await _apiClient.putJson(path, body: body));

  Future<dynamic> _patchJson(
    String path, {
    required Map<String, Object?> body,
  }) async => _unwrapData(await _apiClient.patchJson(path, body: body));

  Future<void> _putEmpty(String path, {Map<String, Object?>? body}) =>
      _apiClient.putJson(path, body: body).then((_) {});

  Future<void> _deleteEmpty(String path) =>
      _apiClient.deleteJson(path).then((_) {});

  dynamic _unwrapData(dynamic response) {
    if (response is Map && response.containsKey('data')) {
      return response['data'];
    }
    return response;
  }

  List<dynamic> _unwrapList(dynamic response) {
    final data = _unwrapData(response);
    if (data is List) return List<dynamic>.from(data);
    throw FormatException('Expected a list response, got ${data.runtimeType}.');
  }
}
