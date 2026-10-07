import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
// PlatformViewHitTestBehavior 在 rendering 层，material.dart 不转出它。
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../platform/map_engine.dart';
import '../platform/petal_map_platform.dart';
import '../platform/sipon_map_host.dart';
import '../platform/sipon_map_protocol.dart';

/// MapKit 引擎的 Dart 侧宿主：把 MethodChannel 包成 [SiponMapHost]。
///
/// 原生的反向调用（[SiponMapEvents] 的四个方法）从构造起就挂在本对象上，
/// 控制器 attach 时通过 [SiponMapHost.onNativeCall] 认领；认领前到达的事件
/// 由 [SiponEventSink] 缓存补发。
class ChannelMapHost implements SiponMapHost {
  ChannelMapHost(this._channel, {this.onEvent}) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  final void Function(String method, Object? arguments)? onEvent;
  String get diagnosticName => _channel.name;
  final SiponEventSink _sink = SiponEventSink();

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    onEvent?.call(call.method, call.arguments);
    _sink.emit(call.method, call.arguments);
    return null;
  }

  @override
  Future<Object?> invoke(
    String method, [
    Map<String, Object?> args = const {},
  ]) {
    return _channel.invokeMethod(method, args.isEmpty ? null : args);
  }

  @override
  void onNativeCall(void Function(String method, Object? arguments) handler) {
    _sink.attachHandler(handler);
  }

  /// 平台视图销毁时调用，断开通道处理器避免泄漏。
  void dispose() {
    _sink.detachHandler();
    _channel.setMethodCallHandler(null);
  }
}

/// 地图页的唯一入口 Widget：内部画自封装的 MKMapView，并把 MethodChannel
/// 包成 [SiponMapHost] 交给页面。
class SiponMapWidget extends StatefulWidget {
  const SiponMapWidget({
    super.key,
    required this.initialStyleId,
    required this.onHostReady,
    this.compassTopInset,
    this.showsUserHeading = false,
    this.engine,
  });

  /// 初始底图档位（`MapBaseStyle.id`）。Kit 版等 attach 后由 setup 下发；
  /// 回退分支在平台视图创建时就用对应 URI 初始化。
  final String initialStyleId;

  /// 原生指北针距地图顶部的距离；null 表示不显示（用于小地图）。
  final double? compassTopInset;

  /// 主地图显示带朝向的个人位置点；小地图沿用 MapKit 系统位置点。
  final bool showsUserHeading;

  final MapEngine? engine;

  /// 平台视图就绪时回调一次，附上引擎宿主。页面在回调里执行 attach。
  final void Function(SiponMapHost host) onHostReady;

  @override
  State<SiponMapWidget> createState() => _SiponMapWidgetState();
}

class _SiponMapWidgetState extends State<SiponMapWidget> {
  ChannelMapHost? _mapHost;
  int? _viewId;
  Brightness? _brightness;
  String? _nativeError;
  int _generation = 0;
  final Map<int, Offset> _pointerStarts = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_brightness == brightness) return;
    _brightness = brightness;
    final host = _mapHost;
    if (host != null) {
      host.invoke(SiponMapCommands.setAppearance, encodeAppearance(brightness));
    }
  }

  void _logPointer(PointerEvent event, String phase) {
    if (!kDebugMode) return;
    if (phase == 'DOWN') _pointerStarts[event.pointer] = event.position;
    final start = _pointerStarts[event.pointer];
    final travel = start == null ? 0.0 : (event.position - start).distance;
    debugPrint(
      '[SiponMapMotion] t=${DateTime.now().toIso8601String()} '
      'view=$_viewId MAP_POINTER_$phase pointer=${event.pointer} '
      'position=${event.localPosition} displacementPx=${travel.toStringAsFixed(1)}',
    );
    if (phase != 'DOWN') _pointerStarts.remove(event.pointer);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _brightness ?? Theme.of(context).brightness;
    final engine = widget.engine ?? selectMapEngine();
    if (engine == MapEngine.unsupported) {
      return const Center(child: Text('此平台暂不支持地图'));
    }
    if (engine == MapEngine.petal && PetalMapPlatform.viewBuilder == null) {
      assert(() {
        debugPrint(
          'SiponMap: missing PetalMapPlatform builder; use ohos/flutter/main.dart',
        );
        return true;
      }());
      return const Center(child: Text('地图暂时无法加载'));
    }
    final params = <String, Object?>{
      'compassTopInset': widget.compassTopInset,
      'showsUserHeading': widget.showsUserHeading,
      ...encodeAppearance(brightness),
    };
    final gestures = <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
    };
    final map = engine == MapEngine.petal
        ? PetalMapPlatform.viewBuilder!(
            key: ValueKey(_generation),
            creationParams: params,
            gestureRecognizers: gestures,
            onPlatformViewCreated: (viewId) =>
                _onCreated(engine, viewId, brightness),
          )
        : engine == MapEngine.mapKit
        ? UiKitView(
            viewType: kSiponMapViewType,
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
            // opaque：空白像素区域也算命中平台视图。它只管「命中」，不管手势归属；
            // 手势竞争由下面的 Eager 识别器解决——没有它，平台视图在竞技场里从不
            // 主动认领手势，外层的滚动 / BottomSheet 拖拽一胜出，原生地图的捏合、
            // 拖动就被 cancel（表现即「地图不能缩放」，见
            // docs/mapkit-gesture-conflict-fix-plan-2026-09-19.md）。
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            // Dart 竞技场中的 Eager 与 iOS 注册工厂的阻塞策略是两个层次。
            // 这里认领地图范围内的触摸；原生侧使用 waitUntilTouchesEnded，
            // 在 Flutter 拒绝手势时仍让 MapKit 收到完整触摸序列。
            gestureRecognizers: gestures,
            onPlatformViewCreated: (viewId) =>
                _onCreated(engine, viewId, brightness),
          )
        : PlatformViewLink(
            key: ValueKey(_generation),
            viewType: kSiponTiandituViewType,
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: gestures,
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            ),
            onCreatePlatformView: (parameters) {
              final controller = PlatformViewsService.initSurfaceAndroidView(
                id: parameters.id,
                viewType: kSiponTiandituViewType,
                layoutDirection: TextDirection.ltr,
                creationParams: params,
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => parameters.onFocusChanged(true),
              );
              controller.addOnPlatformViewCreatedListener(
                parameters.onPlatformViewCreated,
              );
              controller.addOnPlatformViewCreatedListener(
                (viewId) => _onCreated(engine, viewId, brightness),
              );
              controller.create();
              return controller;
            },
          );
    final content = _nativeError != null
        ? Stack(
            fit: StackFit.expand,
            children: [
              map,
              ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.map_outlined, size: 30),
                      const SizedBox(height: 8),
                      Text(_nativeError!, textAlign: TextAlign.center),
                      TextButton(
                        onPressed: () => setState(() {
                          _nativeError = null;
                          ++_generation;
                        }),
                        child: const Text('重试地图'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )
        : map;
    // Listener 只观察原始事件，不加入手势竞技场或改变地图手势策略。
    if (!kDebugMode) return content;
    return Listener(
      onPointerDown: (event) => _logPointer(event, 'DOWN'),
      onPointerUp: (event) => _logPointer(event, 'UP'),
      onPointerCancel: (event) => _logPointer(event, 'CANCEL'),
      child: content,
    );
  }

  void _onCreated(MapEngine engine, int viewId, Brightness brightness) {
    if (!mounted) return;
    _viewId = viewId;
    final oldHost = _mapHost;
    oldHost?.dispose();
    final host = ChannelMapHost(
      MethodChannel(siponChannelName(engine, viewId)),
      onEvent: (method, arguments) {
        if (!mounted || _viewId != viewId) {
          return;
        }
        if (method == SiponMapEvents.onMapError) {
          final args = arguments is Map ? arguments : const {};
          setState(() => _nativeError = '${args['message'] ?? '地图暂时无法加载，请重试'}');
        } else if (method == SiponMapEvents.onMapReady &&
            _nativeError != null) {
          setState(() => _nativeError = null);
        }
      },
    );
    _mapHost = host;
    host.invoke(
      SiponMapCommands.setAppearance,
      encodeAppearance(_brightness ?? brightness),
    );
    widget.onHostReady(host);
  }

  @override
  void dispose() {
    _mapHost?.dispose();
    _mapHost = null;
    super.dispose();
  }
}
