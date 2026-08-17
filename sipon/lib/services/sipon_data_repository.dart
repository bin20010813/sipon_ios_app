import 'sipon_api_client.dart';
import 'sipon_api_models.dart';

class SiponDataRepository {
  SiponDataRepository({SiponApiClient? apiClient})
    : _apiClient = apiClient ?? SiponApiClient();

  static final SiponDataRepository instance = SiponDataRepository();

  final SiponApiClient _apiClient;

  Future<List<SiponBarMapItem>> fetchMapBars({
    required SiponMapBounds bounds,
    required double zoom,
  }) async {
    final json = await _apiClient.getJson(
      '/api/bars/map',
      queryParameters: bounds.toQueryParameters(zoom),
    );
    final response = SiponBarMapResponse.fromJson(json);

    return response.items
        .where((item) => !item.cluster)
        .toList(growable: false);
  }

  Future<List<SiponBarMapItem>> fetchHomeBars() {
    return fetchMapBars(bounds: const SiponMapBounds.china(), zoom: 5);
  }

  Future<List<String>> fetchCities() async {
    final json = await _apiClient.getJson('/api/cities');
    final rawCities = switch (json) {
      List() => json,
      Map() =>
        json['data'] is List
            ? json['data'] as List
            : json['cities'] is List
            ? json['cities'] as List
            : const [],
      _ => const [],
    };

    return rawCities
        .map((city) => city.toString().trim())
        .where((city) => city.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Future<void> refreshMapClusters() async {
    await _apiClient.postAdminJson('/api/admin/map/clusters/refresh');
  }
}
