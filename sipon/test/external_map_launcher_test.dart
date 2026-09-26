import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/map/platform/external_map_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final launched = <Uri>[];
  var installedSchemes = <String>{};

  setUp(() {
    launched.clear();
    installedSchemes = <String>{};
    messenger.setMockMethodCallHandler(channel, (call) async {
      final arguments = (call.arguments as Map).cast<String, Object?>();
      final uri = Uri.parse(arguments['url']! as String);
      if (call.method == 'canLaunch') {
        return installedSchemes.contains(uri.scheme);
      }
      if (call.method == 'launch') {
        launched.add(uri);
        return installedSchemes.contains(uri.scheme);
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('Android 仅列出已安装的地图 App，不列 Apple 地图', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    installedSchemes = {'amapuri', 'baidumap'};

    expect(await ExternalMapLauncher.availableNavigationApps(), [
      ExternalMapApp.amap,
      ExternalMapApp.baidu,
    ]);
  });

  test('Android 高德使用专属路线 URI 与 WGS-84 参数', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    installedSchemes = {'amapuri'};

    final result = await ExternalMapLauncher.openNavigation(
      app: ExternalMapApp.amap,
      name: '  中文 名称  ',
      longitude: 116.397,
      latitude: 39.908,
    );

    expect(result.opened, isTrue);
    expect(launched, hasLength(1));
    final uri = launched.single;
    expect(uri.scheme, 'amapuri');
    expect(uri.host, 'route');
    expect(uri.path, '/plan');
    expect(uri.queryParameters['dname'], '中文 名称');
    expect(uri.queryParameters['dlat'], '39.90800000');
    expect(uri.queryParameters['dlon'], '116.39700000');
    expect(uri.queryParameters['dev'], '1');
    expect(uri.toString(), contains('%20'));
  });

  test('Android 百度路线保留名称、坐标与 WGS-84 标记', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    installedSchemes = {'baidumap'};

    final result = await ExternalMapLauncher.openNavigation(
      app: ExternalMapApp.baidu,
      name: '酒吧 A',
      longitude: 121.5,
      latitude: 31.2,
    );

    expect(result.opened, isTrue);
    final uri = launched.single;
    expect(uri.queryParameters['origin'], '我的位置');
    expect(
      uri.queryParameters['destination'],
      'name:酒吧 A|latlng:31.20000000,121.50000000',
    );
    expect(uri.queryParameters['coord_type'], 'wgs84');
  });

  test('未安装时显示不可用；无效坐标不发起唤起', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await ExternalMapLauncher.availableNavigationApps(), isEmpty);

    final missing = await ExternalMapLauncher.openNavigation(
      app: ExternalMapApp.baidu,
      name: '测试',
      longitude: 121,
      latitude: 31,
    );
    expect(missing.opened, isFalse);

    installedSchemes = {'baidumap'};
    final invalid = await ExternalMapLauncher.openNavigation(
      app: ExternalMapApp.baidu,
      name: '测试',
      longitude: 200,
      latitude: 31,
    );
    expect(invalid.opened, isFalse);
    expect(launched, isEmpty);
  });

  test('iOS 继续提供 Apple 地图及 iOS 高德 scheme', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    installedSchemes = {'http', 'iosamap'};

    expect(await ExternalMapLauncher.availableNavigationApps(), [
      ExternalMapApp.apple,
      ExternalMapApp.amap,
    ]);
    final result = await ExternalMapLauncher.openNavigation(
      app: ExternalMapApp.amap,
      name: '测试',
      longitude: 121.5,
      latitude: 31.2,
    );
    expect(result.opened, isTrue);
    expect(launched.single.scheme, 'iosamap');
  });
}
