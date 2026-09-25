import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/features/map/pages/venue_map_half_page.dart';
import 'package:sipon/features/map/models/map_models.dart';
import 'package:sipon/features/map/platform/sipon_map_host.dart';
import 'package:sipon/features/map/platform/sipon_map_protocol.dart';
import 'package:sipon/features/map/widgets/sipon_map_widget.dart';
import 'package:sipon/shared/services/sipon_city_controller.dart';
import 'package:sipon/features/map/widgets/venue_sheet.dart';
import 'package:sipon/shared/widgets/sipon_city_picker.dart';

class _Host implements SiponMapHost {
  late void Function(String, Object?) handler;
  final calls = <String, Map<String, Object?>>{};

  @override
  void onNativeCall(void Function(String, Object?) handler) {
    this.handler = handler;
  }

  @override
  Future<Object?> invoke(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    calls[method] = args;
    if (method == SiponMapCommands.setup) {
      handler(SiponMapEvents.onMapReady, null);
    }
    if (method == SiponMapCommands.readViewport) {
      throw StateError('No native viewport in widget test');
    }
    return null;
  }
}

void main() {
  testWidgets('非默认城市打开酒吧地图，首帧定位目标且全局选城不覆盖目标', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final city = SiponCityController(initialCity: '北京');
    final language = SiponLanguageController();
    addTearDown(city.dispose);
    addTearDown(language.dispose);
    const venue = MapVenue(
      id: 'wishlist-target',
      name: '想喝的目标酒吧',
      longitude: 113.2644,
      latitude: 23.1291,
      kind: MapVenueKind.pub,
      rating: 4.5,
      address: '测试地址',
      distance: '',
      tags: [],
      imageAsset: 'assest/首页/图片素材/酒吧1.png',
    );
    await tester.pumpWidget(
      SiponCityScope(
        controller: city,
        child: SiponLanguageScope(
          controller: language,
          child: const MaterialApp(home: VenueMapHalfPage(venue: venue)),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<VenueSheetSurface>(find.byType(VenueSheetSurface)).venue,
      venue,
    );

    final host = _Host();
    final map = tester.widget<SiponMapWidget>(find.byType(SiponMapWidget));
    await tester.runAsync(() async {
      await (map.onHostReady as Future<void> Function(SiponMapHost))(host);
    });
    expect(host.calls[SiponMapCommands.setup], isNotNull);
    expect(host.calls[SiponMapCommands.flyToCity], isNull);
    await city.selectCity('深圳');
    await tester.pump();
    expect(
      tester.widget<VenueSheetSurface>(find.byType(VenueSheetSurface)).venue,
      venue,
    );
    expect(host.calls[SiponMapCommands.flyToCity], isNull);
    final expandButton = find.byKey(const ValueKey('expand-venue-map'));
    expect(find.byKey(const ValueKey('venue-sheet-drag-handle')), findsNothing);
    expect(expandButton.hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(expandButton).dy,
      lessThan(tester.getTopLeft(find.byType(VenueSheetSurface)).dy),
    );
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(expandButton.hitTestable(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
