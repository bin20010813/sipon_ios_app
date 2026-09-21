import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/services/map/checkin_pin_icon.dart';
import 'package:sipon/services/map/map_display_options.dart';
import 'package:sipon/services/map/map_models.dart';
import 'package:sipon/services/map/map_scene_controller.dart';
import 'package:sipon/services/map/sipon_map_protocol.dart';

/// 构造一个点位，避免每个用例都手写一长串 [MapPoint]。
MapPoint _point({
  String id = 'p1',
  String name = '庙前冰室',
  double longitude = 121.47,
  double latitude = 31.22,
  MapVenueKind kind = MapVenueKind.pub,
  double weight = 4.5,
  String? venueId = 'v1',
}) {
  return MapPoint(
    id: id,
    name: name,
    longitude: longitude,
    latitude: latitude,
    kind: kind,
    weight: weight,
    venueId: venueId,
  );
}

/// 构造「圆点 + 文字标注 + 可选选中点」的整帧，只改一个字段即可对比。
MapSceneFrame _frameWith({
  double longitude = 121.47,
  double latitude = 31.22,
  MapVenueKind kind = MapVenueKind.pub,
  String? venueId = 'v1',
  String label = '庙前冰室',
  int? sequence,
  MapPoint? selected,
}) {
  return MapSceneFrame(
    circlePoints: [
      _point(
        longitude: longitude,
        latitude: latitude,
        kind: kind,
        venueId: venueId,
      ),
    ],
    markers: [
      MapMarkerSpec(
        venueId: 'v1',
        label: label,
        longitude: longitude,
        latitude: latitude,
        kind: kind,
        sequence: sequence,
      ),
    ],
    selected: selected,
  );
}

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
      markers: [
        MapMarkerSpec(
          venueId: 'v1',
          label: 'Hope & Sesame',
          longitude: 121.4718,
          latitude: 31.2232,
          kind: MapVenueKind.bistro,
        ),
      ],
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

    test('载荷包含点位、标签和选中态字段', () {
      final payload = encodeRenderFrame(frame, zoom: 15);

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
      expect(payload.containsKey('heatmap'), isFalse);
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

    test('iconCategory 覆盖 category 下发，缺省回退到类型 id', () {
      final payload = encodeRenderFrame(
        MapSceneFrame(
          circlePoints: [
            MapPoint(
              id: 'check-in-v1',
              name: '庙前冰室',
              longitude: 121.4712,
              latitude: 31.2227,
              kind: MapVenueKind.pub,
              weight: 1,
              iconCategory: checkInPinCategory,
            ),
          ],
          markers: [
            MapMarkerSpec(
              venueId: 'v1',
              label: '庙前冰室',
              longitude: 121.4712,
              latitude: 31.2227,
              kind: MapVenueKind.pub,
              iconCategory: checkInPinCategory,
            ),
            MapMarkerSpec(
              venueId: 'v2',
              label: '彼楼',
              longitude: 121.4718,
              latitude: 31.2232,
              kind: MapVenueKind.craft,
            ),
          ],
        ),
        zoom: 15,
      );

      expect(
        (payload['circles']! as List).single,
        containsPair('category', checkInPinCategory),
      );
      expect(payload['markers']! as List, [
        containsPair('category', checkInPinCategory),
        containsPair('category', 'craft'),
      ]);
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
          markers: const [],
        ),
        zoom: 11,
      );

      expect(payload['selected'], isNull);
      expect((payload['circles']! as List).single, isNot(contains('venueId')));
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

  group('相机指令', () {
    test('相机指令使用原生约定的 lng 字段', () {
      final payload = encodeCameraMove(
        longitude: 116.4074,
        latitude: 39.9042,
        zoom: 11.8,
        pitch: 24,
        bearing: -12,
        bottomPadding: 0,
      );

      expect(payload['lng'], 116.4074);
      expect(payload.containsKey('lon'), isFalse);
      expect(payload['lat'], 39.9042);
    });
  });

  group('整帧指纹', () {
    test('语言切换只改标签也必须判定整帧变化', () {
      final zh = MapSceneFrame(
        circlePoints: const [],
        markers: [
          MapMarkerSpec(
            venueId: 'v1',
            label: '庙前冰室',
            longitude: 121.47,
            latitude: 31.22,
            kind: MapVenueKind.pub,
          ),
        ],
      );
      final en = MapSceneFrame(
        circlePoints: const [],
        markers: [
          MapMarkerSpec(
            venueId: 'v1',
            label: 'Hope & Sesame',
            longitude: 121.47,
            latitude: 31.22,
            kind: MapVenueKind.pub,
          ),
        ],
      );

      expect(zh.signature, zh.signature);
      expect(zh.signature, isNot(en.signature));
    });

    test('普通点位只改经度或纬度，signature 必须变化', () {
      expect(
        _frameWith().signature,
        isNot(_frameWith(longitude: 121.48).signature),
      );
      expect(
        _frameWith().signature,
        isNot(_frameWith(latitude: 31.23).signature),
      );
    });

    test('普通点位只改类别或 venueId，signature 必须变化', () {
      expect(
        _frameWith().signature,
        isNot(_frameWith(kind: MapVenueKind.craft).signature),
      );
      expect(
        _frameWith().signature,
        isNot(_frameWith(venueId: 'v2').signature),
      );
    });

    test('选中点只改坐标或类别，signature 必须变化', () {
      final base = _frameWith(selected: _point(id: 's1', name: 'x'));
      final moved = _frameWith(
        selected: _point(id: 's1', name: 'x', longitude: 121.48),
      );
      final recat = _frameWith(
        selected: _point(id: 's1', name: 'x', kind: MapVenueKind.craft),
      );

      expect(base.signature, isNot(moved.signature));
      expect(base.signature, isNot(recat.signature));
    });

    test('只改 iconCategory，signature 必须变化', () {
      MapSceneFrame withPin({String? iconCategory}) => MapSceneFrame(
        circlePoints: [
          MapPoint(
            id: 'p1',
            name: '庙前冰室',
            longitude: 121.47,
            latitude: 31.22,
            kind: MapVenueKind.pub,
            weight: 1,
            iconCategory: iconCategory,
          ),
        ],
        markers: [
          MapMarkerSpec(
            venueId: 'v1',
            label: '庙前冰室',
            longitude: 121.47,
            latitude: 31.22,
            kind: MapVenueKind.pub,
            iconCategory: iconCategory,
          ),
        ],
      );

      expect(withPin().signature, isNot(withPin(iconCategory: 'x').signature));
      expect(
        withPin(iconCategory: checkInPinCategory).signature,
        withPin(iconCategory: checkInPinCategory).signature,
      );
    });

    test('数据完全一致时 signature 保持一致', () {
      expect(_frameWith().signature, _frameWith().signature);
    });

    test('标注名称或编号改变时仍触发刷新', () {
      expect(
        _frameWith().signature,
        isNot(_frameWith(label: 'Hope & Sesame').signature),
      );
      expect(
        _frameWith().signature,
        isNot(_frameWith(sequence: 2).signature),
      );
    });
  });
}
