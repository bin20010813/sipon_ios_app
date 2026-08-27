import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/services/map/map_display_options.dart';
import 'package:sipon/services/map/map_models.dart';
import 'package:sipon/services/map/map_scene_controller.dart';
import 'package:sipon/services/map/sipon_map_protocol.dart';

void main() {
  group('encodeRenderFrame', () {
    final frame = MapSceneFrame(
      circlePoints: [
        MapPoint(
          id: 'point-v1',
          name: '庙前冰室',
          longitude: 121.4712,
          latitude: 31.2227,
          kind: MapVenueKind.pub,
          weight: 4.5,
          venueId: 'v1',
        ),
      ],
      heatmapPoints: [
        MapPoint(
          id: 'heat-v1',
          name: '庙前冰室',
          longitude: 121.4712,
          latitude: 31.2227,
          kind: MapVenueKind.craft,
          weight: 4.5,
        ),
      ],
      markers: [
        MapMarkerSpec(
          venueId: 'v1',
          label: 'Hope & Sesame',
          longitude: 121.4718,
          latitude: 31.2232,
          kind: MapVenueKind.bistro,
        ),
      ],
      layerMode: MapLayerMode.pointsAndHeatmap,
      selected: MapPoint(
        id: 'selected-v1',
        name: '庙前冰室',
        longitude: 121.4712,
        latitude: 31.2227,
        kind: MapVenueKind.party,
        weight: 4.5,
        venueId: 'v1',
      ),
    );

    test('载荷包含四组图层的全量字段，snake_case 键与原生约定一致', () {
      final payload = encodeRenderFrame(frame, zoom: 15);

      expect(payload['layerMode'], 'pointsAndHeatmap');
      expect(payload['circleFade'], isA<double>());

      expect(
        (payload['circles']! as List).single,
        allOf(
          containsPair('id', 'point-v1'),
          containsPair('lat', 31.2227),
          containsPair('lng', 121.4712),
          containsPair('category', 'pub'),
          containsPair('venueId', 'v1'),
        ),
      );
      expect(
        (payload['heatmap']! as List).single,
        allOf(
          containsPair('id', 'heat-v1'),
          containsPair('weight', 4.5),
          // 协议约定（指南 §3.2）：热力点不携带 category。
          isNot(contains('category')),
        ),
      );
      expect(
        (payload['markers']! as List).single,
        allOf(
          containsPair('venueId', 'v1'),
          containsPair('label', 'Hope & Sesame'),
          containsPair('category', 'bistro'),
        ),
      );
      expect(
        payload['selected'],
        allOf(
          containsPair('id', 'selected-v1'),
          containsPair('venueId', 'v1'),
          containsPair('category', 'party'),
        ),
      );
    });

    test('没有选中点时 selected 为 null；圆点的 venueId 缺省时不下发该键', () {
      final payload = encodeRenderFrame(
        MapSceneFrame(
          circlePoints: [
            MapPoint(
              id: 'point-h',
              name: '',
              longitude: 0,
              latitude: 0,
              kind: MapVenueKind.pub,
              weight: 0,
            ),
          ],
          heatmapPoints: const [],
          markers: const [],
          layerMode: MapLayerMode.heatmapOnly,
        ),
        zoom: 11,
      );

      expect(payload['selected'], isNull);
      expect((payload['circles']! as List).single, isNot(contains('venueId')));
    });

    test('circleFade 按最新缩放在淡入区间内插值（§5.3 曲线）', () {
      // 分界线以下完全透明，恢复线以上到达满透明度，中间线性。
      expect(encodeRenderFrame(frame, zoom: 12)['circleFade'], 0.0);
      final mid = encodeRenderFrame(frame, zoom: 12.6);
      expect(mid['circleFade'], closeTo(mapCircleFullOpacity / 2, 1e-9));
      expect(encodeRenderFrame(frame, zoom: 13.2)['circleFade'],
          mapCircleFullOpacity);
      expect(encodeRenderFrame(frame, zoom: 16)['circleFade'],
          mapCircleFullOpacity);
    });
  });

  group('parseViewportPayload', () {
    test('合法数字原样解析为视野矩形 + 缩放', () {
      final viewport = parseViewportPayload({
        'west': 121.4,
        'south': 31.2,
        'east': 121.5,
        'north': 31.3,
        'zoom': 15.05,
      });

      expect(viewport, isNotNull);
      expect(viewport!.west, 121.4);
      expect(viewport.south, 31.2);
      expect(viewport.east, 121.5);
      expect(viewport.north, 31.3);
      expect(viewport.zoom, 15.05);
    });

    test('非数字或非法形状返回 null，由调用方兜底中国范围', () {
      expect(parseViewportPayload(null), isNull);
      expect(parseViewportPayload('nope'), isNull);
      expect(
        parseViewportPayload({
          'west': double.nan,
          'south': 0,
          'east': 1,
          'north': 1,
          'zoom': 1,
        }),
        isNull,
        reason: 'NaN 不算合法视野',
      );
      expect(
        parseViewportPayload({'west': 1, 'south': 0, 'east': -1, 'north': 1}),
        isNull,
        reason: '东西颠倒不算合法视野',
      );
    });

    test('数字字符串也能容错解析（channel 编解码兜底）', () {
      final viewport = parseViewportPayload({
        'west': '121.4',
        'south': '31.2',
        'east': '121.5',
        'north': '31.3',
        'zoom': '15.05',
      });
      expect(viewport?.west, 121.4);
      expect(viewport?.zoom, 15.05);
    });
  });

  group('parseVenueTapped', () {
    test('命中 annotation 时回传 venueId，空白点击返回 null', () {
      expect(parseVenueTapped({'venueId': 'v1'}), 'v1');
      expect(parseVenueTapped({'venueId': ''}), isNull);
      expect(parseVenueTapped(null), isNull);
      expect(parseVenueTapped(<Object?, Object?>{}), isNull);
    });
  });

  group('setup 与样式协议', () {
    test('初始 setup 带城市与底图档位 id', () {
      final setup = encodeSetup(city: '上海', style: MapBaseStyle.satellite);

      expect(setup['city'], '上海');
      expect(setup['styleId'], 'satellite');
    });

    test('未知档位 id 归一到 standard（widget 初始样式分支）', () {
      expect(MapBaseStyle.fromId('muted'), MapBaseStyle.muted);
      expect(MapBaseStyle.fromId('whatever'), MapBaseStyle.standard);
    });

    test('marker 资产表覆盖全部酒馆类型', () {
      final assets = encodeMarkerAssets()['assets']! as Map<String, Object?>;

      expect(assets.keys.toSet(), MapVenueKind.values.map((k) => k.id).toSet());
    });
  });

  group('整帧指纹', () {
    test('语言切换只改标签也必须判定整帧变化', () {
      final zh = MapSceneFrame(
        circlePoints: const [],
        heatmapPoints: const [],
        markers: [
          MapMarkerSpec(
            venueId: 'v1',
            label: '庙前冰室',
            longitude: 121.47,
            latitude: 31.22,
            kind: MapVenueKind.pub,
          ),
        ],
        layerMode: MapLayerMode.pointsAndHeatmap,
      );
      final en = MapSceneFrame(
        circlePoints: const [],
        heatmapPoints: const [],
        markers: [
          MapMarkerSpec(
            venueId: 'v1',
            label: 'Hope & Sesame',
            longitude: 121.47,
            latitude: 31.22,
            kind: MapVenueKind.pub,
          ),
        ],
        layerMode: MapLayerMode.pointsAndHeatmap,
      );

      expect(zh.signature, zh.signature);
      expect(zh.signature, isNot(en.signature));
    });
  });
}
