import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/drinks/cocktails/data/recipe_ingredient_repository.dart';
import 'package:sipon/shared/services/sipon_api_models.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';

class _IngredientApi extends SiponApiService {
  final details = <int, Map<String, Object?>>{};
  final detailRequests = <int>[];
  final offsets = <int>[];
  List<dynamic> catalog = [];
  bool failCatalog = false;

  @override
  Future<dynamic> getIngredientDetail(int id) async {
    detailRequests.add(id);
    if (!details.containsKey(id)) throw Exception('Unavailable ingredient');
    return details[id];
  }

  @override
  Future<List<dynamic>> searchIngredients({
    String? category,
    SiponPage page = const SiponPage(),
  }) async {
    offsets.add(page.offset);
    if (failCatalog) throw Exception('Unavailable catalog');
    return catalog.skip(page.offset).take(page.limit).toList();
  }
}

void main() {
  test(
    'maps encyclopedia covers by ingredient ID, preserving doses and order',
    () async {
      final api = _IngredientApi();
      api.details.addAll({
        8: {'id': 8, 'name': '青柠汁', 'imageUrl': '/images/lime.png'},
        2: {'id': 2, 'name': '朗姆酒', 'imageUrl': '/images/rum.png'},
      });
      final lines = [
        const RecipeLine(id: 8, name: '青柠汁', amountText: '20ml'),
        const RecipeLine(id: 2, name: '朗姆酒', amountText: '45ml'),
        const RecipeLine(id: 8, name: '青柠汁', amountText: '1片'),
      ];
      final items = await RecipeIngredientRepository(api).resolve(lines);
      expect(items.map((item) => item.line.amountText), ['20ml', '45ml', '1片']);
      expect(items.map((item) => item.ingredient.imageUrl), [
        '/images/lime.png',
        '/images/rum.png',
        '/images/lime.png',
      ]);
      expect(api.detailRequests, [8, 2]);
      expect(api.offsets, isEmpty);
    },
  );

  test(
    'matches code and name beyond the first page when IDs are absent',
    () async {
      final api = _IngredientApi();
      api.catalog = [
        ...List.generate(100, (index) => {'id': index, 'name': '其他配料$index'}),
        {'id': 102, 'code': 'lime', 'name': '青柠汁', 'imageUrl': '/lime.png'},
        {'id': 103, 'name': '糖浆', 'imageUrl': '/syrup.png'},
      ];
      final items = await RecipeIngredientRepository(api).resolve([
        const RecipeLine(code: ' LIME ', amountText: '20ml'),
        const RecipeLine(name: '糖浆', amountText: '10ml'),
      ]);
      expect(items.map((item) => item.ingredient.id), [102, 103]);
      expect(items.map((item) => item.ingredient.imageUrl), [
        '/lime.png',
        '/syrup.png',
      ]);
      expect(api.offsets, [0, 100]);
      expect(api.detailRequests, isEmpty);
    },
  );

  test(
    'one failed image lookup keeps all quantities and available images',
    () async {
      final api = _IngredientApi()..failCatalog = true;
      api.details[2] = {'id': 2, 'imageUrl': '/rum.png'};
      final items = await RecipeIngredientRepository(api).resolve([
        const RecipeLine(id: 2, name: '朗姆酒', amountText: '45ml'),
        const RecipeLine(id: 8, name: '青柠汁', amountText: '20ml'),
      ]);
      expect(items.first.ingredient.imageUrl, '/rum.png');
      expect(items.last.ingredient.imageUrl, isNull);
      expect(items.last.line.amountText, '20ml');
      expect(items.last.ingredient.name, '青柠汁');
    },
  );

  test(
    'recipe image and explicit ingredient ID need no additional lookup',
    () async {
      final api = _IngredientApi();
      final line = RecipeLine.fromJson({
        'id': 99,
        'ingredientId': 8,
        'imageUrl': '/lime.png',
        'amountText': '20ml',
      });
      final items = await RecipeIngredientRepository(api).resolve([line]);
      expect(items.single.ingredient.id, 8);
      expect(items.single.ingredient.imageUrl, '/lime.png');
      expect(api.detailRequests, isEmpty);
      expect(api.offsets, isEmpty);
    },
  );
}
