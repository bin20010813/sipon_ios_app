import 'package:url_launcher/url_launcher.dart';

enum ExternalMapApp {
  amap('高德地图'),
  baidu('百度地图'),
  tencent('腾讯地图'),
  apple('苹果地图');

  const ExternalMapApp(this.label);

  final String label;
}

/// 外部地图 App 唤起结果。
class ExternalMapLaunchResult {
  const ExternalMapLaunchResult._(this.opened, this.message);

  final bool opened;
  final String message;

  static ExternalMapLaunchResult opened(ExternalMapApp app) =>
      ExternalMapLaunchResult._(true, '已打开${app.label}路线规划');

  static ExternalMapLaunchResult unavailable(ExternalMapApp app) =>
      ExternalMapLaunchResult._(false, '无法打开${app.label}，请确认已安装后再试');

  static const invalidCoordinate = ExternalMapLaunchResult._(
    false,
    '地点坐标异常，暂时无法打开路线规划',
  );
}

/// 第三方地图唤起服务。
///
/// 后端返回的是由高德坐标转换后的 WGS-84 坐标。高德路线规划使用 `dev=1`，
/// 百度传 `coord_type=wgs84`；苹果地图原生使用 WGS-84。
class ExternalMapLauncher {
  const ExternalMapLauncher._();

  static Future<List<ExternalMapApp>> availableRouteApps() async {
    final apps = <ExternalMapApp>[];
    for (final app in ExternalMapApp.values) {
      if (app == ExternalMapApp.apple || await canLaunchUrl(_probeUri(app))) {
        apps.add(app);
      }
    }
    return apps;
  }

  static Future<ExternalMapLaunchResult> openRoutePlan({
    required ExternalMapApp app,
    required String name,
    required double longitude,
    required double latitude,
  }) async {
    if (!longitude.isFinite || !latitude.isFinite) {
      return ExternalMapLaunchResult.invalidCoordinate;
    }

    final uri = _routeUri(
      app: app,
      name: name.trim().isEmpty ? '目的地' : name.trim(),
      longitude: longitude,
      latitude: latitude,
    );

    if (app != ExternalMapApp.apple && !await canLaunchUrl(_probeUri(app))) {
      return ExternalMapLaunchResult.unavailable(app);
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return opened
        ? ExternalMapLaunchResult.opened(app)
        : ExternalMapLaunchResult.unavailable(app);
  }

  static Uri _probeUri(ExternalMapApp app) {
    return switch (app) {
      ExternalMapApp.amap => Uri.parse('iosamap://'),
      ExternalMapApp.baidu => Uri.parse('baidumap://'),
      ExternalMapApp.tencent => Uri.parse('qqmap://'),
      ExternalMapApp.apple => Uri.https('maps.apple.com'),
    };
  }

  static Uri _routeUri({
    required ExternalMapApp app,
    required String name,
    required double longitude,
    required double latitude,
  }) {
    final lat = latitude.toStringAsFixed(8);
    final lon = longitude.toStringAsFixed(8);

    return switch (app) {
      // path 是路线规划页；navi 才是直接导航。dev=1 表示 WGS-84/GPS 坐标。
      ExternalMapApp.amap => Uri(
        scheme: 'iosamap',
        host: 'path',
        queryParameters: {
          'sourceApplication': 'Sipon',
          'dname': name,
          'dlat': lat,
          'dlon': lon,
          'dev': '1',
          't': '0',
        },
      ),
      ExternalMapApp.baidu => Uri(
        scheme: 'baidumap',
        host: 'map',
        path: '/direction',
        queryParameters: {
          'destination': 'latlng:$lat,$lon|name:$name',
          'coord_type': 'wgs84',
          'mode': 'driving',
          'src': 'Sipon',
        },
      ),
      ExternalMapApp.tencent => Uri(
        scheme: 'qqmap',
        host: 'map',
        path: '/routeplan',
        queryParameters: {
          'type': 'drive',
          'to': name,
          'tocoord': '$lat,$lon',
          'referer': 'Sipon',
        },
      ),
      ExternalMapApp.apple => Uri.https('maps.apple.com', '/', {
        'daddr': '$lat,$lon',
        'q': name,
        'dirflg': 'd',
      }),
    };
  }
}
