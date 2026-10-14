import CoreMotion
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let stickerMotion = StickerMotionStream()
  private var languageChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerSiponLanguage(with: engineBridge.pluginRegistry)
    registerSiponMapView(with: engineBridge.pluginRegistry)
    registerSiponSticker(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "StickerMotion"
    ) {
      FlutterEventChannel(
        name: "sipon/sticker_motion",
        binaryMessenger: registrar.messenger()
      ).setStreamHandler(stickerMotion)
    }
  }

  /// MapKit 与 Flutter 使用同一个应用语言，由 iOS 的应用语言设置管理。
  /// 原生 MapKit 没有单独切换底图语言的公开接口。
  private func registerSiponLanguage(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "SiponLanguage") else { return }
    let channel = FlutterMethodChannel(
      name: "sipon/language",
      binaryMessenger: registrar.messenger()
    )
    languageChannel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getLanguage":
        // Locale.preferredLanguages 是设备偏好；Bundle 才反映本应用实际语言。
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        result(language.hasPrefix("zh") ? "zh" : "en")
      case "openSettings":
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          result(false)
          return
        }
        // 用户选择语言后，iOS 会重新启动应用与 MapKit。
        UIApplication.shared.open(url, options: [:]) { opened in
          result(opened)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func registerSiponSticker(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "SiponStickerPlugin") else { return }
    SiponStickerPlugin.register(with: registrar)
  }

  /// 注册自封装的 MKMapView 平台视图（MapKit 迁移，见 docs/mapkit_migration_guide.md）。
  /// Flutter 隐式引擎完成初始化后、任何 UiKitView 构建之前完成。
  private func registerSiponMapView(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "SiponMapFactory") else { return }
    let factory = SiponMapFactory(messenger: registrar.messenger())
    // 当前 SDK 支持 eager / waitUntilTouchesEnded。让原生识别器收到完整
    // 触摸序列，避免 Flutter 拒绝手势时在 began 后立刻中断 MapKit。
    registrar.register(
      factory,
      withId: SiponMapProtocol.viewType,
      gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicyWaitUntilTouchesEnded
    )
  }
}

// 只在贴纸池订阅期间采集手机重力方向。
private final class StickerMotionStream: NSObject, FlutterStreamHandler {
  private let manager = CMMotionManager()

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard manager.isDeviceMotionAvailable else {
      events(FlutterEndOfEventStream)
      return nil
    }

    manager.deviceMotionUpdateInterval = 1.0 / 30.0

    manager.startDeviceMotionUpdates(to: .main) { motion, error in
      guard let gravity = motion?.gravity, error == nil else {
        return
      }

      let orientation = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }?
        .interfaceOrientation

      switch orientation {
      case .landscapeLeft:
        events([-gravity.y, -gravity.x])
      case .landscapeRight:
        events([gravity.y, gravity.x])
      case .portraitUpsideDown:
        events([-gravity.x, gravity.y])
      default:
        events([gravity.x, -gravity.y])
      }
    }

    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager.stopDeviceMotionUpdates()
    return nil
  }

  deinit {
    manager.stopDeviceMotionUpdates()
  }
}
