import 'package:flutter/foundation.dart';

import 'sipon_api_client.dart';
import 'sipon_api_models.dart';
import 'sipon_region_data.dart';
import 'sipon_search_preferences.dart';

class SiponDataRepository {
  SiponDataRepository({SiponApiClient? apiClient})
    : _apiClient = apiClient ?? SiponApiClient();

  static final SiponDataRepository instance = SiponDataRepository();

  final SiponApiClient _apiClient;

  /// 拉取地图页酒吧。
  ///
  /// 聚合点契约（待接口验证）：当前一律丢弃 cluster=true 的点。响应模型已定义
  /// mode/cluster/count，不能忽略其语义，但也不能把聚合点当普通酒吧传给详情页
  /// ——聚合 ID、数量与点击行为必须与真实酒吧 ID 分开。
  ///
  /// TODO(接口验证)：记录不同 zoom 下 /api/bars/map 的 mode、总条数、聚合条数
  /// 与普通酒吧条数，再据此选择契约：始终返回普通酒吧则保留现状并记录约定；
  /// 返回服务端聚合点则新增独立聚合类型（显示数量 + 点击放大）；产品要求客户端
  /// 聚合则与后端确认普通点位获取方式。
  Future<List<SiponBarMapItem>> fetchMapBars({
    required SiponMapBounds bounds,
    required double zoom,
  }) async {
    final json = await _apiClient.getJson(
      '/api/bars/map',
      queryParameters: bounds.toQueryParameters(zoom),
    );
    final response = SiponBarMapResponse.fromJson(json);

    return response.items
        .where((item) => !item.cluster)
        .toList(growable: false);
  }

  /// 拉取首页精选酒吧，支持 [offset]/[limit] 分页。
  ///
  /// 首页精选展示只需第一页；后续若扩展“查看全部酒吧”可由调用方传 offset 翻页。
  Future<List<SiponBarMapItem>> fetchHomeBars({
    String? city,
    String? keyword,
    int offset = 0,
    int limit = 20,
  }) async {
    final json = await _apiClient.getJson(
      '/api/bars',
      queryParameters: {
        'city': city == null ? null : siponApiCityName(city),
        'keyword': keyword,
        'hasImage': true,
        'limit': limit,
        'offset': offset,
      },
    );
    final parsedItems = SiponBarMapResponse.fromJson(json).items;
    final items = parsedItems
        .where((item) => !item.cluster)
        // 服务端即使收到 hasImage=true，仍可能返回带占位图片路径但
        // `hasImage=false` 的酒吧。首页推荐只接受已确认拥有照片的条目。
        .where((item) => item.hasImage)
        .toList(growable: false);
    if (kDebugMode) {
      final rawCount = json is List ? json.length : null;
      debugPrint(
        'Home bars: city=${siponApiCityName(city ?? '')}, '
        'response=${json.runtimeType}, raw=${rawCount ?? 'non-list'}, '
        'parsed=${parsedItems.length}, displayable=${items.length}',
      );
    }
    return SiponBarMapItem.sortForHomeRecommendation(items);
  }

  /// 按经纬度拉取附近酒吧（文档 4.5）：radiusMeters 限 1000~5000，limit 1~10000。
  ///
  /// [radiusMeters] 缺省时使用偏好设置里的全局搜索半径（上限 3km）。
  Future<List<SiponBarMapItem>> fetchNearbyBars({
    required double longitude,
    required double latitude,
    int? radiusMeters,
    int limit = 20,
  }) async {
    final json = await _apiClient.getJson(
      '/api/bars/nearby',
      queryParameters: {
        'longitude': longitude,
        'latitude': latitude,
        'radiusMeters':
            radiusMeters ?? SiponSearchPreferences.instance.radiusMeters,
        'hasImage': true,
        'limit': limit,
      },
    );
    final items = json is List
        ? json
        : json is Map && json['data'] is List
        ? json['data'] as List
        : const [];

    final bars = items
        .whereType<Map>()
        .map((item) => SiponBarMapItem.fromJson(item.cast<String, dynamic>()))
        .where((item) => item.hasCoordinates)
        // 同样在客户端严格过滤，避免附近推荐混入没有照片的酒吧。
        .where((item) => item.hasImage)
        .toList(growable: false);
    return SiponBarMapItem.sortForHomeRecommendation(bars);
  }

  Future<List<String>> fetchCities() async {
    final json = await _apiClient.getJson('/api/cities');
    final rawCities = switch (json) {
      List() => json,
      Map() =>
        json['data'] is List
            ? json['data'] as List
            : json['cities'] is List
            ? json['cities'] as List
            : const [],
      _ => const [],
    };

    return rawCities
        .map((city) => city.toString().trim())
        .where((city) => city.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }
}
