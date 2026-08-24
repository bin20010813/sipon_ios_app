import 'venue_detail_models.dart';
import 'map_models.dart';

/// 地点详情的 Mock 数据源。
///
/// 根据 [MapVenue.id] 稳定生成同一套详情数据，方便在无后端时预览页面效果。
class MockVenueDetailRepository {
  /// 创建 Mock 详情仓库。
  const MockVenueDetailRepository();

  /// 异步获取指定酒吧的详情。
  ///
  /// [latency] 用于模拟网络请求，测试可传 [Duration.zero]。
  Future<VenueDetail> fetchDetail(
    MapVenue venue, {
    Duration latency = const Duration(milliseconds: 200),
  }) async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }

    return _buildDetail(venue);
  }

  VenueDetail _buildDetail(MapVenue venue) {
    final seed = _stableHash(venue.id);
    final kind = venue.kind;
    final descriptions = _descriptionsForKind(kind);
    final drinks = _drinksForKind(kind, seed);
    final features = _featuresForKind(kind, seed);
    final reviews = _reviews(seed);

    final now = DateTime.now();
    const dayKeys = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final todayKey = dayKeys[now.weekday - 1];
    final weekendDays = const {'周六', '周日'};
    final businessHours = {
      for (final day in dayKeys)
        day: weekendDays.contains(day) ? '18:00 - 04:00' : '18:00 - 02:00',
    };
    final todayHoursLabel = businessHours[todayKey]!;

    return VenueDetail(
      venue: venue,
      description: descriptions,
      businessHours: businessHours,
      phone: '021-${6000 + seed % 4000}',
      priceLevel: '¥' * (2 + seed % 3),
      features: features,
      signatureDrinks: drinks,
      reviews: reviews,
      gallery: [
        venue.imageAsset,
        MapAssets.coverForIndex(seed),
        MapAssets.coverForIndex(seed + 1),
        MapAssets.coverForIndex(seed + 2),
      ],
      openNow: _isOpenAt(now, businessHours, dayKeys),
      todayKey: todayKey,
      todayHoursLabel: todayHoursLabel,
      reviewCount: 24 + seed % 176,
    );
  }

  /// 根据当天与前一天的时段判断是否营业，跨午夜部分归属于前一天。
  bool _isOpenAt(
    DateTime now,
    Map<String, String> businessHours,
    List<String> dayKeys,
  ) {
    final todayIndex = now.weekday - 1;
    final currentRange = _parseRange(businessHours[dayKeys[todayIndex]] ?? '');
    final previousIndex = (todayIndex - 1 + dayKeys.length) % dayKeys.length;
    final previousRange = _parseRange(
      businessHours[dayKeys[previousIndex]] ?? '',
    );
    final nowMinutes = now.hour * 60 + now.minute;

    if (currentRange != null) {
      final (startMinutes, endMinutes) = currentRange;
      if (endMinutes > startMinutes) {
        if (nowMinutes >= startMinutes && nowMinutes < endMinutes) {
          return true;
        }
      } else if (nowMinutes >= startMinutes) {
        return true;
      }
    }

    if (previousRange != null) {
      final (startMinutes, endMinutes) = previousRange;
      return endMinutes <= startMinutes && nowMinutes < endMinutes;
    }
    return false;
  }

  (int, int)? _parseRange(String range) {
    final parts = range.split('-');
    if (parts.length != 2) {
      return null;
    }
    final startMinutes = _parseMinutes(parts[0].trim());
    final endMinutes = _parseMinutes(parts[1].trim());
    if (startMinutes == null || endMinutes == null) {
      return null;
    }
    return (startMinutes, endMinutes);
  }

  int? _parseMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return hour * 60 + minute;
  }

  List<String> _descriptionsForKind(MapVenueKind kind) {
    return switch (kind) {
      MapVenueKind.pub => const [
        '这是一家藏在城市夜色里的清吧，木质吧台与柔和烛光营造出放松的私密氛围。',
        '酒单以经典调酒为骨架，调酒师擅长用本土风味重新诠释熟悉配方，适合想要安静小酌的夜晚。',
      ],
      MapVenueKind.craft => const [
        '店内拥有多款自酿精酿与国内外小众厂牌生啤，酒头轮换频繁，每次来都能尝到新鲜味道。',
        '吧台前经常坐满啤酒爱好者，酒保乐于根据你的口味推荐一杯合心意的选择。',
      ],
      MapVenueKind.bistro => const [
        '餐酒结合的小酒馆，菜单由主厨与调酒师共同设计，主打下酒小食与创意鸡尾酒搭配。',
        '空间紧凑而温馨，是下班后与朋友边吃边聊的理想落脚点。',
      ],
      MapVenueKind.party => const [
        '派对氛围十足的夜场，拥有专业灯光与音响系统，周末常有 DJ 驻场与主题派对。',
        '舞池宽敞，卡座区视野开阔，适合想要释放压力、尽兴跳舞的夜晚。',
      ],
      MapVenueKind.livehouse => const [
        '以现场音乐为核心的 Livehouse，舞台不大但声场出色，经常邀请独立乐队与音乐人演出。',
        '除演出时段外也提供酒水小食，提前到场还能占到靠前的位置。',
      ],
    };
  }

  List<VenueDrink> _drinksForKind(MapVenueKind kind, int seed) {
    final templates = switch (kind) {
      MapVenueKind.pub => const [
        ('Old Fashioned', '¥88', '波本威士忌、苦精、方糖，经典永不过时。'),
        ('Martini', '¥92', '干金酒与干味美思的极简平衡。'),
        ('Whisky Sour', '¥86', '波本、柠檬、糖浆，酸甜利落。'),
      ],
      MapVenueKind.craft => const [
        ('浑浊 IPA', '¥78', '热带水果香气，酒体饱满，苦味柔和。'),
        ('酸小麦', '¥68', '明快乳酸感，清爽易饮。'),
        ('帝国世涛', '¥88', '烘焙咖啡与黑巧克力风味，醇厚收尾。'),
      ],
      MapVenueKind.bistro => const [
        ('季节特调', '¥82', '根据当季水果与香草调整的限定酒单。'),
        ('桑格利亚', '¥68', '红酒、水果与香料的西班牙式微醺。'),
        ('起泡酒', '¥78', '清爽气泡，搭配小食的稳妥之选。'),
      ],
      MapVenueKind.party => const [
        ('长岛冰茶', '¥98', '多重基酒混合，派对开场经典款。'),
        ('龙舌兰日出', '¥88', '渐变色彩，口感甜美。'),
        ('香槟套餐', '¥688', '适合卡座分享，气氛拉满。'),
      ],
      MapVenueKind.livehouse => const [
        ('金汤力', '¥68', '简单清爽，适合站着看演出时手持一杯。'),
        ('精酿生啤', '¥72', '当晚酒头轮换，具体款式请咨询吧台。'),
        ('特调鸡尾酒', '¥86', '以演出主题命名的限定款。'),
      ],
    };

    return [
      for (var i = 0; i < templates.length; i++)
        VenueDrink(
          name: templates[i].$1,
          price: templates[i].$2,
          description: templates[i].$3,
          tags: _drinkTags[(seed + i) % _drinkTags.length],
          imageAsset: MapAssets.coverForIndex(seed + i),
        ),
    ];
  }

  List<String> _featuresForKind(MapVenueKind kind, int seed) {
    final base = switch (kind) {
      MapVenueKind.pub => const ['安静', '经典调酒', '约会推荐'],
      MapVenueKind.craft => const ['精酿生啤', '酒头轮换', '啤酒爱好者'],
      MapVenueKind.bistro => const ['餐酒搭配', '下酒小食', '氛围温馨'],
      MapVenueKind.party => const ['DJ 驻场', '舞池', '派对'],
      MapVenueKind.livehouse => const ['现场音乐', '独立乐队', '演出'],
    };

    final extras = const [
      '露台座位',
      '可预订',
      '无烟区',
      'Wi-Fi',
      '宠物友好',
      '无障碍友好',
      '包厢',
      '室外吸烟区',
    ];

    return [...base, extras[seed % extras.length]];
  }

  List<VenueReview> _reviews(int seed) {
    const reviewers = [
      ('琥珀鉴赏家', 'assest/首页/图片素材/Aki Wang.png'),
      ('Matt Hasting', 'assest/首页/图片素材/Matt Hasting.png'),
      ('Bharat Balami', 'assest/首页/图片素材/Bharat Balami.png'),
    ];
    const contents = [
      '氛围很棒，酒单有惊喜，会再来。',
      '服务热情，调酒师很专业，推荐坐在吧台。',
      '周末人比较多，建议提前预约。',
      '音乐品味在线，适合放松。',
      '人均略高但物有所值，酒的品质在线。',
      '招牌酒层次很完整，第一口和收尾都有变化。',
      '空间不大但座位舒服，聊天不会觉得吵。',
      '酒保推荐得很准，下次想试试季节限定。',
    ];

    return [
      for (var i = 0; i < 8; i++)
        VenueReview(
          nickname: reviewers[(seed + i) % reviewers.length].$1,
          rating: 4.2 + (seed + i) % 8 * 0.1,
          date: '${2024 + (seed + i) % 2}-${(seed + i) % 12 + 1}-15',
          content: contents[(seed + i) % contents.length],
          imageAssets: [
            MapAssets.coverForIndex(seed + i),
            if (i.isEven) MapAssets.coverForIndex(seed + i + 1),
          ],
          avatarAsset: reviewers[(seed + i) % reviewers.length].$2,
        ),
    ];
  }

  /// 与平台无关的字符串散列，保证同一 id 始终得到同一套 Mock 数据。
  int _stableHash(String value) {
    var hash = 7;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return hash;
  }
}

const List<List<String>> _drinkTags = [
  ['果香', '清爽'],
  ['烈酒感', '经典'],
  ['甜口', '易饮'],
  ['烟熏', '层次'],
  ['草本', '微苦'],
];
