import 'package:flutter/material.dart' hide Visibility;

import '../../pages/language_transform.dart';
import '../../services/map/map_models.dart';
import 'map_theme.dart';
import 'venue_common.dart';

/// 展开态的详情内容。
///
/// 原来是 [CustomScrollView] 的一组 sliver，现在是普通 [Column]，由
/// `VenueSheetSurface` 里唯一的滚动视图承载，方便整体做透明度动画。
class VenueDetailContent extends StatelessWidget {
  const VenueDetailContent({
    super.key,
    required this.venue,
    required this.topInset,
    required this.bottomOverlayInset,
    required this.onClose,
    required this.onShowOnMap,
  });

  final MapVenue venue;

  /// 全屏过程中逐渐让出的状态栏高度。
  final double topInset;
  final double bottomOverlayInset;
  final VoidCallback onClose;
  final VoidCallback onShowOnMap;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      // 原来每段都是 sliver，宽度是被拉满的；换成 Column 后要显式 stretch
      // 才能保持"在地图中查看"按钮通栏、各段内容左右对齐不变。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(18, topInset + 8, 12, 0),
          // 高度固定为关闭按钮的高度，让手柄始终落在这条带子的中线附近。
          child: SizedBox(
            height: 40,
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: onClose,
                tooltip: text.t('收起地点详情'),
                icon: const Icon(Icons.close_rounded),
                color: MapDesign.ink,
                iconSize: 21,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          child: _VenueDetailHeader(venue: venue),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          child: _VenueFacts(venue: venue),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
          child: _VenueLocation(venue: venue),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            22,
            18,
            bottomOverlayInset + MediaQuery.paddingOf(context).bottom + 24,
          ),
          child: SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: onShowOnMap,
              icon: const Icon(Icons.center_focus_strong_rounded, size: 20),
              label: Text(text.t('在地图中查看')),
              style: FilledButton.styleFrom(
                backgroundColor: MapDesign.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VenueDetailHeader extends StatelessWidget {
  const _VenueDetailHeader({required this.venue});

  final MapVenue venue;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: VenueImage(
            imageUrl: venue.imageUrl,
            assetPath: venue.imageAsset,
            width: 112,
            height: 112,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text.t(venue.name),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MapDesign.ink,
                  fontSize: 21,
                  height: 1.18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: MapDesign.brand,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    venue.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      color: MapDesign.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text.t(venue.distance),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MapDesign.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in venue.tags.take(3))
                    VenueTag(label: text.t(tag)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VenueFacts extends StatelessWidget {
  const _VenueFacts({required this.venue});

  final MapVenue venue;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: MapDesign.hairline),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _VenueFact(
              label: text.t('类型'),
              value: text.t(venue.kind.label),
            ),
          ),
          const _VenueFactDivider(),
          Expanded(
            child: _VenueFact(
              label: text.t('评分'),
              value: venue.rating.toStringAsFixed(1),
            ),
          ),
          const _VenueFactDivider(),
          Expanded(
            child: _VenueFact(
              label: text.t('距离'),
              value: text.t(venue.distance),
            ),
          ),
        ],
      ),
    );
  }
}

class _VenueFact extends StatelessWidget {
  const _VenueFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: MapDesign.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: MapDesign.ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _VenueFactDivider extends StatelessWidget {
  const _VenueFactDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 32,
      child: VerticalDivider(width: 1, color: MapDesign.hairline),
    );
  }
}

class _VenueLocation extends StatelessWidget {
  const _VenueLocation({required this.venue});

  final MapVenue venue;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.t('地点位置'),
          style: const TextStyle(
            color: MapDesign.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: MapDesign.brandSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.location_on_outlined,
                color: MapDesign.brand,
                size: 20,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.t(venue.address),
                    style: const TextStyle(
                      color: MapDesign.ink,
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    text.t(venue.distance),
                    style: const TextStyle(
                      color: MapDesign.muted,
                      fontSize: 12,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
