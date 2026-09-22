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

  test('没有有效评分的路线站点保留空值供胶囊显示 --', () {
    final stops = parseRouteStops({
      'stops': [
        {'barId': 10, 'name': '暂无评分', 'rating': 0},
      ],
    });

    expect(stops.single.rating, isNull);
  });
}
