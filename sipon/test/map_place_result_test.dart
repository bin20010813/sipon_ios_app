import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/services/map/map_place_result.dart';

void main() {
  test('MapKit place payload keeps address, city, and coordinates', () {
    final place = MapPlaceResult.fromPayload({
      'name': '复兴公园',
      'address': '上海市黄浦区皋兰路 2 号',
      'city': '上海市',
      'lat': 31.216,
      'lng': 121.464,
    });

    expect(place?.name, '复兴公园');
    expect(place?.address, '上海市黄浦区皋兰路 2 号');
    expect(place?.city, '上海市');
    expect(place?.location.latitude, 31.216);
    expect(place?.location.longitude, 121.464);
  });

  test('invalid coordinates are not offered as selectable places', () {
    expect(MapPlaceResult.fromPayload({'name': '无坐标'}), isNull);
    expect(
      MapPlaceResult.fromPayload({'name': '无效纬度', 'lat': 100, 'lng': 121}),
      isNull,
    );
  });
}
