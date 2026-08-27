/// Dart ⇄ 原生（MapKit）MethodChannel 协议的编解码。
///
/// 通道名、方法名、载荷形状集中在这一个文件里（原指南 §3），
/// 全部是纯函数：不碰 Flutter 绑定，可被纯 Dart 测试直接构造与回放。
library;

import 'map_display_options.dart';
import 'map_models.dart';
import 'map_scene_controller.dart';

/// PlatformView 注册用的 viewType，同时也是原生 factory 的注册名。
const String kSiponMapViewType = 'sipon/mapkit';

/// 双引擎总开关（迁移期）。默认走 MapKit；回退 Mapbox 用
/// `--dart-define=USE_MAPKIT_MAP=false`。唯一的定义点，widget 与控制器共用。
const bool kUseMapkitMap = bool.fromEnvironment(
  'USE_MAPKIT_MAP',
  defaultValue: true,
);

/// 每个平台视图实例独享一条通道，避免多实例串台。
String siponMapChannelName(int viewId) => 'sipon/mapkit_$viewId';

/// Dart → 原生的方法名。
abstract final class SiponMapCommands {
  static const String setup = 'setup';
  static const String setStyle = 'setStyle';
  static const String setGestures = 'setGestures';
  static const String readViewport = 'readViewport';
  static const String flyToCity = 'flyToCity';
  static const String focusOn = 'focusOn';
  static const String applyStage = 'applyStage';
  static const String renderFrame = 'renderFrame';
  static const String registerAssets = 'registerAssets';
  static const String dispose = 'dispose';
}

/// 原生 → Dart 的方法名。
abstract final class SiponMapEvents {
  static const String onMapReady = 'onMapReady';
  static const String onViewportSettled = 'onViewportSettled';
  static const String onVenueTapped = 'onVenueTapped';
  static const String onBlankTapped = 'onBlankTapped';

  /// 仅 Mapbox 引擎使用：插件样式加载完成，控制器收到后重放上一帧。
  static const String onStyleLoaded = 'onStyleLoaded';
}

// --------------------------------------------------------------------- 载荷

/// `setup` 载荷。原生在收到它之后才装配地图并回报 [SiponMapEvents.onMapReady]，
/// 于是天然不存在「事件早于监听」的竞态。
Map<String, Object?> encodeSetup({
  required String city,
  required MapBaseStyle style,
}) => {
  'city': city,
  'styleId': style.id,
};

Map<String, Object?> encodeStyle(String styleId) => {'styleId': styleId};

Map<String, Object?> encodeGestures() => <String, Object?>{
  // 与原 GesturesSettings(rotate/pinch/scroll 全开) 一致。
  'rotateEnabled': true,
  'zoomEnabled': true,
  'panEnabled': true,
};

/// 相机指令共用参数。[bottomPadding] 是 Mapbox padding.bottom 的等价物：
/// 让目标点出现在「去掉底部面板后的区域」中心。
Map<String, Object?> encodeCameraMove({
  required double longitude,
  required double latitude,
  required double zoom,
  required double pitch,
  required double bearing,
  required double bottomPadding,
}) => {
  'lon': longitude,
  'lat': latitude,
  'zoom': zoom,
  'pitch': pitch,
  'bearing': bearing,
  'bottomPadding': bottomPadding,
};

Map<String, Object?> encodeApplyStage({required double bottomPadding}) =>
    {'bottomPadding': bottomPadding};

/// marker 图标资产表：kind.id → Flutter 资产 key。原生启动时一次性装载，
/// 比每帧传 bytes 省。
Map<String, Object?> encodeMarkerAssets() => {
  'assets': {
    for (final kind in MapVenueKind.values) kind.id: kind.iconAsset,
  },
};

/// [SiponMapCommands.renderFrame] 载荷（对应 [MapSceneFrame]）。
///
/// 约定：列表传全量，原生按 id diff；Dart 侧五套指纹保证没变的帧根本
/// 不会发出这条消息（见基类 [MapSceneController.render]）。
/// [zoom] 是最近一次视野上报的缩放，用来算圆点淡入透明度。
Map<String, Object?> encodeRenderFrame(MapSceneFrame frame,
    {required double zoom}) {
  final fade = mapCircleFadeForZoom(zoom);
  return {
    'layerMode': frame.layerMode.name,
    // handoff→restored 区间内 Dart 预先算好的透明度；区间外原生按最新缩放自插值。
    'circleFade': fade,
    'circles': [
      for (final point in frame.circlePoints)
        {
          'id': point.id,
          'lat': point.latitude,
          'lng': point.longitude,
          'category': point.kind.id,
          if (point.venueId != null) 'venueId': point.venueId,
        },
    ],
    'heatmap': [
      for (final point in frame.heatmapPoints)
        {
          'id': point.id,
          'lat': point.latitude,
          'lng': point.longitude,
          'weight': point.weight,
        },
    ],
    'markers': [
      for (final marker in frame.markers)
        {
          'venueId': marker.venueId,
          'label': marker.label,
          'lat': marker.latitude,
          'lng': marker.longitude,
          'category': marker.kind.id,
        },
    ],
    'selected': frame.selected == null
        ? null
        : {
            'id': frame.selected!.id,
            'lat': frame.selected!.latitude,
            'lng': frame.selected!.longitude,
            'category': frame.selected!.kind.id,
            if (frame.selected!.venueId != null)
              'venueId': frame.selected!.venueId,
          },
  };
}

// ------------------------------------------------------------------- 解析端

/// `readViewport` / `onViewportSettled` 共用的返回形状。
class SiponViewportPayload {
  const SiponViewportPayload({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    required this.zoom,
  });

  final double west;
  final double south;
  final double east;
  final double north;
  final double zoom;

  bool get isValid =>
      west.isFinite &&
      south.isFinite &&
      east.isFinite &&
      north.isFinite &&
      zoom.isFinite &&
      east > west &&
      north > south;
}

/// 解析原生组装的视野载荷；给不出合法数字就返回 null（调用方兜底）。
SiponViewportPayload? parseViewportPayload(Object? arguments) {
  if (arguments is! Map) {
    return null;
  }

  double read(String key) {
    final value = arguments[key];
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? double.nan;
  }

  final payload = SiponViewportPayload(
    west: read('west'),
    south: read('south'),
    east: read('east'),
    north: read('north'),
    zoom: read('zoom'),
  );

  return payload.isValid ? payload : null;
}

/// 解析点选事件的 venueId；空白点击没有这个字段。
String? parseVenueTapped(Object? arguments) {
  if (arguments is! Map) {
    return null;
  }
  final venueId = arguments['venueId'];
  if (venueId is String && venueId.isNotEmpty) {
    return venueId;
  }

  return null;
}
