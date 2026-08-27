import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    registerSiponMapView()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// 注册自封装的 MKMapView 平台视图（MapKit 迁移，见 docs/mapkit_migration_guide.md）。
  /// 必须在任何 Flutter 页面构建 UiKitView 之前完成。
  private func registerSiponMapView() {
    guard let registrar = registrar(forPlugin: "SiponMapFactory") else { return }
    let factory = SiponMapFactory(messenger: registrar.messenger())
    registrar.register(factory, forView: SiponMapProtocol.viewType)
  }
}
