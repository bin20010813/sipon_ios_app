import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/features/drinks/virtual_drinking/pages/virtual_drinking_page.dart';
import 'package:sipon/shared/services/sipon_api_client.dart';
import 'package:sipon/shared/services/sipon_api_config.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/features/drinks/virtual_drinking/controllers/virtual_drinking_audio.dart';
import 'package:sipon/features/drinks/virtual_drinking/data/virtual_drinking_local_store.dart';
import 'package:sipon/features/drinks/virtual_drinking/models/virtual_drinking_models.dart';
import 'package:sipon/features/drinks/virtual_drinking/widgets/virtual_drinking_canvas.dart';

class _SilentAudio extends VirtualDrinkingAudio {
  @override
  bool supports(VirtualSoundPreset preset) => false;

  @override
  Future<void> update({
    required VirtualScene scene,
    required VirtualDrinkingCatalog catalog,
    required VirtualDrinkingPreference preference,
    required bool pageVisible,
  }) async {}

  @override
  Future<void> playEffect(String key) async {}

  @override
  Future<void> dispose() async {}
}

http.Response _jsonResponse(Object value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in {
    401: '登录状态已失效或尚未登录，请登录后再体验虚拟小酌',
    403: '当前账号暂时无法使用虚拟小酌',
    404: '虚拟小酌服务暂未开放，请稍后再试',
    500: '虚拟小酌服务暂时不可用，请稍后重试',
  }.entries) {
    testWidgets('虚拟小酌 HTTP ${entry.key} 显示对应原因', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = SiponApiService(
        apiClient: SiponApiClient(
          config: const SiponApiConfig(baseUrl: 'https://api.example.test'),
          httpClient: MockClient(
            (request) async => http.Response('{}', entry.key),
          ),
        ),
      );
      await tester.pumpWidget(
        SiponLanguageScope(
          controller: SiponLanguageController(),
          child: MaterialApp(
            home: VirtualDrinkingPage(apiService: api, audio: _SilentAudio()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  for (final failBeforeExit in [false, true]) {
    testWidgets(failBeforeExit ? '加载失败后退出虚拟小酌页不会抛异常' : '加载期间退出虚拟小酌页不会抛异常', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final response = Completer<http.Response>();
      final api = SiponApiService(
        apiClient: SiponApiClient(
          config: const SiponApiConfig(baseUrl: 'https://api.example.test'),
          httpClient: MockClient((request) => response.future),
        ),
      );
      await tester.pumpWidget(
        SiponLanguageScope(
          controller: SiponLanguageController(),
          child: MaterialApp(
            home: VirtualDrinkingPage(
              apiService: api,
              localStore: VirtualDrinkingLocalStore(scope: 'dispose_test'),
              audio: _SilentAudio(),
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      if (failBeforeExit) {
        response.complete(_jsonResponse({}));
        await tester.pump();
        expect(find.text('虚拟饮品目录暂时为空'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      if (!failBeforeExit) {
        response.complete(_jsonResponse({}));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('窄屏虚拟小酌页可选饮品并点杯子喝一口', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final api = SiponApiService(
      apiClient: SiponApiClient(
        config: const SiponApiConfig(baseUrl: 'https://api.example.test'),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/bootstrap')) {
            return _jsonResponse({
              'drinks': [
                {
                  'code': 'mojito',
                  'name': '莫吉托',
                  'category': 'cocktail',
                  'subtitle': '薄荷青柠',
                  'defaultGlassCode': 'highball',
                  'defaultIceCode': 'column',
                  'allowedIceCodes': ['column'],
                  'renderConfig': {'color': '#9bbb55', 'opacity': 0.78},
                  'interactionPreset': {'sipAmount': 0.08},
                },
                {
                  'code': 'lager_beer',
                  'name': '冰镇拉格',
                  'category': 'beer',
                  'subtitle': '清爽麦香',
                  'defaultGlassCode': 'beer_mug',
                  'defaultIceCode': 'none',
                  'allowedIceCodes': ['none'],
                  'renderConfig': {'color': '#d6a83f', 'foam': true},
                  'interactionPreset': {'sipAmount': 0.1},
                },
              ],
              'glasses': [
                {
                  'code': 'highball',
                  'name': '高球杯',
                  'renderConfig': {'renderer': 'glass-v1', 'shape': 'highball'},
                },
                {
                  'code': 'beer_mug',
                  'name': '啤酒杯',
                  'renderConfig': {'renderer': 'glass-v1', 'shape': 'beer_mug'},
                },
              ],
              'scenes': [
                {
                  'code': 'rain_window',
                  'name': '雨夜窗边',
                  'renderConfig': {
                    'renderer': 'scene-v1',
                    'background':
                        'linear-gradient(180deg,#222d3b,#121c29,#2b2529)',
                  },
                },
              ],
              'iceOptions': [
                {'code': 'column', 'name': '长冰'},
                {'code': 'none', 'name': '不加冰'},
              ],
              'soundPresets': [],
              'preferenceDefaults': {
                'drinkCode': 'mojito',
                'glassCode': 'highball',
                'sceneCode': 'rain_window',
                'iceCode': 'column',
                'ambientSoundEnabled': false,
                'ambientSoundVolume': 45,
              },
            });
          }
          if (path.endsWith('/drinks/mojito')) {
            return _jsonResponse({
              'code': 'mojito',
              'name': '莫吉托',
              'category': 'cocktail',
              'description': '清爽的薄荷与青柠。',
              'defaultGlassCode': 'highball',
              'defaultIceCode': 'column',
              'allowedIceCodes': ['column'],
              'renderConfig': {'color': '#9bbb55', 'opacity': 0.78},
              'interactionPreset': {'sipAmount': 0.08},
            });
          }
          return http.Response('{}', 200);
        }),
      ),
    );

    await tester.pumpWidget(
      SiponLanguageScope(
        controller: SiponLanguageController(),
        child: MaterialApp(
          home: VirtualDrinkingPage(
            apiService: api,
            localStore: VirtualDrinkingLocalStore(scope: 'widget_test'),
            audio: _SilentAudio(),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
      find.text('莫吉托'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((item) => item.data)
          .toList()
          .toString(),
    );
    expect(find.byType(VirtualGlassCanvas), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(VirtualGlassCanvas));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('本杯第 1 口'), findsOneWidget);
    expect(find.text('今日虚拟喝了 1 口'), findsOneWidget);
    expect(tester.takeException(), isNull);

    int currentSips() {
      final label = tester
          .widgetList<Text>(find.byType(Text))
          .map((item) => item.data ?? '')
          .firstWhere((item) => item.startsWith('本杯第 '));
      return int.parse(RegExp(r'\d+').firstMatch(label)!.group(0)!);
    }

    final hold = await tester.startGesture(
      tester.getCenter(find.byType(VirtualGlassCanvas)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 1400));
    final whileHolding = currentSips();
    expect(whileHolding, greaterThan(1));
    await hold.up();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(currentSips(), whileHolding);

    await tester.tap(find.text('换饮品'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('冰镇拉格'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('冰镇拉格'), findsOneWidget);
    expect(find.text('本杯第 0 口'), findsOneWidget);
    final newGlass = tester.widget<VirtualGlassCanvas>(
      find.byType(VirtualGlassCanvas),
    );
    expect(newGlass.glass.code, 'beer_mug');
    expect(newGlass.iceCode, 'none');
  });
}
