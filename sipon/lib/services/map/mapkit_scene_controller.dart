import 'dart:async';

import 'package:flutter/foundation.dart';

import 'map_display_options.dart';
import 'map_scene_controller.dart';
import 'map_viewport.dart';
import 'sipon_map_host.dart';
import 'sipon_map_protocol.dart';

/// MapKit 引擎实现。对外契约与迁移期的 Mapbox 版完全一致，底层是自封装的
/// MKMapView（PlatformView），指令走 [SiponMapCommands] 描述的 MethodChannel。
///
/// 与 Mapbox 版有意保留的行为差异（均为指南记录过的产品决策）：
/// - 没有样式加载期：[SiponMapEvents.onMapReady] 即视为可画，无需 styleLoaded；
/// - 切底图后没有对应事件，控制器自己重放上一帧兜底（§3b）；
/// - 相机动画时长随指令下发但原生不可控，落到系统默认时长（决策 D3）；
/// - 装饰物（logo / 版权 / 罗盘 / 比例尺）在 MapKit 中不存在，
///   `ornamentBottomMargin` 参数仅作契约兼容被忽略。
class MapkitSceneController extends MapSceneController {
  MapkitSceneController({
    required super.onViewportSettled,
    required super.onVenueTapped,
    required super.onBlankTapped,
  });

  SiponMapHost? _host;

  /// 原生配置完成并回报 ready 之后才允许渲染/读视野。
  bool _ready = false;

  /// attach 阻塞到收到 [SiponMapEvents.onMapReady]，保证后续调用有序。
  Completer<void>? _readyCompleter;

  /// 去抖期间最新的视野数据。原生直接带数据上报，省掉一次 readViewport 往返。
  SiponViewportPayload? _settlingViewport;
  Timer? _settleDebounce;

  @override
  bool get isAttached => _ready && _host != null;

  @override
  Future<void> attach(
    SiponMapHost host, {
    required String city,
    MapBaseStyle style = MapBaseStyle.standard,
  }) async {
    _host = host;
    host.onNativeCall(handleNativeEvent);

    final ready = Completer<void>();
    _readyCompleter = ready;

    // 地图配置（初始相机、底图、手势、装饰物开关）全部收进原生侧的 setup，
    // 收到这条命令后原生才装配地图并回报 onMapReady——不存在事件早于监听。
    await host.invoke(
      SiponMapCommands.setup,
      encodeSetup(city: city, style: style),
    );
    // marker 图标表一次装完，比每帧传 bytes 省（§3e）。
    await host.invoke(
      SiponMapCommands.registerAssets,
      encodeMarkerAssets(),
    );

    // 正常情况 onMapReady 在上面两条 invoke 返回前后就会到；超时兜底放行，
    // 避免原生异常时页面永远停在「等待地图」。
    const readyTimeout = Duration(seconds: 5);
    if (!ready.isCompleted) {
      await ready.future.timeout(readyTimeout, onTimeout: () {
        debugPrint('SiponMap: onMapReady timed out after $readyTimeout');
      });
    }
    _readyCompleter = null;
  }

  @override
  void detach() {
    final host = _host;
    if (host != null) {
      // 尽力通知原生销毁；通道可能已经没了，失败不必上抛。
      unawaited(
        host.invoke(SiponMapCommands.dispose).catchError((_) => null),
      );
    }
    super.detachCommon();
    _cancelSettleDebounce();
    _settlingViewport = null;
    _readyCompleter = null;
    _ready = false;
    _host = null;
  }

  @override
  Future<void> setStyle(MapBaseStyle style) async {
    final host = _host;
    if (host == null || !_ready) {
      return;
    }

    // 样式缓存全灭；帧缓存保留，切完原样重放。
    resetStyleCaches();
    await host.invoke(SiponMapCommands.setStyle, encodeStyle(style.id));

    // MapKit 没有 styleLoaded 事件：切换完成后自行「重置+重放」兜底
    // （§3b —— 若切配置真丢了 overlay/annotation，重放的 diff 会建回来）。
    await handleStyleLoaded();
  }

  @override
  void handleNativeEvent(String method, Object? arguments) {
    switch (method) {
      case SiponMapEvents.onMapReady:
        _ready = true;
        resetStyleCaches();
        _readyCompleter?.complete();
        // setup 之前页面就可能推过一帧（缓存在基类），这里负责真正落图。
        final frame = lastFrame;
        if (frame != null) {
          unawaited(performRender(frame));
        }
      case SiponMapEvents.onViewportSettled:
        final payload = parseViewportPayload(arguments);
        if (payload == null) {
          break;
        }
        // 原生惯性滚动会连发多次，语义与旧引擎的 idle 多连发同构：
        // 只留最新一份，去抖后在 handleViewportSettled 里回调页面。
        _settlingViewport = payload;
        latestZoom = payload.zoom;
        handleViewportSettledFastPath();
      case SiponMapEvents.onVenueTapped:
        final venueId = parseVenueTapped(arguments);
        if (venueId != null) {
          onVenueTapped(venueId);
        } else {
          // 解析不出 venueId 就当点在空白处，保持「有反应」的一致性。
          onBlankTapped();
        }
      case SiponMapEvents.onBlankTapped:
        onBlankTapped();
      case SiponMapEvents.onStyleLoaded:
        break; // MapKit 无此概念；该事件仅 Mapbox 回退分支使用。
      default:
        break;
    }
  }

  /// 去抖后用事件自带的视野数据回调页面，不再二次 readViewport。
  void handleViewportSettledFastPath() {
    _settleDebounce?.cancel();
    _settleDebounce = Timer(MapSceneController.idleDebounce, () {
      final payload = _settlingViewport;
      if (payload == null || !isAttached) {
        return;
      }
      _settlingViewport = null;
      onViewportSettled(
        MapViewport(
          bounds: MapBoundsBox(
            west: payload.west,
            south: payload.south,
            east: payload.east,
            north: payload.north,
          ),
          zoom: payload.zoom,
        ),
      );
    });
  }

  void _cancelSettleDebounce() {
    _settleDebounce?.cancel();
    _settleDebounce = null;
  }

  // ---------------------------------------------------------------- 视野与相机

  @override
  Future<MapViewport?> readViewport() async {
    final host = _host;
    if (host == null || !_ready) {
      return null;
    }

    try {
      final payload = parseViewportPayload(await host.invoke(
        SiponMapCommands.readViewport,
      ));
      if (payload == null) {
        // 相机还没就绪：退回整个中国，语义对齐旧版的 infiniteBounds 兜底。
        return const MapViewport(bounds: MapBoundsBox.china(), zoom: MapSceneController.cityZoom);
      }

      return MapViewport(
        bounds: MapBoundsBox(
          west: payload.west,
          south: payload.south,
          east: payload.east,
          north: payload.north,
        ),
        zoom: payload.zoom,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> easeForPaddingOnly() async {
    await _invokeIfReady(SiponMapCommands.applyStage, {
      'bottomPadding': cameraBottomPadding,
    });
  }

  @override
  Future<void> focusOn({
    required double longitude,
    required double latitude,
  }) {
    return _invokeIfReady(
      SiponMapCommands.focusOn,
      encodeCameraMove(
        longitude: longitude,
        latitude: latitude,
        zoom: MapSceneController.focusZoom,
        pitch: MapSceneController.focusPitch,
        bearing: MapSceneController.focusBearing,
        bottomPadding: cameraBottomPadding,
      )..['durationMs'] = MapSceneController.focusDuration.inMilliseconds,
    );
  }

  @override
  Future<void> flyToCity(String city, {required double zoom}) {
    final center = mapCenterForCity(city);

    return _invokeIfReady(
      SiponMapCommands.flyToCity,
      encodeCameraMove(
        longitude: center.longitude,
        latitude: center.latitude,
        zoom: zoom,
        pitch: MapSceneController.defaultPitch,
        bearing: MapSceneController.defaultBearing,
        bottomPadding: cameraBottomPadding,
      )..['durationMs'] = 780,
    );
  }

  // -------------------------------------------------------------------- 渲染

  @override
  Future<void> performRender(MapSceneFrame frame) {
    // 一条消息整帧下发，原生按 id diff；列表传全量（协议约定见
    // encodeRenderFrame）。分层指纹在单消息协议下没有切分点，
    // 整帧指纹已经在基类 [render] 里把门了。
    return _invokeIfReady(
      SiponMapCommands.renderFrame,
      encodeRenderFrame(frame, zoom: latestZoom),
    );
  }

  Future<void> _invokeIfReady(String method, [Map<String, Object?>? args]) async {
    final host = _host;
    if (host == null || !_ready) {
      return;
    }

    try {
      await host.invoke(method, args ?? const {});
    } catch (error) {
      // 引擎刚销毁或通道断开时静默丢弃这一条指令，与旧行为一致。
      assert(() {
        debugPrint('SiponMap: invoke($method) failed: $error');
        return true;
      }());
    }
  }
}
