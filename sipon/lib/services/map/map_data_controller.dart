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
    MapVenue? initialVenue,
  }) : _repository = repository,
       _city = city,
       _pinnedVenue = initialVenue,
       _venues = initialVenue == null ? const [] : [initialVenue],
       _selectedVenueId = initialVenue?.id;

  final MapVenueRepository _repository;

  final MapVenue? _pinnedVenue;

  String _city;
  List<MapVenue> _venues;
  MapVenueKind? _categoryFilter;
  String _searchQuery = '';
  String? _selectedVenueId;
  MapDataStatus _status = MapDataStatus.idle;
  String? _failureDetail;
  MapBaseStyle _style = MapBaseStyle.standard;
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
  String get searchQuery => _searchQuery;
  MapBaseStyle get style => _style;
  double get zoom => _zoom;

  /// 当前分类筛选下要显示的酒吧。
  List<MapVenue> get visibleVenues {
    final filter = _categoryFilter;
    final query = _searchQuery;

    return _venues
        .where((venue) {
          if (filter != null && venue.kind != filter) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }

          final searchable = [
            venue.name,
            venue.address,
            ...venue.tags,
          ].join(' ').toLowerCase();
          return searchable.contains(query);
        })
        .toList(growable: false);
  }

  /// 要画文字标签的那一批（按当前缩放抽样）。
  List<MapVenue> get markerVenues =>
      sampleVenuesForMarkers(visibleVenues, zoom: _zoom);

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

  /// 选中的那一个点，画高亮光环用。
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
    _zoom = viewport.zoom;

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
    final pinned = _pinnedVenue;

    _venues = pinned == null || venues.any((venue) => venue.id == pinned.id)
        ? venues
        : [pinned, ...venues];
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

  void setSearchQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (_searchQuery == normalized) {
      return;
    }

    _searchQuery = normalized;
    _reconcileSelection();
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
