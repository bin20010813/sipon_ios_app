import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../../../shared/services/sipon_api_models.dart';
import '../../../../shared/widgets/sipon_network_image.dart';

const double kCocktailCardWidth = 142;
const double kCocktailCardHeight = kCocktailCardWidth / 0.82;
const double kCocktailDetailCoverWidth = 260;
const double kCocktailDetailCoverHeight = 347;
const double kRecipeIngredientCardMaxWidth = 112;

/// 推荐缩略图、详情封面和配料卡牌共用的磁盘/解码缓存，与其他业务图片隔离。
class CocktailImageCache {
  CocktailImageCache({BaseCacheManager? cacheManager})
    : _cacheManager = cacheManager ?? _CocktailDiskCache();

  static final instance = CocktailImageCache();
  static const cacheNamespace = 'cocktail_recommendation_images_v1';

  final BaseCacheManager _cacheManager;
  final Set<ImageProvider> _providers = {};
  final Map<ImageProvider, Future<void>> _preloads = {};
  int _generation = 0;
  Future<void>? _clearing;

  ImageProvider imageProvider(String url, {int? width, int? height}) {
    final resolved = siponResolveImageUrl(url);
    final original = CachedNetworkImageProvider(
      resolved,
      cacheManager: _cacheManager,
      // CachedNetworkImageProvider 的内存键不包含 cacheManager，需显式隔离。
      cacheKey: '$cacheNamespace:$resolved',
    );
    final provider = ResizeImage.resizeIfNeeded(width, height, original);
    _providers
      ..add(original)
      ..add(provider);
    return provider;
  }

  ImageProvider thumbnailProvider(String url, double dpr) => imageProvider(
    url,
    width: (kCocktailCardWidth * dpr).round(),
    height: (kCocktailCardHeight * dpr).round(),
  );

  ImageProvider detailProvider(String url, double dpr) => imageProvider(
    url,
    width: (kCocktailDetailCoverWidth * dpr).round(),
    height: (kCocktailDetailCoverHeight * dpr).round(),
  );

  /// 统一按卡牌最大尺寸解码，窄屏和末行卡牌仍命中同一份预取缓存。
  ImageProvider ingredientProvider(String url, double dpr) => imageProvider(
    url,
    width: (kRecipeIngredientCardMaxWidth * dpr).round(),
    height: (kRecipeIngredientCardMaxWidth * 4 / 3 * dpr).round(),
  );

  Future<void> preloadRecipeIngredients(
    List<IngredientInfo> ingredients,
    BuildContext context,
  ) async {
    if (!_canPreload(context) || _clearing != null) return;
    final generation = _generation;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final providers = <ImageProvider>{};
    for (final ingredient in ingredients) {
      final url = ingredient.resolvedImageUrl();
      if (url == null || url.isEmpty) continue;
      providers.add(ingredientProvider(url, dpr));
    }
    await _preloadBatch(providers.toList(), context, generation);
  }

  bool _canPreload(BuildContext context) =>
      context.mounted && ModalRoute.of(context)?.isCurrent != false;

  /// 先预取全部推荐缩略图，再预取详情封面；页面离开前台后停止后续预取。
  Future<void> preloadRecommendations(
    List<CocktailInfo> cocktails,
    BuildContext context,
  ) async {
    if (!_canPreload(context) || _clearing != null) return;
    final generation = _generation;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final thumbnails = <ImageProvider>{};
    final covers = <ImageProvider>{};
    for (final cocktail in cocktails) {
      final thumbnail = cocktail.resolvedThumbnailUrl();
      if (thumbnail != null && thumbnail.isNotEmpty) {
        thumbnails.add(thumbnailProvider(thumbnail, dpr));
      }
      final cover = cocktail.resolvedMediumImageUrl();
      if (cover != null && cover.isNotEmpty) {
        covers.add(detailProvider(cover, dpr));
      }
    }
    for (final batch in [thumbnails.toList(), covers.toList()]) {
      if (!context.mounted ||
          !_canPreload(context) ||
          generation != _generation) {
        return;
      }
      await _preloadBatch(batch, context, generation);
    }
  }

  Future<void> _preloadBatch(
    List<ImageProvider> providers,
    BuildContext context,
    int generation,
  ) async {
    var next = 0;
    Future<void> worker() async {
      while (context.mounted &&
          _canPreload(context) &&
          generation == _generation &&
          next < providers.length) {
        final provider = providers[next];
        final existing = _preloads[provider];
        if (existing != null) {
          next++;
          await existing;
          continue;
        }
        // 渐进更新可能同时提交多批配料，所有批次共用三个预取名额。
        if (_preloads.length >= 3) {
          await Future.any(_preloads.values.toList());
          continue;
        }
        next++;
        if (!context.mounted) return;
        final preload = precacheImage(
          provider,
          context,
          // 预加载失败不影响推荐和用料展示，展示时仍有占位图兜底。
          onError: (error, stackTrace) {},
        );
        _preloads[provider] = preload;
        try {
          await preload;
        } finally {
          _preloads.remove(provider);
        }
      }
    }

    await Future.wait(List.generate(3, (_) => worker()));
  }

  /// 清理时取消尚未开始的预取，等待已开始的下载/解码，再删除磁盘和内存副本。
  Future<void> clear() {
    final clearing = _clearing;
    if (clearing != null) return clearing;
    _generation++;
    _clearing = _clear().whenComplete(() => _clearing = null);
    return _clearing!;
  }

  Future<void> _clear() async {
    await Future.wait(_preloads.values.toList());
    await _cacheManager.emptyCache();
    for (final provider in _providers.toList()) {
      await provider.evict();
    }
    _providers.clear();
  }
}

/// 包括展示发起的下载也必须结束后再删除，避免清理完成后旧请求写回磁盘。
class _CocktailDiskCache extends CacheManager {
  _CocktailDiskCache()
    : super(
        Config(
          CocktailImageCache.cacheNamespace,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 100,
        ),
      );

  final Set<Future<void>> _downloads = {};
  Future<void>? _clearing;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    while (_clearing != null) {
      await _clearing;
    }
    final done = Completer<void>();
    _downloads.add(done.future);
    try {
      yield* super.getFileStream(
        url,
        key: key,
        headers: headers,
        withProgress: withProgress,
      );
    } finally {
      _downloads.remove(done.future);
      done.complete();
    }
  }

  @override
  Future<void> emptyCache() {
    final clearing = _clearing;
    if (clearing != null) return clearing;
    _clearing = _emptyAfterDownloads().whenComplete(() => _clearing = null);
    return _clearing!;
  }

  Future<void> _emptyAfterDownloads() async {
    await Future.wait(_downloads.toList());
    await super.emptyCache();
  }
}
