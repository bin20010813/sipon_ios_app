import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sipon/shared/services/harmony_platform.dart';

/// 可从地点详情页唤起的外部地图 App。
enum ExternalMapApp {
  petal('花瓣地图'),
  apple('Apple 地图'),
  amap('高德地图'),
  baidu('百度地图'),
  tencent('腾讯地图');

  const ExternalMapApp(this.label);

  final String label;
}

/// 外部地图 App 唤起结果。
class ExternalMapLaunchResult {
  const ExternalMapLaunchResult._(this.opened, this.message);

  final bool opened;
  final String message;

  static ExternalMapLaunchResult success(ExternalMapApp app) =>
      ExternalMapLaunchResult._(true, '已打开${app.label}路线规划，请选择交通方式出发');

  static ExternalMapLaunchResult unavailable([ExternalMapApp? app]) =>
      ExternalMapLaunchResult._(
        false,
        app == null ? '未检测到可用地图 App' : '未检测到${app.label}，请先安装后再试',
      );
}

/// 第三方地图唤起服务。
///
/// 「出发」按钮以当前位置为起点、目标地点为终点，调起外部地图的
/// 路线规划界面（而非地点详情）。起点坐标不传，由地图 App 默认取
/// 当前定位；具体交通方式（驾车/步行/公交等）在地图 App 内选择。
class ExternalMapLauncher {
  const ExternalMapLauncher._();

  // 腾讯地图 URI 要求 referer 为开发者 Key，不能用应用名称代替。
  static const String _tencentMapKey = String.fromEnvironment(
    'SIPON_TENCENT_MAP_KEY',
  );

  static bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static bool _isSupported(ExternalMapApp app) {
    if (isHarmonyOS) return app == ExternalMapApp.petal;
    if (app == ExternalMapApp.petal) return false;
    if (!_isMobile) return false;
    if (app == ExternalMapApp.apple) {
      return defaultTargetPlatform == TargetPlatform.iOS;
    }
    if (app == ExternalMapApp.tencent && _tencentMapKey.trim().isEmpty) {
      return false;
    }
    return true;
  }

  static Future<List<ExternalMapApp>> availableNavigationApps() async {
    // Map Kit invokes the system map application directly on HarmonyOS.
    if (isHarmonyOS) return const [ExternalMapApp.petal];
    final apps = <ExternalMapApp>[];
    for (final app in const [
      ExternalMapApp.apple,
      ExternalMapApp.amap,
      ExternalMapApp.baidu,
      ExternalMapApp.tencent,
    ]) {
      if (!_isSupported(app)) continue;
      try {
        if (!await canLaunchUrl(_probeUri(app))) continue;
        apps.add(app);
      } catch (_) {
        // 某些系统对未安装的自定义 scheme 抛异常；其余地图仍可继续探测。
      }
    }
    return apps;
  }

  static Future<ExternalMapLaunchResult> openNavigation({
    required ExternalMapApp app,
    required String name,
    required double longitude,
    required double latitude,
  }) async {
    if (!_isSupported(app) ||
        !longitude.isFinite ||
        !latitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        latitude < -90 ||
        latitude > 90) {
      return ExternalMapLaunchResult.unavailable(app);
    }

    final destinationName = name.trim().isEmpty ? '目的地' : name.trim();
    if (app == ExternalMapApp.petal) {
      try {
        final opened = await harmonyServices.invokeMethod<bool>(
          'openPetalNavigation',
          {'name': destinationName, 'lng': longitude, 'lat': latitude},
        );
        return opened == true
            ? ExternalMapLaunchResult.success(app)
            : ExternalMapLaunchResult.unavailable(app);
      } catch (_) {
        return ExternalMapLaunchResult.unavailable(app);
      }
    }
    final uri = _routeUri(
      app: app,
      name: destinationName,
      longitude: longitude,
      latitude: latitude,
    );

    try {
      if (!await canLaunchUrl(uri)) {
        return ExternalMapLaunchResult.unavailable(app);
      }

      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return opened
          ? ExternalMapLaunchResult.success(app)
          : ExternalMapLaunchResult.unavailable(app);
    } catch (_) {
      return ExternalMapLaunchResult.unavailable(app);
    }
  }

  static Uri _probeUri(ExternalMapApp app) {
    return switch (app) {
      ExternalMapApp.petal => throw UnsupportedError('Use HarmonyOS Map Kit'),
      ExternalMapApp.apple => Uri.parse('http://maps.apple.com/'),
      ExternalMapApp.amap =>
        defaultTargetPlatform == TargetPlatform.android
            ? Uri.parse('amapuri://route/plan')
            : Uri.parse('iosamap://path'),
      ExternalMapApp.baidu => Uri.parse('baidumap://map/direction'),
      ExternalMapApp.tencent => Uri.parse('qqmap://map/routeplan'),
    };
  }

  /// 各地图路线规划的 URL Scheme：
  /// - Apple：`daddr` 打开路线页，起点默认当前位置；
  /// - 高德：`path` 路线规划，`dev=1` 表示传入 WGS-84 坐标，由高德纠偏；
  /// - 百度：`direction` 路线规划，`coord_type=wgs84` 由百度纠偏；
  /// - 腾讯：`routeplan` 路线规划，`coord_type=1` 表示 GPS(WGS-84) 坐标。
  /// 自定义 scheme 使用百分号编码，避免中文或空格被编码为 `+`。
  static Uri _routeUri({
    required ExternalMapApp app,
    required String name,
    required double longitude,
    required double latitude,
  }) {
    final lat = latitude.toStringAsFixed(8);
    final lng = longitude.toStringAsFixed(8);

    return switch (app) {
      ExternalMapApp.petal => throw UnsupportedError('Use HarmonyOS Map Kit'),
      ExternalMapApp.apple => Uri.https('maps.apple.com', '/', {
        'daddr': '$lat,$lng',
      }),
      ExternalMapApp.amap => _customUri(
        scheme: defaultTargetPlatform == TargetPlatform.android
            ? 'amapuri'
            : 'iosamap',
        host: defaultTargetPlatform == TargetPlatform.android
            ? 'route'
            : 'path',
        path: defaultTargetPlatform == TargetPlatform.android ? '/plan' : '',
        parameters: {
          'sourceApplication': 'Sipon',
          'dname': name,
          'dlat': lat,
          'dlon': lng,
          'dev': '1',
          't': '0',
        },
      ),
      ExternalMapApp.baidu => _customUri(
        scheme: 'baidumap',
        host: 'map',
        path: '/direction',
        parameters: {
          'origin': '我的位置',
          'destination': 'name:$name|latlng:$lat,$lng',
          'mode': 'driving',
          'coord_type': 'wgs84',
          'src': 'sipon',
        },
      ),
      ExternalMapApp.tencent => _customUri(
        scheme: 'qqmap',
        host: 'map',
        path: '/routeplan',
        parameters: {
          'type': 'drive',
          'fromcoord': 'CurrentLocation',
          'to': name,
          'tocoord': '$lat,$lng',
          'coord_type': '1',
          'referer': _tencentMapKey,
        },
      ),
    };
  }

  static Uri _customUri({
    required String scheme,
    required String host,
    String path = '',
    required Map<String, String> parameters,
  }) {
    final query = parameters.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
        )
        .join('&');
    return Uri(scheme: scheme, host: host, path: path, query: query);
  }
}
