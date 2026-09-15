# 鸡尾酒与配料百科模块接入实施方案

## Context（背景）

项目手写网络层（`SiponApiService` + `SiponApiClient`），对照 OpenAPI 生成的客户端（`CodeGenerator/`，仅作字段参考）后发现 5 个 C 端接口尚未接入：

- `GET /api/cocktails`（keyword / limit / offset）→ 鸡尾酒列表
- `GET /api/cocktails/{id}` → 鸡尾酒详情
- `GET /api/ingredients`（category / limit / offset）→ 配料列表
- `GET /api/ingredients/{id}` → 配料详情
- `GET /api/ingredients/{id}/cocktails` → 某配料可调制的鸡尾酒列表

且 App 没有对应前端页面；首页"鸡尾酒推荐"区块目前是 3 张固定素材图的静态卡片。

**已与用户确认的范围**：只做鸡尾酒+配料百科；首页"鸡尾酒推荐"改为真实数据并跳转详情；shapefiles/wfs、游戏、拉黑、举报本次不做。

**接口字段（来自 CodeGenerator/lib/model/）**：
- `CocktailSummaryResponse`：id/name/nameEn/description/imageUrl/starRating(int?)/ingredientCount(int?)/difficulty(String?)
- `CocktailDetailResponse`：同 summary + story + ingredients(List<RecipeIngredientResponse>)
- `RecipeIngredientResponse`：仅 amountText(String?)、sortOrder(int?)，无配料子对象 → 详情"用料"只能渲染 amountText 文本
- `IngredientResponse`：id/name/nameEn/category/imageUrl/baseSpirit(bool?)

## 方案

### 1. 服务层 — 修改 lib/services/sipon_api_service.dart

按现有 `_get`/`_getList` 风格新增 5 个方法：

```dart
Future<List<dynamic>> searchCocktails({String? keyword, SiponPage page = const SiponPage()})
Future<dynamic> getCocktailDetail(int id)
Future<List<dynamic>> searchIngredients({String? category, SiponPage page = const SiponPage()})
Future<dynamic> getIngredientDetail(int id)
Future<List<dynamic>> getCocktailsByIngredient(int id, {SiponPage page = const SiponPage()})
```

详情用 `_get(...)`，列表用 `_getList(...)`（已有 `{data:[...]}` 解包）。

### 2. 模型 — 修改 lib/services/sipon_api_models.dart

按现有手写 `fromJson` 风格（参照 `SiponBarMapResponse`）新增轻量模型，供 4 个页面复用，避免页面内到处 cast：
- `CocktailInfo`（含 `String? calcImageUrl(SiponApiConfig)` — 用 `resolveUri` 处理相对路径图片）
- `CocktailDetailInfo`（继承/含 `CocktailInfo` 字段 + story + `List<RecipeLine>`）
- `RecipeLine`（amountText, sortOrder）
- `IngredientInfo`

图片加载统一：`SiponApiConfig.instance.resolveUri(urlOrPath)`（已存在于 `lib/services/sipon_api_config.dart` L37-43）绝对化后 `Image.network`，`errorBuilder` 回退 `assest/首页/图片素材/鸡尾酒系列1.png` 等本地素材（参照 `home_page.dart` `_HomeVenueImage` 模式，L1086-1123）。

### 3. 新页面 — lib/pages/ 下新建 4 个文件

统一模板（参照 `review_page.dart` / `home_page.dart`）：
`Scaffold -> DecoratedBox(浅粉渐变 LinearGradient[0xFFFFF2F3, 0xFFFCFCFC, Colors.white]) -> SafeArea -> Center -> ConstrainedBox(maxWidth:430) -> CustomScrollView(BouncingScrollPhysics) -> SliverPadding -> SliverList.list`
StatefulWidget + initState 拉取，维护 `_loading/_loaded/_error/_offset`，文案全部 `SiponLanguageScope.textOf(context).t('中文')`，主题色 `0xFF9A3D78`。

| 文件 | 类名 | 要点 |
|---|---|---|
| `cocktail_list_page.dart` | `CocktailListPage` | 顶部搜索框（提交触发加载）、纵向卡片列表、分页（上拉加载更多，`hasMore = list.length >= limit`）；卡片：网络图/回退图 + name + 星星(starRating) + difficulty，onTap → 详情 |
| `cocktail_detail_page.dart` | `CocktailDetailPage` | 大图、name/nameEn、star/difficulty/ingredientCount 元信息、description、"用料"按 sortOrder 渲染 amountText 纯文本列表（不做点击）、story 区块（空隐藏）|
| `ingredient_list_page.dart` | `IngredientListPage` | 分类筛选条（"全部/基酒/利口酒"等常用分类，baseSpirit 角标）、分页列表，onTap → 配料详情 |
| `ingredient_detail_page.dart` | `IngredientDetailPage` | `initState` 用 `Future.wait` 并行拉详情 + `getCocktailsByIngredient`；"可用此配料调制的鸡尾酒"子列表复用 CocktailInfo 卡片，onTap → 鸡尾酒详情 |

空/错误态：空列表显示"暂无数据"提示；错误显示"加载失败，点击重试"。

### 4. 首页改造 — 修改 lib/pages/home_page.dart

保留 `_CocktailScroller` 类名，改为自包含 StatefulWidget：`initState` 调 `searchCocktails(page: SiponPage(limit: 8))` 拉前 8 条真实数据；加载成功则用数据渲染 `_CocktailCard`（改造为支持 `Image.network`+asset 回退、onTap 跳转 `CocktailDetailPage`）；加载失败/空列表回退渲染原有 3 张静态素材卡片（优雅降级，不隐藏区块）。不动 `_HomeDataSections`/`_HomeBarsData` 数据流。

### 5. 入口

首页鸡尾酒卡片点击 + 文本"鸡尾酒推荐"区块右侧（可参照 `_SectionHeader`）不做额外入口；如需列表页入口可后续再加（本期不扩展）。

## 复用清单

- 网络客户端：`lib/services/sipon_api_client.dart`（getJson）
- 业务封装模式：`lib/services/sipon_api_service.dart`
- 图片处理：`home_page.dart::_HomeVenueImage`（L1086-1123）+ `SiponApiConfig.resolveUri`
- 页面骨架：`review_page.dart`（L268-326）、文案 `text.t()`
- 空/错/加载三态：参照 `review_page.dart`、`profile_page.dart`

## 验证

1. `flutter analyze` 零 error。
2. 手工验证（`flutter run`）：
   - 首页"鸡尾酒推荐"显示真实数据（图/名），点击进入详情页；断网或返回空时回退静态素材。
   - 鸡尾酒列表：搜索关键词刷新、上拉分页；详情页用料按 sortOrder 展示、story/空字段正常隐藏。
   - 配料列表：分类切换重新加载、baseSpirit 角标；配料详情"相关鸡尾酒"点击回跳鸡尾酒详情。
   - 中英文切换后新页面文案正常。