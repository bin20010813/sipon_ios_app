import 'package:flutter/material.dart';
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
