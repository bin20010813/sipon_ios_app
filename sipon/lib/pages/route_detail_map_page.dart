import 'package:flutter/material.dart';

import '../services/map/map_display_options.dart';
import '../services/map/map_models.dart';
import '../services/map/map_scene_controller.dart';
import '../services/map/map_viewport.dart';
import '../services/map/sipon_map_host.dart';
import '../services/map/sipon_map_widget.dart';
import '../services/sipon_api_service.dart';

/// 路线里的一个站点（酒吧）简况。坐标为 null 时详情页会尝试按 id 补齐。
class RouteStop {
  const RouteStop({
    this.id,
    required this.name,
    this.address,
    this.longitude,
    this.latitude,
    this.city,
    this.kind = MapVenueKind.pub,
    this.rating,
  });

  final int? id;
  final String name;
  final String? address;
  final double? longitude;
  final double? latitude;
  final String? city;
  final MapVenueKind kind;
  final double? rating;
}

/// 从 map 里按候选键读取非空字符串。
String? _pickString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

/// 从 map 里按候选键读取数字。
num? _pickNum(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value;
    if (value is String) {
      final parsed = num.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

double? _pickRating(Map<String, dynamic>? map) {
  if (map == null) return null;
  final value = _pickNum(map, const [
    'averageRating',
    'average_rating',
    'rating',
    'score',
    'star',
  ])?.toDouble();
  return value != null && value.isFinite && value > 0 ? value : null;
}

/// 从 map 里按候选键读取第一个非空列表（用于站点解析时优先真实数据）。
List<dynamic>? _pickNonEmptyList(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is List && value.isNotEmpty) return value;
  }
  return null;
}

/// 从 map 里按候选键读取第一个嵌套 Map（站点里常见 bar/barInfo 等对象）。
Map<String, dynamic>? _pickMapOf(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is Map) return value.cast<String, dynamic>();
  }
  return null;
}

/// 读取坐标数值：优先平铺 longitude/lng/lon、latitude/lat；
/// 兼容嵌套 coordinate/center/location 对象，以及 GeoJSON 的
/// coordinates: [lng, lat]（含 geometry.coordinates）。与地图层的
/// _readCoordinates 解析口径保持一致，避免站点因坐标形态不同而
/// 解析失败，导致路线地图无法定位到站点位置。
double? _pickCoordinate(Map<String, dynamic>? map, {required bool longitude}) {
  if (map == null) return null;
  final keys = longitude
      ? const ['longitude', 'lng', 'lon']
      : const ['latitude', 'lat'];
  final direct = _pickNum(map, keys)?.toDouble();
  if (direct != null) return direct;

  // 嵌套坐标对象：coordinate / center / location。
  for (final key in const ['coordinate', 'center', 'location']) {
    final nested = map[key];
    if (nested is Map) {
      final value = _pickNum(nested.cast<String, dynamic>(), keys)?.toDouble();
      if (value != null) return value;
    }
  }

  // GeoJSON：coordinates: [lng, lat] 或 geometry: {coordinates: [...]}。
  final geometry = _pickMapOf(map, ['geometry']);
  for (final holder in [map, ?geometry]) {
    final raw = holder['coordinates'];
    if (raw is List && raw.length >= 2) {
      final value = _pickNum(
        {'v': raw[longitude ? 0 : 1]},
        const ['v'],
      )?.toDouble();
      if (value != null) return value;
    }
  }
  return null;
}

/// 解析路线站点列表：优先接口契约里的 stops（酒吧对象数组），
/// 兜底 barIds（纯 id 数组）/bars（对象数组），无法识别时生成占位名。
/// 站点可能是完整 Bar 对象，也可能是 {bar: {...}} 等嵌套结构。
List<RouteStop> parseRouteStops(Map<String, dynamic> map) {
  final raw = _pickNonEmptyList(map, ['stops', 'barIds', 'bars']);
  if (raw == null) return const [];
  final stops = <RouteStop>[];
  for (final stop in raw) {
    if (stop is Map) {
      final stopMap = stop.cast<String, dynamic>();
      // 站点嵌套结构：优先取内层真正的酒吧对象。
      final nested = _pickMapOf(stopMap, ['bar', 'barInfo', 'venue', 'place']);
      const empty = <String, dynamic>{};
      final id =
          (_pickNum(stopMap, ['barId']) ??
                  _pickNum(nested ?? empty, ['id', 'barId']) ??
                  _pickNum(stopMap, ['id']))
              ?.toInt();
      final name =
          _pickString(stopMap, ['name', 'barName', 'title', 'barTitle']) ??
          _pickString(nested ?? empty, ['name', 'barName', 'title']);
      stops.add(
        RouteStop(
          id: id,
          name: name ?? (id != null ? '酒吧 #$id' : '未知酒吧'),
          address:
              _pickString(stopMap, ['address']) ??
              _pickString(nested ?? empty, ['address']),
          longitude:
              _pickCoordinate(stopMap, longitude: true) ??
              _pickCoordinate(nested, longitude: true),
          latitude:
              _pickCoordinate(stopMap, longitude: false) ??
              _pickCoordinate(nested, longitude: false),
          city:
              _pickString(stopMap, ['city']) ??
              _pickString(nested ?? empty, ['city']),
          kind: MapVenueKind.fromRaw(
            _pickString(stopMap, ['barSubtype', 'subtype']) ??
                _pickString(nested ?? empty, ['barSubtype', 'subtype']),
          ),
          rating: _pickRating(stopMap) ?? _pickRating(nested),
        ),
      );
    } else if (stop is num) {
      stops.add(RouteStop(id: stop.toInt(), name: '酒吧 #${stop.toInt()}'));
    }
  }
  return stops;
}

/// 路线详情地图页：把站点按顺序渲染到地图上、规划并绘制路线，底部面板逐站列出。
/// 数据来自 GET /api/routes/{id}；缺坐标的站点会按 id 再拉 /api/bars/{id} 补齐。
class RouteDetailMapPage extends StatefulWidget {
  static const Color brand = Color(0xFF9A3D78);
  static const Color ink = Color(0xFF292B32);
  static const Color muted = Color(0xFF8E8790);

  const RouteDetailMapPage({
    super.key,
    required this.routeId,
    required this.title,
    this.subtitle = '',
    this.previewStops = const [],
  });

  final int routeId;
  final String title;
  final String subtitle;
  final List<RouteStop> previewStops;

  @override
  State<RouteDetailMapPage> createState() => _RouteDetailMapPageState();
}

class _RouteDetailMapPageState extends State<RouteDetailMapPage> {
  final SiponApiService _api = SiponApiService();
  late final MapSceneController _scene;

  List<RouteStop> _stops = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stops = widget.previewStops;
    _scene = MapSceneController.create(
      onViewportSettled: (_) {},
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
    _load();
  }

  @override
  void dispose() {
    _scene.detach();
    super.dispose();
  }

  /// 拉取路线详情并补齐缺坐标的站点；接口失败时退回列表页的预览站点。
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getDrinkingRoute(widget.routeId);
      if (!mounted) return;
      final resolved = data is Map
          ? parseRouteStops(data.cast<String, dynamic>())
          : const <RouteStop>[];
      final stops = await _fillMissingCoordinates(
        resolved.isEmpty ? widget.previewStops : resolved,
      );
      if (!mounted) return;
      setState(() {
        _stops = stops;
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      final stops = await _fillMissingCoordinates(widget.previewStops);
      if (!mounted) return;
      setState(() {
        _stops = stops;
        _error = stops.isEmpty ? error.toString() : null;
        _loading = false;
      });
    }
    await _renderStops();
  }

  /// 站点缺坐标时按 id 拉取酒吧详情补齐（只补一次，单项失败不中断）。
  Future<List<RouteStop>> _fillMissingCoordinates(List<RouteStop> stops) async {
    if (stops.isEmpty) return stops;
    final missing = stops
        .where(
          (stop) =>
              (stop.longitude == null || stop.latitude == null) &&
              stop.id != null,
        )
        .toList();
    if (missing.isEmpty) return stops;
    try {
      final details = await Future.wait([
        for (final stop in missing) _api.getBarById(stop.id!),
      ]);
      final byId = <int, Map<String, dynamic>>{};
      for (var index = 0; index < missing.length; index++) {
        final value = details[index];
        if (value is Map) {
          byId[missing[index].id!] = value.cast<String, dynamic>();
        }
      }
      return [for (final stop in stops) _mergeBarIntoStop(stop, byId[stop.id])];
    } on Exception {
      return stops;
    }
  }

  /// 把酒吧详情合并进站点：只补齐缺失的坐标/名称/地址。
  RouteStop _mergeBarIntoStop(RouteStop stop, Map<String, dynamic>? bar) {
    if (bar == null || (stop.longitude != null && stop.latitude != null)) {
      return stop;
    }
    return RouteStop(
      id: stop.id,
      name: _pickString(bar, ['name', 'barName', 'title']) ?? stop.name,
      address: _pickString(bar, ['address']) ?? stop.address,
      longitude: _pickCoordinate(bar, longitude: true) ?? stop.longitude,
      latitude: _pickCoordinate(bar, longitude: false) ?? stop.latitude,
      city: _pickString(bar, ['city']) ?? stop.city,
      kind: MapVenueKind.fromRaw(_pickString(bar, ['barSubtype', 'subtype'])),
      rating: stop.rating ?? _pickRating(bar),
    );
  }

  /// 地图宿主就绪：attach 后把当前站点渲染到地图。
  Future<void> _handleMapCreated(SiponMapHost host) async {
    await _scene.attach(host, city: _routeCity, style: MapBaseStyle.standard);
    await _renderStops();
  }

  /// 用于 attach 的城市：取第一个带 city 的站点，兜底上海。
  String get _routeCity {
    for (final stop in _stops) {
      final city = stop.city;
      if (city != null && city.isNotEmpty) {
        return city;
      }
    }
    return '上海';
  }

  /// 把站点以「白色评分胶囊 + 顺序编号 + 圆点」渲染到地图，并按
  /// 站点顺序请求原生多点连线。原生会先显示直连线，再尝试替换成道路路线，
  /// 并自动取景到整条路线。
  Future<void> _renderStops() async {
    if (!_scene.isAttached || _stops.isEmpty) return;
    final points = <MapPoint>[];
    final markers = <MapMarkerSpec>[];
    for (var index = 0; index < _stops.length; index++) {
      final stop = _stops[index];
      final longitude = stop.longitude;
      final latitude = stop.latitude;
      if (longitude == null || latitude == null) continue;
      final sequence = points.length + 1;
      points.add(
        MapPoint(
          id: 'route-stop-$index-${stop.id ?? index}',
          name: stop.name,
          longitude: longitude,
          latitude: latitude,
          kind: stop.kind,
          weight: 1,
          venueId: '${stop.id ?? index}',
        ),
      );
      markers.add(
        MapMarkerSpec(
          venueId: 'route-stop-$index',
          label: stop.name,
          longitude: longitude,
          latitude: latitude,
          kind: stop.kind,
          rating: stop.rating,
          sequence: sequence,
        ),
      );
    }
    if (points.isEmpty) return;
    await _scene.render(MapSceneFrame(circlePoints: points, markers: markers));

    // 详情页此前只下发 marker，因此即使站点已有坐标也不会有路线折线，
    // 地图仍停留在城市初始视野。这里复用规划页的 MapKit 路线能力；
    // 原生会先按站点顺序连线并取景；方向服务成功后再换成道路折线。
    if (points.length >= 2) {
      await _scene.planRoute(
        points: [
          for (final point in points)
            MapLatLng(longitude: point.longitude, latitude: point.latitude),
        ],
      );
    } else {
      // 只有一个有效站点时无法规划路线，仍将它置于可见区域中央。
      final point = points.single;
      await _scene.focusOn(
        longitude: point.longitude,
        latitude: point.latitude,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SiponMapWidget(
                      initialStyleId: MapBaseStyle.standard.id,
                      onHostReady: _handleMapCreated,
                    ),
                  ),
                  if (_loading && _stops.isEmpty)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x66FFFFFF),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: RouteDetailMapPage.brand,
                          ),
                        ),
                      ),
                    )
                  else if (_error != null && _stops.isEmpty)
                    Positioned.fill(
                      child: ColoredBox(
                        color: const Color(0x66FFFFFF),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF858991),
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('重试'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: RouteDetailMapPage.brand,
                                    side: const BorderSide(
                                      color: RouteDetailMapPage.brand,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _buildStopPanel(),
          ],
        ),
      ),
    );
  }

  /// 底部站点面板：头部摘要 + 按顺序的站点行，点击可在地图上聚焦。
  Widget _buildStopPanel() {
    if (_stops.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Center(
          child: Text(
            '这条路线还没有添加站点',
            style: const TextStyle(color: Color(0xFF858991), fontSize: 13),
          ),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 264),
      decoration: const BoxDecoration(color: Colors.white),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                Text(
                  '共 ${_stops.length} 个站点',
                  style: const TextStyle(
                    color: RouteDetailMapPage.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 10),
                if (widget.subtitle.isNotEmpty)
                  Expanded(
                    child: Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RouteDetailMapPage.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _stops.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => _RouteStopRow(
                index: index,
                stop: _stops[index],
                onTap: () {
                  final stop = _stops[index];
                  final longitude = stop.longitude;
                  final latitude = stop.latitude;
                  if (longitude == null || latitude == null) return;
                  if (_scene.isAttached) {
                    _scene.focusOn(longitude: longitude, latitude: latitude);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 路线详情里的单个站点行：序号圆点 + 酒吧名（含地址）。
class _RouteStopRow extends StatelessWidget {
  const _RouteStopRow({required this.index, required this.stop, this.onTap});

  final int index;
  final RouteStop stop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final address = stop.address ?? '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF8FA),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: index.isEven
                    ? const Color(0xFFFFE6B8)
                    : const Color(0xFFDDE5FF),
                shape: BoxShape.circle,
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: RouteDetailMapPage.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RouteDetailMapPage.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8E8790),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.local_bar_rounded,
              size: 20,
              color: RouteDetailMapPage.brand,
            ),
          ],
        ),
      ),
    );
  }
}
