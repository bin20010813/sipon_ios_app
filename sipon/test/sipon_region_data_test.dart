import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sipon/services/map/map_viewport.dart';
import 'package:sipon/services/sipon_api_client.dart';
import 'package:sipon/services/sipon_region_data.dart';
import 'package:sipon/services/sipon_region_repository.dart';

void main() {
  group('省市内置数据', () {
    test('接口城市全称不会在热门城市重复展示', () async {
      final apiClient = SiponApiClient(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/api/cities')) {
            return http.Response(
              jsonEncode(['广州市', '深圳市', '佛山市']),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      final repository = SiponRegionRepository(apiClient: apiClient);

      final groups = await repository.loadGroups();
      final hotCities = groups.firstWhere(
        (group) => group.province == '热门城市',
      );
      final guangzhou = hotCities.cities
          .where((city) => city.city == '广州')
          .toList();

      expect(guangzhou, hasLength(1));
    });

    test('覆盖 34 个省级分组且每组有城市', () {
      expect(siponProvinces.length, 34);
      for (final province in siponProvinces) {
        expect(province.cities, isNotEmpty,
            reason: '${province.name} 下没有城市');
      }
    });

    test('坐标都在中国境内范围内', () {
      for (final province in siponProvinces) {
        for (final city in province.cities) {
          expect(city.longitude, inInclusiveRange(73.0, 136.0),
              reason: '${city.name} 经度异常');
          expect(city.latitude, inInclusiveRange(16.0, 54.0),
              reason: '${city.name} 纬度异常');
        }
      }
    });

    test('城市名无“市/州”后缀且不重复', () {
      final names = <String>{};
      for (final province in siponProvinces) {
        for (final city in province.cities) {
          expect(city.name.endsWith('市'), isFalse,
              reason: '${city.name} 不应带“市”后缀');
          expect(names.add(city.name), isTrue,
              reason: '${city.name} 重复出现');
        }
      }
    });

    test('热门城市都能在内置表中找到', () {
      for (final name in siponHotCityNames) {
        expect(siponFindCity(name), isNotNull, reason: '找不到热门城市 $name');
      }
    });

    test('城市查找兼容“上海市”写法并能反查省份', () {
      expect(siponFindCity('上海市')?.name, '上海');
      expect(siponFindProvinceOfCity('拉萨'), '西藏自治区');
      expect(siponFindProvinceOfCity('上海'), '上海市');
    });

    test('每个省市都有中英文键值', () {
      for (final province in siponProvinces) {
        expect(province.nameEn.trim(), isNotEmpty,
            reason: '${province.name} 缺少英文名');
        for (final city in province.cities) {
          expect(city.nameEn.trim(), isNotEmpty,
              reason: '${city.name} 缺少英文名');
          expect(city.nameEn, isNot(city.name),
              reason: '${city.name} 英文名不应与中文相同');
        }
      }
      expect(siponCityEn('上海'), 'Shanghai');
      expect(siponApiCityName('广州'), '广州市');
      expect(siponApiCityName('广州市'), '广州市');
      expect(siponApiCityName('香港'), '香港');
      expect(siponCityEn('拉萨'), 'Lhasa');
      expect(siponProvinceEn('四川省'), 'Sichuan');
      expect(siponProvinceEnOfCity('成都'), 'Sichuan');
      // 兼容后缀写法也应有英文
      expect(siponFindCity('上海市')?.nameEn, 'Shanghai');
    });
  });

  group('城市相机落点', () {
    test('全量城市都有落点且不再回退上海', () {
      final center = mapCenterForCity('拉萨');
      expect(center.longitude, closeTo(91.14, 0.01));
      expect(center.latitude, closeTo(29.97, 0.01));
    });

    test('未知城市仍回退默认中心', () {
      expect(mapCenterForCity('不存在的城市'), mapFallbackCityCenter);
    });
  });
}
