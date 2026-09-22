import 'dart:async';

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
    MapVenueSearchRepository? searchRepository,
  }) : _repository = repository,
       // 仓库若同时具备关键词搜索能力（真接口实现），搜索词变化时补一次
       // 远端搜索；纯本地/mock 仓库没有这层能力，就只做视野内过滤。
       _searchRepository = searchRepository ?? _searchCapabilityOf(repository),
       _city = city,
       _pinnedVenue = initialVenue,
       _venues = initialVenue == null ? const [] : [initialVenue],
       _selectedVenueId = initialVenue?.id;

  static MapVenueSearchRepository? _searchCapabilityOf(
    MapVenueRepository repository,
  ) {
    if (repository is MapVenueSearchRepository) {
      return repository as MapVenueSearchRepository;
    }
    return null;
  }

  final MapVenueRepository _repository;
  final MapVenueSearchRepository? _searchRepository;

  final MapVenue? _pinnedVenue;

  String _city;
  List<MapVenue> _venues;
  MapVenueKind? _categoryFilter;
  MapPoiFilter _poiFilter = MapPoiFilter.none;
  String _searchQuery = '';
  String? _selectedVenueId;
  MapDataStatus _status = MapDataStatus.idle;
  String? _failureDetail;
  MapBaseStyle _style = MapBaseStyle.standard;
  double _zoom = 15.05;

  /// 已取数的视野。下一次相机停下时拿它做「值不值得重拉」的比较。
  MapViewport? _loadedViewport;
  MapViewport? _currentViewport;

  /// 目标版本号：最新一次有效视野意图的版本。
  int _targetGeneration = 0;

  /// 关键词远端搜索的去抖定时器与版本号：连续输入只搜最后一个词，
  /// 城市切换、退出页面后迟到的搜索结果据此作废。
  Timer? _searchDebounce;
  int _searchGeneration = 0;

  /// 待处理请求快照：只保留最新一份（视野、城市、版本）。
  _PendingRequest? _pendingRequest;
  bool _inFlight = false;
  bool _disposed = false;

  String get city => _city;
  MapDataStatus get status => _status;
  String? get failureDetail => _failureDetail;
  MapVenueKind? get categoryFilter => _categoryFilter;
  MapPoiFilter get poiFilter => _poiFilter;
  String get searchQuery => _searchQuery;
  MapBaseStyle get style => _style;
  double get zoom => _zoom;

  /// 当前分类筛选下要显示的酒吧。
  List<MapVenue> get visibleVenues {
    final filter = _categoryFilter;
    final poiFilter = _poiFilter;
    final query = _searchQuery;

    final venues = _venues
        .where((venue) {
          if (filter != null && venue.kind != filter) {
            return false;
          }
          final maxAveragePrice = poiFilter.maxAveragePrice;
          if (maxAveragePrice != null) {
            final averagePrice = venue.averagePrice;
            if (averagePrice == null ||
                !averagePrice.isFinite ||
                averagePrice > maxAveragePrice) {
              return false;
            }
          }
          final minimumRating = poiFilter.minimumRating;
          if (minimumRating != null &&
              (!venue.hasRating ||
                  !venue.rating.isFinite ||
                  venue.rating < minimumRating)) {
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
    final center = _currentViewport?.center;
    if (center != null &&
        center.longitude.isFinite &&
        center.latitude.isFinite) {
      final distances = {
        for (final venue in venues)
          venue.id: mapDistanceInMeters(
            center,
            MapLatLng(longitude: venue.longitude, latitude: venue.latitude),
          ),
      };
      venues.sort((a, b) {
        final order = distances[a.id]!.compareTo(distances[b.id]!);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    }
    return venues;
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
  ///
  /// 版本号语义：先登记最新目标并递增版本号（而不是等真正发请求），请求对象
  /// 保存发起时的视野、城市与版本快照；命中缓存或目标作废时让不匹配的在途
  /// 结果失效。
  Future<void> syncViewport(MapViewport viewport, {bool force = false}) async {
    _zoom = viewport.zoom;
    _currentViewport = viewport;

    if (_disposed) {
      return;
    }

    final inflight = _pendingRequest;
    if (!force &&
        inflight != null &&
        inflight.viewport.zoom == viewport.zoom &&
        inflight.viewport.bounds == viewport.bounds) {
      // 与正在处理的目标完全一致且没有 force 的重复事件，合并掉。
      return;
    }

    // 登记最新目标并递增版本号：目标一变更就作废在途结果。
    final generation = ++_targetGeneration;

    final loaded = _loadedViewport;
    if (!force && loaded != null && !viewport.differsMateriallyFrom(loaded)) {
      // 命中缓存：清空过期的待处理请求，让不匹配的在途结果失效。
      _pendingRequest = null;

      // 之前若停在 loading，恢复缓存对应的 ready/empty 状态并清除旧错误。
      if (_status == MapDataStatus.loading) {
        _status = _venues.isEmpty ? MapDataStatus.empty : MapDataStatus.ready;
        _failureDetail = null;
      }

      // 缩放会影响标签抽样，即使不发网络请求也要通知渲染层重算。
      _notify();
      return;
    }

    _pendingRequest = _PendingRequest(
      viewport: viewport,
      city: _city,
      generation: generation,
    );

    if (!_inFlight) {
      await _pump();
    }
  }

  Future<void> _pump() async {
    _inFlight = true;

    try {
      while (true) {
        final request = _pendingRequest;
        if (request == null) {
          break;
        }
        _pendingRequest = null;

        _moveToLoading();

        List<MapVenue>? loaded;
        Object? failure;
        try {
          loaded = await _repository.fetchVenues(
            viewport: request.viewport,
            city: request.city,
          );
        } catch (error) {
          failure = error;
        }

        // 只有页面未销毁、版本仍是最新目标、城市未切换才提交结果；
        // 过期失败同样直接丢弃，不覆盖当前页面状态。
        if (!_disposed &&
            request.generation == _targetGeneration &&
            request.city == _city) {
          if (loaded != null) {
            _applyVenues(loaded, request.viewport);
          } else {
            _applyFailure(failure);
          }
        }
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
  /// （visibleVenues 按距当前视野中心排序），空列表则清空选中。
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

  /// 应用人均与评分条件。它们与当前酒吧分类、搜索词共同按 AND 关系生效。
  void applyPoiFilter(MapPoiFilter filter) {
    if (_poiFilter == filter) {
      return;
    }

    _poiFilter = filter;
    _reconcileSelection();
    _notify();
  }

  void clearPoiFilter() => applyPoiFilter(MapPoiFilter.none);

  void setSearchQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (_searchQuery == normalized) {
      return;
    }

    _searchQuery = normalized;
    _reconcileSelection();
    _notify();
    _scheduleVenueSearch();
  }

  /// 关键词变化后安排一次远端搜索。视野内过滤已经同步生效，这里补的是
  /// 「跨视野的候选」：去抖后按城市 + 关键词再拉一遍，结果合并进数据集。
  /// 失败保持静默——主数据（视野取数）没有失败，不能让搜索拖垮状态条。
  void _scheduleVenueSearch() {
    _searchDebounce?.cancel();
    final repository = _searchRepository;
    final query = _searchQuery;
    if (repository == null || query.isEmpty) {
      return;
    }

    final generation = ++_searchGeneration;
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await repository.searchVenues(
          city: _city,
          keyword: query,
        );
        if (_disposed || generation != _searchGeneration) {
          return;
        }
        _mergeSearchResults(results);
      } on Exception {
        // 搜索失败时保留视野内过滤结果，与路线规划页的处理一致。
      }
    });
  }

  /// 远端搜索结果并入当前数据集（按 id 去重）。下一次视野取数会整体覆盖
  /// `_venues`，搜索带进来的跨视野点自然消失。
  void _mergeSearchResults(List<MapVenue> results) {
    final knownIds = {for (final venue in _venues) venue.id};
    final merged = [
      for (final venue in results)
        if (knownIds.add(venue.id)) venue,
    ];
    if (merged.isEmpty) {
      return;
    }

    _venues = [..._venues, ...merged];
    _reconcileSelection();
    _notify();
  }

  /// 搜索候选被点击：把它并入数据集并选中。候选可能在当前视野外，不先合并
  /// 的话选中会落空、详情卡片空窗；相机聚焦交给页面的 `_applyStage`。
  void adoptSearchedVenue(MapVenue venue) {
    final known = _venues.any((item) => item.id == venue.id);
    if (known && _selectedVenueId == venue.id) {
      return;
    }

    if (!known) {
      _venues = [..._venues, venue];
    }
    _selectedVenueId = venue.id;
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
    // 作废在途结果与旧城市的待处理视野、缓存标记。
    _targetGeneration++;
    _pendingRequest = null;
    _loadedViewport = null;
    // 旧城市的搜索请求与结果一并作废。
    _currentViewport = null;
    _searchDebounce?.cancel();
    _searchGeneration++;
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
    _searchDebounce?.cancel();
    _searchGeneration++;
    // 作废版本，迟到的回调不会通知已销毁的控制器。
    _targetGeneration++;
    _pendingRequest = null;
    super.dispose();
  }
}

/// 待处理取数请求的快照：发起时的视野、城市与版本。
class _PendingRequest {
  _PendingRequest({
    required this.viewport,
    required this.city,
    required this.generation,
  });

  final MapViewport viewport;
  final String city;
  final int generation;
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
