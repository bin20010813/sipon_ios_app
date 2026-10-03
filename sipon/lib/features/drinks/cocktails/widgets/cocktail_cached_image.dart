import 'package:flutter/material.dart';

import '../data/cocktail_image_cache.dart';

/// 与首页预加载共用尺寸和 Provider，滚动到后续卡片时复用已解码图片。
class CocktailCachedImage extends StatelessWidget {
  const CocktailCachedImage({
    super.key,
    required this.url,
    required this.fallbackAsset,
  });

  final String url;
  final String fallbackAsset;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Image.asset(fallbackAsset, fit: BoxFit.cover);
    return Image(
      image: CocktailImageCache.instance.thumbnailProvider(
        url,
        MediaQuery.devicePixelRatioOf(context),
      ),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      frameBuilder: (context, child, frame, synchronouslyLoaded) =>
          synchronouslyLoaded || frame != null ? child : fallback(),
      errorBuilder: (context, error, stackTrace) => fallback(),
    );
  }
}
