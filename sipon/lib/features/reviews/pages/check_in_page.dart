import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../map/widgets/checkin_pin_icon.dart';
import '../../../app/theme/sipon_theme_colors.dart';
import '../../map/models/map_display_options.dart';
import '../../map/models/map_models.dart';
import '../../map/controllers/map_scene_controller.dart';
import '../../map/models/map_viewport.dart';
import '../../map/platform/sipon_map_host.dart';
import '../../map/widgets/sipon_map_widget.dart';
import '../../../shared/services/sipon_api_client.dart';
import '../../../shared/services/sipon_api_service.dart';
import '../../../shared/services/sipon_city_controller.dart';
import '../../../shared/services/sipon_region_data.dart';
import '../../../shared/services/sipon_search_preferences.dart';
import '../../map/pages/venue_detail_page.dart';
import '../widgets/review_composer.dart';
import '../../../shared/widgets/sipon_city_picker.dart';

/// 一级入口以底部弹窗展示，二级的记录页面仍然通过路由全屏打开。
class CheckInPage extends StatefulWidget {
  const CheckInPage({super.key, this.apiService});

  final SiponApiService? apiService;

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  late final SiponApiService _api;

  /// 附近酒吧每页条数。
  static const int _nearbyPageSize = 20;

  /// 地图和附近推荐共用本次获取的设备定位。
  List<_NearbyBar> _bars = [];
  SiponCityController? _cityController;
  SiponLocationPoint? _loadedAnchor;
  String? _locationError;
  int _requestVersion = 0;

  /// 首屏是否还在加载（展示「正在加载附近酒吧…」）。
  bool _loadingBars = true;

  /// 附近酒吧列表的滚动控制器。
  final ScrollController _barsController = ScrollController();
  final TextEditingController _barSearchController = TextEditingController();
  Timer? _barSearchDebounce;
  int _barSearchVersion = 0;
  List<_BarSearchResult> _barSearchResults = const [];
  bool _searchingBars = false;
  bool _barSearchFailed = false;

  late final MapSceneController _scene;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? SiponApiService();
    _scene = MapSceneController.create(
      onViewportSettled: (_) {},
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
    // 偏好设置里调整搜索半径后，即时按新半径重新拉取附近酒吧。
    SiponSearchPreferences.instance.addListener(_handleRadiusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = SiponCityScope.controllerOf(context);
    if (_cityController != controller) {
      _cityController = controller;
      _loadNearbyBars();
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    SiponSearchPreferences.instance.removeListener(_handleRadiusChanged);
    _barsController.dispose();
    _barSearchDebounce?.cancel();
    _barSearchController.dispose();
    _scene.detach();
    super.dispose();
  }

  void _handleRadiusChanged() {
    if (!mounted) return;
    _loadNearbyBars();
  }

  /// 打卡页不等定位：打开即用城市锚点（或默认城市中心）开图，
  /// 真实定位结果就绪后再平移居中。
  MapLatLng get _initialMapCenter {
    final anchor = _cityController?.queryAnchor;
    if (anchor != null) {
      return MapLatLng(longitude: anchor.longitude, latitude: anchor.latitude);
    }
    final fallback = siponFindCity(SiponCityController.defaultCity);
    if (fallback != null) {
      return MapLatLng(
        longitude: fallback.longitude,
        latitude: fallback.latitude,
      );
    }
    return const MapLatLng(longitude: 121.4737, latitude: 31.2304);
  }

  void _onBarSearchChanged(String value) {
    _barSearchDebounce?.cancel();
    final version = ++_barSearchVersion;
    final keyword = value.trim();
    if (keyword.isEmpty) {
      setState(() {
        _barSearchResults = const [];
        _searchingBars = false;
        _barSearchFailed = false;
      });
      return;
    }
    setState(() {
      _searchingBars = true;
      _barSearchFailed = false;
    });
    _barSearchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final matches = await _api.searchBars(
          city: _cityController?.city,
          keyword: keyword,
          page: const SiponPage(limit: 20),
        );
        if (!mounted || version != _barSearchVersion) return;
        setState(() {
          _barSearchResults = matches
              .whereType<Map>()
              .map(
                (item) =>
                    _BarSearchResult.tryParse(item.cast<String, dynamic>()),
              )
              .whereType<_BarSearchResult>()
              .toList(growable: false);
          _searchingBars = false;
        });
      } on Exception {
        if (!mounted || version != _barSearchVersion) return;
        setState(() {
          _barSearchResults = const [];
          _searchingBars = false;
          _barSearchFailed = true;
        });
      }
    });
  }

  /// 每次打开或重试获取实际定位，以同一坐标查询偏好半径内的酒吧。
  Future<void> _loadNearbyBars() async {
    final version = ++_requestVersion;
    setState(() {
      _loadingBars = true;
      _locationError = null;
    });
    final location = await _cityController?.locateCurrentCity(
      purpose: SiponLocationPurpose.checkIn,
    );
    if (!mounted || version != _requestVersion) return;
    final anchor = location?.position;
    if (anchor == null) {
      setState(() {
        _loadingBars = false;
        _locationError = switch (location?.status) {
          SiponLocateStatus.serviceDisabled => '请开启系统定位服务后重试',
          SiponLocateStatus.permissionDenied => '需要定位权限，才能推荐你附近的酒吧',
          SiponLocateStatus.permissionDeniedForever => '请在系统设置中允许 SipOn 使用定位',
          _ => '暂时无法获取当前位置，请重试',
        };
      });
      return;
    }
    final anchorChanged = _loadedAnchor != anchor;
    setState(() => _loadedAnchor = anchor);
    if (_scene.isAttached && anchorChanged) {
      await _scene.centerOnUser(
        longitude: anchor.longitude,
        latitude: anchor.latitude,
      );
    }
    if (!mounted || version != _requestVersion) return;
    try {
      final list = await _api.getNearbyBars(
        longitude: anchor.longitude,
        latitude: anchor.latitude,
        radiusMeters: SiponSearchPreferences.instance.radiusMeters,
        limit: _nearbyPageSize,
      );
      final parsed = [
        for (final item in list.whereType<Map>())
          _NearbyBar.tryParse(item.cast<String, dynamic>()),
      ].whereType<_NearbyBar>().toList();
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _bars = parsed;
        _loadingBars = false;
      });
      await _renderBars();
    } on Exception {
      if (mounted && version == _requestVersion) {
        setState(() {
          _loadingBars = false;
          _bars = [];
        });
      }
    }
  }

  Future<void> _handleMapCreated(SiponMapHost host) async {
    if (!mounted) return;
    // 定位先于建图完成时直接用真实位置开图；否则用城市锚点，由
    // _loadNearbyBars 在定位成功后居中。
    final anchor = _loadedAnchor;
    await _scene.attach(
      host,
      city: _cityController?.city ?? SiponCityController.defaultCity,
      style: MapBaseStyle.standard,
      initialCenter: anchor != null
          ? MapLatLng(longitude: anchor.longitude, latitude: anchor.latitude)
          : _initialMapCenter,
    );
    if (!mounted) return;
    await _renderBars();
  }

  /// 把当前酒吧列表下发到地图图层。
  Future<void> _renderBars() async {
    if (!_scene.isAttached) return;
    await _scene.render(
      MapSceneFrame(
        circlePoints: [
          for (final bar in _bars)
            MapPoint(
              id: 'check-in-${bar.name}',
              name: bar.name,
              longitude: bar.longitude,
              latitude: bar.latitude,
              kind: bar.kind,
              weight: 1,
              // 打卡页不区分酒吧分类，统一用红色图钉浮标。
              iconCategory: checkInPinCategory,
            ),
        ],
        markers: [
          for (final bar in _bars)
            MapMarkerSpec(
              venueId: bar.name,
              label: bar.name,
              longitude: bar.longitude,
              latitude: bar.latitude,
              kind: bar.kind,
              iconCategory: checkInPinCategory,
            ),
        ],
      ),
    );
  }

  Widget _buildBarSearchResults(ColorScheme scheme) {
    return Material(
      color: context.siponColors.elevatedSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Text(
                  '搜索结果',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  _searchingBars
                      ? '正在搜索…'
                      : _barSearchFailed
                      ? '搜索失败，请重试'
                      : '${_barSearchResults.length} 家可打卡',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: _searchingBars
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _barSearchFailed
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextButton(
                      onPressed: () =>
                          _onBarSearchChanged(_barSearchController.text),
                      child: const Text('重试搜索'),
                    ),
                  )
                : _barSearchResults.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('没有找到匹配的酒吧'),
                  )
                : ListView.builder(
                    primary: false,
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _barSearchResults.length,
                    itemBuilder: (context, index) => _BarSearchResultTile(
                      bar: _barSearchResults[index],
                      brand: scheme.primary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    final scheme = Theme.of(context).colorScheme;
    final surface = context.siponColors.elevatedSurface;
    return Material(
      // 打卡面板是底部弹层，用主题浮层表面色（浅色下为白色）。
      color: surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              SizedBox(
                height: height * 0.28 + 84,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SiponMapWidget(
                      initialStyleId: MapBaseStyle.standard.id,
                      onHostReady: _handleMapCreated,
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 120,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                surface,
                                surface.withValues(alpha: 0.9),
                                surface.withValues(alpha: 0),
                              ],
                              stops: const [0, .45, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.35,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '打卡酒吧',
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                  tooltip: '关闭',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 定位失败时在地图上方提示；地图已用城市锚点打开，不整块遮挡。
                    if (_locationError != null)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 16,
                        child: Material(
                          color: context.siponColors.elevatedSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: scheme.outlineVariant),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _locationError!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 14,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _loadNearbyBars,
                                  child: const Text('重新定位'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // 结果浮层从搜索框上方展开，覆盖地图并独立滚动。
                    if (_barSearchController.text.trim().isNotEmpty)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 84, 18, 0),
                          child: _buildBarSearchResults(scheme),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: TextField(
                  controller: _barSearchController,
                  onChanged: _onBarSearchChanged,
                  decoration: InputDecoration(
                    hintText: '搜索当前城市的酒吧',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _barSearchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _barSearchController.clear();
                              _onBarSearchChanged('');
                            },
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: context.siponColors.subtleSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Row(
                  children: [
                    Text(
                      '你附近的酒吧',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _loadingBars
                          ? '正在加载附近酒吧…'
                          : _locationError != null
                          ? '等待定位'
                          : '${_bars.length} 家可打卡',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _barsController,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  itemCount: _bars.length,
                  itemBuilder: (context, index) =>
                      _NearbyBarTile(bar: _bars[index], brand: scheme.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarSearchResult {
  const _BarSearchResult({
    required this.id,
    required this.name,
    required this.address,
  });

  final int id;
  final String name;
  final String address;

  static _BarSearchResult? tryParse(Map<String, dynamic> map) {
    final rawId = map['id'] ?? map['barId'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    final name = (map['name'] ?? map['barName'])?.toString().trim();
    if (id == null || name == null || name.isEmpty) return null;
    return _BarSearchResult(
      id: id,
      name: name,
      address: map['address']?.toString().trim() ?? '',
    );
  }
}

class _BarSearchResultTile extends StatelessWidget {
  const _BarSearchResultTile({required this.bar, required this.brand});

  final _BarSearchResult bar;
  final Color brand;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(bar.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: bar.address.isEmpty
        ? null
        : Text(bar.address, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: FilledButton(
      style: FilledButton.styleFrom(backgroundColor: brand),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CheckInCommentPage(
            barId: bar.id,
            venueName: bar.name,
            venueAddress: bar.address,
          ),
        ),
      ),
      child: const Text('打卡'),
    ),
  );
}

class _NearbyBar {
  const _NearbyBar(
    this.name,
    this.address,
    this.distance,
    this.rating,
    this.longitude,
    this.latitude,
    this.kind,
    this.checkedIn, {
    this.barId,
  });

  final String name;
  final String address;
  final String distance;
  final double rating;
  final double longitude;
  final double latitude;
  final MapVenueKind kind;
  final bool checkedIn;

  /// 后端酒吧 id；为 null 的是演示数据，不能真正提交打卡。
  final int? barId;

  /// 从 getNearbyBars 响应解析；缺关键字段（id/名称/坐标）时返回 null。
  static _NearbyBar? tryParse(Map<String, dynamic> map) {
    final id = (map['id'] as num?)?.toInt() ?? (map['barId'] as num?)?.toInt();
    final name = map['name']?.toString().trim();
    final longitude = (map['longitude'] as num?)?.toDouble();
    final latitude = (map['latitude'] as num?)?.toDouble();
    if (id == null || name == null || name.isEmpty) {
      return null;
    }
    if (longitude == null || latitude == null) {
      return null;
    }
    final meters = (map['distanceMeters'] as num?)?.toDouble();
    return _NearbyBar(
      name,
      map['address']?.toString() ?? '',
      meters == null
          ? ''
          : meters >= 1000
          ? '约${(meters / 1000).toStringAsFixed(1)}km'
          : '约${meters.round()}m',
      (map['averageRating'] as num?)?.toDouble() ??
          (map['rating'] as num?)?.toDouble() ??
          0,
      longitude,
      latitude,
      MapVenueKind.fromRaw(
        map['barSubtype']?.toString() ?? map['subtype']?.toString(),
      ),
      false,
      barId: id,
    );
  }

  MapVenue get venue => MapVenue(
    id: barId?.toString() ?? name,
    name: name,
    longitude: longitude,
    latitude: latitude,
    kind: kind,
    rating: rating,
    address: address,
    distance: distance,
    tags: const [],
    imageAsset: switch (name) {
      '庙前冰室（Hope & Sesame）' => MapAssets.barImage,
      'Speak Low（彼楼）' => MapAssets.speakLowImage,
      'Janes and Hooch' => MapAssets.janesImage,
      'Play House 电音夜店' => MapAssets.playHouseImage,
      _ => MapAssets.coverForIndex(0),
    },
  );
}

class _NearbyBarTile extends StatelessWidget {
  const _NearbyBarTile({required this.bar, required this.brand});

  final _NearbyBar bar;
  final Color brand;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 1, 8, 1),
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VenueDetailPage(venue: bar.venue),
        ),
      ),
      title: Text(
        bar.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('${bar.distance}  ·  ${bar.address}'),
      trailing: SizedBox(
        width: 76,
        height: 34,
        child: bar.checkedIn
            ? DecoratedBox(
                decoration: BoxDecoration(
                  // 已打卡：成功语义的弱底与文字成对出现。
                  color: context.siponColors.successSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '已打卡',
                    style: TextStyle(
                      color: context.siponColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            : FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CheckInCommentPage(
                      barId: bar.barId,
                      venueName: bar.name,
                      venueAddress: bar.address,
                    ),
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: brand,
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('打卡'),
              ),
      ),
    ),
  );
}

/// 打卡与地点评价共用的发布页。
class CheckInCommentPage extends StatefulWidget {
  const CheckInCommentPage({
    super.key,
    required this.barId,
    required this.venueName,
    required this.venueAddress,
    this.returnToVenue = false,
    this.apiService,
  });

  final int? barId;
  final String venueName;
  final String venueAddress;
  final bool returnToVenue;
  final SiponApiService? apiService;

  @override
  State<CheckInCommentPage> createState() => _CheckInCommentPageState();
}

class _CheckInCommentPageState extends State<CheckInCommentPage> {
  static const int _maxUploadBytes = 10 * 1024 * 1024;

  final _controller = TextEditingController();
  late final SiponApiService _api;
  final List<XFile> _images = <XFile>[];
  int _rating = 0;
  ReviewAspectRatings _aspectRatings = const ReviewAspectRatings();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? SiponApiService();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 逐张上传打卡图片（purpose=check_in），返回上传媒体 ID 列表。
  Future<List<String>> _uploadImages() async {
    final mediaIds = <String>[];
    for (final file in _images) {
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxUploadBytes) {
        throw Exception('图片超过 10MiB 限制，请更换图片');
      }
      final response = await _api.uploadMedia(
        fileBytes: bytes,
        filename: file.name,
        mimeType: _mimeTypeFor(file),
        purpose: 'check_in',
      );
      final mediaId = _extractMediaId(response);
      if (mediaId == null) {
        throw Exception('图片上传失败，请重试');
      }
      mediaIds.add(mediaId);
    }
    return mediaIds;
  }

  /// 从上传响应的多种字段名中尽力提取媒体 ID。
  String? _extractMediaId(dynamic response) {
    if (response is! Map) return null;
    final raw =
        response['id'] ??
        response['mediaId'] ??
        (response['data'] is Map ? response['data']['mediaId'] : null);
    final id = raw?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// 根据文件扩展名推断图片 MIME 类型，未知扩展名统一按 JPEG 处理。
  String _mimeTypeFor(XFile file) {
    final mime = file.mimeType?.trim();
    if (mime != null && mime.isNotEmpty) return mime;

    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic') || name.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  /// 提交打卡：先上传附图，再 POST /api/check-ins。
  Future<void> _submit() async {
    if (_rating == 0) {
      _showMessage('请先给这家酒吧评分');
      return;
    }
    final barId = widget.barId;
    if (barId == null) {
      _showMessage('该酒吧暂不支持打卡');
      return;
    }
    if (_submitting) return;

    setState(() => _submitting = true);
    FocusScope.of(context).unfocus();
    try {
      final ratingDetails = _aspectRatings.toPayload();
      final content = _aspectRatings.prependToContent(_controller.text);
      if (content.length > 2000) {
        _showMessage('评价内容不能超过 2000 字');
        return;
      }
      final mediaIds = await _uploadImages();
      final body = <String, Object?>{
        'barId': barId,
        'rating': _rating,
        if (content.isNotEmpty) 'content': content,
        'visibility': 'public',
        'visitedAt': DateTime.now().toUtc().toIso8601String(),
        if (mediaIds.isNotEmpty) 'mediaIds': mediaIds,
        ...ratingDetails,
      };
      try {
        await _api.createCheckIn(body);
      } on SiponApiException catch (error) {
        // Older servers may reject the new fields. The readable score summary
        // in content still preserves every selected rating on retry.
        if (ratingDetails.isEmpty ||
            (error.statusCode != 400 && error.statusCode != 422)) {
          rethrow;
        }
        for (final key in ratingDetails.keys) {
          body.remove(key);
        }
        await _api.createCheckIn(body);
      }
      if (!mounted) return;
      _showMessage('打卡已提交，审核通过后展示在动态中');
      if (widget.returnToVenue) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on Exception catch (error) {
      if (!mounted) return;
      _showMessage('打卡失败：$error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _submitDraft(ReviewDraft draft) async {
    _rating = draft.rating;
    _aspectRatings = draft.aspectRatings;
    _controller.text = draft.content;
    _images
      ..clear()
      ..addAll(draft.images);
    await _submit();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // 页面底沿用主题脚手架底色，与首页、个人页保持一致。
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    appBar: AppBar(
      title: const Text('微醺这一刻', style: TextStyle(fontWeight: FontWeight.w800)),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    body: ReviewComposer(
      venueName: widget.venueName,
      venueAddress: widget.venueAddress,
      submitLabel: '完成打卡',
      onSubmit: _submitDraft,
    ),
    // 说明：下方注释块为未参与构建的历史代码，其中浅色常量保持原样，
    // 不属于深色迁移范围，故不对其做主题替换。
    /* Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.bar.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF252229),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.bar.address,
            style: const TextStyle(color: Color(0xFF8F8790)),
          ),
          const SizedBox(height: 28),
          const Text('本次体验', style: TextStyle(fontWeight: FontWeight.w700)),
          Row(
            children: [
              for (var index = 1; index <= 5; index++)
                IconButton(
                  onPressed: () => setState(() => _rating = index),
                  icon: Icon(
                    index <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: const Color(0xFFE09A35),
                    size: 30,
                  ),
                  tooltip: '$index 星',
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '写下这次的酒、音乐或遇见的人...',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
                borderSide: BorderSide(color: Color(0xFFF0E9ED)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var index = 0; index < _images.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: FutureBuilder<List<int>>(
                            future: _images[index].readAsBytes(),
                            builder: (context, snapshot) {
                              final bytes = snapshot.data;
                              if (bytes == null) {
                                return Container(
                                  width: 76,
                                  height: 76,
                                  color: const Color(0xFFF0E9ED),
                                );
                              }
                              return Image.memory(
                                Uint8List.fromList(bytes),
                                width: 76,
                                height: 76,
                                fit: BoxFit.cover,
                              );
                            },
                          ),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: IconButton(
                            onPressed: () =>
                                setState(() => _images.removeAt(index)),
                            icon: const Icon(Icons.cancel_rounded, size: 20),
                            color: const Color(0xFF9A3D78),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 24,
                              height: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_images.length < _maxImages)
                  InkWell(
                    onTap: _pickImage,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFF0E9ED)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: Color(0xFF9A3D78),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_submitting ? '打卡中…' : '完成打卡'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF9A3D78),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    ), */
  );
}
