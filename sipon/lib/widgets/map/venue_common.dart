import 'package:flutter/material.dart' hide Visibility;

import 'map_theme.dart';

/// 酒吧封面。有网图先用网图，失败或没有就退回本地资产。
class VenueImage extends StatelessWidget {
  const VenueImage({
    super.key,
    required this.imageUrl,
    required this.assetPath,
    required this.width,
    required this.height,
  });

  final String? imageUrl;
  final String assetPath;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _assetImage(),
      );
    }

    return _assetImage();
  }

  Widget _assetImage() {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
  }
}

class VenueTag extends StatelessWidget {
  const VenueTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MapDesign.tagSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: MapDesign.brand,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
