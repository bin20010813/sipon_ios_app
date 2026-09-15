import '../sipon_api_service.dart';
import 'map_models.dart';
import 'mock_venue_detail_repository.dart';
import 'venue_detail_models.dart';

/// 详情数据源抽象（供页面依赖）。
///
/// 页面只认这个接口，具体是 mock 还是真接口由调用方注入，
/// 参照 `map_venue_repository.dart` 的灰度切换方式。
abstract interface class VenueDetailRepository {
  /// 拉取 [venue] 的完整详情。
  Future<VenueDetail> fetchDetail(MapVenue venue);

  /// 分页拉取 [venue] 的评价，从 [offset] 开始取 [limit] 条。
  ///
  /// 详情页「更多评论」翻页时调用；mock 与真接口都支持。
  Future<VenueReviewPage> fetchReviews(
    MapVenue venue, {
    int offset = 0,
    int limit = 10,
  });
}

/// 真接口实现：包一层现有的 [SiponApiService]。
///
/// 调用链：getBarById 为主，reviews/hours/drinks/media 做兜底补充；
/// 任意一路兜底接口失败只损失对应板块，不影响整体展示。
/// [venue.id] 无法解析为后端数字 id 时（例如写死的演示数据），
/// 回退到 [fallback]（默认 Mock），保证页面永远有内容。
class SiponApiVenueDetailRepository implements VenueDetailRepository {
  /// 创建真接口详情仓库。
  SiponApiVenueDetailRepository({
    SiponApiService? api,
    VenueDetailRepository? fallback,
  }) : _api = api ?? SiponApiService(),
       _fallback = fallback ?? const MockVenueDetailRepository();

  final SiponApiService _api;
  final VenueDetailRepository _fallback;

  static const List<String> _dayKeys = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  /// 评价每页条数：详情首屏与「更多评论」翻页共用。
  static const int _reviewPageSize = 10;

  @override
  Future<VenueDetail> fetchDetail(MapVenue venue) async {
    final barId = int.tryParse(venue.id);
    if (barId == null) {
      return _fallback.fetchDetail(venue);
    }

    // 详情主数据必须成功；兜底板块各自容错，失败按空列表处理。
    final bar = _asMap(await _api.getBarById(barId));
    final results = await Future.wait([
      _guarded(
        () => _api.getBarReviews(
          barId,
          page: SiponPage(limit: _reviewPageSize),
        ),
      ),
      _guarded(() => _api.getBarHours(barId)),
      _guarded(() => _api.getBarDrinks(barId)),
      _guarded(() => _api.getBarMedia(barId)),
    ]);
    final reviewJson = results[0] ?? const <dynamic>[];
    final hoursJson = results[1] ?? const <dynamic>[];
    final drinksJson = results[2] ?? const <dynamic>[];
    final mediaJson = results[3] ?? const <dynamic>[];

    final mergedVenue = _mergeVenue(venue, bar);
    final businessHours = _parseBusinessHours(bar, hoursJson);
    final now = DateTime.now();
    final todayKey = _dayKeys[now.weekday - 1];
    final reviews = [
      for (final item in reviewJson.whereType<Map>())
        _parseReview(item.cast<String, dynamic>()),
    ].whereType<VenueReview>().toList(growable: false);

    return VenueDetail(
      venue: mergedVenue,
      description: _parseDescription(bar),
      businessHours: businessHours,
      phone: _readStr(bar, ['phoneNumber', 'phone', 'tel']) ?? '暂无电话',
      priceLevel: _readStr(bar, ['priceRange', 'priceLevel']) ?? '¥¥',
      features: _parseFeatures(bar, mergedVenue),
      signatureDrinks: _parseDrinks(bar, drinksJson),
      reviews: reviews,
      gallery: _parseGallery(bar, mediaJson, mergedVenue),
      openNow: _isOpenAt(now, businessHours),
      todayKey: todayKey,
      todayHoursLabel: businessHours[todayKey] ?? '营业时间待补充',
      reviewCount: _parseReviewCount(bar, reviews.length),
    );
  }

  /// 兜底板块容错：失败返回 null，不阻断详情整体加载。
  Future<T?> _guarded<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on Exception {
      return null;
    }
  }

  @override
  Future<VenueReviewPage> fetchReviews(
    MapVenue venue, {
    int offset = 0,
    int limit = _reviewPageSize,
  }) async {
    final barId = int.tryParse(venue.id);
    if (barId == null) {
      return _fallback.fetchReviews(venue, offset: offset, limit: limit);
    }

    final reviewJson = await _guarded(
      () => _api.getBarReviews(
        barId,
        page: SiponPage(limit: limit, offset: offset),
      ),
    );
    final reviews = [
      for (final item in (reviewJson ?? const <dynamic>[]).whereType<Map>())
        _parseReview(item.cast<String, dynamic>()),
    ].whereType<VenueReview>().toList(growable: false);

    // 总数优先取 Bar 汇总字段；拿不到时用「已拉取条数」兜底（拉满一页视为还有）。
    final bar = _asMap(await _guarded(() => _api.getBarById(barId)));
    final total = _parseReviewCount(bar, offset + reviews.length);
    return VenueReviewPage(
      reviews: reviews,
      totalCount: total,
      hasMore: offset + reviews.length < total,
    );
  }

  /// 用 Bar 响应里的字段刷新基础信息，缺失字段保留地图列表带来的值。
  MapVenue _mergeVenue(MapVenue venue, Map<String, dynamic> bar) {
    final barTags = _readStrList(bar, ['tags', 'labels']);
    final imageUrl =
        _readStr(bar, ['imageUrl', 'image', 'cover', 'coverUrl']) ??
        _firstGalleryUrl(bar['gallery']);
    return MapVenue(
      id: venue.id,
      name: _readStr(bar, ['name', 'barName', 'title']) ?? venue.name,
      longitude:
          _readDouble(bar, ['longitude', 'lng', 'lon']) ?? venue.longitude,
      latitude: _readDouble(bar, ['latitude', 'lat']) ?? venue.latitude,
      kind: MapVenueKind.fromRaw(
        _readStr(bar, ['barSubtype', 'subtype', 'kind']) ?? venue.kind.id,
      ),
      rating:
          _readDouble(bar, ['averageRating', 'rating', 'score']) ??
          venue.rating,
      address: _readStr(bar, ['address', 'addr']) ?? venue.address,
      distance: venue.distance,
      tags: barTags ?? venue.tags,
      imageAsset: venue.imageAsset,
      imageUrl: imageUrl ?? venue.imageUrl,
    );
  }

  /// 简介按换行拆段；后端没给简介时返回空列表，页面展示占位。
  List<String> _parseDescription(Map<String, dynamic> bar) {
    final raw = _readStr(bar, ['description', 'intro', 'about']);
    if (raw == null) {
      return const [];
    }
    return raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  /// 特色标签：优先 Bar.tags，其次沿用地图列表的 tags。
  List<String> _parseFeatures(Map<String, dynamic> bar, MapVenue venue) {
    return _readStrList(bar, ['tags', 'labels', 'features']) ?? venue.tags;
  }

  /// 营业时间：优先详情内嵌 weeklyHours，其次 /hours 接口。
  /// 元素结构以真实响应为准，这里对常见键名做宽容解析。
  Map<String, String> _parseBusinessHours(
    Map<String, dynamic> bar,
    List<dynamic> hoursJson,
  ) {
    final fromDetail = _parseHoursList(bar['weeklyHours']);
    if (fromDetail.isNotEmpty) {
      return fromDetail;
    }
    return _parseHoursList(hoursJson);
  }

  Map<String, String> _parseHoursList(dynamic raw) {
    if (raw is! List) {
      return const {};
    }
    final result = <String, String>{};
    for (final item in raw) {
      if (item is String) {
        // "周一 18:00-02:00" 这类纯文本行。
        final match = RegExp(
          r'^(周[一二三四五六日])\s*[:：]?\s*(.+)$',
        ).firstMatch(item.trim());
        if (match != null) {
          result[match.group(1)!] = match.group(2)!.trim();
        }
        continue;
      }
      if (item is! Map) {
        continue;
      }
      final map = item.cast<String, dynamic>();
      final day = _parseDay(map);
      final range = _parseHourRange(map);
      if (day != null && range != null) {
        result[day] = range;
      }
    }
    return result;
  }

  /// 解析星期字段：支持中文文案、英文缩写与 1-7 数字。
  String? _parseDay(Map<String, dynamic> map) {
    final raw =
        map['day'] ?? map['weekday'] ?? map['dayOfWeek'] ?? map['label'];
    if (raw is int) {
      return raw >= 1 && raw <= 7 ? _dayKeys[raw - 1] : null;
    }
    final text = raw?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    if (text.startsWith('周')) {
      return text;
    }
    const english = {
      'mon': '周一',
      'tue': '周二',
      'wed': '周三',
      'thu': '周四',
      'fri': '周五',
      'sat': '周六',
      'sun': '周日',
    };
    return english[text.substring(0, 3).toLowerCase()];
  }

  /// 解析时段：优先现成文案，否则用 open/close 拼接；标记休息的给「休息」。
  String? _parseHourRange(Map<String, dynamic> map) {
    if (map['closed'] == true || map['isClosed'] == true) {
      return '休息';
    }
    final ready = _readStr(map, ['hours', 'time', 'range', 'businessHours']);
    if (ready != null) {
      return ready;
    }
    final open = _readStr(map, ['openTime', 'open', 'start', 'startTime']);
    final close = _readStr(map, ['closeTime', 'close', 'end', 'endTime']);
    if (open == null || close == null) {
      return null;
    }
    return '$open - $close';
  }

  /// 招牌酒款：优先详情内嵌 signatureDrinks，其次 /drinks 接口。
  List<VenueDrink> _parseDrinks(Map<String, dynamic> bar, List<dynamic> drinks) {
    final raw = bar['signatureDrinks'] is List
        ? bar['signatureDrinks'] as List
        : drinks;
    return [
      for (var index = 0; index < raw.length; index++)
        if (raw[index] is Map)
          _parseDrink(
            (raw[index] as Map).cast<String, dynamic>(),
            MapAssets.coverForIndex(index),
          ),
    ].whereType<VenueDrink>().toList(growable: false);
  }

  VenueDrink? _parseDrink(Map<String, dynamic> map, String fallbackImage) {
    final name = _readStr(map, ['name', 'drinkName', 'title']);
    if (name == null) {
      return null;
    }
    final priceValue = map['price'];
    final price =
        _readStr(map, ['priceText', 'priceLabel']) ??
        (priceValue is num ? '¥${priceValue.toStringAsFixed(0)}' : null) ??
        '';
    return VenueDrink(
      name: name,
      price: price,
      description: _readStr(map, ['description', 'desc', 'flavor']) ?? '',
      tags: _readStrList(map, ['tags', 'flavorTags']) ?? const [],
      imageAsset: _readStr(map, ['imageUrl', 'image', 'cover']) ?? fallbackImage,
    );
  }

  /// 图集：优先详情内嵌 gallery，其次 /media 接口；都没有时用本地封面兜底。
  List<String> _parseGallery(
    Map<String, dynamic> bar,
    List<dynamic> media,
    MapVenue venue,
  ) {
    final urls = <String>[
      ..._readUrlList(bar['gallery']),
      ..._readUrlList(media),
    ];
    if (urls.isEmpty) {
      return [venue.imageAsset];
    }
    return urls;
  }

  String? _firstGalleryUrl(dynamic raw) {
    final urls = _readUrlList(raw);
    return urls.isEmpty ? null : urls.first;
  }

  /// 从图集/媒体列表里提取 URL：元素可能是字符串或带 url 字段的对象。
  List<String> _readUrlList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    return raw
        .map((item) {
          if (item is String) {
            return item.trim();
          }
          if (item is Map) {
            return _readStr(item.cast<String, dynamic>(), [
              'url',
              'imageUrl',
              'path',
              'src',
              'contentUrl',
            ]);
          }
          return null;
        })
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
  }

  /// 评价列表元素是 CheckIn 结构：author 里取昵称/头像，mediaUrls 取图。
  VenueReview? _parseReview(Map<String, dynamic> map) {
    final author = _asMap(map['author']);
    final content = _readStr(map, ['content', 'text', 'comment']) ?? '';
    if (content.isEmpty && map['rating'] == null) {
      return null;
    }
    return VenueReview(
      nickname:
          _readStr(author, ['nickname', 'nickName', 'username', 'name']) ??
          _readStr(map, ['nickname', 'userName']) ??
          '匿名用户',
      rating: _readDouble(map, ['rating', 'score', 'star']) ?? 5,
      date: _formatDate(
        _readStr(map, ['visitedAt', 'createdAt', 'created_on']),
      ),
      content: content,
      imageAssets: _readUrlList(map['mediaUrls'] ?? map['media']),
      avatarAsset: _readStr(author, ['avatarUrl', 'avatar', 'avatarAsset']),
    );
  }

  /// 评价总数：优先 reviewSummary 里的汇总字段，否则用已拉到的列表长度。
  int _parseReviewCount(Map<String, dynamic> bar, int fallback) {
    final summary = _asMap(bar['reviewSummary']);
    return _readInt(summary, ['count', 'total', 'totalCount', 'reviewCount']) ??
        _readInt(bar, ['reviewCount', 'reviewsCount']) ??
        fallback;
  }

  /// ISO 时间转页面用的 `yyyy-M-d` 文案（与详情页日期解析保持一致）。
  String _formatDate(String? iso) {
    final parsed = iso == null ? null : DateTime.tryParse(iso);
    if (parsed == null) {
      return '';
    }
    final local = parsed.toLocal();
    return '${local.year}-${local.month}-${local.day}';
  }

  /// 根据当天与前一天的时段判断是否营业，跨午夜部分归属于前一天。
  bool _isOpenAt(DateTime now, Map<String, String> businessHours) {
    if (businessHours.isEmpty) {
      return false;
    }
    final todayIndex = now.weekday - 1;
    final currentRange = _parseRange(businessHours[_dayKeys[todayIndex]] ?? '');
    final previousRange = _parseRange(
      businessHours[_dayKeys[(todayIndex - 1 + _dayKeys.length) % 7]] ?? '',
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
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const {};
}

String? _readStr(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) {
      continue;
    }
    final text = value.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
  }
  return null;
}

double? _readDouble(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

int? _readInt(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

List<String>? _readStrList(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is List) {
      final strings = value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (strings.isNotEmpty) {
        return strings;
      }
    }
    if (value is String) {
      final strings = value
          .split(RegExp(r'[|,，/、]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (strings.isNotEmpty) {
        return strings;
      }
    }
  }
  return null;
}
