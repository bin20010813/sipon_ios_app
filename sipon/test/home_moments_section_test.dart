import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/shared/services/home_moments_repository.dart';
import 'package:sipon/shared/widgets/home_moments_section.dart';

void main() {
  testWidgets('feed uses server offset, deduplicates and resets on search', (
    tester,
  ) async {
    final repository = _FakeFeedRepository();
    final language = SiponLanguageController();
    await tester.pumpWidget(
      MaterialApp(
        home: SiponLanguageScope(
          controller: language,
          child: Scaffold(
            body: SingleChildScrollView(
              child: HomeMomentsSection(city: '佛山', repository: repository),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.queries.map((query) => query.offset), [0]);
    expect(find.text('第一条'), findsOneWidget);

    await tester.ensureVisible(find.text('查看更多动态'));
    await tester.tap(find.text('查看更多动态'));
    await tester.pumpAndSettle();

    expect(repository.queries.map((query) => query.offset), [0, 20]);
    expect(find.text('第二条'), findsOneWidget);
    expect(find.text('第三条'), findsOneWidget);

    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, '特调');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(repository.queries.last.offset, 0);
    expect(repository.queries.last.keyword, '特调');

    await tester.tap(find.text('全部品类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('鸡尾酒吧').last);
    await tester.pumpAndSettle();
    expect(repository.queries.last.barSubtype, 'cocktail_bar');
    expect(repository.queries.last.offset, 0);

    await tester.tap(find.text('最新优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('热门优先').last);
    await tester.pumpAndSettle();
    expect(repository.queries.last.sort, 'popular');
    expect(repository.queries.last.offset, 0);
  });
}

class _FakeFeedRepository extends HomeMomentsRepository {
  final queries = <HomeFeedQuery>[];

  @override
  Future<List<BarSubtypeOption>> loadBarSubtypes() async => const [
    BarSubtypeOption(code: 'cocktail_bar', name: '鸡尾酒吧'),
  ];

  @override
  Future<HomeFeedPage> load(HomeFeedQuery query) async {
    queries.add(query);
    final items = query.offset == 0
        ? [_item(1, '第一条'), _item(2, '第二条')]
        : [_item(2, '第二条'), _item(3, '第三条')];
    return HomeFeedPage(
      items: items,
      limit: 20,
      offset: query.offset,
      hasMore: query.offset == 0,
    );
  }
}

HomeMoment _item(int id, String content) => HomeMoment.fromJson({
  'id': id,
  'barId': 12,
  'barName': '示例酒吧',
  'content': content,
  'author': {'userId': 5, 'displayName': '小酒'},
});
