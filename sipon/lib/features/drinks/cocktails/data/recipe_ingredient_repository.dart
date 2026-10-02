import '../../../../shared/services/sipon_api_models.dart';
import '../../../../shared/services/sipon_api_service.dart';

/// 保留配方用量与顺序，图片和详情入口复用配料百科的数据。
class RecipeIngredient {
  const RecipeIngredient({required this.line, required this.ingredient});

  factory RecipeIngredient.fromLine(RecipeLine line) => RecipeIngredient(
    line: line,
    ingredient: IngredientInfo(
      id: line.id,
      code: line.code,
      name: line.name,
      nameEn: line.nameEn,
      imageUrl: line.imageUrl,
    ),
  );

  final RecipeLine line;
  final IngredientInfo ingredient;
}

class RecipeIngredientRepository {
  RecipeIngredientRepository(this._api);

  final SiponApiService _api;

  Future<List<RecipeIngredient>> resolve(List<RecipeLine> lines) async {
    // 相同配料只请求一次；每个配料的失败独立降级，不影响整份配方。
    final requests = <int, Future<IngredientInfo?>>{};
    final resolved = await Future.wait([
      for (final line in lines) _resolveLine(line, requests),
    ]);
    final missing = resolved.where(
      (item) => item.ingredient.resolvedImageUrl() == null,
    );
    if (missing.isEmpty) return resolved;

    // 老配方可能只有 code / 名称，或配料列表有图而详情请求失败。
    // 按页匹配百科记录，不依赖列表当前显示的分类或首屏条数。
    final catalog = <IngredientInfo>[];
    try {
      const pageSize = 100;
      var offset = 0;
      while (true) {
        final page = await _api.searchIngredients(
          page: SiponPage(limit: pageSize, offset: offset),
        );
        catalog.addAll(IngredientInfo.listFromJson(page));
        if (page.length < pageSize ||
            missing.every((item) => _match(item.line, catalog) != null)) {
          break;
        }
        offset += page.length;
      }
    } on Exception {
      // 已匹配的图片仍然可用，未匹配项保留图标与用量。
    }
    return [
      for (final item in resolved)
        if (item.ingredient.resolvedImageUrl() != null)
          item
        else
          RecipeIngredient(
            line: item.line,
            ingredient: _match(item.line, catalog) ?? item.ingredient,
          ),
    ];
  }

  Future<RecipeIngredient> _resolveLine(
    RecipeLine line,
    Map<int, Future<IngredientInfo?>> requests,
  ) async {
    final fallback = RecipeIngredient.fromLine(line);
    if (line.imageUrl?.trim().isNotEmpty == true || line.id == null) {
      return fallback;
    }
    final ingredient = await requests.putIfAbsent(
      line.id!,
      () => _getIngredient(line.id!),
    );
    return RecipeIngredient(
      line: line,
      ingredient: IngredientInfo(
        id: ingredient?.id ?? line.id,
        code: ingredient?.code ?? line.code,
        name: ingredient?.name ?? line.name,
        nameEn: ingredient?.nameEn ?? line.nameEn,
        imageUrl: ingredient?.imageUrl ?? line.imageUrl,
        description: ingredient?.description,
        category: ingredient?.category,
        baseSpirit: ingredient?.baseSpirit,
      ),
    );
  }

  Future<IngredientInfo?> _getIngredient(int id) async {
    try {
      return IngredientInfo.fromJson(await _api.getIngredientDetail(id));
    } on Exception {
      return null;
    }
  }

  IngredientInfo? _match(RecipeLine line, List<IngredientInfo> catalog) {
    String normalized(String? value) => (value ?? '').trim().toLowerCase();
    IngredientInfo? find(bool Function(IngredientInfo) matches) {
      for (final item in catalog) {
        if (matches(item)) return item;
      }
      return null;
    }

    final byId = line.id == null ? null : find((item) => item.id == line.id);
    if (byId != null) return byId;
    final code = normalized(line.code);
    if (code.isNotEmpty) {
      final byCode = find((item) => normalized(item.code) == code);
      if (byCode != null) return byCode;
    }
    final name = normalized(line.name);
    final nameEn = normalized(line.nameEn);
    return find(
      (item) =>
          (name.isNotEmpty && normalized(item.name) == name) ||
          (nameEn.isNotEmpty && normalized(item.nameEn) == nameEn),
    );
  }
}
