import 'package:flutter/material.dart';

import '../services/map/map_models.dart';
import '../services/map/venue_sheet_controller.dart';
import 'map_page.dart';

Future<T?> openVenueMapHalfPage<T>(
  BuildContext context,
  MapVenue venue,
) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      builder: (_) => VenueMapHalfPage(venue: venue),
    ),
  );
}

class VenueMapHalfPage extends StatelessWidget {
  const VenueMapHalfPage({
    super.key,
    required this.venue,
  });

  final MapVenue venue;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: MapPage(
            initialVenue: venue,
            initialSheetStage: VenueSheetStage.half,
            showMapControls: false,
            allowSheetCollapse: false,
            onVenueClose: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
