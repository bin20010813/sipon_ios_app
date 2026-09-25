import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/profile/pages/profile_page.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/shared/widgets/sipon_network_image.dart';

class _Api extends SiponApiService {
  final deleted = <int>[];
  bool failSecond = false;
  final requestedBars = <int>[];

  @override
  Future<List<dynamic>> getMyDrinkingRoutes({
    SiponPage page = const SiponPage(),
  }) async => [
    {
      'id': 501,
      'title': 'Route A',
      'stops': [
        {'id': 999, 'barId': 101},
      ],
    },
    {'id': 502, 'title': 'Route B'},
  ];

  @override
  Future<dynamic> getDrinkingRoute(int id) async => {
    'id': id,
    'barIds': [101],
  };

  @override
  Future<void> deleteDrinkingRoute(int id) async {
    if (id == 502 && failSecond) throw Exception('failed');
    deleted.add(id);
  }

  @override
  Future<List<dynamic>> getMyCheckIns({
    SiponPage page = const SiponPage(),
  }) async => [
    {'id': 11, 'barId': 101, 'barName': 'Bar A'},
    {'id': 12, 'barId': 102, 'barName': 'Bar B'},
  ];

  @override
  Future<List<dynamic>> getWishlistBars({
    SiponPage page = const SiponPage(),
  }) async => [
    {'id': 101, 'name': 'Bar A'},
    {'id': 102, 'name': 'Bar B'},
  ];

  @override
  Future<dynamic> getBarById(int id) async {
    requestedBars.add(id);
    return {'id': id, 'thumbnailUrl': '/api/bars/$id/images/thumb/0'};
  }

  @override
  Future<void> deleteCheckIn(int id) async {
    if (id == 12 && failSecond) throw Exception('failed');
    deleted.add(id);
  }

  @override
  Future<void> removeWishlistBar(int barId) async => deleted.add(barId);
}

Future<void> _open(WidgetTester tester, _Api api, ProfileListType type) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showProfileList(context, type, apiService: api),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('routes load station thumbnails and delete by route id', (
    tester,
  ) async {
    final api = _Api()..failSecond = true;
    await _open(tester, api, ProfileListType.route);
    expect(api.requestedBars, [101]);
    expect(
      tester
          .widgetList<SiponNetworkImage>(find.byType(SiponNetworkImage))
          .map((image) => image.url),
      everyElement('/api/bars/101/images/thumb/0'),
    );
    await tester.longPress(find.text('Route A'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('全选已加载'));
    await tester.pump();
    await tester.tap(find.text('删除 (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(api.deleted, [501]);
    expect(find.text('Route A'), findsNothing);
    expect(find.text('Route B'), findsOneWidget);
    api.failSecond = false;
    await tester.tap(find.text('删除 (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(api.deleted, [501, 502]);
    expect(find.text('Route B'), findsNothing);
  });

  testWidgets('selection and confirmation fit a phone screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(tester, _Api(), ProfileListType.wish);
    await tester.longPress(find.text('Bar A'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('删除 (1)'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('check-in bulk deletion retains failed records for retry', (
    tester,
  ) async {
    final api = _Api()..failSecond = true;
    await _open(tester, api, ProfileListType.drank);
    await tester.longPress(find.text('Bar A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选已加载'));
    await tester.pump();
    await tester.tap(find.text('删除 (2)'));
    await tester.pumpAndSettle();
    expect(api.deleted, isEmpty);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(api.deleted, [11]);
    expect(find.text('Bar A'), findsNothing);
    expect(find.text('Bar B'), findsOneWidget);
    expect(find.text('删除 (1)'), findsOneWidget);
    api.failSecond = false;
    await tester.tap(find.text('删除 (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(api.deleted, [11, 12]);
    expect(find.text('Bar B'), findsNothing);
  });

  testWidgets('wishlist supports cancellation and deletes by bar id', (
    tester,
  ) async {
    final api = _Api();
    await _open(tester, api, ProfileListType.wish);
    await tester.longPress(find.text('Bar A'));
    await tester.pump();
    await tester.tap(find.text('删除 (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消').last);
    await tester.pumpAndSettle();
    expect(api.deleted, isEmpty);
    await tester.tap(find.text('Bar B'));
    await tester.pump();
    await tester.tap(find.text('删除 (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(api.deleted, [101, 102]);
    expect(find.text('Bar A'), findsNothing);
    expect(find.text('Bar B'), findsNothing);
  });
}
