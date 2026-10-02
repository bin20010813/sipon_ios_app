import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/drinks/cocktails/data/recipe_ingredient_repository.dart';
import 'package:sipon/features/drinks/cocktails/widgets/recipe_ingredient_fan.dart';
import 'package:sipon/shared/services/sipon_api_models.dart';

List<RecipeIngredient> _items(int count) => [
  for (var index = 0; index < count; index++)
    RecipeIngredient.fromLine(
      RecipeLine(id: index, name: '配料$index', amountText: '${index + 1}0ml'),
    ),
];

Future<void> _open(
  WidgetTester tester, {
  int count = 3,
  double width = 390,
  double textScale = 1,
  double before = 0,
  bool loading = false,
  bool disableAnimations = false,
  ValueChanged<IngredientInfo>? onTap,
}) async {
  final size = Size(width, 780);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: before),
                Padding(
                  padding: const EdgeInsets.all(38),
                  child: RecipeIngredientFan(
                    items: _items(count),
                    loading: loading,
                    onIngredientTap: onTap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('deals covers in sequence, with quantities below and no names', (
    tester,
  ) async {
    IngredientInfo? selected;
    await _open(tester, onTap: (item) => selected = item);
    final first = find.byKey(const ValueKey('recipe-card-0'));
    final last = find.byKey(const ValueKey('recipe-card-2'));
    final initial = tester.getTopLeft(first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getTopLeft(first).dx, lessThan(initial.dx));
    final lastOpacity = tester.widget<Opacity>(
      find.descendant(of: last, matching: find.byType(Opacity)),
    );
    expect(lastOpacity.opacity, 0);
    await tester.pumpAndSettle();
    expect(find.text('配料0'), findsNothing);
    expect(find.text('配料1'), findsNothing);
    expect(find.text('10ml'), findsOneWidget);
    expect(find.text('20ml'), findsOneWidget);
    expect(find.text('30ml'), findsOneWidget);
    final cover = find.descendant(of: first, matching: find.byType(ClipRRect));
    expect(
      tester.getTopLeft(find.text('10ml')).dy,
      greaterThan(tester.getBottomLeft(cover).dy),
    );
    expect(tester.getTopLeft(first).dx, lessThan(tester.getTopLeft(last).dx));
    await tester.tap(find.text('10ml'));
    expect(selected?.id, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waits for the section to enter the viewport before dealing', (
    tester,
  ) async {
    await _open(tester, before: 1050);
    final card = find.byKey(const ValueKey('recipe-card-0'));
    Opacity opacity() => tester.widget<Opacity>(
      find.descendant(of: card, matching: find.byType(Opacity)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(opacity().opacity, 0);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -800),
    );
    await tester.pumpAndSettle();
    expect(opacity().opacity, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow screens, many ingredients, and large quantities stay readable',
    (tester) async {
      await _open(
        tester,
        count: 10,
        width: 320,
        textScale: 2,
        disableAnimations: true,
      );
      expect(tester.takeException(), isNull);
      final firstRow = [
        for (var index = 0; index < 3; index++)
          tester.getRect(find.byKey(ValueKey('recipe-card-$index'))),
      ];
      for (final rect in firstRow) {
        expect(rect.left, greaterThanOrEqualTo(38));
        expect(rect.right, lessThanOrEqualTo(282));
      }
      expect(firstRow[0].right, lessThan(firstRow[1].left));
      expect(firstRow[1].right, lessThan(firstRow[2].left));
      final initial = tester.getTopLeft(find.text('10ml'));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.getTopLeft(find.text('10ml')), initial);
      await tester.scrollUntilVisible(find.text('100ml'), 200);
      expect(find.text('100ml').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
