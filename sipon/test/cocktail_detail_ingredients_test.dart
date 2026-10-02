import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/drinks/cocktails/pages/cocktail_detail_page.dart';
import 'package:sipon/features/drinks/cocktails/widgets/recipe_ingredient_fan.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/shared/widgets/sipon_network_image.dart';

class _CocktailApi extends SiponApiService {
  final imageResponse = Completer<Map<String, Object?>>();

  @override
  Future<dynamic> getCocktailDetail(int id) async => {
    'id': id,
    'name': '莫吉托',
    'story': '这杯酒的故事',
    'ingredients': [
      {'id': 8, 'name': '青柠汁', 'amountText': '20ml', 'sortOrder': 2},
      {'id': 2, 'name': '朗姆酒', 'amountText': '45ml', 'sortOrder': 1},
    ],
  };

  @override
  Future<dynamic> getIngredientDetail(int id) async {
    if (id == 8) return imageResponse.future;
    return {'id': 2, 'name': '朗姆酒', 'imageUrl': '/images/rum.png'};
  }

  @override
  Future<dynamic> getVirtualDrinkingBootstrap() async => {'drinks': []};
}

void main() {
  testWidgets(
    'keeps story before ingredients and fills sorted cards when images arrive',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final language = SiponLanguageController();
      addTearDown(language.dispose);
      final api = _CocktailApi();
      await tester.pumpWidget(
        SiponLanguageScope(
          controller: language,
          child: MaterialApp(
            home: CocktailDetailPage(cocktailId: 1, apiService: api),
          ),
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(find.byType(RecipeIngredientFan), 200);
      final initial = tester.widget<RecipeIngredientFan>(
        find.byType(RecipeIngredientFan),
      );
      expect(initial.loading, isTrue);
      expect(initial.items.map((item) => item.line.amountText), [
        '45ml',
        '20ml',
      ]);
      expect(
        tester.getTopLeft(find.text('背后的故事')).dy,
        lessThan(tester.getTopLeft(find.text('用料')).dy),
      );
      expect(find.text('朗姆酒'), findsNothing);
      expect(find.text('青柠汁'), findsNothing);

      api.imageResponse.complete({
        'id': 8,
        'name': '青柠汁',
        'imageUrl': '/images/lime.png',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      final fan = tester.widget<RecipeIngredientFan>(
        find.byType(RecipeIngredientFan),
      );
      expect(fan.loading, isFalse);
      final images = tester.widgetList<SiponNetworkImage>(
        find.descendant(
          of: find.byType(RecipeIngredientFan),
          matching: find.byType(SiponNetworkImage),
        ),
      );
      expect(images.map((image) => image.url), [
        'https://api.tanjeek.cn/images/rum.png',
        'https://api.tanjeek.cn/images/lime.png',
      ]);
      expect(find.text('45ml'), findsOneWidget);
      expect(find.text('20ml'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
