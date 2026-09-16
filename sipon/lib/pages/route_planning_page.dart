import 'dart:async';
import 'package:flutter/material.dart';
import '../services/map/map_display_options.dart';
import '../services/map/map_models.dart';
import '../services/map/map_scene_controller.dart';
import '../services/map/map_viewport.dart';
import '../services/map/sipon_map_host.dart';
import '../services/map/sipon_map_widget.dart';
import '../services/sipon_api_service.dart';

class RoutePlanningPage extends StatefulWidget {
  const RoutePlanningPage({super.key});

  @override
  State<RoutePlanningPage> createState() => _RoutePlanningPageState();
}

class _RoutePlanningPageState extends State<RoutePlanningPage> {
  static const _brand = Color(0xFF9A3D78);
  static const _ink = Color(0xFF252229);
  static const _muted = Color(0xFF8F8790);
  static const _maxStops = 10;

  /// 可选酒吧的中心点：与打卡页共用同一片演示锚点。
  static const _centerLongitude = 121.4718;
  static const _centerLatitude = 31.2232;

  /// 接口拉取失败时兜底的演示数据（无 barId，保存时会被拦截）。
  static const _fallbackBars = [
    _BarPlace(
      '庙前冰室（Hope & Sesame）',
      '黄浦区复兴中路 579',
      '450m',
      121.4718,
      31.2232,
      MapVenueKind.pub,
    ),
    _BarPlace(
      'Speak Low（彼楼）',
      '黄浦区复兴中路 579',
      '620m',
      121.4734,
      31.2251,
      MapVenueKind.bistro,
    ),
    _BarPlace(
      'Janes and Hooch',
      '黄浦区巨鹿路 158',
      '1.1km',
      121.4686,
      31.2203,
      MapVenueKind.party,
    ),
    _BarPlace(
      'Play House 电音夜店',
      '黄浦区淮海中路 333',
      '1.4km',
      121.4667,
      31.2182,
      MapVenueKind.livehouse,
    ),
    _BarPlace(
      '武康路精酿工坊',
      '徐汇区武康路 388',
      '1.8km',
      121.4448,
      31.2086,
      MapVenueKind.craft,
    ),
  ];

  final SiponApiService _api = SiponApiService();

  List<_BarPlace> _nearbyBars = _fallbackBars;

  _BarPlace? _start;
  _BarPlace? _end;
  final List<_BarPlace?> _stops = [];
  bool _showRemoveActions = false;
  bool _saving = false;
  late final MapSceneController _scene;

  @override
  void initState() {
    super.initState();
    _scene = MapSceneController.create(
      onViewportSettled: (_) {},
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
    _loadNearbyBars();
  }

  @override
  void dispose() {
    _scene.detach();
    super.dispose();
  }

  /// 拉取附近真实酒吧作为可选项；失败时保留演示数据，保存时会被拦截。
  Future<void> _loadNearbyBars() async {
    try {
      final list = await _api.getNearbyBars(
        longitude: _centerLongitude,
        latitude: _centerLatitude,
        radiusMeters: 5000,
      );
      final parsed = [
        for (final item in list.whereType<Map>())
          _BarPlace.tryParse(item.cast<String, dynamic>()),
      ].whereType<_BarPlace>().toList();
      if (!mounted || parsed.isEmpty) return;
      setState(() => _nearbyBars = parsed);
    } on Exception {
      // 演示数据兜底，页面照常可用。
    }
  }

  Future<void> _handleMapCreated(SiponMapHost host) async {
    await _scene.attach(host, city: '上海', style: MapBaseStyle.standard);
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
          for (final place in places)
            MapMarkerSpec(
              venueId: place.name,
              label: place.name,
              longitude: place.longitude,
              latitude: place.latitude,
              kind: place.kind,
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

  void _reorderRoute(int oldIndex, int newIndex) {
    _invalidatePlanning();
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 站点编排变更后清除已规划的路线，必须重新规划才能保存。
  void _invalidatePlanning() {
    if (!_planned) return;
    _scene.clearRoute();
    setState(() => _planned = false);
  }

  /// 点击「出发」：按已选站点顺序调用原生路径规划（MKDirections）
  /// 并在地图上绘制路线折线；规划成功后才允许保存为我的路线。
  Future<void> _planRoute() async {
    if (_planning) return;
    if (!_scene.isAttached) {
      _showMessage('地图还没准备好，请稍后再试');
      return;
    }
    final places = _routeItems.whereType<_BarPlace>().toList();
    if (places.length < 2) {
      _showMessage('请先选择起点和终点酒吧');
      return;
    }

    setState(() => _planning = true);
    try {
      final ok = await _scene.planRoute(
        points: [
          for (final place in places)
            MapLatLng(longitude: place.longitude, latitude: place.latitude),
        ],
      );
      if (!mounted) return;
      setState(() {
        _planning = false;
        _planned = ok;
      });
      _showMessage(ok ? '路线已规划，可以保存为我的路线了' : '路径规划失败，请检查站点或稍后重试');
      if (ok) {
        // 折线绘制后再重画一次点位，保证编号 marker 落在折线上层。
        unawaited(_renderMap());
      }
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _planning = false);
      _showMessage('路径规划失败：$error');
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
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      children: [
                        const Text(
                          '按顺序安排今晚的酒吧行程',
                          style: TextStyle(color: _muted, fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          clipBehavior: Clip.none,
                          itemCount: _routeItems.length,
                          onReorder: _reorderRoute,
                          itemBuilder: (context, index) {
                            final isStart = index == 0;
                            final isEnd = index == _routeItems.length - 1;
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
                                stopIndex: isStart || isEnd ? null : stopIndex,
                              ),
                              onRemove: _showRemoveActions
                                  ? () => _removeRouteItem(index)
                                  : null,
                              dragIndex: index,
                            );
                          },
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                onPressed: _stops.length >= _maxStops
                                    ? null
                                    : () => setState(() {
                                        _showRemoveActions = true;
                                        _stops.add(null);
                                      }),
                                icon: const Icon(Icons.add_rounded, size: 18),
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
                              icon: const Icon(Icons.send_rounded, size: 18),
                              label: Text(_planning ? '规划中…' : '出发'),
                              style: FilledButton.styleFrom(
                                backgroundColor: _brand,
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ],
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
  });
  final String name;
  final String address;
  final String distance;
  final double longitude;
  final double latitude;
  final MapVenueKind kind;

  /// 后端酒吧 id；为 null 的是演示数据，不能用于保存路线。
  final int? barId;

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
                    if (widget.dragIndex != null)
                      ReorderableDragStartListener(
                        index: widget.dragIndex!,
                        child: const IconButton(
                          onPressed: null,
                          icon: Icon(Icons.drag_handle_rounded, size: 18),
                          tooltip: '调整顺序',
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
