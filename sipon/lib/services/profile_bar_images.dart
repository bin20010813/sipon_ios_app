import 'sipon_api_models.dart';
import 'sipon_api_service.dart';

/// Resolve profile covers with the same image ordering as home recommendations.
Future<List<dynamic>> loadProfileBarImages(
  SiponApiService api,
  List<dynamic> entries, {
  required bool checkIns,
}) async {
  final requests = <int, Future<String?>>{};
  Future<String?> fetchThumbnail(int id) async {
    try {
      final response = await api.getBarById(id);
      if (response is! Map) return null;
      return SiponBarMapItem.fromJson(
        response.cast<String, dynamic>(),
      ).resolvedThumbnailUrl;
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
      var thumbnail = SiponBarMapItem.fromJson(source).resolvedThumbnailUrl;
      if (thumbnail == null && id != null && id > 0) {
        thumbnail = await requests.putIfAbsent(id, () => fetchThumbnail(id));
      }
      return <String, dynamic>{
        ...map,
        'profileThumbnailUrl': ?thumbnail,
      };
    }),
  );
}
