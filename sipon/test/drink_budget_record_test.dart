import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/services/drink_budget_store.dart';

void main() {
  group('DrinkBudgetRecord sticker metadata', () {
    test('preserves the local cutout path through JSON persistence', () {
      final record = DrinkBudgetRecord(
        id: 'local-sticker',
        date: DateTime(2026, 9, 17),
        amount: 68,
        drinkType: '鸡尾酒',
        place: 'SipOn',
        photoPath: '/app/original.jpg',
        stickerImagePath: '/app/sticker.png',
      );

      final restored = DrinkBudgetRecord.fromJson(record.toJson());

      expect(restored.photoPath, '/app/original.jpg');
      expect(restored.stickerImagePath, '/app/sticker.png');
    });

    test('maps backend stickerUrl into the display image field', () {
      final record = DrinkBudgetRecord.fromApiJson({
        'id': 42,
        'clientRecordId': 'server-sticker',
        'occurredOn': '2026-09-17',
        'amount': 88,
        'drinkType': '威士忌',
        'place': 'SipOn',
        'photoUrl': 'https://cdn.example.com/original.jpg',
        'stickerUrl': 'https://cdn.example.com/sticker.png',
      });

      expect(record.photoPath, 'https://cdn.example.com/original.jpg');
      expect(record.stickerImagePath, 'https://cdn.example.com/sticker.png');
    });
  });
}
