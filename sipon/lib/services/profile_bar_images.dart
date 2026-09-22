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
      final rawId =
          map['barId'] ??
          bar?['barId'] ??
          bar?['id'] ??
          (checkIns ? null : map['id']);
      final id = int.tryParse(rawId?.toString() ?? '');
      final source = bar ?? (checkIns ? <String, dynamic>{} : map);
      final parsedSource = SiponBarMapItem.fromJson(source);
      Map<String, dynamic>? fetchedBar;
      if (id != null &&
          id > 0 &&
          (!parsedSource.hasCoordinates ||
              parsedSource.resolvedThumbnailUrl == null)) {
        fetchedBar = await requests.putIfAbsent(id, () => fetchBar(id));
      }

      // 接口详情是对应 barId 的权威数据，放在最后覆盖列表里的精简/旧字段；
      // 顶层打卡记录本身保持原样，尤其不能用酒吧 id 覆盖打卡记录 id。
      final resolvedBar = fetchedBar == null
          ? bar
          : <String, dynamic>{...?bar, ...fetchedBar};
      final thumbnail = SiponBarMapItem.fromJson(
        resolvedBar ?? source,
      ).resolvedThumbnailUrl;
      return <String, dynamic>{
        ...map,
        'bar': ?resolvedBar,
        'profileThumbnailUrl': ?thumbnail,
      };
    }),
  );
}
