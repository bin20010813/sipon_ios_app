import 'package:flutter/material.dart';

import '../../../app/theme/sipon_theme_colors.dart';
import '../models/map_models.dart';
import '../widgets/venue_mini_map.dart';
import '../../../shared/localization/language_transform.dart';

/// A full-screen, gesture-enabled view of a venue's location.
class VenueFullscreenMapPage extends StatelessWidget {
  const VenueFullscreenMapPage({super.key, required this.venue});

  final MapVenue venue;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: VenueMiniMap(venue: venue, centered: true)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: context.siponColors.elevatedSurface,
                  elevation: 3,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: text.t('返回'),
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).pop(),
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
