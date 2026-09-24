import 'sipon_api_models.dart';
import 'sipon_api_service.dart';

/// 补齐个人页条目对应的酒吧详情，并按首页推荐相同的顺序解析封面。
///
/// 喝过列表通常只有打卡记录 id + barId，想喝列表也不保证携带坐标；因此这里
/// 已经请求 `/api/bars/{id}` 时，不能只留下缩略图，还要把完整酒吧对象并入
/// `bar`，供点击条目打开地图时解析准确坐标。
Future<List<dynamic>> loadProfileBarImages(
  SiponApiService api,
  List<dynamic> entries, {
  required bool checkIns,
}) async {
  final requests = <int, Future<Map<String, dynamic>?>>{};
  Future<Map<String, dynamic>?> fetchBar(int id) async {
    try {
      final response = await api.getBarById(id);
      if (response is! Map) return null;
      return response.cast<String, dynamic>();
    } on Exception {
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchCheckIn(int id) async {
    try {
      final response = await api.getCheckIn(id);
      if (response is! Map) return null;
      return response.cast<String, dynamic>();
    } on Exception {
      return null;
    }
  }

  return Future.wait(
    entries.map((entry) async {
      if (entry is! Map) return entry;
      final map = entry.cast<String, dynamic>();
      Map<String, dynamic>? bar;
      for (final key in ['bar', 'barInfo', 'venue', 'place']) {
        if (map[key] is Map) {
          bar = (map[key] as Map).cast<String, dynamic>();
          break;
        }
      }
      // A check-in's own id identifies the visit, not the bar.
      var rawId =
          map['barId'] ??
          bar?['barId'] ??
          bar?['id'] ??
          (checkIns ? null : map['id']);
      // The list can omit barId. Resolve the visit first; its top-level id
      // must never be used as a bar id even when the two happen to coincide.
      Map<String, dynamic>? checkInDetail;
      if (checkIns && rawId == null) {
        final checkInId = int.tryParse(map['id']?.toString() ?? '');
        if (checkInId != null && checkInId > 0) {
          checkInDetail = await fetchCheckIn(checkInId);
          for (final key in ['bar', 'barInfo', 'venue', 'place']) {
            if (checkInDetail?[key] is Map) {
              bar = (checkInDetail![key] as Map).cast<String, dynamic>();
              break;
            }
          }
          rawId = checkInDetail?['barId'] ?? bar?['barId'] ?? bar?['id'];
        }
      }
      final id = int.tryParse(rawId?.toString() ?? '');
      final source = bar ?? (checkIns ? <String, dynamic>{} : map);
      final parsedSource = SiponBarMapItem.fromJson(source);
      Map<String, dynamic>? fetchedBar;
      if (id != null &&
          id > 0 &&
          (checkIns ||
              !parsedSource.hasCoordinates ||
              parsedSource.resolvedThumbnailUrl == null)) {
        fetchedBar = await requests.putIfAbsent(id, () => fetchBar(id));
      }

      // 接口详情是对应 barId 的权威数据，放在最后覆盖列表里的精简/旧字段；
      // 顶层打卡记录本身保持原样，尤其不能用酒吧 id 覆盖打卡记录 id。
      final nestedId = int.tryParse(
        (bar?['barId'] ?? bar?['id'])?.toString() ?? '',
      );
      final trustedBar =
          checkIns && id != null && nestedId != null && nestedId != id
          ? null
          : bar;
      final resolvedBar = fetchedBar == null
          ? trustedBar
          : checkIns
          ? fetchedBar
          : <String, dynamic>{...?trustedBar, ...fetchedBar};
      final thumbnail = SiponBarMapItem.fromJson(
        resolvedBar ?? (checkIns ? const <String, dynamic>{} : source),
      ).resolvedThumbnailUrl;
      return <String, dynamic>{
        ...map,
        if (checkIns && id != null && id > 0) 'barId': id,
        'bar': ?resolvedBar,
        'profileThumbnailUrl': ?thumbnail,
      };
    }),
  );
}
