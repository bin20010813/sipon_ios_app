import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/map_data_controller.dart';
import '../models/map_models.dart';
import '../controllers/map_scene_controller.dart';
import '../data/map_venue_repository.dart';
import '../models/map_viewport.dart';
import '../platform/sipon_map_host.dart';
import '../widgets/sipon_map_widget.dart';
import '../controllers/venue_sheet_controller.dart';
import '../../../shared/services/sipon_city_controller.dart';
import '../widgets/map_controls.dart';
import '../widgets/map_tools_sheet.dart';
import '../widgets/venue_sheet.dart';
import '../../../shared/widgets/sipon_city_picker.dart';
import '../../../shared/localization/language_transform.dart';

/// 地图页只做组装：把三个控制器接到一起，再把它们的状态摊给几个展示组件。
///
/// 真正的逻辑分别在：
/// - [MapDataController]：有哪些酒吧、选中哪个、筛选了什么；
/// - [MapSceneController]：底图、annotation、相机与图层显隐（MapKit 引擎）；
/// - [VenueSheetController]：详情面板的 extent 与吸附档位。
class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    this.bottomOverlayInset = 0,
    this.initialVenue,
    this.requestedVenue,
    this.initialSheetStage = VenueSheetStage.collapsed,
    this.showMapControls = true,
    this.showSheetDragHandle = true,
    this.active = true,
    this.allowSheetCollapse = true,
    this.onMapTapped,
    this.onExpandMap,
    this.onVenueClose,
    this.onSheetProgressChanged,
  });

  final double bottomOverlayInset;
  final MapVenue? initialVenue;

  /// 首页地址入口请求在地图 Tab 中选中并聚焦的 POI。
  final MapVenue? requestedVenue;
  final VenueSheetStage initialSheetStage;
  final bool showMapControls;
  final bool showSheetDragHandle;

  /// IndexedStack 中只有地图 Tab 可见时才请求一次当前位置。
  final bool active;
  final bool allowSheetCollapse;

  /// Optional map tap action for embedded map pages.
  final VoidCallback? onMapTapped;
  final VoidCallback? onExpandMap;
  final VoidCallback? onVenueClose;
  final ValueChanged<double>? onSheetProgressChanged;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  /// 收起态下地图 logo / 版权信息的下边距：正好落在悬浮卡片上方。
  static const double _collapsedOrnamentMargin = 184;

  /// 定位按钮距面板顶边与右边的间距。
  static const double _locateButtonGap = 12;
  static const double _locateButtonRightInset = 18;

  late final MapDataController _data;
  late final MapSceneController _scene;
  late final VenueSheetController _sheet;
  DateTime? _lastExtentLogAt;
  VenueSheetStage? _lastLoggedStage;
  String _mapDiagnosticName = 'pending';
  bool _sheetCameraUpdateScheduled = false;
  MapLatLng? _pendingLocatedCenter;
  int _locationRequest = 0;

  void _logMapMotion(String event, String details) {
    if (!kDebugMode) return;
    debugPrint(
      '[SiponMapMotion] t=${DateTime.now().toIso8601String()} '
      'page=$hashCode map=$_mapDiagnosticName $event stage=${_sheet.stage.name} '
      'extent=${_sheet.currentExtent.toStringAsFixed(3)} $details',
    );
  }

  SiponCityController? _cityController;

  @override
  void initState() {
    super.initState();
    _sheet = VenueSheetController(initialStage: widget.initialSheetStage);
    _lastLoggedStage = _sheet.stage;
    _sheet.extent.addListener(_handleSheetExtent);
    _data = MapDataController(
      repository: SiponApiMapVenueRepository(),
      city: SiponCityController.defaultCity,
      initialVenue: widget.initialVenue ?? widget.requestedVenue,
    )..addListener(_handleDataChanged);
    _scene = MapSceneController.create(
      onViewportSettled: _handleViewportSettled,
      onVenueTapped: _handleVenueTapped,
      // 点地图空白处就收起面板。原来这里毫无反应。
      onBlankTapped: _handleMapBackgroundTap,
    );

    // 档位变化时重新取景（收起/半屏/全屏的 padding 不同）。
    _sheet.addListener(_handleSheetStage);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final cityController = SiponCityScope.controllerOf(context);
    if (_cityController != cityController) {
      _cityController?.removeListener(_handleCityChanged);
      _cityController = cityController..addListener(_handleCityChanged);
      _handleCityChanged();
    }
    if (widget.active &&
        widget.initialVenue == null &&
        widget.requestedVenue == null &&
        _locationRequest == 0) {
      unawaited(_centerOnCurrentLocation());
    }

    // 语言也是一条依赖：marker 的文字标签在这一层翻译好再交给地图，
    // 所以切换语言要重新下发一帧。
    unawaited(_pushFrame());
  }

  @override
  void didUpdateWidget(covariant MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        widget.requestedVenue != null &&
        (!oldWidget.active ||
            !identical(widget.requestedVenue, oldWidget.requestedVenue))) {
      _locationRequest++;
      _pendingLocatedCenter = null;
      _data.focusVenueFromPage(widget.requestedVenue!);
      _sheet.collapse();
      if (_scene.isAttached) unawaited(_applyStage(reason: 'homeVenue'));
    } else if (widget.active && !oldWidget.active) {
      unawaited(_centerOnCurrentLocation());
    } else if (!widget.active && oldWidget.active) {
      _locationRequest++;
    }
  }

  @override
  void dispose() {
    _locationRequest++;
    _cityController?.removeListener(_handleCityChanged);
    _data.removeListener(_handleDataChanged);
    _scene.detach();
    _sheet.removeListener(_handleSheetStage);
    _sheet.extent.removeListener(_handleSheetExtent);
    _sheet.dispose();
    _data.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ 地图生命周期

  Future<void> _handleMapCreated(SiponMapHost host) async {
    if (host is ChannelMapHost) _mapDiagnosticName = host.diagnosticName;
    _logMapMotion('MAP_CREATED', '');
    final anchor = _cityController?.detectedPosition;
    final targetVenue = widget.initialVenue ?? widget.requestedVenue;
    await _scene.attach(
      host,
      city: _data.city,
      style: _data.style,
      initialCenter: targetVenue != null
          ? MapLatLng(
              longitude: targetVenue.longitude,
              latitude: targetVenue.latitude,
            )
          : anchor != null
          ? MapLatLng(longitude: anchor.longitude, latitude: anchor.latitude)
          : null,
    );
    final locatedCenter = _pendingLocatedCenter;
    final movingToLocation =
        locatedCenter != null &&
        widget.active &&
        widget.initialVenue == null &&
        widget.requestedVenue == null;
    if (movingToLocation) {
      _pendingLocatedCenter = null;
      await _scene.focusOn(
        longitude: locatedCenter.longitude,
        latitude: locatedCenter.latitude,
      );
    }
    await _applyStage(
      focusSelection:
          widget.initialVenue != null || widget.requestedVenue != null,
      reason: 'mapReady',
    );

    // 原「styleLoaded 回调」的职责（重下发帧 + 按当前视野补一次取数）已并入
    // 控制器；页面只需要在 attach 完成后把首帧交给它，并补齐首次取数。
    await _pushFrame();

    if (movingToLocation) return;
    final viewport = await _scene.readViewport();
    if (viewport == null || !mounted) {
      return;
    }

    await _data.syncViewport(viewport);
  }

  /// 相机停稳（已在 [MapSceneController] 里去抖）。视野有没有实质变化由
  /// [MapViewport.differsMateriallyFrom] 说了算，所以自己的 `flyTo` 不会引起重拉，
  /// 也就不再需要原来的 `_skipNextIdleReload` 标志位。
  void _handleViewportSettled(MapViewport viewport) {
    _logMapMotion(
      'VIEWPORT_SETTLED',
      'center=${viewport.bounds.center} zoom=${viewport.zoom.toStringAsFixed(3)}',
    );
    unawaited(_data.syncViewport(viewport));
  }

  // ---------------------------------------------------------------- 状态联动

  void _handleDataChanged() {
    if (!mounted) {
      return;
    }

    // 界面部分由 ListenableBuilder 自己重建，这里只负责把新的一帧交给地图。
    unawaited(_pushFrame());
  }

  /// 面板档位变化（收起/半屏/全屏）时重新取景。只监听档位，不接 extent 的
  /// 每帧变化——extent 继续只驱动卡片与按钮动画。
  void _handleSheetStage() {
    if (!mounted || !_scene.isAttached) return;
    _logMapMotion('SHEET_STAGE', 'from=${_lastLoggedStage?.name ?? "initial"}');
    _lastLoggedStage = _sheet.stage;
    unawaited(_applyStage(reason: 'sheetStage'));
  }

  void _handleSheetExtent() {
    // 连续拖拽最多每 250ms 一条，避免逐帧打印干扰手势时序。
    if (kDebugMode) {
      final now = DateTime.now();
      if (_lastExtentLogAt == null ||
          now.difference(_lastExtentLogAt!).inMilliseconds >= 250) {
        _lastExtentLogAt = now;
        _logMapMotion('SHEET_EXTENT', 'settledStage=${_sheet.stage.name}');
      }
    }
    widget.onSheetProgressChanged?.call(
      _sheet.progressFor(_sheet.currentExtent),
    );
    _scheduleSheetCameraFollow();
  }

  /// DraggableScrollableSheet 可能在一帧里连续发多次通知。这里合并到帧末，
  /// 既让相机逐帧跟住面板，又避免平台通道堆积重复的中间值。
  void _scheduleSheetCameraFollow() {
    if (_sheetCameraUpdateScheduled || !mounted || !_scene.isAttached) return;
    _sheetCameraUpdateScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sheetCameraUpdateScheduled = false;
      if (!mounted || !_scene.isAttached) return;

      final venue = _data.selectedVenue;
      if (venue == null) return;
      unawaited(
        _scene.followSelectionForSheet(
          cameraBottomPadding: _sheet.cameraBottomPadding,
          focus: MapLatLng(
            longitude: venue.longitude,
            latitude: venue.latitude,
          ),
        ),
      );
    });
  }

  /// 把当前数据整帧交给地图。[MapSceneController] 自己比指纹决定要不要真下发。
  Future<void> _pushFrame() async {
    if (!_scene.isAttached) {
      return;
    }

    final text = SiponLanguageScope.textOf(context);

    await _scene.render(
      MapSceneFrame(
        circlePoints: _data.circlePoints,
        markers: [
          for (final venue in _data.markerVenues)
            MapMarkerSpec(
              venueId: venue.id,
              label: text.t(venue.name),
              longitude: venue.longitude,
              latitude: venue.latitude,
              kind: venue.kind,
              rating: venue.hasRating ? venue.rating : null,
            ),
        ],
        selected: _data.selectedPoint,
      ),
    );
  }

  /// 面板落定到新档位。**这里是相机与装饰物的唯一触发点**：原来
  /// `_expandVenueDetails` / `_collapseVenueDetails` / `_settleVenueSheet` /
  /// `_showSelectedVenueOnMap` 四处各自调一遍 `_focusVenue`。

  Future<void> _applyStage({
    bool focusSelection = true,
    String reason = 'selection',
  }) async {
    final venue = _data.selectedVenue;

    _logMapMotion(
      'APPLY_STAGE',
      'reason=$reason padding=${_sheet.cameraBottomPadding.toStringAsFixed(1)} '
          'focus=${focusSelection && venue != null} attached=${_scene.isAttached}',
    );
    await _scene.applyStage(
      cameraBottomPadding: _sheet.cameraBottomPadding,
      ornamentBottomMargin: _sheet.ornamentBottomMargin(
        _collapsedOrnamentMargin + widget.bottomOverlayInset,
      ),
      focus: focusSelection && venue != null
          ? MapLatLng(longitude: venue.longitude, latitude: venue.latitude)
          : null,
    );
  }

  /// 点中圆点或带标签的 marker。当前档位保持不变：收起态就换卡片，半屏态就换详情。
  void _handleVenueTapped(String venueId) {
    if (widget.onMapTapped != null) {
      widget.onMapTapped!();
      return;
    }
    if (_data.isSelected(venueId)) {
      // 已经选中的点再点一次 = 打开详情。
      _sheet.expand();
      return;
    }

    _data.selectVenue(venueId);
    unawaited(_applyStage());
  }

  void _handleCityChanged() {
    // 独立酒吧地图以传入的地点为目标；全局选城及其异步恢复不能清空
    // 该酒吧的选中态，也不能把相机从酒吧位置移到城市中心。
    if (widget.initialVenue != null) return;
    final city = _cityController?.city ?? SiponCityController.defaultCity;
    if (city == _data.city) {
      return;
    }

    _data.setCity(city);
    unawaited(_scene.flyToCity(city, zoom: MapSceneController.cityZoom));
  }

  Future<void> _centerOnCurrentLocation() async {
    if (widget.initialVenue != null) return;
    final controller = _cityController;
    if (controller == null) return;
    final request = ++_locationRequest;
    final result = await controller.locateCurrentCity();
    if (!mounted || !widget.active || request != _locationRequest) return;
    final position = result.position;
    if (position == null) return;
    if (result.city != null && result.city!.name != _data.city) {
      _data.setCity(result.city!.name);
    }
    final center = MapLatLng(
      longitude: position.longitude,
      latitude: position.latitude,
    );
    if (!_scene.isAttached) {
      _pendingLocatedCenter = center;
      return;
    }
    await _scene.focusOn(
      longitude: center.longitude,
      latitude: center.latitude,
    );
  }

  /// 点地图空白处：收起面板，同时收起搜索下拉与键盘。候选列表挂在
  /// root overlay 上，焦点不收它就一直浮在地图上。
  void _handleMapBackgroundTap() {
    if (widget.onMapTapped != null) {
      widget.onMapTapped!();
    } else if (widget.allowSheetCollapse) {
      _handleBlankTapped();
    }
  }

  void _handleBlankTapped() {
    FocusManager.instance.primaryFocus?.unfocus();
    _sheet.collapse();
  }

  // ------------------------------------------------------------- 地点搜索

  /// 搜索候选被点击：先把候选并入数据集并选中（它可能在当前视野外，
  /// 不合并的话详情卡片会空窗），再把搜索词对齐成酒吧名，让顶部输入框
  /// 通过 initialValue 联动回显；相机聚焦由 [_applyStage] 按选中点完成。
  void _handleSearchVenueSelected(MapVenue venue) {
    _data.adoptSearchedVenue(venue);
    _data.setSearchQuery(venue.name);
    unawaited(_applyStage());
  }

  // --------------------------------------------------------------- POI 筛选

  /// 右下角定位按钮：重新获取并聚焦当前位置。
  Future<void> _handleFocusDowntown() => _centerOnCurrentLocation();

  void _applyPoiFilter(MapPoiFilter filter) {
    final previousSelection = _data.selectedVenue?.id;
    _data.applyPoiFilter(filter);
    if (_data.selectedVenue != null &&
        _data.selectedVenue?.id != previousSelection) {
      unawaited(_applyStage(reason: 'poiFilter'));
    }
  }

  Future<void> _showPoiFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => MapPoiFilterSheet(
        initialFilter: _data.poiFilter,
        onApply: _applyPoiFilter,
      ),
    );
  }

  // ---------------------------------------------------------------------- 组装

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          // 收起态卡片原本浮在导航栏之上，这段间距一并算进面板高度，
          // 于是同一个面板既能表现"悬浮卡片"，也能表现"贴底面板"。
          final collapsedBottomGap = math.max(
            MediaQuery.paddingOf(context).bottom,
            widget.bottomOverlayInset + 12,
          );
          final collapsedExtent = availableHeight <= 0
              ? 0.2
              : mapClamp(
                  (VenueSheetController.collapsedCardHeight +
                          collapsedBottomGap) /
                      availableHeight,
                  0.08,
                  0.42,
                );
          // 布局算出来的数只能从布局来，但由它派生的档位变化会被推到帧末再通知，
          // 所以这里不会在 build 期触发 setState。
          _sheet.updateMetrics(
            availableHeight: availableHeight,
            collapsedExtent: collapsedExtent,
          );

          return Stack(
            children: [
              SiponMapWidget(
                key: const ValueKey('sipon_map_widget'),
                initialStyleId: _data.style.id,
                compassTopInset:
                    MediaQuery.paddingOf(context).top +
                    (widget.showMapControls ? 130 : 12),
                onHostReady: _handleMapCreated,
              ),
              if (widget.showMapControls) _buildTopControls(),

              if (widget.onExpandMap != null) _buildExpandMapButton(),

              if (widget.showMapControls)
                _buildLocateButton(
                  collapsedExtent: collapsedExtent,
                  availableHeight: availableHeight,
                ),
              _buildVenueSheet(
                collapsedExtent: collapsedExtent,
                collapsedBottomGap: collapsedBottomGap,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopControls() {
    return ValueListenableBuilder<double>(
      valueListenable: _sheet.extent,
      builder: (context, rawExtent, _) {
        final progress = _sheet.progressFor(
          rawExtent <= 0 ? _sheet.collapsedExtent : rawExtent,
        );
        return IgnorePointer(
          ignoring: progress > 0.05,
          child: Opacity(
            opacity: 1 - progress,
            child: Transform.translate(
              offset: Offset(0, -32 * progress),
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ListenableBuilder(
                    listenable: _data,
                    builder: (context, _) => MapSearchAndFilters(
                      selectedKind: _data.categoryFilter,
                      poiFilter: _data.poiFilter,
                      status: _data.status,
                      searchQuery: _data.searchQuery,
                      suggestions: _data.visibleVenues,
                      onCategoryToggled: _data.toggleCategory,
                      onFilterPressed: _showPoiFilters,
                      onSearchChanged: _data.setSearchQuery,
                      onVenueSelected: _handleSearchVenueSelected,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpandMapButton() {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 12,
      right: 16,
      child: ValueListenableBuilder<double>(
        valueListenable: _sheet.extent,
        builder: (context, rawExtent, child) {
          final extent = rawExtent <= 0 ? _sheet.currentExtent : rawExtent;
          final progress = _sheet.fullscreenProgressFor(extent);
          return IgnorePointer(
            ignoring: progress >= 0.5,
            child: Opacity(
              opacity: 1 - progress,
              child: Transform.translate(
                offset: Offset(0, -16 * progress),
                child: child,
              ),
            ),
          );
        },
        child: Material(
          color: Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            key: const ValueKey('expand-venue-map'),
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onExpandMap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.open_in_full_rounded, size: 16),
                  const SizedBox(width: 5),
                  Text(
                    SiponLanguageScope.languageOf(context) == SiponLanguage.zh
                        ? '放大地图'
                        : 'Expand map',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 定位按钮跟面板共用同一个 extent，拖动过程中连续跟随而不是瞬移。
  Widget _buildLocateButton({
    required double collapsedExtent,
    required double availableHeight,
  }) {
    return Positioned.fill(
      child: ValueListenableBuilder<double>(
        valueListenable: _sheet.extent,
        builder: (context, rawExtent, child) {
          final extent = rawExtent <= 0 ? collapsedExtent : rawExtent;

          return Align(
            alignment: Alignment.bottomRight,
            child: Transform.translate(
              offset: Offset(
                -_locateButtonRightInset,
                -(extent * availableHeight + _locateButtonGap),
              ),
              child: child,
            ),
          );
        },
        child: MapLocateButton(onPressed: _handleFocusDowntown),
      ),
    );
  }

  Widget _buildVenueSheet({
    required double collapsedExtent,
    required double collapsedBottomGap,
  }) {
    return Positioned.fill(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: NotificationListener<DraggableScrollableNotification>(
          onNotification: _sheet.handleNotification,
          child: DraggableScrollableSheet(
            controller: _sheet.sheet,
            // 只让面板实际占用的区域参与命中测试，露出的地图区域继续接收手势。
            expand: false,
            initialChildSize: _sheet.currentExtent,
            minChildSize: widget.allowSheetCollapse
                ? collapsedExtent
                : VenueSheetController.halfExtent,
            maxChildSize: VenueSheetController.maxExtent,
            snap: true,
            snapSizes: widget.allowSheetCollapse
                ? const [VenueSheetController.halfExtent]
                : null,
            snapAnimationDuration: VenueSheetController.motionDuration,
            builder: (context, scrollController) {
              // builder 只在面板重建时调用，缓存下来供收起时归零滚动位置。
              _sheet.attachScrollController(scrollController);

              // 两条来源不同的重建：数据换了（选中的酒吧、内容）走 _data，
              // 拖拽过程中的形变走 extent。
              return ListenableBuilder(
                listenable: _data,
                builder: (context, _) => ValueListenableBuilder<double>(
                  valueListenable: _sheet.extent,
                  builder: (context, rawExtent, _) {
                    final extent = rawExtent <= 0 ? collapsedExtent : rawExtent;

                    return VenueSheetSurface(
                      venue: _data.selectedVenue,
                      filterActive:
                          _data.poiFilter.isActive ||
                          _data.categoryFilter != null,
                      scrollController: scrollController,
                      progress: _sheet.progressFor(extent),
                      fullscreenProgress: _sheet.fullscreenProgressFor(extent),
                      collapsedBottomGap: collapsedBottomGap,
                      bottomOverlayInset: mapLerp(
                        widget.bottomOverlayInset,
                        MediaQuery.paddingOf(context).bottom,
                        _sheet.progressFor(extent),
                      ),
                      onExpand: _sheet.expand,
                      showDragHandle: widget.showSheetDragHandle,
                      onCollapse: widget.onVenueClose ?? _sheet.collapse,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
