import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
// PlatformViewHitTestBehavior 在 rendering 层，material.dart 不转出它。
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'sipon_map_host.dart';
import 'sipon_map_protocol.dart';

/// MapKit 引擎的 Dart 侧宿主：把 MethodChannel 包成 [SiponMapHost]。
///
/// 原生的反向调用（[SiponMapEvents] 的四个方法）从构造起就挂在本对象上，
/// 控制器 attach 时通过 [SiponMapHost.onNativeCall] 认领；认领前到达的事件
/// 由 [SiponEventSink] 缓存补发。
class ChannelMapHost implements SiponMapHost {
  ChannelMapHost(this._channel) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  final SiponEventSink _sink = SiponEventSink();

  Future<dynamic> _handleNativeCall(MethodCall call) async {
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
  });

  /// 初始底图档位（`MapBaseStyle.id`）。Kit 版等 attach 后由 setup 下发；
  /// 回退分支在平台视图创建时就用对应 URI 初始化。
  final String initialStyleId;

  /// 平台视图就绪时回调一次，附上引擎宿主。页面在回调里执行 attach。
  final void Function(SiponMapHost host) onHostReady;

  @override
  State<SiponMapWidget> createState() => _SiponMapWidgetState();
}

class _SiponMapWidgetState extends State<SiponMapWidget> {
  ChannelMapHost? _kitHost;

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: kSiponMapViewType,
      // opaque：空白像素区域也算命中平台视图。它只管「命中」，不管手势归属；
      // 手势竞争由下面的 Eager 识别器解决——没有它，平台视图在竞技场里从不
      // 主动认领手势，外层的滚动 / BottomSheet 拖拽一胜出，原生地图的捏合、
      // 拖动就被 cancel（表现即「地图不能缩放」，见
      // docs/mapkit-gesture-conflict-fix-plan-2026-09-19.md）。
      hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      // 构建机上的 Flutter 已移除 UiKitView 的 gestureBlockingPolicy 参数：
      // 旧版默认 eager 依赖的 blocking recognizer 整套机制一并删除，含 iOS 26
      // 上卡在 failed 状态不再复位的缺陷（flutter/flutter#191267、#175099）。
      // 现在触摸归属只由 hitTestBehavior + 下面的 gestureRecognizers 决定。
      // Eager 识别器在竞技场里立即认领落在地图上的每一次触摸，原生
      // MKMapView 从 touchesBegan 起实时拿到事件流。代价是地图区域内的
      // Flutter 手势全部让位（点空白收面板走原生 onBlankTapped，不受影响）。
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
      onPlatformViewCreated: (viewId) {
        // 处理器必须在创建回调里立刻挂上，否则原生首发事件会丢；
        // 真正的 onMapReady 由 setup 命令触发，见原生侧实现。
        final host = ChannelMapHost(MethodChannel(siponMapChannelName(viewId)));
        _kitHost = host;
        widget.onHostReady(host);
      },
    );
  }

  @override
  void dispose() {
    _kitHost?.dispose();
    _kitHost = null;
    super.dispose();
  }
}
