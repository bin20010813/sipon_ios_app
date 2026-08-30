import 'package:flutter/foundation.dart';

import 'map_display_options.dart';
import 'map_models.dart';
import 'map_venue_repository.dart';
import 'map_viewport.dart';

/// 地图页的数据与筛选状态。
///
/// 这里只管「有哪些酒吧、选中哪个、显示哪些」，完全不碰地图引擎：地图侧的事情
/// 在 [MapSceneController]，面板动画在 [VenueSheetController]。
///
/// 取数用「单飞 + 最后一次胜出」：并发的相机停顿不会叠出多个请求，也不会像原来
/// 那样在 `finally` 里递归调用自己。
class MapDataController extends ChangeNotifier {
  MapDataController({
    required MapVenueRepository repository,
    required String city,
  }) : _repository = repository,
       _city = city;

  final MapVenueRepository _repository;

  String _city;
  List<MapVenue> _venues = const [];
  MapVenueKind? _categoryFilter;
  String? _selectedVenueId;
  MapDataStatus _status = MapDataStatus.idle;
  String? _failureDetail;
  MapBaseStyle _style = MapBaseStyle.standard;
  MapLayerMode _layerMode = MapLayerMode.pointsAndHeatmap;
  double _zoom = 15.05;

  /// 已取数的视野。下一次相机停下时拿它做「值不值得重拉」的比较。
  MapViewport? _loadedViewport;
  MapViewport? _pendingViewport;
  bool _inFlight = false;
  int _requestToken = 0;
  bool _disposed = false;

  String get city => _city;
  MapDataStatus get status => _status;
  String? get failureDetail => _failureDetail;
  MapVenueKind? get categoryFilter => _categoryFilter;
  MapBaseStyle get style => _style;
  MapLayerMode get layerMode => _layerMode;
  double get zoom => _zoom;

  /// 叠上缩放之后真正画出来的图层模式。缩到 [mapHeatmapHandoffZoom] 以下就是
  /// 纯热力图。
  MapLayerMode get effectiveLayerMode =>
      mapEffectiveLayerMode(_layerMode, _zoom);

  /// 当前分类筛选下要显示的酒吧。圆点与热力图层用这份全量数据。
  List<MapVenue> get visibleVenues {
    final filter = _categoryFilter;
    if (filter == null) {
      return _venues;
    }

    return _venues
        .where((venue) => venue.kind == filter)
        .toList(growable: false);
  }

  /// 要画文字标签的那一批（按当前缩放抽样）。
  ///
  /// 到了热力图层级就直接给空表：标注是 `PointAnnotation`，没有按缩放隐藏的
  /// 接口，索性不生成。手动选「热力」也走这条 —— 原来那种模式下圆点藏了，
  /// 文字标签却还赖在图上。
  List<MapVenue> get markerVenues => effectiveLayerMode.showsPoints
      ? sampleVenuesForMarkers(visibleVenues, zoom: _zoom)
      : const [];

  MapVenue? get selectedVenue {
    final id = _selectedVenueId;
    if (id == null) {
      return null;
    }

    for (final venue in _venues) {
      if (venue.id == id) {
        return venue;
      }
    }

    return null;
  }

  List<MapPoint> get circlePoints => [
    for (final venue in visibleVenues)
      venue.toMapPoint(idPrefix: 'point').copyWithVenue(venue.id),
  ];

  /// 热力点由酒吧评分派生：评分越高越热。原来还掺了 4 个写死的假热区，
  /// 数据换城市后它们还赖在上海不走，删掉。
  List<MapPoint> get heatmapPoints => [
    for (final venue in visibleVenues) venue.toMapPoint(idPrefix: 'heat'),
  ];

  /// 选中的那一个点，画高亮光环用。带上 `venueId`：缩到热力图层级时圆点整层
  /// 摘掉了，点这个高亮点仍然要能打开详情。
  MapPoint? get selectedPoint {
    final venue = selectedVenue;
    if (venue == null) {
      return null;
    }

    return venue.toMapPoint(idPrefix: 'selected').copyWithVenue(venue.id);
  }

  bool isSelected(String venueId) => _selectedVenueId == venueId;

  /// 相机停下后调用。视野没有实质变化就直接返回，不发请求。
  Future<void> syncViewport(MapViewport viewport, {bool force = false}) async {
    final previousMode = effectiveLayerMode;
    _zoom = viewport.zoom;

    // 缩放跨过了热力图分界线：这一帧的内容变了（文字标注要全部退场或者回来），
    // 即使不需要重新取数也得通知一次。
    if (effectiveLayerMode != previousMode) {
      _notify();
    }

    final loaded = _loadedViewport;
    if (!force && loaded != null && !viewport.differsMateriallyFrom(loaded)) {
      return;
    }

    if (_inFlight) {
      // 前一次还在路上：记下最新视野，由取数循环收尾时接着跑。
      _pendingViewport = viewport;
      return;
    }

    await _pump(viewport);
  }

  Future<void> _pump(MapViewport first) async {
    _inFlight = true;
    var current = first;

    try {
      while (true) {
        final token = ++_requestToken;
        _moveToLoading();

        List<MapVenue>? loaded;
        Object? failure;
        try {
          loaded = await _repository.fetchVenues(
            viewport: current,
            city: _city,
          );
        } catch (error) {
          failure = error;
        }

        if (_disposed) {
          return;
        }

        // 期间城市变了或者被外部作废了，这批结果直接丢弃。
        if (token == _requestToken) {
          if (loaded != null) {
            _applyVenues(loaded, current);
          } else {
            _applyFailure(failure);
          }
        }

        final pending = _pendingViewport;
        if (pending == null) {
          break;
        }
        _pendingViewport = null;
        current = pending;
      }
    } finally {
      _inFlight = false;
    }
  }

  void _moveToLoading() {
    if (_status == MapDataStatus.loading) {
      return;
    }

    _status = MapDataStatus.loading;
    _failureDetail = null;
    _notify();
  }

  void _applyVenues(List<MapVenue> venues, MapViewport viewport) {
    _venues = venues;
    _loadedViewport = viewport;
    _zoom = viewport.zoom;
    _status = venues.isEmpty ? MapDataStatus.empty : MapDataStatus.ready;
    _failureDetail = null;
    _reconcileSelection();
    _notify();
  }

  void _applyFailure(Object? error) {
    _status = MapDataStatus.failed;
    _failureDetail = error?.toString();
    _notify();
  }

  /// 新数据到达或筛选变化后对齐选中态：原来选的还在就留着，否则退回第一个
  /// （数据源按距视野中心排序，第一个就是最近的），空列表则清空选中。
  void _reconcileSelection() {
    final candidates = visibleVenues;
    if (candidates.isEmpty) {
      _selectedVenueId = null;
      return;
    }

    final selectedId = _selectedVenueId;
    if (selectedId != null &&
        candidates.any((venue) => venue.id == selectedId)) {
      return;
    }

    _selectedVenueId = candidates.first.id;
  }

  void selectVenue(String? venueId) {
    if (_selectedVenueId == venueId) {
      return;
    }

    _selectedVenueId = venueId;
    _notify();
  }

  /// 再点一次已选中的分类就取消筛选（顶部没有「全部」pill）。
  void toggleCategory(MapVenueKind kind) {
    _categoryFilter = _categoryFilter == kind ? null : kind;
    _reconcileSelection();
    _notify();
  }

  void setLayerMode(MapLayerMode mode) {
    if (_layerMode == mode) {
      return;
    }

    _layerMode = mode;
    _notify();
  }

  void setStyle(MapBaseStyle style) {
    if (_style == style) {
      return;
    }

    _style = style;
    _notify();
  }

  /// 切城市：作废在途请求并清空已加载视野，下一次 [syncViewport] 必定重新取数。
  void setCity(String city) {
    if (_city == city) {
      return;
    }

    _city = city;
    _requestToken++;
    _loadedViewport = null;
    _venues = const [];
    _selectedVenueId = null;
    _status = MapDataStatus.loading;
    _failureDetail = null;
    _notify();
  }

  /// 底图样式换了以后图层要重建，数据本身没变，但需要重新下发一次。
  void invalidateLoadedViewport() {
    _loadedViewport = null;
  }

  void _notify() {
    if (_disposed) {
      return;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

extension on MapPoint {
  /// 给圆点补上 `venueId`，点击圆点时才能反查是哪家酒吧。
  MapPoint copyWithVenue(String venueId) => MapPoint(
    id: id,
    name: name,
    longitude: longitude,
    latitude: latitude,
    kind: kind,
    weight: weight,
    venueId: venueId,
  );
}
