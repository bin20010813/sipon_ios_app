import 'home_moments_repository.dart';

/// Local preview data; never sends simulated interactions to the API.
class MockHomeMomentsRepository extends HomeMomentsRepository {
  @override
  Future<List<BarSubtypeOption>> loadBarSubtypes() async => const [
    BarSubtypeOption(code: 'cocktail_bar', name: '鸡尾酒吧'),
    BarSubtypeOption(code: 'livehouse', name: 'Livehouse'),
  ];

  @override
  Future<HomeFeedPage> load(HomeFeedQuery query) async {
    final now = DateTime.now();
    final items =
        List.generate(4, (index) {
          final video = index.isOdd;
          return HomeMoment.fromJson({
            'id': -100 - index,
            'preview': true,
            'previewDuration': video ? (index == 1 ? '00:18' : '00:32') : null,
            'author': {
              'displayName': ['微醺的阿柚', '周末听现场', '一杯金汤力', '夜游小林'][index],
              'followedByViewer': index < 2,
            },
            'barName': ['巷口小酒馆', '回声现场', '落日露台', '深夜调酒室'][index],
            'city': query.city ?? '上海',
            'address': '城市街角 · 预览地点',
            'barSubtype': index == 1 ? 'livehouse' : 'cocktail_bar',
            'content': [
              '今晚的快乐是这杯柑橘特调，酸甜刚好。和朋友慢慢聊到打烊。',
              '记录今晚最喜欢的十八秒！现场的鼓点配一杯冰啤酒，周末就该这样过。',
              '收集了三张今晚的微醺瞬间，落日、酒杯，还有喜欢的小角落。',
              '调酒师摇壶的节奏太好听了，最后那一下橙皮喷香是点睛之笔。',
            ][index],
            'mediaUrls': [
              ['assest/首页/图片素材/鸡尾酒系列1.png', 'assest/首页/图片素材/酒吧1.png'],
              ['assest/首页/图片素材/Play House 电音夜店.png'],
              [
                'assest/首页/图片素材/鸡尾酒系列2.png',
                'assest/首页/图片素材/酒吧2.png',
                'assest/首页/图片素材/鸡尾酒系列3.png',
              ],
              ['assest/首页/图片素材/庙前冰室.png'],
            ][index],
            'createdAt': now
                .subtract(Duration(minutes: 12 + index * 37))
                .toIso8601String(),
            'likeCount': [28, 56, 19, 42][index],
            'commentCount': [3, 8, 2, 6][index],
            'rating': 5,
          });
        }).where((item) {
          final keyword = query.keyword?.toLowerCase() ?? '';
          return (query.scope != 'following' ||
                  item.author.isFollowing == true) &&
              (query.barSubtype == null ||
                  item.barSubtype == query.barSubtype) &&
              (keyword.isEmpty ||
                  '${item.content} ${item.venue.name} ${item.author.displayName}'
                      .toLowerCase()
                      .contains(keyword));
        }).toList();
    if (query.sort == 'popular') {
      items.sort((a, b) => b.likeCount.compareTo(a.likeCount));
    }
    return HomeFeedPage(
      items: items.skip(query.offset).take(query.limit).toList(),
      limit: query.limit,
      offset: query.offset,
      hasMore: query.offset + query.limit < items.length,
    );
  }
}
