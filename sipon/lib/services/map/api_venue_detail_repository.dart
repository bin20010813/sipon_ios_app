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

  static const List<String> _dayKeys = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  /// 评价每页条数：详情首屏与「更多评论」翻页共用。
  static const int _reviewPageSize = 10;
  static const Duration _supplementaryRequestTimeout = Duration(
    milliseconds: 800,
  );

  @override
  Future<VenueDetail> fetchDetail(MapVenue venue) async {
    final barId = int.tryParse(venue.id);
    if (barId == null) {
      return _fallback.fetchDetail(venue);
    }

    // 所有请求同时发出。评价、营业时间、酒款和媒体都是补充模块，不能因为
    // 其中一路缓慢或无响应而让详情首屏一直停在加载态。
    final results = await Future.wait<dynamic>([
      _api.getBarById(barId),
      _guarded(
        () =>
            _api.getBarReviews(barId, page: SiponPage(limit: _reviewPageSize)),
      ),
      _guarded(() => _api.getBarHours(barId)),
      _guarded(() => _api.getBarDrinks(barId)),
      _guarded(() => _api.getBarMedia(barId)),
    ]);
    final bar = _asMap(results[0]);
    final reviewJson = results[1] ?? const <dynamic>[];
    final hoursJson = results[2] ?? const <dynamic>[];
    final drinksJson = results[3] ?? const <dynamic>[];
    final mediaJson = results[4] ?? const <dynamic>[];

    final mergedVenue = _mergeVenue(venue, bar);
    final businessHours = _parseBusinessHours(bar, hoursJson);
    final now = DateTime.now();
    final todayKey = _dayKeys[now.weekday - 1];
    final reviews = await _parseReviews(reviewJson);
    final gallery = _parseGallery(bar, mediaJson, mergedVenue);

    return VenueDetail(
      venue: mergedVenue,
      description: _parseDescription(bar),
      latestUpdates: _parseLatestUpdates(bar),
      businessHours: businessHours,
      phone: _readStr(bar, ['phoneNumber', 'phone', 'tel']) ?? '暂无电话',
      priceLevel: _readStr(bar, ['priceRange', 'priceLevel']) ?? '¥¥',
      features: _parseFeatures(bar, mergedVenue),
      signatureDrinks: _parseDrinks(bar, drinksJson),
      reviews: reviews,
      gallery: gallery,
      openNow: _isOpenAt(now, businessHours),
      todayKey: todayKey,
      todayHoursLabel: businessHours[todayKey] ?? '营业时间待补充',
      reviewCount: _parseReviewCount(bar, reviews.length),
    );
  }

  /// 兜底板块容错：失败返回 null，不阻断详情整体加载。
  Future<T?> _guarded<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(_supplementaryRequestTimeout);
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
    final reviews = await _parseReviews(reviewJson ?? const <dynamic>[]);

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
        _readStr(bar, [
          'mediumImageUrl',
          'imageUrl',
          'image',
          'cover',
          'coverUrl',
        ]) ??
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

  List<String> _parseLatestUpdates(Map<String, dynamic> bar) {
    final raw = bar['latestUpdates'] ?? bar['latest_updates'] ?? bar['updates'];
    if (raw is List) {
      return raw
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .toList();
    }
    final single = _readStr(bar, ['latestUpdate', 'latest_update']);
    return single == null ? const [] : [single];
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
  List<VenueDrink> _parseDrinks(
    Map<String, dynamic> bar,
    List<dynamic> drinks,
  ) {
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
      imageAsset:
          _readStr(map, ['imageUrl', 'image', 'cover']) ?? fallbackImage,
    );
  }

  /// 图集：优先读取详情的 images 数组，并按 sortOrder 升序排列。
  /// 轮播使用 mediumImageUrl，点击放大后使用同一项的 imageUrl。
  /// 旧的 gallery 和 /media 响应仍作为兼容兜底。
  List<VenueGalleryImage> _parseGallery(
    Map<String, dynamic> bar,
    List<dynamic> media,
    MapVenue venue,
  ) {
    final images = _readGalleryImages(bar['images']);
    if (images.isNotEmpty) {
      return images;
    }

    final cover = venue.imageUrl?.trim();
    final legacyImages = <VenueGalleryImage>[
      if (cover != null && cover.isNotEmpty)
        VenueGalleryImage(mediumImageUrl: cover, imageUrl: cover),
      ..._readGalleryImages(bar['gallery']),
      ..._readGalleryImages(media),
    ];
    if (legacyImages.isEmpty) {
      return const [];
    }
    final seen = <String>{};
    return legacyImages
        .where(
          (image) => seen.add('${image.mediumImageUrl}\n${image.imageUrl}'),
        )
        .toList(growable: false);
  }

  List<VenueGalleryImage> _readGalleryImages(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    final candidates = <_GalleryCandidate>[];
    for (var index = 0; index < raw.length; index++) {
      final item = raw[index];
      if (item is String) {
        final url = item.trim();
        if (url.isNotEmpty) {
          candidates.add(
            _GalleryCandidate(
              image: VenueGalleryImage(mediumImageUrl: url, imageUrl: url),
              sortOrder: null,
              sourceIndex: index,
            ),
          );
        }
        continue;
      }
      if (item is! Map) {
        continue;
      }
      final map = item.cast<String, dynamic>();
      final original = _readStr(map, ['imageUrl', 'url', 'path', 'src']);
      final medium =
          _readStr(map, ['mediumImageUrl']) ??
          _readStr(map, ['thumbnailUrl']) ??
          original;
      final fullSize = original ?? medium;
      if (medium == null || fullSize == null) {
        continue;
      }
      candidates.add(
        _GalleryCandidate(
          image: VenueGalleryImage(mediumImageUrl: medium, imageUrl: fullSize),
          sortOrder: _readInt(map, ['sortOrder', 'order']),
          sourceIndex: index,
        ),
      );
    }
    candidates.sort((a, b) {
      final byOrder = (a.sortOrder ?? 0x7fffffff).compareTo(
        b.sortOrder ?? 0x7fffffff,
      );
      return byOrder != 0 ? byOrder : a.sourceIndex.compareTo(b.sourceIndex);
    });
    return candidates
        .map((candidate) => candidate.image)
        .toList(growable: false);
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

  /// 签到配图：`mediaIds` 是上传 ID，需换成上传内容相对路径才能展示；
  /// 没有 `mediaIds` 时回退旧的 `mediaUrls` / `media` 字段。
  List<String> _readCheckInImages(Map<String, dynamic> map) {
    final fromIds = _readUrlList(
      map['mediaIds'],
    ).map((mediaId) => '/api/uploads/$mediaId/content').toList(growable: false);
    if (fromIds.isNotEmpty) {
      return fromIds;
    }
    return _readUrlList(map['mediaUrls'] ?? map['media']);
  }

  static const _reviewNameKeys = [
    'displayName',
    'nickname',
    'nickName',
    'username',
    'userName',
    'name',
  ];
  static const _reviewAvatarKeys = [
    'avatarUrl',
    'avatar',
    'avatarImageUrl',
    'avatarAsset',
  ];

  Map<String, dynamic> _reviewAuthor(Map<String, dynamic> map) => {
    ..._asMap(map['user']),
    ..._asMap(map['author']),
  };

  /// 只返回作者 ID 时补查公开资料；同一批次按用户去重，失败保留评价。
  Future<List<VenueReview>> _parseReviews(List<dynamic> items) async {
    final profiles = <int, Future<dynamic>>{};
    final reviews = await Future.wait(
      items.whereType<Map>().map((item) async {
        final map = item.cast<String, dynamic>();
        final author = _reviewAuthor(map);
        final userId =
            _readInt(author, ['id', 'userId']) ??
            _readInt(map, ['userId', 'authorId']);
        final name =
            _readStr(author, _reviewNameKeys) ?? _readStr(map, _reviewNameKeys);
        final avatar =
            _readStr(author, _reviewAvatarKeys) ??
            _readStr(map, _reviewAvatarKeys);
        if (userId != null && (name == null || avatar == null)) {
          final raw = _asMap(
            await profiles.putIfAbsent(
              userId,
              () => _guarded(() => _api.getUserProfile(userId)),
            ),
          );
          final profile = {...raw, ..._asMap(raw['user'])};
          return _parseReview({
            ...map,
            'author': {
              ...author,
              'displayName': name ?? _readStr(profile, _reviewNameKeys),
              'avatarUrl': avatar ?? _readStr(profile, _reviewAvatarKeys),
            },
          });
        }
        return _parseReview(map);
      }),
    );
    return reviews.whereType<VenueReview>().toList(growable: false);
  }

  /// 评价列表元素是 CheckIn 结构，兼容内嵌作者与平铺资料。
  VenueReview? _parseReview(Map<String, dynamic> map) {
    final author = _reviewAuthor(map);
    final content = _readStr(map, ['content', 'text', 'comment']) ?? '';
    if (content.isEmpty && map['rating'] == null) {
      return null;
    }
    final createdAt = DateTime.tryParse(
      _readStr(map, ['visitedAt', 'createdAt', 'created_on']) ?? '',
    )?.toLocal();
    return VenueReview(
      id: _readInt(map, ['id', 'checkInId']),
      myReaction: _readStr(map, ['myReaction', 'reaction']),
      nickname:
          _readStr(author, _reviewNameKeys) ??
          _readStr(map, _reviewNameKeys) ??
          '匿名用户',
      rating: _readDouble(map, ['rating', 'score', 'star']) ?? 5,
      likeCount: _readInt(map, ['likeCount', 'likes', 'thumbsUp']) ?? 0,
      date: _formatDate(createdAt),
      createdAt: createdAt,
      content: content,
      imageAssets: _readCheckInImages(map),
      avatarAsset:
          _readStr(author, _reviewAvatarKeys) ??
          _readStr(map, _reviewAvatarKeys),
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
  String _formatDate(DateTime? parsed) {
    if (parsed == null) {
      return '';
    }
    return '${parsed.year}-${parsed.month}-${parsed.day}';
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

class _GalleryCandidate {
  const _GalleryCandidate({
    required this.image,
    required this.sortOrder,
    required this.sourceIndex,
  });

  final VenueGalleryImage image;
  final int? sortOrder;
  final int sourceIndex;
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
