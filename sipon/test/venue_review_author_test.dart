import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/services/map/api_venue_detail_repository.dart';
import 'package:sipon/services/map/map_models.dart';
import 'package:sipon/services/sipon_api_service.dart';

const venue = MapVenue(
  id: '42',
  name: 'Bar',
  longitude: 121,
  latitude: 31,
  kind: MapVenueKind.pub,
  rating: 4,
  address: 'Address',
  distance: '',
  tags: [],
  imageAsset: '',
);

void main() {
  for (final firstPage in [true, false]) {
    test(
      'review authors resolve on ${firstPage ? "detail" : "pagination"}',
      () async {
        final api = _ReviewApi();
        final repository = SiponApiVenueDetailRepository(api: api);
        final reviews = firstPage
            ? (await repository.fetchDetail(venue)).reviews
            : (await repository.fetchReviews(venue)).reviews;
        expect(reviews.map((r) => r.nickname), [
          'Alice',
          'Bob',
          'Carol',
          'Carol',
        ]);
        expect(reviews.map((r) => r.avatarAsset), [
          '/alice.png',
          '/bob.png',
          '/carol.png',
          '/carol.png',
        ]);
        expect(api.profileCalls, 1);
      },
    );
  }

  test('profile failure preserves reviews and existing author names', () async {
    final api = _ReviewApi(failProfile: true);
    final reviews = (await SiponApiVenueDetailRepository(
      api: api,
    ).fetchReviews(venue)).reviews;
    expect(reviews.length, 4);
    expect(reviews.first.nickname, 'Alice');
    expect(reviews[2].nickname, '匿名用户');
    expect(reviews[2].avatarAsset, isNull);
  });
}

class _ReviewApi extends SiponApiService {
  _ReviewApi({this.failProfile = false});
  final bool failProfile;
  int profileCalls = 0;

  @override
  Future<dynamic> getBarById(int id) async => {'id': id};

  @override
  Future<List<dynamic>> getBarReviews(
    int id, {
    SiponPage page = const SiponPage(),
  }) async => [
    {
      'rating': 4,
      'author': {'displayName': 'Alice', 'avatarUrl': '/alice.png'},
    },
    {
      'rating': 4,
      'user': {'displayName': 'Bob'},
      'avatarUrl': '/bob.png',
    },
    {'rating': 4, 'userId': 7},
    {
      'rating': 5,
      'author': {'id': 7},
    },
  ];

  @override
  Future<dynamic> getUserProfile(int userId) async {
    profileCalls++;
    expect(userId, 7);
    if (failProfile) throw Exception('unavailable');
    return {
      'user': {'displayName': 'Carol', 'avatarImageUrl': '/carol.png'},
    };
  }

  @override
  Future<List<dynamic>> getBarHours(int id) async => [];
  @override
  Future<List<dynamic>> getBarDrinks(
    int id, {
    SiponPage page = const SiponPage(),
  }) async => [];
  @override
  Future<List<dynamic>> getBarMedia(int id) async => [];
}
