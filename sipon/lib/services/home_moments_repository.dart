import 'map/map_models.dart';
import 'sipon_api_service.dart';
import 'user_profile_data.dart';

class HomeFeedQuery {
  const HomeFeedQuery({
    this.city,
    this.keyword,
    this.barSubtype,
    this.scope = 'all',
    this.sort = 'latest',
    this.limit = 20,
    this.offset = 0,
  });

  final String? city;
  final String? keyword;
  final String? barSubtype;
  final String scope;
  final String sort;
  final int limit;
  final int offset;

  HomeFeedQuery atOffset(int value) => HomeFeedQuery(
    city: city,
    keyword: keyword,
    barSubtype: barSubtype,
    scope: scope,
    sort: sort,
    limit: limit,
    offset: value,
  );
}

class HomeFeedPage {
  const HomeFeedPage({
    required this.items,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  final List<HomeMoment> items;
  final int limit;
  final int offset;
  final bool hasMore;

  factory HomeFeedPage.fromJson(Object? value) {
    final map = _map(value);
    if (map == null || map['items'] is! List) {
      throw const FormatException('Invalid check-in feed response');
    }
    return HomeFeedPage(
      items: (map['items'] as List)
          .whereType<Map>()
          .map((entry) => HomeMoment.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      limit: _integer(map, ['limit']) ?? 20,
      offset: _integer(map, ['offset']) ?? 0,
      hasMore: map['hasMore'] == true,
    );
  }
}

class BarSubtypeOption {
  const BarSubtypeOption({required this.code, required this.name});

  final String code;
  final String name;

  static BarSubtypeOption? fromJson(Object? value) {
    final map = _map(value);
    if (map == null) return null;
    final code = _string(map, ['code']);
    if (code == null) return null;
    return BarSubtypeOption(code: code, name: _string(map, ['name']) ?? code);
  }
}

/// A public, approved check-in returned by GET /api/feed/check-ins.
class HomeMoment {
  const HomeMoment({
    required this.id,
    required this.entry,
    required this.venue,
    required this.author,
    required this.city,
    required this.address,
    required this.barSubtype,
    required this.barCategory,
    required this.priceRange,
    required this.content,
    required this.photos,
    required this.createdAt,
    required this.visitedAt,
    required this.likeCount,
    required this.commentCount,
    required this.myReaction,
    required this.rating,
  });

  final int id;
  final Map<String, dynamic> entry;
  final MapVenue venue;
  final UserProfileData author;
  final String? city;
  final String? address;
  final String? barSubtype;
  final String? barCategory;
  final String? priceRange;
  final String content;
  final List<String> photos;
  final DateTime? createdAt;
  final DateTime? visitedAt;
  final int likeCount;
  final int commentCount;
  final String? myReaction;
  final int? rating;

  HomeMoment withReaction(String? reaction) => HomeMoment(
    id: id,
    entry: entry,
    venue: venue,
    author: author,
    city: city,
    address: address,
    barSubtype: barSubtype,
    barCategory: barCategory,
    priceRange: priceRange,
    content: content,
    photos: photos,
    createdAt: createdAt,
    visitedAt: visitedAt,
    likeCount:
        (likeCount +
                (reaction == 'like' ? 1 : 0) -
                (myReaction == 'like' ? 1 : 0))
            .clamp(0, 1 << 30),
    commentCount: commentCount,
    myReaction: reaction,
    rating: rating,
  );

  HomeMoment withFollowing(bool followed) => HomeMoment(
    id: id,
    entry: entry,
    venue: venue,
    author: UserProfileData.fromJson({
      'id': author.id,
      'displayName': author.displayName,
      'avatarUrl': author.avatarUrl,
      'followedByViewer': followed,
      'reviewCount': author.checkInCount,
    }),
    city: city,
    address: address,
    barSubtype: barSubtype,
    barCategory: barCategory,
    priceRange: priceRange,
    content: content,
    photos: photos,
    createdAt: createdAt,
    visitedAt: visitedAt,
    likeCount: likeCount,
    commentCount: commentCount,
    myReaction: myReaction,
    rating: rating,
  );

  factory HomeMoment.fromJson(Map<String, dynamic> entry) {
    final id = _integer(entry, ['id']);
    if (id == null) throw const FormatException('Feed item is missing id');
    final authorMap = _map(entry['author']) ?? const <String, dynamic>{};
    final author = UserProfileData.fromJson({
      ...authorMap,
      'id':
          _integer(authorMap, ['userId', 'id']) ?? _integer(entry, ['userId']),
    });
    final photos =
        (entry['mediaUrls'] is List ? entry['mediaUrls'] as List : const [])
            .map((url) => url?.toString().trim() ?? '')
            .where((url) => url.isNotEmpty)
            .toList(growable: false);
    final barId = _integer(entry, ['barId']);
    final barSubtype = _string(entry, ['barSubtype']);
    final barCategory = _string(entry, ['barCategory']);
    final address = _string(entry, ['address']);
    final longitude = _number(entry, ['longitude']);
    final latitude = _number(entry, ['latitude']);
    return HomeMoment(
      id: id,
      entry: entry,
      venue: MapVenue(
        id: barId?.toString() ?? '',
        name: _string(entry, ['barName']) ?? '酒吧',
        longitude: longitude ?? 0,
        latitude: latitude ?? 0,
        kind: MapVenueKind.fromRaw(barSubtype ?? barCategory),
        rating: 0,
        hasRating: false,
        address: address ?? '',
        distance: '',
        tags: barCategory == null ? const [] : [barCategory],
        imageAsset: 'assest/首页/图片素材/酒吧1.png',
      ),
      author: author,
      city: _string(entry, ['city']),
      address: address,
      barSubtype: barSubtype,
      barCategory: barCategory,
      priceRange: _string(entry, ['priceRange']),
      content: _string(entry, ['content']) ?? '',
      photos: photos,
      createdAt: _date(entry, 'createdAt'),
      visitedAt: _date(entry, 'visitedAt'),
      likeCount: _integer(entry, ['likeCount']) ?? 0,
      commentCount: _integer(entry, ['commentCount']) ?? 0,
      myReaction: _string(entry, ['myReaction']),
      rating: _integer(entry, ['rating']),
    );
  }
}

class HomeMomentsRepository {
  HomeMomentsRepository({SiponApiService? api})
    : _api = api ?? SiponApiService();

  final SiponApiService _api;

  Future<HomeFeedPage> load(HomeFeedQuery query) async => HomeFeedPage.fromJson(
    await _api.getCheckInFeed(
      city: query.city,
      keyword: query.keyword,
      barSubtype: query.barSubtype,
      scope: query.scope,
      sort: query.sort,
      page: SiponPage(limit: query.limit, offset: query.offset),
    ),
  );

  Future<List<BarSubtypeOption>> loadBarSubtypes() async =>
      (await _api.getBarSubtypes())
          .map(BarSubtypeOption.fromJson)
          .whereType<BarSubtypeOption>()
          .toList(growable: false);
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : null;

String? _string(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

int? _integer(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed != null) return parsed;
  }
  return null;
}

double? _number(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return null;
}

DateTime? _date(Map<String, dynamic> map, String key) =>
    DateTime.tryParse(_string(map, [key]) ?? '')?.toLocal();
