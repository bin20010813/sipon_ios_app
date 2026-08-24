import 'map_models.dart';
import 'map_venue_repository.dart';
import 'map_viewport.dart';

/// 后端接口还没接入时使用的假数据源。
///
/// 两个刻意的设计：
/// 1. **确定性**。用固定种子的线性同余生成器，不用 `Random()`。同一个城市每次
///    生成的点位完全一样，用户平移出去再回来点位不会跳，测试也能断言。
/// 2. **按视野取数**。和真接口一样只返回落在 [MapViewport.fetchBounds] 里的点，
///    距离按视野中心实时算。于是「平移到没有数据的区域」这条分支能被真实触发，
///    不是写死的 4 条精选。
class MockMapVenueRepository implements MapVenueRepository {
  MockMapVenueRepository({
    this.latency = const Duration(milliseconds: 180),
    this.venuesPerCity = 40,
  });

  /// 模拟网络往返，让加载态在真机上能被看见。测试里传 [Duration.zero]。
  final Duration latency;
  final int venuesPerCity;

  final Map<String, List<MapVenue>> _cache = {};

  @override
  Future<List<MapVenue>> fetchVenues({
    required MapViewport viewport,
    required String city,
  }) async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }

    final bounds = viewport.fetchBounds;
    final origin = viewport.center;
    final matches =
        <({MapVenue venue, double meters})>[
          for (final venue in _venuesForCity(city))
            if (bounds.containsPoint(venue.longitude, venue.latitude))
              (
                venue: venue,
                meters: mapDistanceInMeters(
                  origin,
                  MapLatLng(
                    longitude: venue.longitude,
                    latitude: venue.latitude,
                  ),
                ),
              ),
        ]..sort((a, b) => a.meters.compareTo(b.meters));

    return [
      for (final match in matches)
        match.venue.copyWith(distance: mapFormatDistance(match.meters)),
    ];
  }

  List<MapVenue> _venuesForCity(String city) =>
      _cache.putIfAbsent(city, () => _generateVenues(city));

  List<MapVenue> _generateVenues(String city) {
    final center = mapCenterForCity(city);
    final random = _SeededRandom(_stableHash(city));
    final blocks = _cityBlocks[city] ?? _cityBlocks['上海']!;
    final districts = _cityDistricts[city] ?? _cityDistricts['上海']!;
    final venues = <MapVenue>[
      // 上海保留这 4 家真实精选（坐标、地址、标签都来自原来的兜底数据），
      // 首页/详情页的截图素材也是按它们准备的。
      if (city == '上海') ..._shanghaiFeaturedVenues,
    ];

    for (var index = venues.length; index < venuesPerCity; index++) {
      final kind = MapVenueKind.values[index % MapVenueKind.values.length];
      final block = blocks[index % blocks.length];
      final district = districts[index % districts.length];

      venues.add(
        MapVenue(
          id: '${_citySlug(city)}-mock-$index',
          name: '$block${_kindNameSuffix(kind)}',
          // 围绕城市中心散布，经度跨度约 ±0.05°（≈5km），纬度略窄一些。
          longitude: center.longitude + random.nextSigned() * 0.052,
          latitude: center.latitude + random.nextSigned() * 0.038,
          kind: kind,
          rating: 4.1 + random.nextInt(9) * 0.1,
          address: '$city市$district$block ${120 + random.nextInt(680)}',
          // 真实距离在 fetchVenues 里按视野中心覆盖，这里只是占位。
          distance: '距离待计算',
          tags: _tagsForKind(kind),
          imageAsset: MapAssets.coverForIndex(index),
        ),
      );
    }

    return List<MapVenue>.unmodifiable(venues);
  }
}

/// 固定种子的线性同余生成器。够随机到看起来自然，又完全可复现。
class _SeededRandom {
  _SeededRandom(int seed) : _state = (seed & 0x7FFFFFFF) | 1;

  int _state;

  int nextInt(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;

    return _state % max;
  }

  double nextDouble() => nextInt(1 << 24) / (1 << 24);

  /// -1.0 ~ 1.0
  double nextSigned() => nextDouble() * 2 - 1;
}

/// 与平台无关的字符串散列。`String.hashCode` 不保证跨进程稳定，不能用来做种子。
int _stableHash(String value) {
  var hash = 7;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }

  return hash;
}

String _citySlug(String city) => 'city${_stableHash(city)}';

String _kindNameSuffix(MapVenueKind kind) {
  return switch (kind) {
    MapVenueKind.pub => '清吧',
    MapVenueKind.craft => '精酿工坊',
    MapVenueKind.bistro => '小酒馆',
    MapVenueKind.party => '夜店',
    MapVenueKind.livehouse => 'Livehouse',
  };
}

List<String> _tagsForKind(MapVenueKind kind) {
  return switch (kind) {
    MapVenueKind.pub => const ['安静清吧', '经典调酒'],
    MapVenueKind.craft => const ['精酿', '自酿啤酒'],
    MapVenueKind.bistro => const ['餐酒搭配', '微醺小食'],
    MapVenueKind.party => const ['派对夜场', '电音'],
    MapVenueKind.livehouse => const ['现场音乐', '乐队演出'],
  };
}

const List<MapVenue> _shanghaiFeaturedVenues = [
  MapVenue(
    id: 'hope-sesame',
    name: '庙前冰室（Hope & Sesame）',
    longitude: 121.4718,
    latitude: 31.2232,
    kind: MapVenueKind.pub,
    rating: 4.9,
    address: '上海市黄浦区复兴中路 579',
    distance: '距离待计算',
    tags: ['鸡尾酒吧', '中式复古风'],
    imageAsset: MapAssets.barImage,
  ),
  MapVenue(
    id: 'speak-low',
    name: 'Speak Low（彼楼）',
    longitude: 121.4734,
    latitude: 31.2251,
    kind: MapVenueKind.bistro,
    rating: 4.9,
    address: '上海市黄浦区复兴中路 579',
    distance: '距离待计算',
    tags: ['经典吧台', 'Speakeasy'],
    imageAsset: MapAssets.speakLowImage,
  ),
  MapVenue(
    id: 'janes-hooch',
    name: 'Janes and Hooch',
    longitude: 121.4686,
    latitude: 31.2203,
    kind: MapVenueKind.party,
    rating: 4.5,
    address: '上海市黄浦区巨鹿路 158',
    distance: '距离待计算',
    tags: ['派对', '经典调酒'],
    imageAsset: MapAssets.janesImage,
  ),
  MapVenue(
    id: 'play-house',
    name: 'Play House 电音夜店',
    longitude: 121.4749,
    latitude: 31.2208,
    kind: MapVenueKind.craft,
    rating: 4.8,
    address: '上海市黄浦区淮海中路 333',
    distance: '距离待计算',
    tags: ['精酿', '现场音乐'],
    imageAsset: MapAssets.playHouseImage,
  ),
];

/// 各城市的街区名，用来拼酒吧名和地址。
const Map<String, List<String>> _cityBlocks = {
  '上海': [
    '复兴中路',
    '巨鹿路',
    '安福路',
    '武康路',
    '思南路',
    '新天地',
    '外滩源',
    '愚园路',
    '延平路',
    '永康路',
    '陕西南路',
    '大学路',
  ],
  '北京': [
    '三里屯',
    '工体北路',
    '鼓楼东大街',
    '五道营',
    '南锣鼓巷',
    '朝阳门',
    '国子监',
    '什刹海',
    '亮马桥',
    '双井',
    '大望路',
    '五棵松',
  ],
  '深圳': [
    '蛇口海上世界',
    '南山科苑',
    '华侨城',
    '车公庙',
    '福田CBD',
    '万象天地',
    '八卦岭',
    '大冲',
    '深大南路',
    '海岸城',
    '园岭',
    '龙华壹方',
  ],
  '广州': [
    '珠江新城',
    '沙面岛',
    '东山口',
    '天河北',
    '五羊新城',
    '员村',
    '琶洲',
    '同福路',
    '文明路',
    '客村',
    '昌岗',
    '北京路',
  ],
  '成都': [
    '玉林路',
    '镗钯街',
    '奎星楼',
    '太古里',
    '望平街',
    '交子公园',
    '香槟广场',
    '天府三街',
    '少城',
    '宽窄巷子',
    '建设巷',
    '锦江边',
  ],
  '杭州': [
    '湖滨银泰',
    '嘉里中心',
    '天目里',
    '滨江星光',
    '南宋御街',
    '武林路',
    '钱江新城',
    '文二路',
    '西溪湿地',
    '运河边',
    '黄龙万科',
    '滨盛路',
  ],
};

const Map<String, List<String>> _cityDistricts = {
  '上海': ['黄浦区', '静安区', '徐汇区', '长宁区'],
  '北京': ['朝阳区', '东城区', '西城区', '海淀区'],
  '深圳': ['南山区', '福田区', '罗湖区', '龙华区'],
  '广州': ['天河区', '越秀区', '海珠区', '荔湾区'],
  '成都': ['武侯区', '锦江区', '青羊区', '高新区'],
  '杭州': ['上城区', '西湖区', '滨江区', '拱墅区'],
};
