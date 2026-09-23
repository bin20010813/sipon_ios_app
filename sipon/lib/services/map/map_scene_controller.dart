import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'map_display_options.dart';
import 'map_models.dart';
import 'map_viewport.dart';
import 'mapkit_scene_controller.dart';
import 'sipon_map_host.dart';

/// 一帧要画到地图上的全部内容。
///
/// 页面每次 `setState` 后把它整体交给 [MapSceneController]，控制器自己比对
/// 哪些部分真的变了。这样「什么时候下发」只有一个入口。
class MapSceneFrame {
  const MapSceneFrame({
    required this.circlePoints,
    required this.markers,
    this.selected,
  });

  final List<MapPoint> circlePoints;
  final List<MapMarkerSpec> markers;

  /// 当前选中的那个点，用来画高亮光环。没有选中就是 null。
  final MapPoint? selected;

  /// 非有限浮点值在 JSON 编码里可能抛错，转成字符串令牌，避免整帧指纹炸掉。
  /// 非法坐标仍应在数据入口过滤，这里只是防御性令牌化，不是坐标修正手段。
  static Object _coordinateToken(double value) =>
      value.isFinite ? value : value.toString();

  /// 普通点位/选中点的指纹片段：纳入坐标、类别、venueId 等实际渲染字段。
  static List<Object?> _pointToken(MapPoint point) => [
    point.id,
    _coordinateToken(point.longitude),
    _coordinateToken(point.latitude),
    point.iconCategory ?? point.kind.id,
    point.venueId,
  ];

  /// 整帧指纹。相同就说明这一帧跟上一帧画出来一模一样，可以整段跳过。
  /// 字段对应实际传给原生的渲染数据；不把未用于地图显示的接口对象放进来，
  /// 以免无关字段变化就触发地图刷新。
  String get signature => jsonEncode([
    [for (final point in circlePoints) _pointToken(point)],
    [
      for (final marker in markers)
        [
          marker.venueId,
          marker.label,
          _coordinateToken(marker.longitude),
          _coordinateToken(marker.latitude),
          marker.iconCategory ?? marker.kind.id,
          marker.rating == null ? null : _coordinateToken(marker.rating!),
          marker.sequence,
        ],
    ],
    selected == null ? null : _pointToken(selected!),
  ]);
}

/// 地图侧的唯一负责人：底图、annotation、相机、图层显隐。
///
/// 它是整个地图页里**唯一**碰地图引擎的地方。页面不再直接碰引擎，
/// 于是「相机为什么动了」永远只有实现类里的几个方法可查。这里只放契约、
/// 相机常量与 MapKit 引擎共享的帧指纹机制；MapKit 细节在
/// [MapkitSceneController]。
///
/// 三个回调把地图事件翻译成业务意图交回页面：
/// - [onViewportSettled]：相机停稳（已去抖）后的视野，页面拿去决定要不要取数；
/// - [onVenueTapped]：点中了某个点位；
/// - [onBlankTapped]：点在空白处。原来点空白毫无反应，现在用来收起面板。
abstract class MapSceneController {
  MapSceneController({
    required this.onViewportSettled,
    required this.onVenueTapped,
    required this.onBlankTapped,
  });

  final void Function(MapViewport viewport) onViewportSettled;
  final void Function(String venueId) onVenueTapped;
  final VoidCallback onBlankTapped;

  /// 当前只使用 MapKit 引擎。
  static MapSceneController create({
    required void Function(MapViewport viewport) onViewportSettled,
    required void Function(String venueId) onVenueTapped,
    required VoidCallback onBlankTapped,
  }) {
    return MapkitSceneController(
      onViewportSettled: onViewportSettled,
      onVenueTapped: onVenueTapped,
      onBlankTapped: onBlankTapped,
    );
  }

  /// 相机停下后再等这么久才回调。一次飞行会连着抛好几个 idle，
  /// 去抖之后只剩最后一个。两个引擎语义一致，去抖都留在 Dart。
  static const Duration idleDebounce = Duration(milliseconds: 220);

  /// 与面板动画同时长，两条动画节奏一致。（MapKit 的动画时长不可控，
  /// 只作为参数随指令下发，原生能忽略就忽略。）
  static const Duration focusDuration = Duration(milliseconds: 420);
  static const double defaultZoom = 15.05;
  static const double cityZoom = 11.8;
  static const double focusZoom = 15.4;

  /// MapKit 统一使用正北朝上的 2D 相机；原生层也会禁用俯仰手势兜底。
  static const double defaultPitch = 0;
  static const double defaultBearing = 0;
  static const double focusPitch = 0;
  static const double focusBearing = 0;

  /// 命中测试的容差（逻辑像素）。圆点半径只有 4~11pt，手指比它大得多；
  /// MapKit 版把命中区做到 max(视觉直径, 22pt)，与这个旧值同量级。
  static const double tapSlop = 18;

  SiponEventSink get eventSink => _eventSink;
  final SiponEventSink _eventSink = SiponEventSink();

  /// 最近一次视野上报的缩放，算圆点淡入透明度用。
  double latestZoom = defaultZoom;

  /// 渲染过最后一帧的缓存：样式重载后没有专门的「重画」入口，
  /// 控制器自己负责原样重放（页面对此无感）。
  @protected
  MapSceneFrame? lastFrame;

  /// 整帧指纹。页面每次 `setState` 都会把一帧送进来，但绝大多数 `setState`
  /// （面板形变等重建）跟地图内容无关。先比整帧指纹，避免空跑。
  @protected
  String? frameSignature;

  /// 相机 padding 的下边距。每次相机调用都显式带上它——不带的旧版引擎会
  /// 沿用上一次的值，聚焦过详情之后 padding 就一直粘着不还。
  @protected
  double cameraBottomPadding = 0;

  /// 装饰物下边距。MapKit 没有装饰物，保留字段只为兼容页面调用。
  @protected
  double ornamentBottomMargin = 184;

  bool get isAttached;

  Future<void> attach(
    SiponMapHost host, {
    required String city,
    MapBaseStyle style = MapBaseStyle.standard,
    MapLatLng? initialCenter,
  });

  void detach();

  Future<void> setStyle(MapBaseStyle style);

  /// 读当前相机看到的范围。相机还没就绪时兜底返回整个中国。
  Future<MapViewport?> readViewport();

  /// 面板落定后调一次：相机取景与 padding 一次对齐。
  ///
  /// **相机意图的唯一出口之一。** 页面所有档位变化都汇聚到这里。
  Future<void> applyStage({
    required double cameraBottomPadding,
    required double ornamentBottomMargin,
    MapLatLng? focus,
  }) async {
    final paddingChanged = this.cameraBottomPadding != cameraBottomPadding;
    this.cameraBottomPadding = cameraBottomPadding;
    this.ornamentBottomMargin = ornamentBottomMargin;

    if (focus != null) {
      await focusOn(longitude: focus.longitude, latitude: focus.latitude);
      return;
    }
    if (!paddingChanged) {
      return;
    }

    await easeForPaddingOnly();
  }

  /// 面板拖动时让选中点持续位于扣除底部遮挡后的地图中心。
  ///
  /// 与 [focusOn] 不同，这个入口只更新相机中心与 padding，不重置用户当前的
  /// 缩放、俯仰和朝向。页面会把高频 extent 通知合并成每帧最多一次调用。
  Future<void> followSelectionForSheet({
    required double cameraBottomPadding,
    required MapLatLng focus,
  }) async {
    this.cameraBottomPadding = cameraBottomPadding;
    await performSheetFollow(focus);
  }

  /// 把某个坐标居中（附带聚焦缩放/俯仰/朝向）。
  Future<void> focusOn({required double longitude, required double latitude});

  Future<void> flyToCity(String city, {required double zoom});

  /// 按 [points] 顺序规划每对相邻站点的道路路线；全部成功后才绘制。
  /// 任一路段失败、点位不足或引擎未就绪时返回 false。
  Future<bool> planRoute({required List<MapLatLng> points});

  /// 清除已绘制的路线折线（站点变更后调用，避免旧路线残留）。
  void clearRoute();

  /// 把一帧内容下发到地图。整帧没变就直接返回。
  Future<void> render(MapSceneFrame frame) async {
    lastFrame = frame;
    if (!isAttached) {
      return;
    }

    final signature = frame.signature;
    if (signature == frameSignature) {
      return;
    }
    frameSignature = signature;

    await performRender(frame);
  }

  /// 引擎事件的唯一入口。[SiponMapHost.onNativeCall] 转进来的东西
  /// 全部从这条缝进来。
  void handleNativeEvent(String method, Object? arguments);

  // ------------------------------------------------------------ 引擎差异化

  /// 各引擎真正的渲染动作。[render] 已经做完指纹闸门与帧缓存。
  @protected
  Future<void> performRender(MapSceneFrame frame);

  /// 覆盖物重建后恢复地图手势。部分平台在重建原生覆盖物时可能重置
  /// 手势状态；默认实现给不需要这一步的引擎留空。
  @protected
  Future<void> restoreGestures() async {}

  /// padding 变了但没有要聚焦的目标时的平移（各引擎自行取景）。
  @protected
  Future<void> easeForPaddingOnly();

  /// 保持现有相机姿态，仅按当前 padding 把 [focus] 放到可见地图中心。
  @protected
  Future<void> performSheetFollow(MapLatLng focus);

  /// 样式重新加载后引擎侧全被清空，缓存的指纹也得作废，
  /// 否则下一帧会以为「没变化」而什么都不画。随后原样重放上一帧。
  Future<void> handleStyleLoaded() async {
    resetStyleCaches();
    final frame = lastFrame;
    if (frame != null && isAttached) {
      await performRender(frame);
    }
  }

  @protected
  void resetStyleCaches() {
    frameSignature = null;
  }

  /// 相机可能停了（原生高频上报）。去抖后读一次视野回调给页面。
  /// Kit 实现改走事件自带数据的快路径，这里是通用兜底。
  void handleViewportSettled() {
    _idleDebounceTimer?.cancel();
    _idleDebounceTimer = Timer(idleDebounce, () async {
      final viewport = await readViewport();
      if (viewport != null && isAttached) {
        onViewportSettled(viewport);
      }
    });
  }

  Timer? _idleDebounceTimer;

  @protected
  void cancelIdleDebounce() {
    _idleDebounceTimer?.cancel();
    _idleDebounceTimer = null;
  }

  /// 子类 detach 时统一清理公共状态。
  @protected
  void detachCommon() {
    cancelIdleDebounce();
    _eventSink.detachHandler();
    lastFrame = null;
    frameSignature = null;
  }
}
