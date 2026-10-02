import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/sipon_theme_colors.dart';

/// 封面显示尺寸（逻辑像素）；预取与展示共用，保证解码缓存键一致。
const double kCocktailDetailCoverWidth = 260.0;
const double kCocktailDetailCoverHeight = 347.0;

/// 详情封面的图片 Provider：按封面显示尺寸（260×347 × dpr）解码。
/// 首页/列表预取与详情页展示必须共用同一 Provider（同一缓存键），
/// 预取后点进详情才能直接命中内存缓存；磁盘缓存由 CachedNetworkImageProvider 提供。
ImageProvider cocktailDetailCoverImageProvider(String url, double dpr) =>
    ResizeImage(
      CachedNetworkImageProvider(url),
      width: (kCocktailDetailCoverWidth * dpr).round(),
      height: (kCocktailDetailCoverHeight * dpr).round(),
    );

/// 鸡尾酒与配料详情共用的居中大图封面。
class DrinkDetailCover extends StatelessWidget {
  const DrinkDetailCover({
    super.key,
    this.imageUrl,
    required this.fallbackAsset,
  });

  final String? imageUrl;
  final String fallbackAsset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const coverWidth = kCocktailDetailCoverWidth;
    const coverHeight = kCocktailDetailCoverHeight;
    const radius = 24.0;
    final url = imageUrl;

    Widget image() {
      if (url != null && url.isNotEmpty) {
        return Container(
          // 加载中/淡入前的占位底色，跟随主题占位色，深色下不再闪白。
          color: context.siponColors.skeleton,
          child: Image(
            image: cocktailDetailCoverImageProvider(
              url,
              MediaQuery.devicePixelRatioOf(context),
            ),
            width: coverWidth,
            height: coverHeight,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: child,
              );
            },
            errorBuilder: (_, _, _) => Image.asset(
              fallbackAsset,
              width: coverWidth,
              height: coverHeight,
              fit: BoxFit.cover,
            ),
          ),
        );
      }
      return Image.asset(
        fallbackAsset,
        width: coverWidth,
        height: coverHeight,
        fit: BoxFit.cover,
      );
    }

    return SizedBox(
      width: coverWidth,
      height: coverHeight + 27,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                // 封面投影与高光都随主题，深色下不再出现白色亮边。
                BoxShadow(
                  color: context.siponColors.shadow,
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: const Offset(0, 9),
                ),
                BoxShadow(
                  color: scheme.surface.withValues(alpha: 0.7),
                  blurRadius: 6,
                  spreadRadius: -2,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                children: [
                  image(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 36,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // 封面底部渐隐到页面表面色，深色下不再出现白色亮带。
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            scheme.surface.withValues(alpha: 0),
                            scheme.surface.withValues(alpha: 0.22),
                            scheme.surface.withValues(alpha: 0.3),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            top: coverHeight + 1,
            height: 36,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              // dstIn 蒙版语义：白色代表保留、透明代表擦除，与主题无关，保留常量。
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.transparent],
              ).createShader(bounds),
              child: ClipRect(
                child: Opacity(
                  opacity: 0.25,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minWidth: coverWidth - 16,
                    maxWidth: coverWidth - 16,
                    minHeight: coverHeight,
                    maxHeight: coverHeight,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(1.0, -1.0, 1.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: image(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
