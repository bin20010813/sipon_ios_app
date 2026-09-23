import 'package:flutter/material.dart';

import '../services/map/map_models.dart';
import '../services/map/venue_sheet_controller.dart';
import 'language_transform.dart';
import 'map_page.dart';
import 'venue_fullscreen_map_page.dart';

Future<T?> openVenueMapHalfPage<T>(BuildContext context, MapVenue venue) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(builder: (_) => VenueMapHalfPage(venue: venue)),
  );
}

class VenueMapHalfPage extends StatelessWidget {
  const VenueMapHalfPage({super.key, required this.venue});

  final MapVenue venue;

  @override
  Widget build(BuildContext context) {
    void openFullscreenMap() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VenueFullscreenMapPage(venue: venue),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: MapPage(
            initialVenue: venue,
            initialSheetStage: VenueSheetStage.half,
            showMapControls: false,
            allowSheetCollapse: false,
            onMapTapped: openFullscreenMap,
            onVenueClose: () => Navigator.of(context).pop(),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          left: 16,
          child: Material(
            color: Colors.white,
            elevation: 2,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              key: const ValueKey('expand-venue-map'),
              borderRadius: BorderRadius.circular(20),
              onTap: openFullscreenMap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.open_in_full_rounded, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      SiponLanguageScope.languageOf(context) == SiponLanguage.zh
                          ? '放大地图'
                          : 'Expand map',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
