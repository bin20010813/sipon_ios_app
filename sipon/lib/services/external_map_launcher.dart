import 'package:url_launcher/url_launcher.dart';

/// 外部地图 App 唤起结果。
class ExternalMapLaunchResult {
  const ExternalMapLaunchResult._(this.opened, this.message);

  final bool opened;
  final String message;

  static const openedAmap = ExternalMapLaunchResult._(true, '已打开高德地图导航');

  static const unavailable = ExternalMapLaunchResult._(
    false,
    '未检测到高德地图，请先安装高德地图后再试',
  );
}

/// 第三方地图唤起服务。
///
/// 后端返回的是由高德坐标转换后的 WGS-84 坐标，因此调起高德导航时使用
/// `dev=1`，让高德按 GPS 坐标解析目的地。
class ExternalMapLauncher {
  const ExternalMapLauncher._();

  static Future<ExternalMapLaunchResult> openAmapNavigation({
    required String name,
    required double longitude,
    required double latitude,
  }) async {
    if (!longitude.isFinite || !latitude.isFinite) {
      return ExternalMapLaunchResult.unavailable;
    }

    final destinationName = name.trim().isEmpty ? '目的地' : name.trim();
    final uri = Uri(
      scheme: 'iosamap',
      host: 'navi',
      queryParameters: {
        'sourceApplication': 'Sipon',
        'poiname': destinationName,
        'lat': latitude.toStringAsFixed(8),
        'lon': longitude.toStringAsFixed(8),
        'dev': '1',
        'style': '2',
      },
    );

    if (!await canLaunchUrl(uri)) {
      return ExternalMapLaunchResult.unavailable;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return opened
        ? ExternalMapLaunchResult.openedAmap
        : ExternalMapLaunchResult.unavailable;
  }
}
