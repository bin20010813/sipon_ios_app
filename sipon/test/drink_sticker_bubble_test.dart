import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/services/drink_budget_store.dart';
import 'package:sipon/widgets/drink_sticker.dart';

void main() {
  testWidgets('sticker floats until its bubble is tapped, then falls', (
    tester,
  ) async {
    final record = DrinkBudgetRecord(
      id: 'bubble-1',
      date: DateTime(2026, 9, 26),
      amount: 68,
      drinkType: '鸡尾酒',
      place: 'SipOn',
    );
    var detailOpens = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: DrinkStickerGravityPool(
                records: [record],
                height: 220,
                onStickerTap: (_) => detailOpens++,
              ),
            ),
          ),
        ),
      ),
    );

    final sticker = find.byType(DrinkSticker);
    final initialTop = tester.getTopLeft(sticker).dy;
    for (var frame = 0; frame < 25; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getTopLeft(sticker).dy, closeTo(initialTop, 5));

    await tester.tapAt(tester.getCenter(sticker));
    await tester.pump();
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getTopLeft(sticker).dy, greaterThan(initialTop + 30));
    expect(detailOpens, 0);

    await tester.pump(const Duration(milliseconds: 250));
    expect(detailOpens, 1);
  });
}
