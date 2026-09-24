import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sipon/services/sipon_api_client.dart';
import 'package:sipon/services/sipon_api_config.dart';
import 'package:sipon/services/sipon_api_service.dart';
import 'package:sipon/services/virtual_drinking_local_store.dart';
import 'package:sipon/services/virtual_drinking_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(SiponApiClient.clearSession);

  test('虚拟饮品接口使用独立路径，偏好为 PUT', () async {
    final paths = <String>[];
    final api = SiponApiService(
      apiClient: SiponApiClient(
        config: const SiponApiConfig(baseUrl: 'https://api.example.test'),
        httpClient: MockClient((request) async {
          paths.add('${request.method} ${request.url.path}');
          if (request.method == 'PUT') {
            expect(jsonDecode(request.body), {
              'drinkCode': 'mojito',
              'glassCode': 'highball',
              'sceneCode': 'rain_window',
              'iceCode': 'column',
              'ambientSoundEnabled': false,
              'ambientSoundVolume': 30,
            });
          }
          return http.Response(
            request.url.path.endsWith('/drinks') ? '[]' : '{}',
            200,
          );
        }),
      ),
    );

    await api.getVirtualDrinkingBootstrap();
    await api.searchVirtualDrinks(keyword: '莫吉托');
    await api.getVirtualDrink('mojito');
    await api.getVirtualDrinkingPreferences();
    await api.updateVirtualDrinkingPreferences(
      const VirtualDrinkingPreference(
        drinkCode: 'mojito',
        glassCode: 'highball',
        sceneCode: 'rain_window',
        iceCode: 'column',
        ambientSoundEnabled: false,
        ambientSoundVolume: 30,
      ).toJson(),
    );

    expect(paths, [
      'GET /api/virtual-drinking/bootstrap',
      'GET /api/virtual-drinking/drinks',
      'GET /api/virtual-drinking/drinks/mojito',
      'GET /api/virtual-drinking/users/me/preferences',
      'PUT /api/virtual-drinking/users/me/preferences',
    ]);
  });

  test('渲染目录读取具体饮品配置，未知渐层安全回退', () {
    final catalog = VirtualDrinkingCatalog.fromJson({
      'drinks': [
        {
          'code': 'mojito',
          'name': '莫吉托',
          'category': 'cocktail',
          'defaultGlassCode': 'highball',
          'defaultIceCode': 'column',
          'allowedIceCodes': ['column', 'crushed'],
          'renderConfig': {'color': '#9bbb55', 'opacity': 0.78},
          'interactionPreset': {'sipAmount': 0.08, 'holdRepeatMs': 650},
        },
      ],
      'glasses': [
        {
          'code': 'highball',
          'name': '高球杯',
          'renderConfig': {'shape': 'highball'},
        },
      ],
      'scenes': [
        {
          'code': 'rain_window',
          'name': '雨夜窗边',
          'renderConfig': {'background': 'bad input'},
        },
      ],
      'preferenceDefaults': {'drinkCode': 'mojito'},
    });

    expect(catalog.drink('mojito')!.liquidColor.toARGB32(), 0xFF9BBB55);
    expect(catalog.drink('mojito')!.sipAmount, 0.08);
    expect(catalog.scene('rain_window')!.backgroundColors.length, 3);
  });

  test('3D 资源目录解析杯子、酒液轮廓和冰型', () {
    final catalog = VirtualDrinkingCatalog.fromJson({
      'modelRendererVersion': '1',
      'assets': [
        {
          'code': 'glass.highball',
          'kind': 'glass_model',
          'url': '/assets/virtual-drinking/models/glasses/highball.glb',
          'title': 'Glass Collection',
          'author': 'RagingCow',
          'license': 'CC BY 4.0',
        },
      ],
      'glasses': [
        {
          'code': 'highball',
          'renderConfig': {
            'model3d': {
              'assetCode': 'glass.highball',
              'liquidProfile': {
                'points': [
                  {'y': 0.11, 'radius': 0.17},
                  {'y': 0.9, 'radius': 0.23},
                ],
              },
            },
          },
        },
      ],
      'iceOptions': [
        {
          'code': 'large',
          'model3d': {'renderer': 'glb-v1', 'assetCode': 'ice.cube'},
        },
      ],
    });

    expect(catalog.modelRendererVersion, '1');
    expect(catalog.asset('glass.highball')?.kind, 'glass_model');
    expect(catalog.asset('glass.highball')?.author, 'RagingCow');
    expect(catalog.glass('highball')?.modelAssetCode, 'glass.highball');
    expect(catalog.glass('highball')?.liquidProfile.last['radius'], 0.23);
    expect(catalog.iceOptions.single.renderer, 'glb-v1');
    expect(catalog.iceOptions.single.modelAssetCode, 'ice.cube');
  });

  test('本地虚拟喝口计数按日期重置，并与偏好独立保存', () async {
    SharedPreferences.setMockInitialValues({});
    final store = VirtualDrinkingLocalStore(scope: 'test_user');
    final day = DateTime(2026, 9, 23, 20);
    await store.saveTodayCount(day, 7);
    await store.savePreference(
      const VirtualDrinkingPreference(
        drinkCode: 'mojito',
        glassCode: 'highball',
        sceneCode: 'rain_window',
        iceCode: 'column',
        ambientSoundEnabled: true,
        ambientSoundVolume: 45,
      ),
    );

    expect(await store.loadTodayCount(day), 7);
    expect(await store.loadTodayCount(DateTime(2026, 9, 24)), 0);
    expect((await store.loadPreference())?.drinkCode, 'mojito');
  });
}
