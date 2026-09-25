import 'package:flutter/material.dart';

import '../services/map/map_models.dart';
import '../services/map/venue_sheet_controller.dart';
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

    return MapPage(
      initialVenue: venue,
      initialSheetStage: VenueSheetStage.half,
      showMapControls: false,
      showSheetDragHandle: false,
      allowSheetCollapse: false,
      onMapTapped: openFullscreenMap,
      onExpandMap: openFullscreenMap,
      onVenueClose: () => Navigator.of(context).pop(),
    );
  }
}
