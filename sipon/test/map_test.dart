import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/services/map/map_data_controller.dart';
import 'package:sipon/services/map/map_display_options.dart';
import 'package:sipon/services/map/map_models.dart';
import 'package:sipon/services/map/map_venue_repository.dart';
import 'package:sipon/services/map/map_viewport.dart';
import 'package:sipon/services/map/mock_map_venue_repository.dart';
import 'package:sipon/services/map/venue_sheet_controller.dart';

/// 上海市中心一块典型视野：经度跨 0.12°，纬度跨 0.09°。
const MapViewport _shanghaiViewport = MapViewport(
  bounds: MapBoundsBox(west: 121.4112, south: 31.1777, east: 121.5312, north: 31.2677),
  zoom: 15.05,
);

MapViewport _shifted(double deltaLongitude, {double? zoom}) {
  final bounds = _shanghaiViewport.bounds;

  return MapViewport(
    bounds: MapBoundsBox(
      west: bounds.west + deltaLongitude,
      south: bounds.south,
      east: bounds.east + deltaLongitude,
      north: bounds.north,
    ),
    zoom: zoom ?? _shanghaiViewport.zoom,
  );
}

MapVenue _venue(
  String id, {
  MapVenueKind kind = MapVenueKind.pub,
  double longitude = 121.47,
  double latitude = 31.22,
}) {
  return MapVenue(
    id: id,
    name: id,
    longitude: longitude,
    latitude: latitude,
    kind: kind,
    rating: 4.5,
    address: '上海市黄浦区测试路 1',
    distance: '约1.0km',
    tags: const ['测试'],
    imageAsset: MapAssets.barImage,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapViewport', () {
    test('同一片视野不重新取数', () {
      expect(_shanghaiViewport.differsMateriallyFrom(_shanghaiViewport), isFalse);
    });

    test('缩放没跨档不重拉，跨档就重拉', () {
      // 阈值是 MapViewport.zoomEpsilon（0.35），基准视野的缩放是 15.05。
      expect(_shifted(0, zoom: 15.35).differsMateriallyFrom(_shanghaiViewport), isFalse);
      expect(_shifted(0, zoom: 15.45).differsMateriallyFrom(_shanghaiViewport), isTrue);
    });

    test('预取范围内的小幅平移不重拉，平移出去才重拉', () {
      // 预取范围按经度跨度外扩 20%（0.12 × 0.2 = 0.024）。
      expect(_shifted(0.02).differsMateriallyFrom(_shanghaiViewport), isFalse);
      expect(_shifted(0.06).differsMateriallyFrom(_shanghaiViewport), isTrue);
    });

    test('相机还没就绪（无穷大范围）时一律重拉', () {
      const pending = MapViewport(
        bounds: MapBoundsBox(
          west: double.negativeInfinity,
          south: double.negativeInfinity,
          east: double.infinity,
          north: double.infinity,
        ),
        zoom: 15.05,
      );

      expect(pending.differsMateriallyFrom(_shanghaiViewport), isTrue);
    });
  });

  group('MockMapVenueRepository', () {
    test('只返回落在预取范围内的点，并按视野中心补上距离文案', () async {
      final repository = MockMapVenueRepository(latency: Duration.zero);
      final venues = await repository.fetchVenues(
        viewport: _shanghaiViewport,
        city: '上海',
      );

      expect(venues, isNotEmpty);
      final fetchBounds = _shanghaiViewport.fetchBounds;
      for (final venue in venues) {
        expect(
          fetchBounds.containsPoint(venue.longitude, venue.latitude),
          isTrue,
          reason: '${venue.id} 落在了预取范围之外',
        );
        expect(venue.distance, isNot('距离待计算'));
      }
    });

    test('确定性：同一视野两次取数结果完全一致', () async {
      final repository = MockMapVenueRepository(latency: Duration.zero);
      final first = await repository.fetchVenues(
        viewport: _shanghaiViewport,
        city: '上海',
      );
      final second = await repository.fetchVenues(
        viewport: _shanghaiViewport,
        city: '上海',
      );

      expect(
        second.map((venue) => venue.id).toList(),
        first.map((venue) => venue.id).toList(),
      );
    });

    test('结果按距视野中心由近到远排序', () async {
      final repository = MockMapVenueRepository(latency: Duration.zero);
      final venues = await repository.fetchVenues(
        viewport: _shanghaiViewport,
        city: '上海',
      );
      final center = _shanghaiViewport.center;
      final distances = [
        for (final venue in venues)
          mapDistanceInMeters(
            center,
            MapLatLng(longitude: venue.longitude, latitude: venue.latitude),
          ),
      ];

      expect(distances, orderedEquals(List<double>.from(distances)..sort()));
    });

    test('平移到没有数据的海面上会真返回空', () async {
      final repository = MockMapVenueRepository(latency: Duration.zero);
      final venues = await repository.fetchVenues(
        viewport: const MapViewport(
          bounds: MapBoundsBox(west: 150, south: 10, east: 151, north: 11),
          zoom: 12,
        ),
        city: '上海',
      );

      expect(venues, isEmpty);
    });
  });

  group('MapDataController', () {
    test('分类 pill 真的过滤点位，再点一次取消', () async {
      final controller = MapDataController(
        repository: _StubRepository([
          _venue('pub-1'),
          _venue('craft-1', kind: MapVenueKind.craft),
          _venue('craft-2', kind: MapVenueKind.craft),
        ]),
        city: '上海',
      );
      addTearDown(controller.dispose);

      await controller.syncViewport(_shanghaiViewport);
      expect(controller.visibleVenues, hasLength(3));

      controller.toggleCategory(MapVenueKind.craft);
      expect(
        controller.visibleVenues.map((venue) => venue.id),
        ['craft-1', 'craft-2'],
      );
      // 圆点与热力都跟着筛选走。
      expect(controller.circlePoints, hasLength(2));
      expect(controller.heatmapPoints, hasLength(2));

      controller.toggleCategory(MapVenueKind.craft);
      expect(controller.visibleVenues, hasLength(3));
    });

    test('圆点用全量数据，只有文字标签按缩放抽样', () async {
      final controller = MapDataController(
        repository: _StubRepository([
          for (var index = 0; index < 300; index++) _venue('venue-$index'),
        ]),
        city: '上海',
      );
      addTearDown(controller.dispose);

      // zoom 5 本身低于热力图分界线（effectiveLayerMode 会变成热力），
      // 显式选「点位」让标签抽样逻辑独立于缩放交接被验证。
      controller.setLayerMode(MapLayerMode.pointsOnly);
      await controller.syncViewport(_shifted(0, zoom: 5));
      expect(controller.circlePoints, hasLength(300));
      expect(controller.heatmapPoints, hasLength(300));
      expect(controller.markerVenues, hasLength(mapMarkerLabelLimitForZoom(5)));
    });

    test('圆点带上 venueId，点击才能反查是哪家酒吧', () async {
      final controller = MapDataController(
        repository: _StubRepository([_venue('pub-1')]),
        city: '上海',
      );
      addTearDown(controller.dispose);

      await controller.syncViewport(_shanghaiViewport);
      expect(controller.circlePoints.single.venueId, 'pub-1');
      // 热力点不需要反查，保持为空。
      expect(controller.heatmapPoints.single.venueId, isNull);
    });

    test('视野没有实质变化时不再发请求', () async {
      final repository = _StubRepository([_venue('pub-1')]);
      final controller = MapDataController(repository: repository, city: '上海');
      addTearDown(controller.dispose);

      await controller.syncViewport(_shanghaiViewport);
      await controller.syncViewport(_shifted(0.02));
      expect(repository.callCount, 1);

      await controller.syncViewport(_shifted(0.06));
      expect(repository.callCount, 2);
    });

    test('单飞：在途请求期间进来的新视野排队，最后一次胜出', () async {
      final repository = _QueuedRepository();
      final controller = MapDataController(repository: repository, city: '上海');
      addTearDown(controller.dispose);

      unawaited(controller.syncViewport(_shanghaiViewport));
      unawaited(controller.syncViewport(_shifted(0.06)));
      await pumpEventQueue();
      expect(repository.pending, hasLength(1), reason: '第二次视野应该在排队而不是并发');

      repository.pending.removeAt(0).complete([_venue('old')]);
      await pumpEventQueue();
      expect(repository.pending, hasLength(1), reason: '排队的视野应该接着跑');

      repository.pending.removeAt(0).complete([_venue('new')]);
      await pumpEventQueue();
      expect(controller.visibleVenues.map((venue) => venue.id), ['new']);
    });

    test('切城市会作废在途请求的结果', () async {
      final repository = _QueuedRepository();
      final controller = MapDataController(repository: repository, city: '上海');
      addTearDown(controller.dispose);

      unawaited(controller.syncViewport(_shanghaiViewport));
      await pumpEventQueue();

      controller.setCity('北京');
      repository.pending.removeAt(0).complete([_venue('shanghai-only')]);
      await pumpEventQueue();

      expect(controller.city, '北京');
      expect(controller.visibleVenues, isEmpty, reason: '上海的结果不该落到北京');
    });

    test('选中的酒吧还在就留着，消失了退回最近的一家', () async {
      final repository = _StubRepository([_venue('a'), _venue('b')]);
      final controller = MapDataController(repository: repository, city: '上海');
      addTearDown(controller.dispose);

      await controller.syncViewport(_shanghaiViewport);
      expect(controller.selectedVenue?.id, 'a', reason: '默认选中最近的一家');

      controller.selectVenue('b');
      repository.venues = [_venue('b'), _venue('c')];
      await controller.syncViewport(_shifted(0.06));
      expect(controller.selectedVenue?.id, 'b', reason: '还在就不要动用户的选择');

      repository.venues = [_venue('c'), _venue('d')];
      await controller.syncViewport(_shifted(0.12));
      expect(controller.selectedVenue?.id, 'c');

      repository.venues = const [];
      await controller.syncViewport(_shifted(0.18));
      expect(controller.selectedVenue, isNull);
    });
  });

  group('缩放交接（热力图接手）', () {
    test('选「全部」时，缩过分界线就只剩热力图', () {
      MapLayerMode modeAt(double zoom) =>
          mapEffectiveLayerMode(MapLayerMode.pointsAndHeatmap, zoom);

      // 分界线是 mapHeatmapHandoffZoom（12）。
      expect(modeAt(11.8), MapLayerMode.heatmapOnly, reason: '城市总览就该是热力图');
      expect(modeAt(11.99), MapLayerMode.heatmapOnly);
      expect(modeAt(12), MapLayerMode.pointsAndHeatmap);
      expect(modeAt(15.05), MapLayerMode.pointsAndHeatmap);
    });

    test('显式选「点位」时缩放不接手，否则会剩一张空地图', () {
      expect(
        mapEffectiveLayerMode(MapLayerMode.pointsOnly, 5),
        MapLayerMode.pointsOnly,
      );
      expect(
        mapEffectiveLayerMode(MapLayerMode.pointsOnly, 17),
        MapLayerMode.pointsOnly,
      );
    });

    test('显式选「热力」时任何层级都是热力', () {
      expect(
        mapEffectiveLayerMode(MapLayerMode.heatmapOnly, 17),
        MapLayerMode.heatmapOnly,
      );
    });

    test('相机还没就绪（zoom 非有限值）时不误判成热力图', () {
      expect(
        mapEffectiveLayerMode(MapLayerMode.pointsAndHeatmap, double.nan),
        MapLayerMode.pointsAndHeatmap,
      );
    });

    test('热力图层级下文字标注清空，热力点仍是全量', () async {
      final controller = MapDataController(
        repository: _StubRepository([
          for (var index = 0; index < 50; index++) _venue('venue-$index'),
        ]),
        city: '上海',
      );
      addTearDown(controller.dispose);

      await controller.syncViewport(_shifted(0, zoom: 11.5));
      expect(controller.effectiveLayerMode, MapLayerMode.heatmapOnly);
      expect(controller.markerVenues, isEmpty, reason: '文字标注要全部退场');
      expect(controller.heatmapPoints, hasLength(50), reason: '热力图反倒要全量');
      // 圆点数据本身留着，由图层的 minzoom 摘掉，避免每次跨线都重传 source。
      expect(controller.circlePoints, hasLength(50));

      await controller.syncViewport(_shifted(0, zoom: 13.5));
      expect(controller.markerVenues, hasLength(50), reason: '推回街区尺度标注要回来');
    });

    test('手动选「热力」时文字标注也一并退场', () async {
      final controller = MapDataController(
        repository: _StubRepository([_venue('pub-1')]),
        city: '上海',
      );
      addTearDown(controller.dispose);

      await controller.syncViewport(_shanghaiViewport);
      expect(controller.markerVenues, hasLength(1));

      controller.setLayerMode(MapLayerMode.heatmapOnly);
      expect(controller.markerVenues, isEmpty);
    });

    test('跨过分界线即使不用重新取数也会通知重画', () async {
      final repository = _StubRepository([_venue('pub-1')]);
      final controller = MapDataController(repository: repository, city: '上海');
      addTearDown(controller.dispose);

      await controller.syncViewport(_shifted(0, zoom: 12.2));
      expect(repository.callCount, 1);

      var notifications = 0;
      controller.addListener(() => notifications++);

      // 12.2 → 11.9 只有 0.3 的缩放差，够不上重拉的门槛（0.35），
      // 但跨过了热力图分界线。
      await controller.syncViewport(_shifted(0, zoom: 11.9));
      expect(repository.callCount, 1, reason: '不该重新取数');
      expect(notifications, 1, reason: '但要通知一次，让标注退场');
      expect(controller.effectiveLayerMode, MapLayerMode.heatmapOnly);
    });

    test('选中点带 venueId，热力图层级下还能点开详情', () async {
      final controller = MapDataController(
        repository: _StubRepository([_venue('pub-1')]),
        city: '上海',
      );
      addTearDown(controller.dispose);

      await controller.syncViewport(_shifted(0, zoom: 11.5));
      expect(controller.selectedPoint?.venueId, 'pub-1');
    });
  });

  group('VenueSheetController', () {
    const collapsedExtent = 0.2;

    test('extent 落在哪个档位', () {
      VenueSheetStage stageOf(double extent) =>
          venueSheetStageForExtent(extent, collapsedExtent: collapsedExtent);

      expect(stageOf(collapsedExtent), VenueSheetStage.collapsed);
      // 收起态与半屏态的分界是两者中点 0.375。
      expect(stageOf(0.37), VenueSheetStage.collapsed);
      expect(stageOf(0.38), VenueSheetStage.half);
      expect(stageOf(VenueSheetController.halfExtent), VenueSheetStage.half);
      // 半屏与全屏的分界是两者中点 0.775。
      expect(stageOf(0.77), VenueSheetStage.half);
      expect(stageOf(0.78), VenueSheetStage.full);
      expect(stageOf(VenueSheetController.maxExtent), VenueSheetStage.full);
    });

    test('形变进度在收起态与半屏态之间归一化', () {
      final controller = VenueSheetController();
      addTearDown(controller.dispose);
      controller.updateMetrics(
        availableHeight: 800,
        collapsedExtent: collapsedExtent,
      );

      expect(controller.progressFor(collapsedExtent), 0);
      expect(controller.progressFor(0.375), closeTo(0.5, 0.001));
      expect(controller.progressFor(VenueSheetController.halfExtent), 1);
      // 继续上拖到全屏时形变进度已经饱和，交给全屏进度接手。
      expect(controller.progressFor(0.8), 1);
      expect(controller.fullscreenProgressFor(0.5), 0);
      expect(controller.fullscreenProgressFor(0.775), closeTo(0.5, 0.001));
      expect(controller.fullscreenProgressFor(1), 1);
    });

    test('收起态不让出相机空间，装饰物贴在悬浮卡片上方', () {
      final controller = VenueSheetController();
      addTearDown(controller.dispose);
      controller.updateMetrics(
        availableHeight: 800,
        collapsedExtent: collapsedExtent,
      );

      expect(controller.stage, VenueSheetStage.collapsed);
      expect(controller.cameraBottomPadding, 0);
      expect(controller.ornamentBottomMargin(184), 184);
    });
  });

  group('marker 抽样与指纹', () {
    test('文字标签上限随缩放增长', () {
      expect(mapMarkerLabelLimitForZoom(5), 24);
      expect(mapMarkerLabelLimitForZoom(9.5), 48);
      expect(mapMarkerLabelLimitForZoom(11), 80);
      expect(mapMarkerLabelLimitForZoom(13), 120);
      expect(mapMarkerLabelLimitForZoom(15.05), 180);
      expect(mapMarkerLabelLimitForZoom(17), 260);
    });

    test('抽样后的数量不超过上限，且不足上限时原样返回', () {
      final many = [for (var index = 0; index < 300; index++) _venue('v$index')];
      expect(sampleVenuesForMarkers(many, zoom: 5), hasLength(24));
      expect(sampleVenuesForMarkers(many, zoom: 17), hasLength(260));

      final few = many.take(10).toList();
      expect(sampleVenuesForMarkers(few, zoom: 5), same(few));
    });

    test('指纹只在真正画出来的 marker 数据变化时才变', () {
      const zh = MapMarkerSpec(
        venueId: 'hope-sesame',
        label: '庙前冰室（Hope & Sesame）',
        longitude: 121.4718,
        latitude: 31.2232,
        kind: MapVenueKind.pub,
      );
      const en = MapMarkerSpec(
        venueId: 'hope-sesame',
        label: 'Hope & Sesame',
        longitude: 121.4718,
        latitude: 31.2232,
        kind: MapVenueKind.pub,
      );

      expect(
        markerAnnotationSignature(const [zh]),
        markerAnnotationSignature(const [zh]),
      );
      // 切换语言只改标签文字，也必须重建 annotation。
      expect(
        markerAnnotationSignature(const [zh]),
        isNot(markerAnnotationSignature(const [en])),
      );
    });
  });
}

/// 立即返回一份固定数据的仓库。[venues] 可以在两次取数之间替换。
class _StubRepository implements MapVenueRepository {
  _StubRepository(this.venues);

  List<MapVenue> venues;
  int callCount = 0;

  @override
  Future<List<MapVenue>> fetchVenues({
    required MapViewport viewport,
    required String city,
  }) async {
    callCount++;

    return venues;
  }
}

/// 把每次取数挂起，由测试决定完成顺序，用来验证单飞逻辑。
class _QueuedRepository implements MapVenueRepository {
  final List<Completer<List<MapVenue>>> pending = [];

  @override
  Future<List<MapVenue>> fetchVenues({
    required MapViewport viewport,
    required String city,
  }) {
    final completer = Completer<List<MapVenue>>();
    pending.add(completer);

    return completer.future;
  }
}
