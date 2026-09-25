import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sipon/features/map/controllers/map_data_controller.dart';
import 'package:sipon/features/map/data/map_venue_repository.dart';
import 'package:sipon/shared/services/sipon_api_client.dart';
import 'package:sipon/shared/services/sipon_api_config.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/shared/services/sipon_city_controller.dart';
import 'package:sipon/shared/services/sipon_data_repository.dart';

void main() {
  const config = SiponApiConfig(baseUrl: 'https://api.example.test');

  test('手动选城后附近查询锚点使用该城市中心', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SiponCityController();
    addTearDown(controller.dispose);

    await controller.selectCity('北京');
    expect(controller.city, '北京');
    expect(controller.queryAnchor!.longitude, closeTo(116.41, 0.1));
    expect(controller.queryAnchor!.latitude, closeTo(39.90, 0.1));
  });

  test('nearby 仅发送文档支持的坐标、半径和 limit', () async {
    final api = SiponApiService(
      apiClient: SiponApiClient(
        config: config,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/bars/nearby');
          expect(request.url.queryParameters, {
            'longitude': '116.41',
            'latitude': '39.9',
            'radiusMeters': '3000',
            'limit': '20',
          });
          return http.Response('[]', 200);
        }),
      ),
    );

    expect(
      await api.getNearbyBars(
        longitude: 116.41,
        latitude: 39.9,
        radiusMeters: 3000,
      ),
      isEmpty,
    );
  });

  test('地图搜索发送全局城市和关键词，并展示跨视野结果', () async {
    final requests = <Uri>[];
    final repository = SiponApiMapVenueRepository(
      repository: SiponDataRepository(
        apiClient: SiponApiClient(
          config: config,
          httpClient: MockClient((request) async {
            requests.add(request.url);
            return http.Response.bytes(
              utf8.encode(
                jsonEncode([
                  {
                    'id': 7,
                    'name': '北京精酿',
                    'barSubtype': 'craft',
                    'longitude': 116.40,
                    'latitude': 39.90,
                  },
                ]),
              ),
              200,
            );
          }),
        ),
      ),
    );
    expect(
      (await repository.searchVenues(city: '北京', keyword: '精酿')).single.name,
      '北京精酿',
    );
    requests.clear();
    final controller = MapDataController(repository: repository, city: '北京');
    addTearDown(controller.dispose);

    controller.setSearchQuery('精酿');
    await Future<void>.delayed(const Duration(milliseconds: 450));

    expect(requests, hasLength(1));
    expect(requests.single.path, '/api/bars');
    expect(requests.single.queryParameters['city'], '北京市');
    expect(requests.single.queryParameters['keyword'], '精酿');
    expect(controller.failureDetail, isNull);
    expect(controller.visibleVenues.single.name, '北京精酿');
  });
}
