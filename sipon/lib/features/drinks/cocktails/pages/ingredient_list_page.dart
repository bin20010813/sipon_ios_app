import 'package:flutter/material.dart';

import '../../../../app/theme/sipon_theme_colors.dart';
import '../../../../shared/services/sipon_api_client.dart';
import '../../../../shared/services/sipon_api_models.dart';
import '../../../../shared/services/sipon_api_service.dart';
import '../widgets/ingredient_bookshelf.dart';
import 'ingredient_detail_page.dart';
import '../../../../shared/localization/language_transform.dart';

/// 配料百科——三层书架页（GET /api/ingredients）。
class IngredientListPage extends StatefulWidget {
  const IngredientListPage({super.key, this.initialCategory, this.apiService});

  /// 进入页面时预选的分类值（后端枚举，如 rum/vodka/gin）；为空表示全部。
  final String? initialCategory;
  final SiponApiService? apiService;

  @override
  State<IngredientListPage> createState() => _IngredientListPageState();
}

class _IngredientListPageState extends State<IngredientListPage> {
  static const int _pageSize = 100;
  // 私有浅色色板已移除：品牌/正文/次要文字统一在 build 中读主题语义色
  // （scheme.primary / scheme.onSurface / scheme.onSurfaceVariant）。
  static const String _fallbackAsset = 'assest/首页/图片素材/鸡尾酒系列2.png';

  late final SiponApiService _api = widget.apiService ?? SiponApiService();
  final TextEditingController _searchController = TextEditingController();

  final List<IngredientInfo> _items = [];
  bool _loading = false;
  bool _loaded = false;
  int _loadGeneration = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  /// 分页补齐书架内容；重载时忽略尚未完成的旧请求。
  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final category = widget.initialCategory;
    setState(() {
      _loading = true;
      _loaded = false;
      _error = null;
      _items.clear();
    });
    var offset = 0;
    try {
      while (mounted && generation == _loadGeneration) {
        final list = await _api.searchIngredients(
          category: category,
          page: SiponPage(limit: _pageSize, offset: offset),
        );
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _items.addAll(IngredientInfo.listFromJson(list));
          _loaded = true;
        });
        if (list.length < _pageSize) break;
        offset += list.length;
      }
    } on Exception catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = _describeError(error));
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  /// 打开配料详情页。
  void _openDetail(IngredientInfo item) {
    final id = item.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IngredientDetailPage(ingredientId: id),
      ),
    );
  }

  /// 把异常转为用户可读文案。
  String _describeError(Exception error) {
    if (error is SiponApiException) {
      final detail = error.message?.trim();
      if (detail != null && detail.isNotEmpty) return detail;
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Scaffold(
      // 键盘覆盖页面底部，保持三层书架的可用高度和封面尺寸。
      resizeToAvoidBottomInset: false,
      body: DecoratedBox(
        // 页面渐变跟随主题外观。
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: context.siponColors.pageGradient,
            stops: const [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          // 书架自身预留底部系统安全区。
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                    child: _IngredientTopBar(
                      title: text.t('配料'),
                      back: text.back,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
                    child: _buildSearchField(text),
                  ),
                  Expanded(child: _buildBody(text)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(SiponAppText text) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      style: TextStyle(color: scheme.onSurface, fontSize: 15, letterSpacing: 0),
      decoration: InputDecoration(
        hintText: text.t('搜索配料'),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 14,
          letterSpacing: 0,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                onPressed: _searchController.clear,
                tooltip: text.t('清除搜索'),
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
        filled: true,
        fillColor: scheme.surface.withValues(alpha: 0.9),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// 依据加载/错误/空/列表状态渲染内容区。
  Widget _buildBody(SiponAppText text) {
    final scheme = Theme.of(context).colorScheme;
    final keyword = _searchController.text.trim().toLowerCase();
    final items = keyword.isEmpty
        ? _items
        : _items.where((item) {
            return (item.name ?? '').toLowerCase().contains(keyword) ||
                (item.nameEn ?? '').toLowerCase().contains(keyword);
          }).toList();
    if (_loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                text.t(_error!),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: context.siponColors.brandSurface,
                foregroundColor: scheme.primary,
              ),
              child: Text(text.t('点击重试')),
            ),
          ],
        ),
      );
    }
    if (_loaded && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.liquor_rounded,
              size: 40,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              text.t('没有找到相关配料'),
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: IngredientBookshelf(
            items: items,
            fallbackAsset: _fallbackAsset,
            onIngredientTap: _openDetail,
          ),
        ),
        if (_error != null)
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(text.t('点击重试')),
          ),
      ],
    );
  }
}

/// 顶部：返回按钮 + 标题。
class _IngredientTopBar extends StatelessWidget {
  const _IngredientTopBar({required this.title, required this.back});

  final String title;
  final String back;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Tooltip(
            message: back,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: IconButton.styleFrom(
                fixedSize: const Size(40, 40),
                // 悬浮按钮：半透明表面色 + 主题正文色图标。
                backgroundColor: scheme.surface.withValues(alpha: 0.78),
                foregroundColor: scheme.onSurface,
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
