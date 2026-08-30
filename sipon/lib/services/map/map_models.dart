/// 地图域的数据模型。这一层刻意不依赖具体地图引擎：
/// 坐标一律用裸 double，GeoJSON 也只是普通 Map。这样模型可以被纯 Dart
/// 测试直接构造。
library;

/// 酒吧类型。原来 `kind` 是裸 String，图标、中文名、圆点配色各写一处 switch，
/// 三处经常忘记同步；收进枚举后新增一种类型只改这一个文件。
enum MapVenueKind {
  pub('清吧', MapAssets.pub, 0x9A3D78),
  craft('精酿', MapAssets.craft, 0x0D9488),
  bistro('Bistro', MapAssets.bistro, 0x2563EB),
  party('派对', MapAssets.party, 0xDC2626),
  livehouse('Livehouse', MapAssets.livehouse, 0xF59E0B);

  const MapVenueKind(this.label, this.iconAsset, this.circleRgb);

  /// 中文展示名，交给 `SiponAppText.t` 翻译。
  final String label;
  final String iconAsset;

  /// 圆点图层用的 RGB（不含 alpha，透明度在图层表达式里统一给）。
  final int circleRgb;

  int get circleRed => (circleRgb >> 16) & 0xFF;
  int get circleGreen => (circleRgb >> 8) & 0xFF;
  int get circleBlue => circleRgb & 0xFF;

  /// 圆点图层 `match` 表达式里用的 key，同时也是 GeoJSON 的 `category` 属性值。
  String get id => name;

  /// 把后端/文案里五花八门的类型串归一到枚举。命中不了就当清吧。
  static MapVenueKind fromRaw(String? raw) {
    final kind = raw?.trim().toLowerCase() ?? '';
    if (kind.isEmpty) {
      return MapVenueKind.pub;
    }
    if (kind.contains('craft') ||
        kind.contains('精酿') ||
        kind.contains('beer')) {
      return MapVenueKind.craft;
    }
    if (kind.contains('bistro') || kind.contains('餐酒')) {
      return MapVenueKind.bistro;
    }
    if (kind.contains('party') ||
        kind.contains('club') ||
        kind.contains('派对')) {
      return MapVenueKind.party;
    }
    if (kind.contains('live') || kind.contains('音乐')) {
      return MapVenueKind.livehouse;
    }

    return MapVenueKind.pub;
  }
}

/// 地图上的一家酒吧。
class MapVenue {
  const MapVenue({
    required this.id,
    required this.name,
    required this.longitude,
    required this.latitude,
    required this.kind,
    required this.rating,
    required this.address,
    required this.distance,
    required this.tags,
    required this.imageAsset,
    this.imageUrl,
  });

  final String id;
  final String name;
  final double longitude;
  final double latitude;
  final MapVenueKind kind;
  final double rating;
  final String address;

  /// 已经格式化好的距离文案（"约2.0km"），由数据源按视野中心算出。
  final String distance;
  final List<String> tags;
  final String imageAsset;
  final String? imageUrl;

  String get iconAsset => kind.iconAsset;

  MapVenue copyWith({String? distance}) {
    return MapVenue(
      id: id,
      name: name,
      longitude: longitude,
      latitude: latitude,
      kind: kind,
      rating: rating,
      address: address,
      distance: distance ?? this.distance,
      tags: tags,
      imageAsset: imageAsset,
      imageUrl: imageUrl,
    );
  }

  MapPoint toMapPoint({String idPrefix = 'venue', double weightBoost = 0}) {
    return MapPoint(
      id: '$idPrefix-$id',
      name: name,
      longitude: longitude,
      latitude: latitude,
      kind: kind,
      weight: rating + weightBoost,
    );
  }
}

/// 送进 GeoJSON source 的一个点。圆点图层、热力图层都用它。
class MapPoint {
  const MapPoint({
    required this.id,
    required this.name,
    required this.longitude,
    required this.latitude,
    required this.kind,
    required this.weight,
    this.venueId,
  });

  final String id;
  final String name;
  final double longitude;
  final double latitude;
  final MapVenueKind kind;
  final double weight;

  /// 点击圆点后要选中哪家酒吧。热力点没有对应酒吧，为 null。
  final String? venueId;

  Map<String, dynamic> toFeature() {
    return {
      'type': 'Feature',
      'properties': {
        'id': id,
        'name': name,
        'category': kind.id,
        'weight': weight,
        if (venueId != null) 'venueId': venueId,
      },
      'geometry': {
        'type': 'Point',
        'coordinates': [longitude, latitude],
      },
    };
  }
}

/// 带文字标签的 marker 规格。标签在页面层就用 [SiponAppText] 翻译好再传进来，
/// 于是 [MapSceneController] 不需要 `BuildContext`，也能被纯 Dart 测试。
class MapMarkerSpec {
  const MapMarkerSpec({
    required this.venueId,
    required this.label,
    required this.longitude,
    required this.latitude,
    required this.kind,
  });

  final String venueId;
  final String label;
  final double longitude;
  final double latitude;
  final MapVenueKind kind;

  /// 参与 marker 重建判定的全部字段。任一变化才值得 `deleteAll` + 重建。
  String get signaturePart =>
      [venueId, label, longitude, latitude, kind.id].join('|');
}

/// 顶部分类筛选 pill。
class MapCategory {
  const MapCategory({required this.kind});

  final MapVenueKind kind;

  String get label => kind.label;
  String get iconAsset => kind.iconAsset;
}

const List<MapCategory> mapCategoryFilters = [
  MapCategory(kind: MapVenueKind.pub),
  MapCategory(kind: MapVenueKind.livehouse),
  MapCategory(kind: MapVenueKind.craft),
  MapCategory(kind: MapVenueKind.bistro),
  MapCategory(kind: MapVenueKind.party),
];

class MapAssets {
  const MapAssets._();

  static const String pub = 'assest/地图/清吧 默认@3x.png';
  static const String livehouse = 'assest/地图/Livehouse 默认@3x.png';
  static const String craft = 'assest/地图/精酿 默认@3x.png';
  static const String bistro = 'assest/地图/Bistro 默认@3x.png';
  static const String party = 'assest/地图/派对 默认@3x.png';
  static const String filter = 'assest/地图/筛选 默认@3x.png';

  static const String barImage = 'assest/首页/图片素材/庙前冰室.png';
  static const String speakLowImage = 'assest/首页/图片素材/Speak Low（彼楼）.png';
  static const String janesImage = 'assest/首页/图片素材/酒吧 Janes and Hooch.png';
  static const String playHouseImage = 'assest/首页/图片素材/Play House 电音夜店.png';

  /// 没有网图时按序轮换的本地封面。
  static const List<String> venueCovers = [
    barImage,
    speakLowImage,
    janesImage,
    playHouseImage,
  ];

  static String coverForIndex(int index) =>
      venueCovers[index.abs() % venueCovers.length];
}

/// 带文字标签的 marker 数量上限。标签会互相挤，缩得越远越要少画。
int mapMarkerLabelLimitForZoom(double zoom) {
  if (!zoom.isFinite) {
    return 24;
  }
  if (zoom < 7) {
    return 24;
  }
  if (zoom < 10) {
    return 48;
  }
  if (zoom < 12) {
    return 80;
  }
  if (zoom < 14) {
    return 120;
  }
  if (zoom < 16) {
    return 180;
  }

  return 260;
}

/// 从 venues 里等距抽样出要画文字标签的那一批。
///
/// 注意只有 marker 需要抽样：圆点和热力图层用全量数据。原来两者共用抽样结果，
/// 导致缩小地图时圆点也跟着变少。
List<MapVenue> sampleVenuesForMarkers(
  List<MapVenue> venues, {
  required double zoom,
}) {
  final limit = mapMarkerLabelLimitForZoom(zoom);
  if (venues.length <= limit) {
    return venues;
  }

  final step = venues.length / limit;

  return [
    for (var index = 0; index < limit; index++) venues[(index * step).floor()],
  ];
}

/// marker 数据指纹。只要它没变就跳过 `deleteAll` + `createMulti`。
String markerAnnotationSignature(List<MapMarkerSpec> markers) {
  return markers.map((marker) => marker.signaturePart).join(';');
}

double mapClamp(double value, double lower, double upper) {
  if (value < lower) {
    return lower;
  }
  if (value > upper) {
    return upper;
  }

  return value;
}

double mapClamp01(double value) => mapClamp(value, 0, 1);

double mapLerp(double from, double to, double t) => from + (to - from) * t;
