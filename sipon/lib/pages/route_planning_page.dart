import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/map/map_display_options.dart';
import '../services/map/map_models.dart';
import '../services/map/map_scene_controller.dart';
import '../services/map/map_viewport.dart';
import '../services/map/sipon_map_host.dart';
import '../services/map/sipon_map_widget.dart';
import '../services/sipon_api_service.dart';
import '../services/sipon_city_controller.dart';
import '../widgets/sipon_city_picker.dart';

class RoutePlanningPage extends StatefulWidget {
  const RoutePlanningPage({super.key});

  @override
  State<RoutePlanningPage> createState() => _RoutePlanningPageState();
}

class _RoutePlanningPageState extends State<RoutePlanningPage> {
  static const _brand = Color(0xFF9A3D78);
  static const _ink = Color(0xFF252229);
  static const _muted = Color(0xFF8F8790);
  static const _maxStops = 8;

  final SiponApiService _api = SiponApiService();

  List<_BarPlace> _nearbyBars = [];
  SiponCityController? _cityController;
  String? _loadedCity;
  SiponLocationPoint? _loadedAnchor;
  int _requestVersion = 0;

  _BarPlace? _start;
  _BarPlace? _end;
  final List<_BarPlace?> _stops = [];
  bool _showRemoveActions = false;
  bool _saving = false;

  /// 站点编辑区的滚动控制器；供 Scrollbar 滑块联动。
  final ScrollController _routeListController = ScrollController();
  late final MapSceneController _scene;

  @override
  void initState() {
    super.initState();
    _scene = MapSceneController.create(
      onViewportSettled: (_) {},
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = SiponCityScope.controllerOf(context);
    if (_cityController != controller) {
      _cityController?.removeListener(_handleCityChanged);
      _cityController = controller..addListener(_handleCityChanged);
    }
    _handleCityChanged();
  }

  void _handleCityChanged() {
    final city = _cityController?.city;
    final anchor = _cityController?.queryAnchor;
    if (city == null || (city == _loadedCity && anchor == _loadedAnchor)) {
      return;
    }
    final wasLoaded = _loadedCity != null;
    _loadedCity = city;
    _loadedAnchor = anchor;
    _nearbyBars = [];
    if (wasLoaded) {
      _start = null;
      _end = null;
      _stops.clear();
    }
    if (wasLoaded && mounted) setState(() {});
    _loadNearbyBars();
    if (_scene.isAttached && anchor != null) {
      _scene.flyToCity(city, zoom: MapSceneController.cityZoom);
      _renderMap();
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    _cityController?.removeListener(_handleCityChanged);
    _routeRevision++;
    _scene.detach();
    _routeListController.dispose();
    super.dispose();
  }

  /// 拉取附近真实酒吧作为可选项；失败时保持空列表。
  Future<void> _loadNearbyBars() async {
    final version = ++_requestVersion;
    final anchor = await _cityController?.resolveQueryAnchor();
    if (!mounted || version != _requestVersion || anchor == null) return;
    if (_scene.isAttached && _cityController?.queryAnchor == null) {
      await _scene.focusOn(
        longitude: anchor.longitude,
        latitude: anchor.latitude,
      );
    }
    try {
      final list = await _api.getNearbyBars(
        longitude: anchor.longitude,
        latitude: anchor.latitude,
        radiusMeters: 5000,
      );
      final parsed = [
        for (final item in list.whereType<Map>())
          _BarPlace.tryParse(item.cast<String, dynamic>()),
      ].whereType<_BarPlace>().toList();
      if (!mounted || version != _requestVersion) return;
      setState(() => _nearbyBars = parsed);
    } on Exception {
      // 查询失败时保持空列表，避免其他城市展示上海演示酒吧。
    }
  }

  Future<void> _handleMapCreated(SiponMapHost host) async {
    await _scene.attach(
      host,
      city: _cityController?.city ?? SiponCityController.defaultCity,
      style: MapBaseStyle.standard,
    );
    await _renderMap();
  }

  Future<void> _renderMap() async {
    if (!_scene.isAttached) return;
    final places = [_start, ..._stops, _end].whereType<_BarPlace>().toList();
    await _scene.render(
      MapSceneFrame(
        circlePoints: [
          for (var index = 0; index < places.length; index++)
            MapPoint(
              id: 'route-point-$index-${places[index].name}',
              name: places[index].name,
              longitude: places[index].longitude,
              latitude: places[index].latitude,
              kind: places[index].kind,
              weight: 1,
            ),
        ],
        markers: [
          for (var index = 0; index < places.length; index++)
            MapMarkerSpec(
              venueId:
                  'route-point-$index-${places[index].barId ?? places[index].name}',
              label: places[index].name,
              longitude: places[index].longitude,
              latitude: places[index].latitude,
              kind: places[index].kind,
              rating: places[index].rating,
              sequence: index + 1,
            ),
        ],
      ),
    );
  }

  void _select(_RouteStopType type, _BarPlace selected, {int? stopIndex}) {
    _invalidatePlanning();
    setState(() {
      switch (type) {
        case _RouteStopType.start:
          _start = selected;
        case _RouteStopType.stop:
          _stops[stopIndex!] = selected;
        case _RouteStopType.end:
          _end = selected;
      }
    });
    unawaited(_renderMap());
  }

  List<_BarPlace?> get _routeItems => [_start, ..._stops, _end];

  /// ReorderableListView 的 [newIndex] 是移除旧项前的位置；向后拖动时先减一，
  /// 才是移除后的真实插入下标。站点列表与地图 marker/路线顺序共用此结果。
  void _reorderRoute(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    _invalidatePlanning();
    final items = _routeItems;
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    setState(() {
      _start = items.first;
      _end = items.last;
      _stops
        ..clear()
        ..addAll(items.sublist(1, items.length - 1));
    });
    unawaited(_renderMap());
  }

  void _removeRouteItem(int index) {
    _invalidatePlanning();
    final items = _routeItems..removeAt(index);
    if (items.length == 1) {
      if (index == 0) {
        items.insert(0, null);
      } else {
        items.add(null);
      }
    }
    setState(() {
      _start = items.first;
      _end = items.last;
      _stops
        ..clear()
        ..addAll(items.sublist(1, items.length - 1));
      _showRemoveActions = _stops.isNotEmpty;
    });
    unawaited(_renderMap());
  }

  Set<_BarPlace> get _usedPlaces =>
      {_start, _end, ..._stops}.whereType<_BarPlace>().toSet();

  /// 是否已完成路径规划：规划成功前不允许保存为我的路线。
  bool _planned = false;
  bool _planning = false;

  /// 路线版本号：站点或顺序变更、退出页面都递增，旧规划结果据此作废。
  int _routeRevision = 0;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 站点编排变更后清除已规划的路线，必须重新规划才能保存。
  ///
  /// 不管之前是否已规划成功都要作废：首次规划尚未完成时 `_planned` 仍为 false，
  /// 但旧的在途请求必须作废，否则旧结果会把新站点保存状态置为可用。
  void _invalidatePlanning() {
    _routeRevision++;
    _scene.clearRoute();

    if (!mounted) return;
    setState(() {
      _planned = false;
      _planning = false;
    });
  }

  /// 点击「出发」：按已选站点顺序绘制原生多点折线，再尝试用 MKDirections
  /// 的道路路线替换；折线显示成功后允许保存为我的路线。
  Future<void> _planRoute() async {
    if (_planning) return;
    if (!_scene.isAttached) {
      _showMessage('地图还没准备好，请稍后再试');
      return;
    }

    final places = _routeItems.whereType<_BarPlace>().toList(growable: false);
    if (_start == null || _end == null || places.length < 2) {
      _showMessage('请先选择起点和终点酒吧');
      return;
    }

    final revision = ++_routeRevision;
    final points = [
      for (final place in places)
        MapLatLng(longitude: place.longitude, latitude: place.latitude),
    ];

    setState(() {
      _planning = true;
      _planned = false;
    });

    try {
      final ok = await _scene.planRoute(points: points);
      if (!mounted || revision != _routeRevision) return;

      setState(() => _planned = ok);
      _showMessage(ok ? '路线已规划，可以保存为我的路线了' : '路径规划失败，请检查站点或稍后重试');
      if (ok) {
        // 折线绘制后再重画一次点位，保证编号 marker 落在折线上层。
        unawaited(_renderMap());
      }
    } on Exception catch (error) {
      if (!mounted || revision != _routeRevision) return;
      _showMessage('路径规划失败：$error');
    } finally {
      if (mounted && revision == _routeRevision) {
        setState(() => _planning = false);
      }
    }
  }

  /// 点击「保存为我的酒馆路线」：必须已完成路径规划，之后走 POST 创建。
  Future<void> _saveRoute() async {
    if (!_planned) {
      _showMessage('请先点击「出发」规划路线');
      return;
    }
    if (_saving) return;
    final places = _routeItems.whereType<_BarPlace>().toList();
    if (_start == null || _end == null) {
      _showMessage('请先选择起点酒吧和终点酒吧');
      return;
    }
    final barIds = [
      for (final place in places)
        if (place.barId != null) place.barId!,
    ];
    if (barIds.length != places.length) {
      _showMessage('演示数据暂不支持保存，请从真实酒吧中选择');
      return;
    }
    if (barIds.toSet().length != barIds.length ||
        barIds.length < 2 ||
        barIds.length > _maxStops + 2) {
      _showMessage('路线需要 2-${_maxStops + 2} 家互不相同的酒吧');
      return;
    }

    final title = await _promptRouteTitle();
    if (title == null || title.isEmpty || !mounted) {
      return;
    }

    setState(() => _saving = true);
    try {
      final today = DateTime.now();
      final dateKey =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await _api.createDrinkingRoute({
        'title': title,
        'barIds': barIds,
        'localStartDate': dateKey,
        'localEndDate': dateKey,
        'timezone': 'Asia/Shanghai',
        'visibility': 'private',
      });
      if (!mounted) return;
      _showMessage('路线「$title」已保存');
    } on Exception catch (error) {
      if (!mounted) return;
      _showMessage('保存失败：$error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// 弹出路线标题输入框，默认取起点酒吧名。
  Future<String?> _promptRouteTitle() {
    final controller = TextEditingController(text: '${_start!.name} 夜饮路线');
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            '保存路线',
            style: TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: '给这条路线起个名字',
              filled: true,
              fillColor: const Color(0xFFF3F3F3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: _brand),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // Keep the map preview and the persistent save action fixed while a
      // route-place field is being edited. The input list can still scroll,
      // but the keyboard must not resize the whole page.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text(
          '规划路线',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // A route row is 48px tall. Show at most five rows; the
                  // station area scrolls internally once more are added.
                  final visibleItemCount = _routeItems.length > 5
                      ? 5
                      : _routeItems.length;
                  final naturalEditorHeight = 82.0 + visibleItemCount * 48.0;
                  final maxEditorHeight = (constraints.maxHeight - 180.0).clamp(
                    0.0,
                    double.infinity,
                  );
                  final editorHeight = naturalEditorHeight
                      .clamp(0.0, maxEditorHeight)
                      .toDouble();

                  return Column(
                    children: [
                      SizedBox(
                        height: editorHeight,
                        child: Column(
                          children: [
                            Expanded(
                              // 细滑块：站点超出可见行数后才需要滚动，滑块始终
                              // 可见，引导用户下拉查看已添加的地点。
                              child: Scrollbar(
                                controller: _routeListController,
                                thumbVisibility: true,
                                thickness: 2.5,
                                radius: const Radius.circular(3),
                                child: ListView(
                                  controller: _routeListController,
                                  // The editable station list has its own
                                  // viewport. Do not paint its extra content
                                  // over the preview header when more
                                  // waypoints are added.
                                  clipBehavior: Clip.hardEdge,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    12,
                                  ),
                                  children: [
                                    const Text(
                                      '按顺序安排今晚的酒吧行程',
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    ReorderableListView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      clipBehavior: Clip.hardEdge,
                                      itemCount: _routeItems.length,
                                      // 长按拖动手柄后给出震动反馈，提示拖拽已开始。
                                      onReorderStart: (_) =>
                                          HapticFeedback.mediumImpact(),
                                      onReorder: _reorderRoute,
                                      itemBuilder: (context, index) {
                                        final isStart = index == 0;
                                        final isEnd =
                                            index == _routeItems.length - 1;
                                        final stopIndex = index - 1;
                                        return _RoutePlaceTile(
                                          key: ValueKey(
                                            'route-$index-${_routeItems[index]?.name ?? 'empty'}',
                                          ),
                                          dotColor: isStart
                                              ? const Color(0xFFD95151)
                                              : isEnd
                                              ? const Color(0xFF39A568)
                                              : const Color(0xFFB8AEB4),
                                          bar: _routeItems[index],
                                          placeholder: isStart || isEnd
                                              ? '请输入起终点'
                                              : '请输入途径酒吧',
                                          bars: _nearbyBars,
                                          used: _usedPlaces,
                                          onSelected: (bar) => _select(
                                            isStart
                                                ? _RouteStopType.start
                                                : isEnd
                                                ? _RouteStopType.end
                                                : _RouteStopType.stop,
                                            bar,
                                            stopIndex: isStart || isEnd
                                                ? null
                                                : stopIndex,
                                          ),
                                          onRemove: _showRemoveActions
                                              ? () => _removeRouteItem(index)
                                              : null,
                                          dragIndex: index,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // 「添加途径酒吧 + 出发」固定在编辑区底部，不随列表滚动。
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextButton.icon(
                                      onPressed: _stops.length >= _maxStops
                                          ? null
                                          : () => setState(() {
                                              _showRemoveActions = true;
                                              _stops.add(null);
                                            }),
                                      icon: const Icon(
                                        Icons.add_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('添加途径酒吧'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: _brand,
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                      ),
                                    ),
                                  ),
                                  FilledButton.icon(
                                    onPressed: _planning ? null : _planRoute,
                                    icon: const Icon(
                                      Icons.send_rounded,
                                      size: 18,
                                    ),
                                    label: Text(_planning ? '规划中…' : '出发'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _brand,
                                      minimumSize: const Size(0, 40),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: const Text(
                            '路线预览',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SiponMapWidget(
                              initialStyleId: MapBaseStyle.standard.id,
                              onHostReady: _handleMapCreated,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEDE5E9))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_planned)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '先点击「出发」规划路线，才能保存为我的路线',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF8F8790),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: (!_planned || _saving) ? null : _saveRoute,
                    icon: const Icon(Icons.alt_route_rounded),
                    label: Text(_saving ? '保存中…' : '保存为我的酒馆路线'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _brand,
                      minimumSize: const Size.fromHeight(48),
                      disabledBackgroundColor: const Color(0xFFE6D3DF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _RouteStopType { start, stop, end }

class _BarPlace {
  const _BarPlace(
    this.name,
    this.address,
    this.distance,
    this.longitude,
    this.latitude,
    this.kind, {
    this.barId,
    this.rating,
  });
  final String name;
  final String address;
  final String distance;
  final double longitude;
  final double latitude;
  final MapVenueKind kind;

  /// 后端酒吧 id；为 null 的是演示数据，不能用于保存路线。
  final int? barId;
  final double? rating;

  /// 从 getNearbyBars 响应解析；缺关键字段（id/名称/坐标）时返回 null。
  static _BarPlace? tryParse(Map<String, dynamic> map) {
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
    final rawRating =
        (map['averageRating'] as num?)?.toDouble() ??
        (map['rating'] as num?)?.toDouble() ??
        double.tryParse(map['averageRating']?.toString() ?? '') ??
        double.tryParse(map['rating']?.toString() ?? '');
    return _BarPlace(
      name,
      map['address']?.toString() ?? '',
      meters == null
          ? ''
          : meters >= 1000
          ? '约${(meters / 1000).toStringAsFixed(1)}km'
          : '约${meters.round()}m',
      longitude,
      latitude,
      MapVenueKind.fromRaw(
        map['barSubtype']?.toString() ?? map['subtype']?.toString(),
      ),
      barId: id,
      rating: rawRating != null && rawRating.isFinite && rawRating > 0
          ? rawRating
          : null,
    );
  }
}

class _RoutePlaceTile extends StatelessWidget {
  const _RoutePlaceTile({
    super.key,
    required this.bar,
    required this.dotColor,
    required this.placeholder,
    required this.bars,
    required this.used,
    required this.onSelected,
    this.onRemove,
    this.dragIndex,
  });
  final _BarPlace? bar;
  final Color dotColor;
  final String placeholder;
  final List<_BarPlace> bars;
  final Set<_BarPlace> used;
  final ValueChanged<_BarPlace> onSelected;
  final VoidCallback? onRemove;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final tile = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 36,
              child: Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InlineBarSearchField(
                bar: bar,
                placeholder: placeholder,
                bars: bars,
                used: used,
                onSelected: onSelected,
                onRemove: onRemove,
                dragIndex: dragIndex,
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(padding: const EdgeInsets.only(bottom: 2), child: tile);
  }
}

class _InlineBarSearchField extends StatefulWidget {
  const _InlineBarSearchField({
    required this.bar,
    required this.placeholder,
    required this.bars,
    required this.used,
    required this.onSelected,
    required this.onRemove,
    required this.dragIndex,
  });
  final _BarPlace? bar;
  final String placeholder;
  final List<_BarPlace> bars;
  final Set<_BarPlace> used;
  final ValueChanged<_BarPlace> onSelected;
  final VoidCallback? onRemove;
  final int? dragIndex;

  @override
  State<_InlineBarSearchField> createState() => _InlineBarSearchFieldState();
}

class _InlineBarSearchFieldState extends State<_InlineBarSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.bar?.name,
  );
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  OverlayEntry? _resultsOverlay;
  double _fieldWidth = 0;

  List<_BarPlace> get _results {
    final query = _controller.text.trim().toLowerCase();
    return widget.bars.where((bar) {
      return query.isNotEmpty &&
          '${bar.name} ${bar.address}'.toLowerCase().contains(query) &&
          (!widget.used.contains(bar) || widget.bar == bar);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() {});
    _syncResultsOverlay();
  }

  void _syncResultsOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = _fieldKey.currentContext?.findRenderObject();
      if (renderObject is RenderBox) {
        _fieldWidth = renderObject.size.width;
      }
      final shouldShow = _focusNode.hasFocus && _results.isNotEmpty;
      if (shouldShow) {
        if (_resultsOverlay == null) {
          _resultsOverlay = OverlayEntry(builder: (_) => _buildResults());
          Overlay.of(context, rootOverlay: true).insert(_resultsOverlay!);
        } else {
          _resultsOverlay!.markNeedsBuild();
        }
      } else {
        _resultsOverlay?.remove();
        _resultsOverlay = null;
      }
    });
  }

  Widget _buildResults() {
    final results = _results;
    final panelHeight = (results.length * 56.0).clamp(0.0, 176.0).toDouble();
    return Positioned(
      width: _fieldWidth,
      height: panelHeight,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 40),
        child: Material(
          elevation: 6,
          color: Colors.white,
          borderRadius: BorderRadius.circular(7),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE9DDE3)),
              borderRadius: BorderRadius.circular(7),
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemExtent: 56,
              itemCount: results.length,
              itemBuilder: (context, index) {
                final bar = results[index];
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  leading: const Icon(
                    Icons.local_bar_outlined,
                    size: 17,
                    color: Color(0xFF9A3D78),
                  ),
                  title: Text(
                    bar.name,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${bar.address}  |  ${bar.distance}',
                    style: const TextStyle(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    _controller.text = bar.name;
                    _controller.selection = TextSelection.collapsed(
                      offset: _controller.text.length,
                    );
                    _focusNode.unfocus();
                    widget.onSelected(bar);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _resultsOverlay?.remove();
    _controller.dispose();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CompositedTransformTarget(
          link: _layerLink,
          child: SizedBox(
            key: _fieldKey,
            height: 36,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: (_) {
                setState(() {});
                _syncResultsOverlay();
              },
              decoration: InputDecoration(
                hintText: widget.placeholder,
                hintStyle: const TextStyle(
                  color: Color(0xFFAAA1A8),
                  fontSize: 14,
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (query.isNotEmpty && widget.onRemove == null)
                      IconButton(
                        onPressed: () {
                          _controller.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded, size: 17),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 32,
                        ),
                        tooltip: '清空',
                      ),
                    if (widget.onRemove != null)
                      IconButton(
                        onPressed: widget.onRemove,
                        icon: const Icon(Icons.close_rounded, size: 17),
                        tooltip: '删除路线点',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 32,
                        ),
                      ),
                    // 真机触摸下，立即拖动手势会在手势竞技场里输给外层可
                    // 滚动的 ListView（模拟器鼠标默认不参与滚动手势竞争，
                    // 所以表现正常），因此必须用长按触发拖拽。
                    // 注意：这里不能给 IconButton 设置 tooltip——Tooltip 的
                    // LongPressGestureRecognizer 与 DelayedMultiDrag 同为
                    // 500ms 且层级更深，会先赢得竞技场并弹出提示文字，导致
                    // 真机长按只显示提示、永远拖不动。
                    if (widget.dragIndex != null)
                      ReorderableDelayedDragStartListener(
                        index: widget.dragIndex!,
                        child: const IconButton(
                          onPressed: null,
                          icon: Icon(
                            Icons.drag_handle_rounded,
                            size: 18,
                            semanticLabel: '长按拖动调整顺序',
                          ),
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints.tightFor(
                            width: 30,
                            height: 32,
                          ),
                        ),
                      ),
                  ],
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 38,
                  minHeight: 32,
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 32,
                ),
                filled: true,
                fillColor: const Color(0xFFF3F3F3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
