import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerSiponMapView(with: engineBridge.pluginRegistry)
  }

  /// 注册自封装的 MKMapView 平台视图（MapKit 迁移，见 docs/mapkit_migration_guide.md）。
  /// Flutter 隐式引擎完成初始化后、任何 UiKitView 构建之前完成。
  private func registerSiponMapView(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "SiponMapFactory") else { return }
    let factory = SiponMapFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: SiponMapProtocol.viewType)
  }
}
