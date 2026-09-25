import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/sipon_api_client.dart';
import '../services/sipon_api_config.dart';

/// 把后端图片字段（绝对 URL 或 `/api/...` 相对路径）解析成完整 URL。
String siponResolveImageUrl(String urlOrPath) =>
    SiponApiConfig.instance.resolveUri(urlOrPath).toString();

/// 受登录保护图片的请求头：仅当目标与 API 同域且已登录时才返回，
/// 避免把访问令牌泄露给第三方域名；未登录时返回 null（与不带头行为一致）。
Map<String, String>? siponImageAuthHeaders(String resolvedUrl) {
  final headers = SiponApiClient.imageRequestHeaders;
  if (headers.isEmpty) return null;
  final host = Uri.tryParse(resolvedUrl)?.host;
  final apiHost = Uri.tryParse(SiponApiConfig.instance.baseUrl)?.host;
  if (host == null || apiHost == null || host != apiHost) return null;
  return headers;
}

/// 全局统一的网络图片组件（磁盘 + 内存双层缓存，基于 cached_network_image）。
///
/// - 相对路径自动拼 API base，重复进入页面/列表滚动直接命中缓存不再回源；
/// - [auth] 为 true 时附带登录态请求头（头像等受保护上传内容，仅同域生效）；
/// - 加载中与加载失败都回退 [fallbackWidget] 或 [fallbackAsset]，
///   保持原有“网络图优先、本地资产兜底”的优雅降级体验；
/// - 无淡入动画，与原 `Image.network` 解码完成即直出的表现一致。
class SiponNetworkImage extends StatelessWidget {
  const SiponNetworkImage({
    super.key,
    required this.url,
    this.fallbackAsset,
    this.fallbackWidget,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.low,
    this.auth = false,
    this.onError,
  });

  /// 图片地址：绝对 URL 或后端相对路径均可。
  final String url;

  /// 加载中/失败时展示的本地资产图。
  final String? fallbackAsset;

  /// 加载中/失败时展示的自定义占位组件（优先于 [fallbackAsset]）。
  final Widget? fallbackWidget;

  final double? width;
  final double? height;
  final BoxFit fit;

  /// CachedNetworkImage 的 alignment 只接受具体 [Alignment] 类型。
  final Alignment alignment;

  /// 按显示尺寸解码（等价 `Image.network` 的 cacheWidth/cacheHeight），
  /// 避免小坑位全尺寸解码原图；磁盘缓存仍保留原图。
  final int? cacheWidth;
  final int? cacheHeight;

  final FilterQuality filterQuality;

  /// 是否附带登录态请求头（仅当目标与 API 同域时实际生效）。
  final bool auth;

  /// 加载失败回调，用于保留调用方原有的 debugPrint 诊断。
  final ValueChanged<Object>? onError;

  @override
  Widget build(BuildContext context) {
    final resolved = siponResolveImageUrl(url);
    return CachedNetworkImage(
      imageUrl: resolved,
      httpHeaders: auth ? siponImageAuthHeaders(resolved) : null,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      filterQuality: filterQuality,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, _) => _fallback(),
      errorWidget: (_, _, _) => _fallback(),
      errorListener: onError,
    );
  }

  Widget _fallback() {
    final widget = fallbackWidget;
    if (widget != null) return widget;
    final asset = fallbackAsset;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
      );
    }
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF0E9ED),
    );
  }
}
