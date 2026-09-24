import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/services/profile_bar_images.dart';
import 'package:sipon/services/sipon_api_service.dart';

class _BarApi extends SiponApiService {
  final requestedIds = <int>[];
  final requestedCheckIns = <int>[];
  int? resolvedBarId;

  @override
  Future<dynamic> getCheckIn(int id) async {
    requestedCheckIns.add(id);
    return {'id': id, if (resolvedBarId != null) 'barId': resolvedBarId};
  }

  @override
  Future<dynamic> getBarById(int id) async {
    requestedIds.add(id);
    return {
      'id': id,
      'name': '酒吧 $id',
      'longitude': 121.40 + id / 1000,
      'latitude': 31.20 + id / 1000,
      'thumbnailUrl': '/api/bars/$id/images/thumb/0',
    };
  }
}

void main() {
  test('resolves a missing barId through the check-in detail', () async {
    final api = _BarApi()..resolvedBarId = 205;
    final result = await loadProfileBarImages(api, [
      {'id': 11, 'barName': 'Bar A'},
    ], checkIns: true);

    final entry = (result.single as Map).cast<String, dynamic>();
    expect(entry['id'], 11);
    expect(entry['barId'], 205);
    expect((entry['bar'] as Map)['id'], 205);
    expect(api.requestedCheckIns, [11]);
    expect(api.requestedIds, [205]);
  });

  test('never uses a check-in id as a bar id', () async {
    final api = _BarApi();
    final result = await loadProfileBarImages(api, [
      {'id': 11, 'barName': 'Bar A'},
    ], checkIns: true);

    final entry = (result.single as Map).cast<String, dynamic>();
    expect(entry['id'], 11);
    expect(entry.containsKey('barId'), isFalse);
    expect(api.requestedCheckIns, [11]);
    expect(api.requestedIds, isEmpty);
  });

  test(
    'uses the barId detail over complete but mismatched embedded bar',
    () async {
      final api = _BarApi();
      final result = await loadProfileBarImages(api, [
        {
          'id': 11,
          'barId': 205,
          'bar': {
            'id': 11,
            'name': 'Wrong bar',
            'longitude': 120.0,
            'latitude': 30.0,
            'thumbnailUrl': '/wrong-thumb',
          },
        },
      ], checkIns: true);

      final entry = (result.single as Map).cast<String, dynamic>();
      final bar = (entry['bar'] as Map).cast<String, dynamic>();
      expect(bar['id'], 205);
      expect(bar['name'], '酒吧 205');
      expect(bar['longitude'], closeTo(121.605, 0.000001));
      expect(api.requestedIds, [205]);
    },
  );

  test('喝过条目保留打卡 id，并用 barId 详情补齐 POI 坐标', () async {
    final api = _BarApi();
    final result = await loadProfileBarImages(api, [
      {'id': 11, 'barId': 101, 'barName': 'Bar A'},
    ], checkIns: true);

    final entry = (result.single as Map).cast<String, dynamic>();
    final bar = (entry['bar'] as Map).cast<String, dynamic>();
    expect(entry['id'], 11, reason: '顶层 id 必须继续表示打卡记录');
    expect(bar['id'], 101);
    expect(bar['longitude'], closeTo(121.501, 0.000001));
    expect(bar['latitude'], closeTo(31.301, 0.000001));
    expect(entry['profileThumbnailUrl'], '/api/bars/101/images/thumb/0');
    expect(api.requestedIds, [101]);
  });

  test('想喝条目缺少坐标时按酒吧 id 补齐详情', () async {
    final api = _BarApi();
    final result = await loadProfileBarImages(api, [
      {'id': 102, 'name': 'Bar B', 'thumbnailUrl': '/existing-thumb'},
    ], checkIns: false);

    final entry = (result.single as Map).cast<String, dynamic>();
    final bar = (entry['bar'] as Map).cast<String, dynamic>();
    expect(bar['id'], 102);
    expect(bar['longitude'], closeTo(121.502, 0.000001));
    expect(bar['latitude'], closeTo(31.302, 0.000001));
    expect(api.requestedIds, [102], reason: '已有缩略图也必须补取缺失的坐标');
  });

  test('条目已有完整坐标与封面时不重复请求详情', () async {
    final api = _BarApi();
    final result = await loadProfileBarImages(api, [
      {
        'id': 103,
        'name': 'Bar C',
        'longitude': 121.6,
        'latitude': 31.3,
        'thumbnailUrl': '/existing-thumb',
      },
    ], checkIns: false);

    final entry = (result.single as Map).cast<String, dynamic>();
    expect(entry['profileThumbnailUrl'], '/existing-thumb');
    expect(entry.containsKey('bar'), isFalse);
    expect(api.requestedIds, isEmpty);
  });
}
