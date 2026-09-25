import 'package:flutter/material.dart';

import '../../../app/theme/sipon_theme_colors.dart';
import '../../map/models/map_models.dart';
import '../../../shared/services/sipon_api_models.dart';
import '../../../shared/services/sipon_api_service.dart';
import '../../profile/data/user_profile_data.dart';
import '../../map/widgets/venue_mini_map.dart';
import '../../../shared/widgets/sipon_network_image.dart';
import '../../map/pages/venue_map_half_page.dart';

/// A single visit, including its own rating and photos (not the bar gallery).
class ReviewDetailPage extends StatefulWidget {
  const ReviewDetailPage({
    super.key,
    required this.entry,
    required this.venue,
    this.author,
    this.apiService,
  });

  final Map<String, dynamic> entry;
  final MapVenue venue;
  final UserProfileData? author;
  final SiponApiService? apiService;

  @override
  State<ReviewDetailPage> createState() => _ReviewDetailPageState();
}

List<String> reviewPhotoUrls(Map<String, dynamic> entry) {
  final ids = entry['mediaIds'];
  if (ids is List && ids.isNotEmpty) {
    return ids
        .where((id) => id != null && id.toString().trim().isNotEmpty)
        .map(
          (id) => '/api/uploads/${Uri.encodeComponent(id.toString())}/content',
        )
        .toList(growable: false);
  }
  final media = entry['mediaUrls'] ?? entry['media'];
  if (media is! List) return const [];
  return media
      .map((item) {
        if (item is String) return item.trim();
        if (item is Map) {
          return (item['url'] ??
                  item['imageUrl'] ??
                  item['contentUrl'] ??
                  item['path'] ??
                  '')
              .toString()
              .trim();
        }
        return '';
      })
      .where((url) => url.isNotEmpty)
      .toList(growable: false);
}

class _ReviewDetailPageState extends State<ReviewDetailPage> {
  late MapVenue _venue = widget.venue;
  late UserProfileData? _author = widget.author;
  late final _api = widget.apiService ?? SiponApiService();

  bool get _hasLocation =>
      (int.tryParse(_venue.id) ?? 0) > 0 &&
      _venue.longitude.isFinite &&
      _venue.latitude.isFinite &&
      _venue.longitude.abs() <= 180 &&
      _venue.latitude.abs() <= 90 &&
      (_venue.longitude != 0 || _venue.latitude != 0);

  @override
  void initState() {
    super.initState();
    _loadAuthor();
    _loadVenue();
  }

  Future<void> _loadAuthor() async {
    if (_author != null) return;
    try {
      final profile = UserProfileData.fromJson(await _api.getMyProfile());
      if (mounted) setState(() => _author = profile);
    } on Exception {
      // The visit remains readable when the profile is unavailable.
    }
  }

  Future<void> _loadVenue() async {
    final id = int.tryParse(_venue.id);
    if (id == null) return;
    try {
      final response = await _api.getBarById(id);
      if (response is! Map || !mounted) return;
      final bar = SiponBarMapItem.fromJson(response.cast<String, dynamic>());
      final resolvedName =
          (response['name'] ?? response['barName'] ?? response['title'])
              ?.toString()
              .trim();
      setState(
        () => _venue = MapVenue(
          id: _venue.id,
          name: resolvedName?.isNotEmpty == true ? resolvedName! : _venue.name,
          longitude: bar.longitude ?? _venue.longitude,
          latitude: bar.latitude ?? _venue.latitude,
          kind: _venue.kind,
          rating: _venue.rating,
          address: bar.address.isEmpty ? _venue.address : bar.address,
          distance: _venue.distance,
          tags: _venue.tags,
          imageAsset: _venue.imageAsset,
          imageUrl: bar.resolvedThumbnailUrl ?? _venue.imageUrl,
        ),
      );
    } on Exception {
      // Keep the data supplied by the list when enrichment fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final rawRating = double.tryParse('${entry['rating'] ?? ''}');
    final rating = rawRating != null && rawRating.isFinite && rawRating > 0
        ? rawRating.clamp(0.0, 5.0)
        : null;
    final date = DateTime.tryParse(
      '${entry['visitedAt'] ?? entry['createdAt'] ?? ''}',
    )?.toLocal();
    final dateLabel = date == null
        ? '日期未知'
        : '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
    final content = '${entry['content'] ?? ''}'.trim();
    final photos = reviewPhotoUrls(entry);
    final scheme = Theme.of(context).colorScheme;
    final siponColors = context.siponColors;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        centerTitle: true,
        title: const Text(
          '评价详情',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 58,
                          height: 58,
                          child: _author?.avatarUrl == null
                              // 头像占位：与图片占位共用骨架色。
                              ? ColoredBox(
                                  color: siponColors.skeleton,
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: scheme.onSurfaceVariant,
                                    size: 32,
                                  ),
                                )
                              : SiponNetworkImage(
                                  url: _author!.avatarUrl!,
                                  auth: true,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _author?.name ?? 'Sipon 用户',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              dateLabel,
                              style: TextStyle(
                                fontSize: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(
                                    5,
                                    (i) => Icon(
                                      rating != null && rating >= i + 1
                                          ? Icons.star_rounded
                                          : rating != null && rating > i
                                          ? Icons.star_half_rounded
                                          : Icons.star_rounded,
                                      size: 20,
                                      // 点亮星用评分语义色，未点亮星用描边色。
                                      color: rating != null && rating > i
                                          ? siponColors.starRating
                                          : scheme.outlineVariant,
                                    ),
                                  ),
                                ),
                                Text(
                                  rating?.toStringAsFixed(1) ?? '未评分',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: rating == null
                                        ? scheme.onSurfaceVariant
                                        : siponColors.starRating,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    content.isEmpty ? '这次打卡还没有留下文字评价' : content,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.65,
                      color: content.isEmpty
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                  if (photos.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, size) {
                        final width = photos.length == 1
                            ? size.maxWidth * .72
                            : (size.maxWidth - 12) / 3;
                        return Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var i = 0; i < photos.length; i++)
                              Semantics(
                                label: '打卡照片 ${i + 1}，共 ${photos.length} 张',
                                button: true,
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => _ReviewPhotoViewer(
                                        urls: photos,
                                        initialIndex: i,
                                      ),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SiponNetworkImage(
                                      url: photos[i],
                                      auth: true,
                                      width: width,
                                      height: width,
                                      fallbackWidget: ColoredBox(
                                        color: siponColors.skeleton,
                                        child: Center(
                                          child: Icon(
                                            Icons.image_outlined,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 22),
                  Material(
                    color: scheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _hasLocation
                          ? () => openVenueMapHalfPage<void>(context, _venue)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(11),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: SizedBox(
                                width: 80,
                                height: 80,
                                child: _venue.imageUrl == null
                                    ? Image.asset(
                                        _venue.imageAsset,
                                        fit: BoxFit.cover,
                                      )
                                    : SiponNetworkImage(
                                        url: _venue.imageUrl!,
                                        fallbackAsset: _venue.imageAsset,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _venue.name,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.location_on_outlined,
                                        size: 17,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          _venue.address.isEmpty
                                              ? '地址暂无'
                                              : _venue.address,
                                          style: TextStyle(
                                            fontSize: 13,
                                            height: 1.4,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 22)),
          SliverLayoutBuilder(
            builder: (context, constraints) => SliverToBoxAdapter(
              child: SizedBox(
                // Fill the viewport after short reviews, while retaining a
                // usable map below long text and photo collections.
                height:
                    (constraints.viewportMainAxisExtent -
                            constraints.precedingScrollExtent)
                        .clamp(300.0, double.infinity),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_hasLocation)
                      VenueMiniMap(
                        key: ValueKey('${_venue.longitude},${_venue.latitude}'),
                        venue: _venue,
                        centered: true,
                      )
                    else
                      // 无坐标时的地图占位底，复用图片骨架色。
                      ColoredBox(
                        color: siponColors.skeleton,
                        child: Center(
                          child: Text(
                            '暂无位置信息',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 130,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                scheme.surface,
                                scheme.surface.withValues(alpha: 0.9),
                                scheme.surface.withValues(alpha: 0),
                              ],
                              stops: const [0, .25, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewPhotoViewer extends StatefulWidget {
  const _ReviewPhotoViewer({required this.urls, required this.initialIndex});
  final List<String> urls;
  final int initialIndex;
  @override
  State<_ReviewPhotoViewer> createState() => _ReviewPhotoViewerState();
}

class _ReviewPhotoViewerState extends State<_ReviewPhotoViewer> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // 全屏看图属于沉浸式内容底：纯黑与白色前景是内容固有色，两种外观保持一致。
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${_index + 1} / ${widget.urls.length}'),
      centerTitle: true,
    ),
    body: SafeArea(
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (_, index) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: SiponNetworkImage(
              url: widget.urls[index],
              auth: true,
              fit: BoxFit.contain,
              fallbackWidget: const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  // 沉浸式纯黑底上的失败图标，保留白色半透明。
                  color: Colors.white54,
                  size: 40,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
