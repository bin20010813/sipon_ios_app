import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/drinks/cocktails/pages/ingredient_list_page.dart';
import 'package:sipon/features/drinks/cocktails/widgets/ingredient_bookshelf.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';

class _IngredientApi extends SiponApiService {
  final requests = <({String? category, SiponPage page})>[];
  Future<List<dynamic>> Function(String? category, SiponPage page)? handler;

  @override
  Future<List<dynamic>> searchIngredients({
    String? category,
    SiponPage page = const SiponPage(),
  }) {
    requests.add((category: category, page: page));
    return handler!(category, page);
  }
}

Future<void> _open(
  WidgetTester tester,
  _IngredientApi api, {
  String? initialCategory,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 780));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final language = SiponLanguageController();
  addTearDown(language.dispose);
  await tester.pumpWidget(
    SiponLanguageScope(
      controller: language,
      child: MaterialApp(
        home: IngredientListPage(
          apiService: api,
          initialCategory: initialCategory,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'bookshelf loads every page without requiring vertical scrolling',
    (tester) async {
      final api = _IngredientApi();
      api.handler = (_, page) async => List.generate(
        page.offset == 0 ? page.limit : 1,
        (index) => {
          'id': page.offset + index,
          'name': '配料${page.offset + index}',
        },
      );
      await _open(tester, api);
      await tester.pump();
      final shelf = tester.widget<IngredientBookshelf>(
        find.byType(IngredientBookshelf),
      );
      expect(shelf.items, hasLength(101));
      expect(api.requests.map((request) => request.page.offset), [0, 100]);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bookshelf preserves the category supplied by its entry point', (
    tester,
  ) async {
    final api = _IngredientApi();
    api.handler = (_, _) async => [
      {'id': 200, 'name': '金酒配料'},
    ];
    await _open(tester, api, initialCategory: 'gin');
    final shelf = tester.widget<IngredientBookshelf>(
      find.byType(IngredientBookshelf),
    );
    expect(shelf.items.single.id, 200);
    expect(api.requests.single.category, 'gin');
  });

  testWidgets(
    'an empty category keeps the empty state instead of moving rows',
    (tester) async {
      final api = _IngredientApi()..handler = (_, _) async => [];
      await _open(tester, api);
      expect(find.text('没有找到相关配料'), findsOneWidget);
      expect(find.byType(IngredientBookshelf), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search filters Chinese and English names and clearing restores books',
    (tester) async {
      final api = _IngredientApi();
      api.handler = (_, _) async => [
        {'id': 1, 'name': '伦敦干金酒', 'nameEn': 'London Dry Gin'},
        {'id': 2, 'name': '白朗姆酒', 'nameEn': 'White Rum'},
        {'id': 3, 'name': '青柠汁', 'nameEn': 'Lime Juice'},
      ];
      await _open(tester, api);

      Future<List<int?>> search(String value) async {
        await tester.enterText(find.byType(TextField), value);
        await tester.pump();
        return tester
            .widget<IngredientBookshelf>(find.byType(IngredientBookshelf))
            .items
            .map((item) => item.id)
            .toList();
      }

      expect(await search('金酒'), [1]);
      expect(await search('  RUM  '), [2]);
      expect(await search('   '), [1, 2, 3]);

      await tester.enterText(find.byType(TextField), '不存在的配料');
      await tester.pump();
      expect(find.text('没有找到相关配料'), findsOneWidget);
      expect(find.byType(IngredientBookshelf), findsNothing);

      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pump();
      final shelf = tester.widget<IngredientBookshelf>(
        find.byType(IngredientBookshelf),
      );
      expect(shelf.items, hasLength(3));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(api.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening and closing the keyboard preserves all shelf sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);

    final api = _IngredientApi();
    api.handler = (_, _) async =>
        List.generate(9, (index) => {'id': index, 'name': '配料$index'});
    await _open(tester, api);
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();

    List<Rect> covers() {
      final shelves = find.byWidgetPredicate(
        (widget) => widget is ClipRect && widget.child is LayoutBuilder,
      );
      expect(shelves, findsNWidgets(3));
      return [
        for (var row = 0; row < 3; row++)
          tester.getRect(
            find
                .descendant(
                  of: shelves.at(row),
                  matching: find.byType(AspectRatio),
                )
                .first,
          ),
      ];
    }

    final initial = covers();
    void expectStableShelves() {
      final current = covers();
      for (var row = 0; row < 3; row++) {
        expect(current[row].size, initial[row].size);
        expect(current[row].top, initial[row].top);
      }
      expect(tester.takeException(), isNull);
    }

    for (final keyboardHeight in [120.0, 300.0, 360.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
      tester.view.padding = const FakeViewPadding(top: 44);
      await tester.pump();
      expectStableShelves();
    }

    await tester.enterText(find.byType(TextField), '配料');
    await tester.pump();
    expectStableShelves();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    tester.view.viewInsets = const FakeViewPadding();
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    await tester.pump();
    expectStableShelves();
  });
}
