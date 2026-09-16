import 'package:url_launcher/url_launcher.dart';

/// 可从 POI 详情页唤起的外部地图 App。
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
      ExternalMapLaunchResult._(true, '已打开${app.label}，请在地图内选择交通方式');

  static ExternalMapLaunchResult unavailable([ExternalMapApp? app]) =>
      ExternalMapLaunchResult._(
        false,
        app == null ? '未检测到可用地图 App' : '未检测到${app.label}，请先安装后再试',
      );
}

/// 第三方地图唤起服务。
///
/// POI 详情页只把目标点交给外部地图展示，不直接指定驾车/步行路线。
/// 用户进入地图 App 后再按自己的场景选择交通方式，符合 iOS MapKit/地图 App
/// 对地点展示与路线规划的分工。
class ExternalMapLauncher {
  const ExternalMapLauncher._();

  static Future<List<ExternalMapApp>> availablePoiApps() async {
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

  static Future<ExternalMapLaunchResult> openPoi({
    required ExternalMapApp app,
    required String name,
    required double longitude,
    required double latitude,
    String? address,
  }) async {
    if (!longitude.isFinite || !latitude.isFinite) {
      return ExternalMapLaunchResult.unavailable(app);
    }

    final poiName = name.trim().isEmpty ? '目的地' : name.trim();
    final uri = _poiUri(
      app: app,
      name: poiName,
      longitude: longitude,
      latitude: latitude,
      address: address,
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

  static Uri _poiUri({
    required ExternalMapApp app,
    required String name,
    required double longitude,
    required double latitude,
    String? address,
  }) {
    final lat = latitude.toStringAsFixed(8);
    final lng = longitude.toStringAsFixed(8);
    final addr = address?.trim();

    return switch (app) {
      ExternalMapApp.apple => Uri.https('maps.apple.com', '/', {
        'll': '$lat,$lng',
        'q': name,
      }),
      ExternalMapApp.amap => Uri(
        scheme: 'iosamap',
        host: 'viewMap',
        queryParameters: {
          'sourceApplication': 'Sipon',
          'poiname': name,
          'lat': lat,
          'lon': lng,
          'dev': '1',
        },
      ),
      ExternalMapApp.baidu => Uri(
        scheme: 'baidumap',
        host: 'map',
        path: '/marker',
        queryParameters: {
          'location': '$lat,$lng',
          'title': name,
          'content': (addr == null || addr.isEmpty) ? name : addr,
          'coord_type': 'wgs84',
          'src': 'Sipon',
        },
      ),
      ExternalMapApp.tencent => Uri(
        scheme: 'qqmap',
        host: 'map',
        path: '/marker',
        queryParameters: {
          'marker':
              'coord:$lat,$lng;title:$name${addr == null || addr.isEmpty ? '' : ';addr:$addr'}',
          'referer': 'Sipon',
        },
      ),
    };
  }
}
