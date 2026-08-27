import Flutter
import UIKit

/// `sipon/mapkit` 平台视图的工厂。注册发生在 AppDelegate 启动流程里
/// （registrar.register(forView:)），每个平台视图实例对应一个 SiponMapView。
final class SiponMapFactory: NSObject, FlutterPlatformViewFactory {

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments: Any?
  ) -> FlutterPlatformView {
    SiponMapView(frame: frame, viewId: viewId, messenger: messenger)
  }

  /// 老版本 Flutter 需要 implements ->NSObjectProtocol 的 createArgsCodec；
  /// 标准编解码即可满足 Dart 侧 JSON 参数的收发。
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}
