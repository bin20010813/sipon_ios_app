import 'sipon_api_client.dart';
import 'sipon_region_data.dart';

/// 城市选择器用的一行城市选项。
class SiponCityOption {
  const SiponCityOption({
    required this.city,
    required this.cityEn,
    required this.province,
    required this.provinceEn,
    required this.longitude,
    required this.latitude,
  });

  final String city;
  final String cityEn;
  final String province;
  final String provinceEn;
  final double longitude;
  final double latitude;

  /// 按当前语言取展示名，无需再走 `SiponAppText.t` 的正则分支。
  String displayName(bool isZh) => isZh ? city : cityEn;
}

/// 城市选择器左侧一栏：一个省级分组。
class SiponProvinceGroup {
  const SiponProvinceGroup({
    required this.province,
    required this.provinceEn,
    required this.cities,
  });

  final String province;
  final String provinceEn;
  final List<SiponCityOption> cities;

  String displayName(bool isZh) => isZh ? province : provinceEn;
}

/// 省市数据的组装层：内置全量表打底，后端接口做增强。
///
/// - 层级结构永远有兜底：即使断网 / 接口异常，也能展示全国省市。
/// - `GET /api/cities`（需登录）返回的城市如果不在内置表中，会被收进
///   “热门城市”分组，保证后端有酒吧数据的城市一定可选。
/// - `GET /api/regions`（公开接口）如果返回了坐标，会按名称匹配覆盖内置
///   概略坐标；解析失败时静默忽略，不影响选择器展示。
class SiponRegionRepository {
  SiponRegionRepository({SiponApiClient? apiClient})
    : _apiClient = apiClient ?? SiponApiClient();

  static final SiponRegionRepository instance = SiponRegionRepository();

  final SiponApiClient _apiClient;

  List<SiponProvinceGroup>? _cache;

  Future<List<SiponProvinceGroup>> loadGroups({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) {
      return _cache!;
    }

    var coordinateOverrides = const <String, _LngLat>{};
    try {
      coordinateOverrides = await _fetchRegionCoordinates();
    } catch (_) {
      coordinateOverrides = const <String, _LngLat>{};
    }

    var backendCities = const <String>[];
    try {
      backendCities = await _fetchBackendCities();
    } catch (_) {
      backendCities = const <String>[];
    }

    final groups = _buildGroups(coordinateOverrides, backendCities);
    _cache = groups;
    return groups;
  }

  List<SiponProvinceGroup> _buildGroups(
    Map<String, _LngLat> coordinateOverrides,
    List<String> backendCities,
  ) {
    SiponCityOption toOption(
      SiponCityEntry entry,
      String provinceName,
      String provinceEn,
    ) {
      final override = _matchOverride(entry.name, coordinateOverrides);
      return SiponCityOption(
        city: entry.name,
        cityEn: entry.nameEn,
        province: provinceName,
        provinceEn: provinceEn,
        longitude: override?.longitude ?? entry.longitude,
        latitude: override?.latitude ?? entry.latitude,
      );
    }

    final knownNames = <String>{};
    final groups = <SiponProvinceGroup>[
      for (final province in siponProvinces)
        SiponProvinceGroup(
          province: province.name,
          provinceEn: province.nameEn,
          cities: [
            for (final city in province.cities)
              () {
                knownNames.add(city.name);
                return toOption(city, province.name, province.nameEn);
              }(),
          ],
        ),
    ];

    // 后端有酒吧数据的城市优先曝光：未知城市收进“热门城市”分组。
    final hotCities = <SiponCityOption>[];
    for (final name in siponHotCityNames) {
      final entry = siponFindCity(name);
      if (entry == null) {
        continue;
      }
      knownNames.add(entry.name);
      final provName = siponFindProvinceOfCity(entry.name) ?? '';
      final provEn = siponProvinceEnOfCity(entry.name) ?? provName;
      hotCities.add(toOption(entry, provName, provEn));
    }
    for (final backendCity in backendCities) {
      final normalized = backendCity.trim();
      if (normalized.isEmpty) {
        continue;
      }
      final entry = siponFindCity(normalized);
      if (entry != null) {
        // 接口使用“广州市”这类全称，本地使用“广州”这类简称。
        // 必须按内置城市的规范名去重，避免同一城市重复进入热门列表。
        if (!knownNames.add(entry.name)) {
          continue;
        }
        final provName = siponFindProvinceOfCity(entry.name) ?? '';
        final provEn = siponProvinceEnOfCity(entry.name) ?? provName;
        hotCities.add(toOption(entry, provName, provEn));
        continue;
      }
      if (!knownNames.add(normalized)) {
        continue;
      }
      // 完全未知城市：无坐标，相机落点用省会兜底意义不大，直接用北京坐标
      // 占位并仍然可点，酒吧列表接口按 city 过滤不受坐标影响。
      hotCities.add(
        SiponCityOption(
          city: normalized,
          cityEn: normalized,
          province: '',
          provinceEn: '',
          longitude: 116.41,
          latitude: 39.90,
        ),
      );
    }

    if (hotCities.isNotEmpty) {
      groups.insert(
        0,
        SiponProvinceGroup(
          province: '热门城市',
          provinceEn: 'Hot Cities',
          cities: hotCities,
        ),
      );
    }
    return groups;
  }

  Future<List<String>> _fetchBackendCities() async {
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
        .toList(growable: false);
  }

  /// 拉取行政区划坐标：只取名称与经纬度做覆盖，不重组层级。
  ///
  /// 后端返回格式可能为列表或 `{data/items/list: [...]}` 包裹，条目字段名
  /// 可能为 name/code/parentCode + longitude/latitude（或 lng/lat），这里
  /// 全部做兼容解析。
  Future<Map<String, _LngLat>> _fetchRegionCoordinates() async {
    final json = await _apiClient.getJson(
      '/api/regions',
      queryParameters: const {'limit': 500, 'offset': 0},
    );
    final rawItems = switch (json) {
      List() => json,
      Map() =>
        json['data'] is List
            ? json['data'] as List
            : json['items'] is List
            ? json['items'] as List
            : json['list'] is List
            ? json['list'] as List
            : const [],
      _ => const [],
    };

    final overrides = <String, _LngLat>{};
    for (final item in rawItems) {
      if (item is! Map) {
        continue;
      }
      final map = item.cast<String, dynamic>();
      final name = (map['name'] ?? map['regionName'] ?? '').toString().trim();
      final longitude = _toDouble(map['longitude'] ?? map['lng']);
      final latitude = _toDouble(map['latitude'] ?? map['lat']);
      if (name.isEmpty || longitude == null || latitude == null) {
        continue;
      }
      if (!longitude.isFinite || !latitude.isFinite) {
        continue;
      }
      overrides[name] = _LngLat(longitude, latitude);
    }
    return overrides;
  }

  _LngLat? _matchOverride(
    String shortName,
    Map<String, _LngLat> overrides,
  ) {
    if (overrides.isEmpty) {
      return null;
    }
    // 后端 region 名可能是“上海市”全称，内置是“上海”简称：双向匹配。
    for (final entry in overrides.entries) {
      final backendName = entry.key;
      if (backendName == shortName ||
          backendName.startsWith(shortName) ||
          shortName.startsWith(backendName)) {
        return entry.value;
      }
    }
    return null;
  }

  double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }
}

class _LngLat {
  const _LngLat(this.longitude, this.latitude);

  final double longitude;
  final double latitude;
}
