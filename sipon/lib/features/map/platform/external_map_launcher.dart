import 'package:url_launcher/url_launcher.dart';

/// 可从地点详情页唤起的外部地图 App。
enum ExternalMapApp {
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

  static Future<List<ExternalMapApp>> availableNavigationApps() async {
    final apps = <ExternalMapApp>[ExternalMapApp.apple];
    for (final app in const [
      ExternalMapApp.amap,
      ExternalMapApp.baidu,
      ExternalMapApp.tencent,
    ]) {
      if (await canLaunchUrl(_probeUri(app))) {
        apps.add(app);
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
    if (!longitude.isFinite || !latitude.isFinite) {
      return ExternalMapLaunchResult.unavailable(app);
    }

    final destinationName = name.trim().isEmpty ? '目的地' : name.trim();
    final uri = _routeUri(
      app: app,
      name: destinationName,
      longitude: longitude,
      latitude: latitude,
    );

    if (!await canLaunchUrl(uri)) {
      return ExternalMapLaunchResult.unavailable(app);
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return opened
        ? ExternalMapLaunchResult.success(app)
        : ExternalMapLaunchResult.unavailable(app);
  }

  static Uri _probeUri(ExternalMapApp app) {
    return switch (app) {
      ExternalMapApp.apple => Uri.parse('http://maps.apple.com/'),
      ExternalMapApp.amap => Uri.parse('iosamap://'),
      ExternalMapApp.baidu => Uri.parse('baidumap://'),
      ExternalMapApp.tencent => Uri.parse('qqmap://'),
    };
  }

  /// 各地图路线规划的 URL Scheme：
  /// - Apple：`daddr` 打开路线页，起点默认当前位置；
  /// - 高德：`path` 路线规划，`dev=1` 表示传入 WGS-84 坐标，由高德纠偏；
  /// - 百度：`direction` 路线规划，`coord_type=wgs84` 由百度纠偏；
  /// - 腾讯：`routeplan` 路线规划，`coord_type=1` 表示 GPS(WGS-84) 坐标。
  static Uri _routeUri({
    required ExternalMapApp app,
    required String name,
    required double longitude,
    required double latitude,
  }) {
    final lat = latitude.toStringAsFixed(8);
    final lng = longitude.toStringAsFixed(8);

    return switch (app) {
      ExternalMapApp.apple => Uri.https('maps.apple.com', '/', {
        'daddr': '$lat,$lng',
      }),
      ExternalMapApp.amap => Uri(
        scheme: 'iosamap',
        host: 'path',
        queryParameters: {
          'sourceApplication': 'Sipon',
          'dname': name,
          'dlat': lat,
          'dlon': lng,
          'dev': '1',
          't': '0',
        },
      ),
      ExternalMapApp.baidu => Uri(
        scheme: 'baidumap',
        host: 'map',
        path: '/direction',
        queryParameters: {
          'destination': '$lat,$lng',
          'mode': 'driving',
          'coord_type': 'wgs84',
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
          'tocoord': '$lat,$lng',
          'coord_type': '1',
          'referer': 'Sipon',
        },
      ),
    };
  }
}
