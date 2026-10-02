import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/drinks/cocktails/widgets/ingredient_bookshelf.dart';
import 'package:sipon/shared/services/sipon_api_models.dart';

const _fallback = 'assest/首页/图片素材/鸡尾酒系列2.png';

List<IngredientInfo> _ingredients(int count) => List.generate(
  count,
  (index) => IngredientInfo(id: index, name: '配料$index'),
);

Finder _shelves() => find.byWidgetPredicate(
  (widget) => widget is ClipRect && widget.child is LayoutBuilder,
);

Future<void> _open(
  WidgetTester tester, {
  int count = 15,
  bool disableAnimations = false,
  ValueChanged<IngredientInfo>? onTap,
  Size size = const Size(390, 620),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: disableAnimations,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: IngredientBookshelf(
            items: _ingredients(count),
            fallbackAsset: _fallback,
            onIngredientTap: onTap ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('three shelves use 3:4 covers and alternate moving directions', (
    tester,
  ) async {
    await _open(tester);
    final clips = _shelves();
    expect(clips, findsNWidgets(3));
    final covers = find.byType(AspectRatio);
    for (final cover in covers.evaluate()) {
      final size = tester.getSize(find.byWidget(cover.widget));
      expect(size.width / size.height, closeTo(3 / 4, 0.001));
    }
    final positions = [
      for (var row = 0; row < 3; row++)
        tester.getTopLeft(find.text('配料${row + 3}')).dx,
    ];
    await tester.pump(const Duration(seconds: 1));
    for (var row = 0; row < 3; row++) {
      final dx = tester.getTopLeft(find.text('配料${row + 3}')).dx;
      expect(dx - positions[row], closeTo(row == 1 ? -18 : 18, 0.1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('single ingredient fills all shelves across repeated loops', (
    tester,
  ) async {
    await _open(tester, count: 1);
    for (var cycle = 0; cycle < 6; cycle++) {
      await tester.pump(const Duration(seconds: 7));
      final viewports = _shelves();
      for (var row = 0; row < 3; row++) {
        final viewport = tester.getRect(viewports.at(row));
        final books = find.descendant(
          of: viewports.at(row),
          matching: find.byType(InkWell),
        );
        final rects = [
          for (final book in books.evaluate())
            tester.getRect(find.byWidget(book.widget)),
        ];
        expect(rects.first.left, lessThanOrEqualTo(viewport.left));
        expect(rects.last.right, greaterThanOrEqualTo(viewport.right));
        for (var index = 1; index < rects.length; index++) {
          expect(rects[index].left - rects[index - 1].right, closeTo(14, 0.1));
        }
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('holding pauses motion and a cover tap opens its ingredient', (
    tester,
  ) async {
    IngredientInfo? selected;
    await _open(tester, onTap: (item) => selected = item);
    final book = find.text('配料3');
    final gesture = await tester.startGesture(tester.getCenter(book));
    final heldPosition = tester.getTopLeft(book).dx;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getTopLeft(book).dx, closeTo(heldPosition, 0.01));
    await gesture.up();
    await tester.pump();
    expect(selected?.id, 3);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(book).dx, greaterThan(heldPosition));
  });

  testWidgets('reduced motion keeps covers still and allows manual swiping', (
    tester,
  ) async {
    await _open(tester, disableAnimations: true);
    final book = find.text('配料3');
    final initial = tester.getTopLeft(book).dx;
    await tester.pump(const Duration(seconds: 3));
    expect(tester.getTopLeft(book).dx, initial);
    await tester.drag(book, const Offset(-30, 0));
    await tester.pump();
    expect(tester.getTopLeft(book).dx, lessThan(initial));
    final afterDrag = tester.getTopLeft(book).dx;
    await tester.pump(const Duration(seconds: 3));
    expect(tester.getTopLeft(book).dx, afterDrag);
  });

  testWidgets(
    'small screens and enlarged labels can scroll all three shelves',
    (tester) async {
      await _open(
        tester,
        size: const Size(320, 380),
        textScale: 2,
        disableAnimations: true,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pump();
      final last = tester.getRect(_shelves().last);
      expect(last.bottom, lessThanOrEqualTo(380));
      expect(tester.takeException(), isNull);
    },
  );
}
