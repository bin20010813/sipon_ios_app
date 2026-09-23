import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/pages/route_detail_map_page.dart';
import 'package:sipon/services/map/map_models.dart';

void main() {
  test('路线站点解析保留原始顺序、分类与评分', () {
    final stops = parseRouteStops({
      'stops': [
        {
          'barId': 10,
          'bar': {
            'name': '第一站精酿',
            'longitude': 121.1,
            'latitude': 31.1,
            'subtype': 'craft',
            'averageRating': 4.8,
          },
        },
        {
          'barId': 20,
          'name': '第二站 Bistro',
          'longitude': 121.2,
          'latitude': 31.2,
          'subtype': 'bistro',
          'rating': '4.6',
        },
      ],
    });

    expect(stops.map((stop) => stop.id), [10, 20]);
    expect(stops.map((stop) => stop.name), ['第一站精酿', '第二站 Bistro']);
    expect(stops.first.kind, MapVenueKind.craft);
    expect(stops.last.kind, MapVenueKind.bistro);
    expect(stops.map((stop) => stop.rating), [4.8, 4.6]);
  });

  test('没有有效评分的路线站点仍保留空值', () {
    final stops = parseRouteStops({
      'stops': [
        {'barId': 10, 'name': '暂无评分', 'rating': 0},
      ],
    });

    expect(stops.single.rating, isNull);
  });

  test('导航路线必须保留每个相邻站点，缺少中间站坐标时不能跨站连接', () {
    const stops = [
      RouteStop(id: 1, name: '起点', longitude: 121.1, latitude: 31.1),
      RouteStop(id: 2, name: '中间站'),
      RouteStop(id: 3, name: '终点', longitude: 121.3, latitude: 31.3),
    ];

    expect(routeNavigationCoordinates(stops), isNull);
    final complete = [
      stops.first,
      const RouteStop(id: 2, name: '中间站', longitude: 121.2, latitude: 31.2),
      stops.last,
    ];
    final coordinates = routeNavigationCoordinates(complete)!;
    expect(coordinates.map((point) => point.longitude), [121.1, 121.2, 121.3]);
  });
}
