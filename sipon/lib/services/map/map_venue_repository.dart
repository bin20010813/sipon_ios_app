import '../sipon_api_models.dart';
import '../sipon_data_repository.dart';
import 'map_models.dart';
import 'map_viewport.dart';

/// 地图页取数的唯一入口。
///
/// 页面只认这个接口，具体是 mock 还是真接口由 [MapPage] 注入
/// （见 `map_page.dart` 顶部的 `_useMockMapData`）。
abstract interface class MapVenueRepository {
  /// 拉取落在 [viewport] 视野内的酒吧。
  ///
  /// [city] 用于数据源做城市级筛选，同时也是 mock 数据集的 key。
  /// 距离文案由实现方按 `viewport.center` 算好，页面不再自己算。
  Future<List<MapVenue>> fetchVenues({
    required MapViewport viewport,
    required String city,
  });
}

/// 真接口实现：包一层现有的 [SiponDataRepository]。
///
/// 后端就绪时把 `map_page.dart` 里的 `_useMockMapData` 改成 false 即可启用，
/// 页面代码一行都不用动。
class SiponApiMapVenueRepository implements MapVenueRepository {
  SiponApiMapVenueRepository({SiponDataRepository? repository})
    : _repository = repository ?? SiponDataRepository.instance;

  final SiponDataRepository _repository;

  @override
  Future<List<MapVenue>> fetchVenues({
    required MapViewport viewport,
    required String city,
  }) async {
    final fetchBounds = viewport.fetchBounds;
    final bars = await _repository.fetchMapBars(
      bounds: SiponMapBounds(
        west: fetchBounds.west,
        south: fetchBounds.south,
        east: fetchBounds.east,
        north: fetchBounds.north,
      ),
      zoom: viewport.zoom,
    );

    return [
      for (var index = 0; index < bars.length; index++)
        if (bars[index].hasCoordinates)
          _venueFromApi(bars[index], index, viewport.center),
    ];
  }

  MapVenue _venueFromApi(SiponBarMapItem item, int index, MapLatLng origin) {
    final location = MapLatLng(
      longitude: item.longitude!,
      latitude: item.latitude!,
    );

    return MapVenue(
      id: item.id,
      name: item.name,
      longitude: location.longitude,
      latitude: location.latitude,
      kind: MapVenueKind.fromRaw(item.kind),
      rating: item.rating,
      address: item.address,
      // 接口给了现成文案就用它，否则按当前视野中心补算一个。
      distance: item.distance == '距离待计算'
          ? mapFormatDistance(mapDistanceInMeters(origin, location))
          : item.distance,
      tags: item.tags,
      imageAsset: MapAssets.coverForIndex(index),
      imageUrl: item.imageUrl,
    );
  }
}
