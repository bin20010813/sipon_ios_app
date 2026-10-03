import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/services/sipon_api_models.dart';
import '../../../../shared/services/sipon_api_service.dart';

/// 首页「鸡尾酒推荐」数据源：候选池拉取 + 随机抽取 + 本地缓存兜底。
///
/// 每次冷启动拉一整页候选并随机抽取展示，保证重启后推荐内容不同；
/// 拉取成功后把候选池写入 SharedPreferences，网络失败时退回缓存池
/// （同样随机抽取），缓存也没有时返回空列表，由页面回退静态素材。
///
/// 抽取结果按进程缓存：首页滑块在 SliverList 中滚出可视区会被销毁重建，
/// 重建后再次调用 [loadRecommendations] 时直接返回本次启动已抽取的列表，
/// 不会重新随机；App 重启或主动清理推荐缓存后才会重新抽取。
class CocktailRecommendationStore {
  CocktailRecommendationStore({SiponApiService? api, Random? random})
    : _api = api ?? SiponApiService(),
      _random = random ?? Random();

  /// 候选池缓存键；更换候选结构时递增版本号避免读到旧格式。
  static const String _poolKey = 'home_cocktail_pool_v1';

  /// 本进程内已选定的推荐列表。static 生命周期与进程一致：
  /// 首页滑块 State 被滚动销毁重建后仍能复用同一份推荐，
  /// App 冷启动或主动清理缓存后才会重新拉取并随机抽取。
  static List<CocktailInfo>? _sessionRecommendations;
  static int _generation = 0;
  static final Set<Future<bool>> _pendingWrites = {};
  static Future<void>? _clearing;

  /// 仅清除推荐候选池和会话，不触碰登录、饮酒记录或预算。
  static Future<void> clearCache() {
    final clearing = _clearing;
    if (clearing != null) return clearing;

    _generation++;
    _sessionRecommendations = null;
    _clearing = _removeCachedPool().whenComplete(() => _clearing = null);
    return _clearing!;
  }

  static Future<void> _removeCachedPool() async {
    // 已提交的写入无法取消，等它们结束再删除；尚未提交的旧请求由 generation 拦截。
    try {
      await Future.wait(_pendingWrites.toList());
    } catch (_) {
      // 写入失败也仍需尝试删除此前的缓存。
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_poolKey)) {
      throw StateError('Failed to clear cocktail recommendation cache');
    }
  }

  /// 单次拉取的候选池上限，受 SiponPage 约束不超过 100；
  /// 候选池越大，每次重启抽取出的推荐组合越分散。
  static const int _poolLimit = 100;

  final SiponApiService _api;
  final Random _random;

  /// 取 [count] 条推荐：优先用接口候选池，失败时退缓存池。
  /// 本进程内只抽取一次，之后直接返回已选定的列表，保证滚动导致
  /// 页面 State 重建时推荐内容不变；App 重启或清理缓存后才会重新抽取。
  Future<List<CocktailInfo>> loadRecommendations({int count = 10}) async {
    while (_clearing != null) {
      await _clearing;
    }
    final generation = _generation;
    final cached = _sessionRecommendations;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    var pool = await _fetchPool(generation);
    if (generation != _generation) return const [];
    if (pool.isEmpty) {
      pool = await _loadCachedPool();
    }
    if (generation != _generation) return const [];
    final shuffled = pool.toList()..shuffle(_random);
    final picked = shuffled.take(count).toList(growable: false);
    // 有结果才锁定本次启动的推荐；空列表允许下次再试。
    if (picked.isNotEmpty) {
      _sessionRecommendations = picked;
    }
    return picked;
  }

  /// 拉取候选池；成功后把接口原始返回写入缓存，失败时返回空交给缓存兜底。
  Future<List<CocktailInfo>> _fetchPool(int generation) async {
    try {
      final list = await _api.searchCocktails(
        page: const SiponPage(limit: _poolLimit),
      );
      if (generation != _generation) return const [];
      final pool = CocktailInfo.listFromJson(list);
      if (pool.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        if (generation != _generation) return const [];
        final write = prefs.setString(_poolKey, jsonEncode(list));
        _pendingWrites.add(write);
        try {
          await write;
        } finally {
          _pendingWrites.remove(write);
        }
      }
      return pool;
    } on Exception {
      // 离线/超时属预期情况，返回空让调用方走缓存兜底。
      return const [];
    }
  }

  Future<List<CocktailInfo>> _loadCachedPool() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_poolKey);
      if (raw == null || raw.isEmpty) return const [];
      return CocktailInfo.listFromJson(jsonDecode(raw));
    } on Exception {
      // 缓存损坏按无缓存处理，回退页面静态素材。
      return const [];
    }
  }
}
