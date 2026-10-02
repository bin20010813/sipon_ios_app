import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/shared/services/home_moments_repository.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';

void main() {
  test('feed item maps author, venue, price range and reaction', () {
    final item = HomeMoment.fromJson({
      'id': 100,
      'userId': 5,
      'barId': 12,
      'barName': '示例酒吧',
      'city': '佛山',
      'address': '示例路 1 号',
      'barSubtype': 'cocktail_bar',
      'priceRange': '¥100-200',
      'content': '特调很好喝',
      'mediaUrls': ['/api/uploads/photo/content'],
      'likeCount': 3,
      'myReaction': 'like',
      'createdAt': '2026-09-28T12:05:00Z',
      'author': {
        'userId': 5,
        'displayName': '小酒',
        'avatarUrl': '/api/uploads/avatar/content',
      },
    });

    expect(item.author.id, 5);
    expect(item.author.name, '小酒');
    expect(item.venue.id, '12');
    expect(item.photos.single, '/api/uploads/photo/content');
    expect(item.priceRange, '¥100-200');
    expect(item.withReaction(null).likeCount, 2);
  });

  test('repository forwards server filters and parses pagination', () async {
    final api = _FakeApi();
    final repository = HomeMomentsRepository(api: api);
    final page = await repository.load(
      const HomeFeedQuery(
        city: '佛山',
        keyword: '特调',
        barSubtype: 'cocktail_bar',
        scope: 'following',
        sort: 'popular',
        offset: 20,
      ),
    );

    expect(api.city, '佛山');
    expect(api.keyword, '特调');
    expect(api.barSubtype, 'cocktail_bar');
    expect(api.scope, 'following');
    expect(api.sort, 'popular');
    expect(api.page?.offset, 20);
    expect(page.items.single.id, 100);
    expect(page.hasMore, isTrue);
    expect(page.offset, 20);
  });

  test('subtype options come from the API codes', () async {
    final options = await HomeMomentsRepository(
      api: _FakeApi(),
    ).loadBarSubtypes();
    expect(options.single.code, 'cocktail_bar');
    expect(options.single.name, '鸡尾酒吧');
  });
}

class _FakeApi extends SiponApiService {
  String? city;
  String? keyword;
  String? barSubtype;
  String? scope;
  String? sort;
  SiponPage? page;

  @override
  Future<dynamic> getCheckInFeed({
    String? city,
    String? keyword,
    String? barSubtype,
    String scope = 'all',
    String sort = 'latest',
    SiponPage page = const SiponPage(),
  }) async {
    this.city = city;
    this.keyword = keyword;
    this.barSubtype = barSubtype;
    this.scope = scope;
    this.sort = sort;
    this.page = page;
    return {
      'items': [
        {
          'id': 100,
          'barId': 12,
          'barName': '示例酒吧',
          'author': {'userId': 5, 'displayName': '小酒'},
        },
      ],
      'limit': 20,
      'offset': 20,
      'hasMore': true,
    };
  }

  @override
  Future<List<dynamic>> getBarSubtypes() async => [
    {'code': 'cocktail_bar', 'name': '鸡尾酒吧'},
  ];
}
