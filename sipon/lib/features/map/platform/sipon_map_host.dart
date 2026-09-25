import 'dart:async';

/// Dart 侧共用的地图句柄。
///
/// - MapKit 实现（`ChannelMapHost`，见 `sipon_map_widget.dart`）：
///   [invoke] 走 MethodChannel 到原生；[onNativeCall] 注册的是
///   原生反向调用的唯一入口。
abstract class SiponMapHost {
  /// 向地图引擎下发一条指令。方法名与载荷见 `SiponMapProtocol`。
  ///
  /// 返回原生的应答值（目前只有 `readViewport` 有返回）；没有应答就是 null。
  Future<Object?> invoke(String method, [Map<String, Object?> args]);

  /// 注册原生 → Dart 的统一事件入口。控制器在 attach 时调用一次；
  /// 注册之前到达的事件由宿主缓存并在注册后补发，保证 `onMapReady`
  /// 这类最早的事件不丢。
  void onNativeCall(void Function(String method, Object? arguments) handler);
}

/// 把一条事件派发给当前登记的处理器；没人登记就先攒着。
class SiponEventSink {
  final List<MapEntry<String, Object?>> _pending = [];
  void Function(String method, Object? arguments)? _handler;

  void attachHandler(void Function(String method, Object? arguments)? handler) {
    _handler = handler;
    if (handler != null && _pending.isNotEmpty) {
      // 补发早于注册到达的事件。copy 后清空，避免补发过程再入队造成重放。
      final buffered = List<MapEntry<String, Object?>>.of(_pending);
      _pending.clear();
      for (final event in buffered) {
        handler(event.key, event.value);
      }
    }
  }

  void detachHandler() {
    _handler = null;
    _pending.clear();
  }

  void emit(String method, Object? arguments) {
    final handler = _handler;
    if (handler == null) {
      if (_pending.length < 32) {
        _pending.add(MapEntry(method, arguments));
      }
      return;
    }

    // 控制器回调里可能同步触发页面 setState，异步化保证不在平台消息泵里执行。
    Timer.run(() => handler(method, arguments));
  }
}
