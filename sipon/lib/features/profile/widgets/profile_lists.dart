part of '../pages/profile_page.dart';

enum ProfileListType { drank, wish, route }

/// 我的页列表条目：名称、描述、meta 与可选网络封面图。
class _ProfileListEntry {
  const _ProfileListEntry({
    required this.name,
    required this.description,
    required this.meta,
    this.id,
    this.imageUrl,
    this.venue,
    this.isCheckIn = false,
    this.reviewEntry,
    this.reviewApi,
    this.city,
    this.visitedDate,
    this.isPrivate = false,
    this.viewCount,
    this.stops = const [],
    this.routeThumbnails = const [],
  });

  final String name;
  final String description;
  final String meta;

  /// 后端资源 id：打卡 ID、想喝酒吧 ID 或路线 ID。
  final int? id;

  /// 后端返回的封面图（相对或绝对地址）；为空或加载失败时用 [fallbackImagePath]。
  final String? imageUrl;

  /// 解析出的地点信息；喝过/想喝条目用于跳转半屏地图，礼券等无地点列表为 null。
  final MapVenue? venue;

  /// 打卡卡会使用评论标题与地点、时间两行信息布局。
  final bool isCheckIn;
  final Map<String, dynamic>? reviewEntry;
  final SiponApiService? reviewApi;
  final String? city;
  final String? visitedDate;

  /// 封面加载失败时的本地兜底素材。
  String get fallbackImagePath => 'assest/首页/图片素材/酒吧1.png';

  /// 路线可见性：仅路线卡片使用。
  final bool isPrivate;
  final int? viewCount;

  /// 路线站点简况（按顺序）；仅路线卡片使用。
  final List<RouteStop> stops;
  final List<String> routeThumbnails;
}

/// 打开喝过/想喝/酒鬼路线列表弹窗，数据源为真实后端接口，列表按页加载。
/// 返回的 Future 在弹窗关闭后完成，便于调用方刷新计数。
Future<void> showProfileList(
  BuildContext context,
  ProfileListType type, {
  SiponApiService? apiService,
}) {
  final api = apiService ?? SiponApiService();
  final (title, loader, emptyText) = switch (type) {
    ProfileListType.drank => (
      '喝过的酒吧',
      (int offset, int limit) =>
          _loadCheckInEntries(api, offset: offset, limit: limit),
      '还没有喝过记录，去打卡第一家酒吧吧',
    ),
    ProfileListType.wish => (
      '想喝的酒吧',
      (int offset, int limit) =>
          _loadWishlistEntries(api, offset: offset, limit: limit),
      '还没有想喝的酒吧，去地图上收藏一家吧',
    ),
    ProfileListType.route => (
      '我的酒鬼路线',
      (int offset, int limit) =>
          _loadRouteEntries(api, offset: offset, limit: limit),
      '还没有酒鬼路线，去规划一条吧',
    ),
  };

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProfileListSheet(
      title: title,
      loader: loader,
      emptyText: emptyText,
      routeStyle: type == ProfileListType.route,
      deleteEntry: switch (type) {
        ProfileListType.drank => api.deleteCheckIn,
        ProfileListType.wish => api.removeWishlistBar,
        ProfileListType.route => api.deleteDrinkingRoute,
      },
    ),
  );
}

/// 从 map 里按候选键读取非空字符串。
String? _pickString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

/// 从 map 里按候选键读取数字。
num? _pickNum(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value;
    if (value is String) {
      final parsed = num.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

/// 从 map 里按候选键读取列表。
List<dynamic>? _pickList(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is List) return value;
  }
  return null;
}

/// 从 map 里按候选键读取第一个嵌套 Map（站点里常见 bar/barInfo 等对象）。
Map<String, dynamic>? _pickMapOf(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is Map) return value.cast<String, dynamic>();
  }
  return null;
}

/// 读取坐标数值：优先平铺 longitude/lng/lon、latitude/lat；
/// 兼容嵌套 coordinate/center/location 对象，以及 GeoJSON 的
/// coordinates: [lng, lat]（含 geometry.coordinates）。与地图层的
/// _readCoordinates 解析口径保持一致，避免想喝/喝过条目因坐标形态
/// 不同而解析成 0，导致点击后无法跳转到对应位置。
double? _pickCoordinate(Map<String, dynamic>? map, {required bool longitude}) {
  if (map == null) return null;
  final keys = longitude
      ? const ['longitude', 'lng', 'lon']
      : const ['latitude', 'lat'];
  final direct = _pickNum(map, keys)?.toDouble();
  if (direct != null) return direct;

  // 嵌套坐标对象：coordinate / center / location。
  for (final key in const ['coordinate', 'center', 'location']) {
    final nested = map[key];
    if (nested is Map) {
      final value = _pickNum(nested.cast<String, dynamic>(), keys)?.toDouble();
      if (value != null) return value;
    }
  }

  // GeoJSON：coordinates: [lng, lat] 或 geometry: {coordinates: [...]}。
  final geometry = _pickMapOf(map, ['geometry']);
  for (final holder in [map, ?geometry]) {
    final raw = holder['coordinates'];
    if (raw is List && raw.length >= 2) {
      final value = _pickNum(
        {'v': raw[longitude ? 0 : 1]},
        const ['v'],
      )?.toDouble();
      if (value != null) return value;
    }
  }
  return null;
}

/// 从图集/媒体列表里提取第一个 URL：元素可能是字符串或带 url 字段的对象。
String? _pickFirstUrl(Map<String, dynamic> map, List<String> keys) {
  final list = _pickList(map, keys);
  if (list == null) return null;
  for (final item in list) {
    if (item is String && item.trim().isNotEmpty) return item.trim();
    if (item is Map) {
      final url = _pickString(item.cast<String, dynamic>(), [
        'url',
        'imageUrl',
        'path',
        'src',
        'contentUrl',
      ]);
      if (url != null) return url;
    }
  }
  return null;
}

/// 打卡配图：`mediaIds` 存的是上传 ID，要换成上传内容相对路径才能展示；
/// 没有 `mediaIds` 时回退旧的 `mediaUrls` / `media` / `gallery` 字段。
String? _pickCheckInImageUrl(Map<String, dynamic> map) {
  final mediaId = _pickFirstUrl(map, ['mediaIds']);
  if (mediaId != null) return '/api/uploads/$mediaId/content';
  return _pickFirstUrl(map, ['mediaUrls', 'media', 'gallery']);
}

/// 从喝过/想喝条目的原始 JSON 里解析跳转半屏地图所需的 [MapVenue]。
/// 喝过条目（CheckIn）的酒吧字段可能平铺在顶层，也可能嵌在 bar/barInfo 等对象里；
/// 坐标缺失时以 0 占位，跳转前由 [_openVenueHalfMap] 统一校验。
MapVenue _venueFromEntryMap(
  Map<String, dynamic> map, {
  required String name,
  bool checkIn = false,
}) {
  final nested = _pickMapOf(map, ['bar', 'barInfo', 'venue', 'place']);
  const empty = <String, dynamic>{};
  // 嵌套对象可能不存在，统一用空 map 兜底，便于直接复用宽松取值函数。
  final bar = nested ?? empty;
  final rawTags = _pickList(map, ['tags']) ?? _pickList(bar, ['tags']);
  return MapVenue(
    // 注意顺序：顶层 `id` 在心愿单接口里是「心愿记录 id」而不是酒吧 id，
    // 直接用它调 /api/bars/{id} 会 422（通信传入参数不正确）并显示成别的酒吧。
    // 打卡记录的顶层 id 不是酒吧 id；仅想喝条目可用顶层 id 兜底。
    id:
        (_pickNum(map, ['barId']) ??
                _pickNum(bar, ['barId', 'id']) ??
                (checkIn ? null : _pickNum(map, ['id'])))
            ?.toString() ??
        name,
    name: name,
    // 跳转目标是酒吧 POI：优先使用补齐后的 bar 详情坐标。打卡记录顶层即使
    // 打卡记录的顶层位置可能是打卡位置，只有想喝条目可用它兜底。
    longitude:
        _pickCoordinate(nested, longitude: true) ??
        (checkIn ? null : _pickCoordinate(map, longitude: true)) ??
        0,
    latitude:
        _pickCoordinate(nested, longitude: false) ??
        (checkIn ? null : _pickCoordinate(map, longitude: false)) ??
        0,
    kind: MapVenueKind.fromRaw(
      _pickString(map, ['barSubtype', 'subtype', 'kind', 'type']) ??
          _pickString(bar, ['barSubtype', 'subtype', 'kind', 'type']),
    ),
    rating:
        (_pickNum(map, ['averageRating', 'rating', 'score']) ??
                _pickNum(bar, ['averageRating', 'rating', 'score']))
            ?.toDouble() ??
        0,
    address:
        _pickString(map, ['address']) ?? _pickString(bar, ['address']) ?? '',
    distance: '',
    tags: [
      if (rawTags != null)
        for (final tag in rawTags)
          if (tag != null) tag.toString(),
    ],
    imageAsset: 'assest/首页/图片素材/酒吧1.png',
    imageUrl:
        (map['profileThumbnailUrl'] as String?) ??
        _pickString(map, ['imageUrl', 'image', 'cover', 'coverUrl']) ??
        _pickString(bar, ['imageUrl', 'image', 'cover', 'coverUrl']),
  );
}

/// 点击喝过/想喝条目：坐标有效时打开锁定的半屏地图（[VenueMapHalfPage]），
/// 否则提示暂无位置，与独立详情页点地址的行为一致。
Future<void> _openVenueHalfMap(BuildContext context, MapVenue venue) async {
  final longitude = venue.longitude;
  final latitude = venue.latitude;
  if (!longitude.isFinite ||
      !latitude.isFinite ||
      longitude.abs() > 180 ||
      latitude.abs() > 90 ||
      (longitude == 0 && latitude == 0)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('该地点暂无可用位置'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    return;
  }
  await openVenueMapHalfPage<void>(context, venue);
}

/// ISO 时间截断为 `yyyy-MM-dd` 日期文案。
String _shortDate(String? iso) {
  if (iso == null || iso.length < 10) return '';
  return iso.substring(0, 10);
}

/// 喝过的酒吧：GET /api/users/me/check-ins，元素为 CheckIn 结构，按页拉取。
Future<_ProfileListPage> _loadCheckInEntries(
  SiponApiService api, {
  required int offset,
  required int limit,
}) async {
  final list = await loadProfileBarImages(
    api,
    await api.getMyCheckIns(
      page: SiponPage(limit: limit, offset: offset),
    ),
    checkIns: true,
  );
  final entries = [
    for (final item in list.whereType<Map>())
      () {
        final map = item.cast<String, dynamic>();
        final name = _pickString(map, ['barName', 'name', 'barTitle']);
        if (name == null) return null;
        final city =
            _pickString(map, ['city']) ??
            _pickString(
              _pickMapOf(map, ['bar', 'barInfo', 'venue', 'place']) ?? const {},
              ['city'],
            ) ??
            '';
        final date = _shortDate(_pickString(map, ['visitedAt', 'createdAt']));
        final meta = [
          if (city.isNotEmpty) city,
          if (date.isNotEmpty) date,
        ].join(' · ');
        return _ProfileListEntry(
          id: _pickNum(map, ['id'])?.toInt(),
          name: name,
          description: _pickString(map, ['content']) ?? '',
          meta: meta,
          isCheckIn: true,
          reviewEntry: map,
          reviewApi: api,
          city: city.isEmpty ? null : city,
          visitedDate: date.isEmpty ? null : date,
          imageUrl:
              map['profileThumbnailUrl'] as String? ??
              _pickCheckInImageUrl(map),
          venue: _venueFromEntryMap(map, name: name, checkIn: true),
        );
      }(),
  ].whereType<_ProfileListEntry>().toList(growable: false);
  // 拉满一页视为还有更多，由弹窗滚动触底继续翻页。
  return _ProfileListPage(items: entries, hasMore: list.length >= limit);
}

/// 想喝的酒吧：GET /api/users/me/wishlist/bars，元素为 Bar 结构，按页拉取。
Future<_ProfileListPage> _loadWishlistEntries(
  SiponApiService api, {
  required int offset,
  required int limit,
}) async {
  final list = await loadProfileBarImages(
    api,
    await api.getWishlistBars(
      page: SiponPage(limit: limit, offset: offset),
    ),
    checkIns: false,
  );
  final entries = [
    for (final item in list.whereType<Map>())
      () {
        final map = item.cast<String, dynamic>();
        final name = _pickString(map, ['name', 'barName', 'title']);
        if (name == null) return null;
        final rating = _pickNum(map, ['averageRating', 'rating', 'score']);
        final meta = [
          ?_pickString(map, ['city']),
          if (rating != null) '${rating.toStringAsFixed(1)} 分',
        ].join(' · ');
        return _ProfileListEntry(
          id:
              (_pickNum(map, ['barId']) ??
                      _pickNum(
                        _pickMapOf(map, ['bar', 'barInfo', 'venue', 'place']) ??
                            const {},
                        ['id', 'barId'],
                      ) ??
                      _pickNum(map, ['id']))
                  ?.toInt(),
          name: name,
          description: _pickString(map, ['address', 'description']) ?? '',
          meta: meta,
          imageUrl:
              (map['profileThumbnailUrl'] as String?) ??
              _pickString(map, ['imageUrl', 'image', 'cover', 'coverUrl']) ??
              _pickFirstUrl(map, ['gallery']),
          venue: _venueFromEntryMap(map, name: name),
        );
      }(),
  ].whereType<_ProfileListEntry>().toList(growable: false);
  return _ProfileListPage(items: entries, hasMore: list.length >= limit);
}

/// 我的酒鬼路线：GET /api/users/me/routes，元素为 DrinkingRoute 结构，按页拉取。
/// 站点数取自接口契约的 stops 数组（兜底 barIds/bars）。
Future<_ProfileListPage> _loadRouteEntries(
  SiponApiService api, {
  required int offset,
  required int limit,
}) async {
  final list = await api.getMyDrinkingRoutes(
    page: SiponPage(limit: limit, offset: offset),
  );
  final routes = await Future.wait(
    list.whereType<Map>().map((item) async {
      final map = item.cast<String, dynamic>();
      if (parseRouteStops(map).isNotEmpty) return map;
      final id = _pickNum(map, ['id'])?.toInt();
      if (id == null) return map;
      try {
        final detail = await api.getDrinkingRoute(id);
        if (detail is Map) return {...map, ...detail.cast<String, dynamic>()};
      } on Exception {
        // A missing preview must not hide the route or prevent deletion.
      }
      return map;
    }),
  );
  final barIds = routes
      .expand((map) => parseRouteStops(map).take(3))
      .map((stop) => stop.id)
      .whereType<int>()
      .where((id) => id > 0)
      .toSet();
  final images = await loadProfileBarImages(api, [
    for (final id in barIds) {'id': id},
  ], checkIns: false);
  final thumbnails = <int, String>{
    for (final image in images.whereType<Map>())
      if (image['profileThumbnailUrl'] is String)
        image['id'] as int: image['profileThumbnailUrl'] as String,
  };
  final entries = [
    for (final item in routes)
      () {
        final map = item.cast<String, dynamic>();
        final title = _pickString(map, ['title', 'name']);
        if (title == null) return null;
        final stops = parseRouteStops(map);
        return _ProfileListEntry(
          id: _pickNum(map, ['id'])?.toInt(),
          name: title,
          // 日期仍由服务端保存，但酒鬼路线只表达路线本身，不展示起止日期。
          description: '',
          meta: '${stops.length} 个地点',
          isPrivate:
              _pickString(map, ['visibility'])?.toLowerCase() != 'public',
          viewCount: _pickNum(map, ['viewCount', 'views'])?.toInt(),
          stops: stops,
          routeThumbnails: [
            for (final stop in stops.take(3))
              if (thumbnails[stop.id] != null) thumbnails[stop.id]!,
          ],
        );
      }(),
  ].whereType<_ProfileListEntry>().toList(growable: false);
  return _ProfileListPage(items: entries, hasMore: list.length >= limit);
}

/// 打开「我的礼券」列表弹窗：GET /api/users/me/coupons。
Future<void> _showCouponList(BuildContext context) {
  final api = SiponApiService();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProfileListSheet(
      title: '我的礼券',
      emptyText: '暂无可用礼券',
      // 礼券接口暂不分页，一次性拉取并标记无更多。
      loader: (int _, int _) async {
        final list = await api.getCoupons();
        return _ProfileListPage(
          hasMore: false,
          items: [
            for (final item in list.whereType<Map>())
              () {
                final map = item.cast<String, dynamic>();
                final name = _pickString(map, ['title', 'name', 'couponName']);
                if (name == null) return null;
                final amount = _pickNum(map, ['amount', 'discount', 'value']);
                final validTo = _shortDate(
                  _pickString(map, ['validTo', 'expireAt', 'expiredAt']),
                );
                return _ProfileListEntry(
                  name: name,
                  description:
                      _pickString(map, ['description', 'rule', 'condition']) ??
                      '',
                  meta: [
                    if (amount != null) '¥${amount.toStringAsFixed(0)}',
                    if (validTo.isNotEmpty) '有效期至 $validTo',
                  ].join(' · '),
                );
              }(),
          ].whereType<_ProfileListEntry>().toList(growable: false),
        );
      },
    ),
  );
}

/* 成就勋章暂时隐藏，保留逻辑待后续启用。
/// 打开「成就勋章」列表弹窗：GET /api/users/me/achievements。
Future<void> _showAchievementList(BuildContext context) {
  final api = SiponApiService();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProfileListSheet(
      title: '成就勋章',
      emptyText: '还没有解锁任何成就',
      // 成就接口暂不分页，一次性拉取并标记无更多。
      loader: (int _, int _) async {
        final list = await api.getAchievements();
        return _ProfileListPage(
          hasMore: false,
          items: [
            for (final item in list.whereType<Map>())
              () {
                final map = item.cast<String, dynamic>();
                final name = _pickString(map, ['name', 'title', 'badgeName']);
                if (name == null) return null;
                final unlocked =
                    map['unlocked'] == true ||
                    map['achieved'] == true ||
                    map['isUnlocked'] == true;
                return _ProfileListEntry(
                  name: name,
                  description: _pickString(map, ['description', 'desc']) ?? '',
                  meta: unlocked ? '已解锁' : '未解锁',
                );
              }(),
          ].whereType<_ProfileListEntry>().toList(growable: false),
        );
      },
    ),
  );
}
*/

/// 打开「Sipon 会员」摘要弹窗：GET /api/users/me/membership。
void _showMembershipSheet(BuildContext context, {int? userLevel}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MembershipSheet(userLevel: userLevel),
  );
}

/// 会员卡摘要：固定展示已开放权益，其余会员信息来自接口。
class _ProfileListPage {
  const _ProfileListPage({required this.items, required this.hasMore});

  final List<_ProfileListEntry> items;
  final bool hasMore;
}

/// 我的页通用列表弹窗：loading / empty / error（带重试）三态齐全，
/// 数据由 [loader] 按页提供，列表触底自动翻页；路线列表用 [routeStyle] 切换卡片样式。
class _ProfileListSheet extends StatefulWidget {
  const _ProfileListSheet({
    required this.title,
    required this.loader,
    required this.emptyText,
    this.routeStyle = false,
    this.deleteEntry,
  });

  final String title;
  final Future<_ProfileListPage> Function(int offset, int limit) loader;
  final String emptyText;
  final bool routeStyle;
  final Future<void> Function(int id)? deleteEntry;

  @override
  State<_ProfileListSheet> createState() => _ProfileListSheetState();
}

class _ProfileListSheetState extends State<_ProfileListSheet> {
  /// 每页条数。
  static const int _pageSize = 20;

  /// 已加载的条目（首屏 + 触底翻页追加）。
  List<_ProfileListEntry> _items = const [];

  bool _loading = true;
  bool _selecting = false;
  bool _deleting = false;
  final Set<int> _selected = {};

  void _toggleSelection(_ProfileListEntry item) {
    final id = item.id;
    if (_deleting || _loadingMore || id == null || id <= 0) return;
    setState(() {
      _selecting = true;
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  Future<void> _deleteSelected() async {
    final deleteEntry = widget.deleteEntry;
    if (_deleting || _selected.isEmpty || deleteEntry == null) return;
    final ids = Set<int>.of(_selected);
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '取消删除',
      barrierColor: context.siponColors.scrim,
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curve),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) =>
          _DeleteRecordsDialog(
            count: ids.length,
            name: ids.length == 1
                ? _items.firstWhere((item) => item.id == ids.first).name
                : null,
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final deleted = <int>{};
    for (final id in ids) {
      try {
        await deleteEntry(id);
        deleted.add(id);
      } on Exception {
        // Keep failed entries selected so they can be retried.
      }
    }
    if (!mounted) return;
    setState(() {
      _items = _items.where((item) => !deleted.contains(item.id)).toList();
      _selected.removeAll(deleted);
      _deleting = false;
      _selecting = _selected.isNotEmpty;
    });
    final failed = ids.length - deleted.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '已删除 ${deleted.length} 条记录'
              : '已删除 ${deleted.length} 条，$failed 条删除失败，请重试',
        ),
      ),
    );
    if (_items.isEmpty && _hasMore) await _load();
  }

  Widget _selectionActions() {
    final scheme = Theme.of(context).colorScheme;
    final siponColors = context.siponColors;
    final selectable = _items
        .map((item) => item.id)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
    final allSelected =
        selectable.isNotEmpty && _selected.containsAll(selectable);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: siponColors.elevatedSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: scheme.primary),
            onPressed: _deleting
                ? null
                : () => setState(() {
                    if (allSelected) {
                      _selected.clear();
                    } else {
                      _selected.addAll(selectable);
                    }
                  }),
            child: Text(allSelected ? '取消全选' : '全选已加载'),
          ),
          const Spacer(),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
            ),
            onPressed: _deleting
                ? null
                : () => setState(() {
                    _selecting = false;
                    _selected.clear();
                  }),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _deleting || _selected.isEmpty ? null : _deleteSelected,
            child: Text(_deleting ? '删除中…' : '删除 (${_selected.length})'),
          ),
        ],
      ),
    );
  }

  /// 正在翻页加载下一批。
  bool _loadingMore = false;

  /// 是否还有下一页可加载。
  bool _hasMore = true;

  String? _error;

  /// 列表滚动控制器，用于触底自动翻页。
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// 滚动接近底部时自动加载下一页。
  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.extentAfter < 200) {
      _loadMore();
    }
  }

  /// 拉取列表第一页；错误统一展示 SiponApiException 文案。
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.loader(0, _pageSize);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _hasMore = page.items.isNotEmpty && page.hasMore;
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  /// 触底翻页，追加下一页条目。
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _selecting || _deleting || !_hasMore) {
      return;
    }

    setState(() => _loadingMore = true);
    try {
      final page = await widget.loader(_items.length, _pageSize);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _hasMore = page.items.isNotEmpty && page.hasMore;
        _loadingMore = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        // 翻页失败停止继续尝试，避免触底无限重试。
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final siponColors = context.siponColors;
    // 固定弹窗高度：让加载/空态/列表态高度一致，避免数据返回时 bottom sheet
    // 因内容高度变化而重新调整自身尺寸，出现“抖动/跳动”。
    final sheetHeight = math.min(
      620.0,
      MediaQuery.of(context).size.height * 0.8,
    );
    return PopScope(
      canPop: !_deleting,
      child: Container(
        height: sheetHeight,
        decoration: BoxDecoration(
          color: siponColors.elevatedSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _deleting
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (_selecting) _selectionActions(),
                if (!_selecting &&
                    widget.deleteEntry != null &&
                    _items.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      '长按记录可多选删除',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Flexible(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.primary,
          ),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.primary,
                side: BorderSide(color: scheme.primary),
              ),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text(
            widget.emptyText,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      shrinkWrap: true,
      itemCount:
          _items.length + (!_selecting && (_hasMore || _loadingMore) ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return _ProfileListFooter(
            loading: _loadingMore,
            onLoadMore: _loadMore,
          );
        }
        final item = _items[index];
        return widget.routeStyle
            ? _MockRouteCard(
                item: item,
                index: index,
                selecting: _selecting,
                selected: _selected.contains(item.id),
                onLongPress: _loadingMore || _deleting
                    ? null
                    : () => _toggleSelection(item),
                onTap: _deleting
                    ? null
                    : _selecting
                    ? () => _toggleSelection(item)
                    : () => _showRouteDetail(context, item),
              )
            : _MockListCard(
                item: item,
                selecting: _selecting,
                selected: _selected.contains(item.id),
                onLongPress:
                    widget.deleteEntry == null || _loadingMore || _deleting
                    ? null
                    : () => _toggleSelection(item),
                onOpenMap: _deleting
                    ? null
                    : _selecting
                    ? () => _toggleSelection(item)
                    : item.venue == null
                    ? null
                    : () {
                        if (item.isCheckIn && item.reviewEntry != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ReviewDetailPage(
                                entry: item.reviewEntry!,
                                venue: item.venue!,
                                apiService: item.reviewApi,
                              ),
                            ),
                          );
                        } else {
                          _openVenueHalfMap(context, item.venue!);
                        }
                      },
              );
      },
    );
  }
}

/// 个人中心列表弹窗的尾部：加载中显示转圈，空闲时可点击手动翻页。
class _ProfileListFooter extends StatelessWidget {
  const _ProfileListFooter({required this.loading, required this.onLoadMore});

  final bool loading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: onLoadMore,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                ),
                child: const Text(
                  '加载更多',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
      ),
    );
  }
}

/// 条目封面图：有网络图先用网络图，失败或没有就退回本地资产。
Widget _entryImage(
  _ProfileListEntry item, {
  required double width,
  required double height,
}) {
  final url = item.imageUrl;
  if (url != null && url.isNotEmpty) {
    return SiponNetworkImage(
      url: url,
      fallbackAsset: item.fallbackImagePath,
      width: width,
      height: height,
    );
  }
  return Image.asset(
    item.fallbackImagePath,
    width: width,
    height: height,
    fit: BoxFit.cover,
  );
}

class _DeleteRecordsDialog extends StatelessWidget {
  const _DeleteRecordsDialog({required this.count, this.name});
  final int count;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final siponColors = context.siponColors;
    return Dialog(
      backgroundColor: siponColors.elevatedSurface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: siponColors.brandSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: scheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '删除 $count 条记录？',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              if (name != null) ...[
                Text(
                  name!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                '删除后无法恢复，请确认后再操作。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: siponColors.subtleSurface,
                        foregroundColor: scheme.onSurfaceVariant,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: scheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MockListCard extends StatefulWidget {
  const _MockListCard({
    required this.item,
    this.onOpenMap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;
  final _ProfileListEntry item;

  /// 点击条目打开半屏地图；无地点的列表（如礼券）为 null，整卡不响应。
  final VoidCallback? onOpenMap;

  @override
  State<_MockListCard> createState() => _MockListCardState();
}

class _MockListCardState extends State<_MockListCard> {
  bool _pressed = false;
  _ProfileListEntry get item => widget.item;
  bool get selecting => widget.selecting;
  bool get selected => widget.selected;
  VoidCallback? get onOpenMap => widget.onOpenMap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final siponColors = context.siponColors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = Duration(milliseconds: reduceMotion ? 0 : 180);
    return AnimatedScale(
      scale: _pressed ? 0.965 : 1,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: InkWell(
        onTap: onOpenMap,
        onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                setState(() => _pressed = false);
                widget.onLongPress!();
              },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? siponColors.brandSurface : scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.55)
                  : Colors.transparent,
              width: 1.5,
            ),
            // 深色卡片靠层级 + 描边区分，不再依赖品牌色阴影。
            boxShadow: [
              if (selected || _pressed)
                BoxShadow(
                  color: siponColors.shadow,
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _entryImage(item, width: 88, height: 88),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: item.isCheckIn
                    ? _CheckInListDetails(item: item)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.meta,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
              if (selecting)
                Semantics(
                  checked: selected,
                  label: '选择 ${item.name}',
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AnimatedContainer(
                        duration: duration,
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? scheme.primary : scheme.surface,
                          border: Border.all(
                            color: selected
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: 1.5,
                          ),
                        ),
                        child: AnimatedSwitcher(
                          duration: duration,
                          child: selected
                              ? Icon(
                                  Icons.check_rounded,
                                  key: ValueKey(true),
                                  size: 17,
                                  color: scheme.onPrimary,
                                )
                              : const SizedBox.shrink(key: ValueKey(false)),
                        ),
                      ),
                    ),
                  ),
                )
              else
                IconButton(
                  // 箭头与整卡同行为；无地点列表保持原先"可点无操作"，避免变灰。
                  onPressed: onOpenMap ?? () {},
                  icon: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckInListDetails extends StatelessWidget {
  const _CheckInListDetails({required this.item});

  final _ProfileListEntry item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final review = item.description.trim();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          review.isEmpty ? item.name : review,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            height: 1.3,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        _CheckInMetaLine(
          icon: Icons.location_on_outlined,
          text: [
            if (item.city?.isNotEmpty == true) item.city!,
            item.name,
          ].join(' · '),
        ),
        const SizedBox(height: 4),
        _CheckInMetaLine(
          icon: Icons.access_time_rounded,
          text: item.visitedDate ?? '日期待补充',
        ),
      ],
    );
  }
}

class _CheckInMetaLine extends StatelessWidget {
  const _CheckInMetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: scheme.primary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MockRouteCard extends StatefulWidget {
  const _MockRouteCard({
    required this.item,
    required this.index,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  final _ProfileListEntry item;
  final int index;

  @override
  State<_MockRouteCard> createState() => _MockRouteCardState();
}

class _MockRouteCardState extends State<_MockRouteCard> {
  bool _pressed = false;
  _ProfileListEntry get item => widget.item;
  int get index => widget.index;

  @override
  Widget build(BuildContext context) {
    final isPrivate = item.isPrivate;
    // 内容固有色：路线卡片多彩底与深色文字成对（浅底 + 深字），深色模式下保持原样以保证
    // 对比度；多彩底无现有语义色可映射，已上报需新增路线卡片语义色，待主题层收敛后再迁移。
    // 同理卡片内深灰文字、选中品牌色、图片白色描边与占位色暂保留。
    const routeColors = [
      Color(0xFFFFE6B8), // 杏桃
      Color(0xFFDDE5FF), // 雾蓝
      Color(0xFFE3F2E4), // 鼠尾草绿
      Color(0xFFF8DFE8), // 玫瑰粉
      Color(0xFFE9E0F7), // 薰衣草紫
      Color(0xFFFFE7D6), // 蜜桃橘
      Color(0xFFDDF0F0), // 薄荷青
    ];
    final backgroundColor = routeColors[index % routeColors.length];
    final routeImages = item.routeThumbnails;
    final duration = Duration(
      milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 180,
    );
    return AnimatedScale(
      scale: _pressed ? 0.965 : 1,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                setState(() => _pressed = false);
                widget.onLongPress!();
              },
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 144,
          child: Material(
            color: widget.selected ? const Color(0xFFF9E8F4) : backgroundColor,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 112, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ProfilePage._ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          height: 1.25,
                          letterSpacing: 0,
                        ),
                      ),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          item.description,
                          style: const TextStyle(
                            color: Color(0xFF79747C),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        item.meta,
                        style: const TextStyle(
                          color: Color(0xFF79747C),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 13,
                  right: 14,
                  child: widget.selecting
                      ? AnimatedContainer(
                          duration: duration,
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.selected
                                ? ProfilePage._brand
                                : Colors.white,
                            border: Border.all(
                              color: widget.selected
                                  ? ProfilePage._brand
                                  : const Color(0xFFD9D1DC),
                            ),
                          ),
                          child: widget.selected
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: Colors.white,
                                )
                              : null,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPrivate
                                  ? Icons.lock_outline_rounded
                                  : Icons.public_rounded,
                              size: 15,
                              color: const Color(0xFF7B7580),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.visibility_outlined,
                              size: 16,
                              color: Color(0xFF7B7580),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${item.viewCount ?? 0}',
                              style: const TextStyle(
                                color: Color(0xFF7B7580),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                ),
                Positioned(
                  right: 12,
                  bottom: 6,
                  child: SizedBox(
                    width: 112,
                    height: 76,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (routeImages.isEmpty)
                          const Center(
                            child: Icon(
                              Icons.route_rounded,
                              size: 44,
                              color: Color(0xFFAC9EAD),
                            ),
                          ),
                        for (
                          var imageIndex = 0;
                          imageIndex < routeImages.length;
                          imageIndex++
                        )
                          Positioned(
                            right: imageIndex * 16.0,
                            bottom: imageIndex * 5.0,
                            child: Transform.rotate(
                              angle: (imageIndex - 1) * 0.10,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 76,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      width: 2,
                                    ),
                                  ),
                                  child: SiponNetworkImage(
                                    url: routeImages[imageIndex],
                                    fit: BoxFit.cover,
                                    fallbackWidget: const ColoredBox(
                                      color: Color(0xFFF1ECF1),
                                      child: Icon(
                                        Icons.local_bar_outlined,
                                        color: Color(0xFFAC9EAD),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 点击路线卡片进入路线详情地图页：先展示列表接口已带的数据，
/// 地图页内再拉取 GET /api/routes/{id} 渲染各站点并补齐缺失坐标。
void _showRouteDetail(BuildContext context, _ProfileListEntry item) {
  final routeId = item.id;
  if (routeId == null) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RouteDetailMapPage(
        routeId: routeId,
        title: item.name,
        subtitle: item.description,
        previewStops: item.stops,
      ),
    ),
  );
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 42,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _ProfileListCard extends StatelessWidget {
  const _ProfileListCard({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.siponColors.glassSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            rows[index],
            if (index != rows.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 42),
                child: Divider(height: 1, color: scheme.outlineVariant),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProfileListRow extends StatelessWidget {
  const _ProfileListRow({
    required this.assetPath,
    required this.title,
    this.badge,
    // 成就勋章暂时隐藏，trailingText 保留待后续启用。
    // this.trailingText,
    this.onTap,
  });

  final String assetPath;
  final String title;
  final String? badge;
  // final String? trailingText;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Image.asset(assetPath, width: 26, height: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.siponColors.brandSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            // 成就勋章暂时隐藏，trailingText 渲染保留待后续启用。
            // if (trailingText != null)
            //   Text(
            //     trailingText!,
            //     style: const TextStyle(
            //       color: ProfilePage._brand,
            //       fontSize: 10,
            //       fontWeight: FontWeight.w700,
            //       letterSpacing: 0,
            //     ),
            //   ),
            const SizedBox(width: 7),
            Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
