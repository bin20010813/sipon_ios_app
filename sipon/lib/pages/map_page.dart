import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/map/map_data_controller.dart';
import '../services/map/map_display_options.dart';
import '../services/map/map_models.dart';
import '../services/map/map_scene_controller.dart';
import '../services/map/map_venue_repository.dart';
import '../services/map/map_viewport.dart';
import '../services/map/mock_map_venue_repository.dart';
import '../services/map/sipon_map_host.dart';
import '../services/map/sipon_map_widget.dart';
import '../services/map/venue_sheet_controller.dart';
import '../services/sipon_city_controller.dart';
import '../widgets/map/map_controls.dart';
import '../widgets/map/map_tools_sheet.dart';
import '../widgets/map/venue_sheet.dart';
import '../widgets/sipon_city_picker.dart';
import 'language_transform.dart';

/// 地图数据源开关。后端接口就绪后改成 false 就切到 [SiponApiMapVenueRepository]，
/// 页面代码一行都不用动。
const bool _useMockMapData = true;

/// 地图页只做组装：把三个控制器接到一起，再把它们的状态摊给几个展示组件。
///
/// 真正的逻辑分别在：
/// - [MapDataController]：有哪些酒吧、选中哪个、筛选了什么；
/// - [MapSceneController]：底图、annotation、相机与图层显隐（引擎为
///   MapKit，迁移期可用 dart-define 切回 Mapbox 对照）；
/// - [VenueSheetController]：详情面板的 extent 与吸附档位。
class MapPage extends StatefulWidget {
  const MapPage({super.key, this.bottomOverlayInset = 0});

  final double bottomOverlayInset;

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
  final VenueSheetController _sheet = VenueSheetController();

  SiponCityController? _cityController;

  @override
  void initState() {
    super.initState();
    _data = MapDataController(
      repository: _useMockMapData
          ? MockMapVenueRepository()
          : SiponApiMapVenueRepository(),
      city: SiponCityController.defaultCity,
    )..addListener(_handleDataChanged);
    _scene = MapSceneController.create(
      onViewportSettled: _handleViewportSettled,
      onVenueTapped: _handleVenueTapped,
      // 点地图空白处就收起面板。原来这里毫无反应。
      onBlankTapped: _sheet.collapse,
    );
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

    // 语言也是一条依赖：marker 的文字标签在这一层翻译好再交给地图，
    // 所以切换语言要重新下发一帧。
    unawaited(_pushFrame());
  }

  @override
  void dispose() {
    _cityController?.removeListener(_handleCityChanged);
    _sheet.removeListener(_handleSheetStage);
    _data.removeListener(_handleDataChanged);
    _scene.detach();
    _sheet.dispose();
    _data.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ 地图生命周期

  Future<void> _handleMapCreated(SiponMapHost host) async {
    await _scene.attach(host, city: _data.city, style: _data.style);
    await _applyStage(focusSelection: false);

    // 原「styleLoaded 回调」的职责（重下发帧 + 按当前视野补一次取数）已并入
    // 控制器；页面只需要在 attach 完成后把首帧交给它，并补齐首次取数。
    await _pushFrame();

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

  /// 把当前数据整帧交给地图。[MapSceneController] 自己比指纹决定要不要真下发。
  Future<void> _pushFrame() async {
    if (!_scene.isAttached) {
      return;
    }

    final text = SiponLanguageScope.textOf(context);

    await _scene.render(
      MapSceneFrame(
        circlePoints: _data.circlePoints,
        heatmapPoints: _data.heatmapPoints,
        markers: [
          for (final venue in _data.markerVenues)
            MapMarkerSpec(
              venueId: venue.id,
              label: text.t(venue.name),
              longitude: venue.longitude,
              latitude: venue.latitude,
              kind: venue.kind,
            ),
        ],
        layerMode: _data.layerMode,
        selected: _data.selectedPoint,
      ),
    );
  }

  /// 面板落定到新档位。**这里是相机与装饰物的唯一触发点**：原来
  /// `_expandVenueDetails` / `_collapseVenueDetails` / `_settleVenueSheet` /
  /// `_showSelectedVenueOnMap` 四处各自调一遍 `_focusVenue`。
  void _handleSheetStage() => unawaited(_applyStage());

  Future<void> _applyStage({bool focusSelection = true}) async {
    final venue = _data.selectedVenue;

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
    if (_data.isSelected(venueId)) {
      // 已经选中的点再点一次 = 打开详情。
      _sheet.expand();
      return;
    }

    _data.selectVenue(venueId);
    unawaited(_applyStage());
  }

  void _handleCityChanged() {
    final city = _cityController?.city ?? SiponCityController.defaultCity;
    if (city == _data.city) {
      return;
    }

    _data.setCity(city);
    unawaited(_scene.flyToCity(city, zoom: MapSceneController.cityZoom));
  }

  // ------------------------------------------------------------------ 工具面板

  Future<void> _handleStyleChanged(MapBaseStyle style) async {
    if (style == _data.style) {
      return;
    }

    _data.setStyle(style);
    await _scene.setStyle(style);
  }

  /// 「回到总览」：拉回当前城市的默认缩放。原来这里写死的是上海中心。
  Future<void> _handleResetCamera() =>
      _scene.flyToCity(_data.city, zoom: MapSceneController.defaultZoom);

  /// 「聚焦城区」与右下角定位按钮：城市级视野。
  Future<void> _handleFocusDowntown() =>
      _scene.flyToCity(_data.city, zoom: MapSceneController.cityZoom);

  Future<void> _showMapTools() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        // 弹窗内也监听数据：原来它拿的是打开那一刻的快照，切完样式看不出选中变化。
        return ListenableBuilder(
          listenable: _data,
          builder: (context, _) => MapToolsSheet(
            currentStyle: _data.style,
            currentLayerMode: _data.layerMode,
            effectiveLayerMode: _data.effectiveLayerMode,
            status: _data.status,
            visibleCount: _data.visibleVenues.length,
            markerCount: _data.markerVenues.length,
            failureDetail: _data.failureDetail,
            onStyleChanged: _handleStyleChanged,
            onLayerModeChanged: _data.setLayerMode,
            onResetCamera: _handleResetCamera,
            onFocusDowntown: _handleFocusDowntown,
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------- 组装

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          // 收起态卡片原本浮在导航栏之上，这段间距一并算进面板高度，
          // 于是同一个面板既能表现"悬浮卡片"，也能表现"贴底面板"。
          final collapsedBottomGap = math.max(
            MediaQuery.paddingOf(context).bottom,
            widget.bottomOverlayInset + 2,
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
                onHostReady: _handleMapCreated,
              ),
              _buildTopControls(),
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
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ListenableBuilder(
          listenable: _data,
          builder: (context, _) => MapSearchAndFilters(
            selectedKind: _data.categoryFilter,
            status: _data.status,
            onCategoryToggled: _data.toggleCategory,
            onFilterPressed: _showMapTools,
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
      child: NotificationListener<DraggableScrollableNotification>(
        onNotification: _sheet.handleNotification,
        child: DraggableScrollableSheet(
          controller: _sheet.sheet,
          initialChildSize: collapsedExtent,
          minChildSize: collapsedExtent,
          maxChildSize: VenueSheetController.maxExtent,
          snap: true,
          snapSizes: const [VenueSheetController.halfExtent],
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
                    scrollController: scrollController,
                    progress: _sheet.progressFor(extent),
                    fullscreenProgress: _sheet.fullscreenProgressFor(extent),
                    collapsedBottomGap: collapsedBottomGap,
                    bottomOverlayInset: widget.bottomOverlayInset,
                    onExpand: _sheet.expand,
                    onCollapse: _sheet.collapse,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
