import CoreImage
import Flutter
import UIKit
import Vision

final class SiponStickerPlugin: NSObject, FlutterPlugin {
  private static let channelName = "sipon/sticker_cutout"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(SiponStickerPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "generateSticker" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let sourcePath = arguments["sourcePath"] as? String,
      !sourcePath.isEmpty
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "sourcePath is required.",
          details: nil
        )
      )
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      self.generateSticker(sourcePath: sourcePath, result: result)
    }
  }

  private func generateSticker(
    sourcePath: String,
    result: @escaping FlutterResult
  ) {
    let sourceURL = URL(fileURLWithPath: sourcePath)
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      complete(
        result,
        value: FlutterError(
          code: "source_missing",
          message: "Selected photo no longer exists.",
          details: nil
        )
      )
      return
    }

    let savedPhotoURL: URL
    let stickerURL: URL
    do {
      let directory = try stickerDirectory()
      let identifier = UUID().uuidString.lowercased()
      let sourceExtension = sourceURL.pathExtension.isEmpty
        ? "jpg"
        : sourceURL.pathExtension.lowercased()
      savedPhotoURL = directory
        .appendingPathComponent(identifier + "_original")
        .appendingPathExtension(sourceExtension)
      stickerURL = directory
        .appendingPathComponent(identifier + "_sticker")
        .appendingPathExtension("png")
      try FileManager.default.copyItem(at: sourceURL, to: savedPhotoURL)
    } catch {
      complete(
        result,
        value: FlutterError(
          code: "storage_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
      return
    }

    guard #available(iOS 17.0, *) else {
      complete(
        result,
        value: payload(
          photoURL: savedPhotoURL,
          stickerURL: nil,
          status: "unsupported"
        )
      )
      return
    }

    do {
      let handler = VNImageRequestHandler(url: savedPhotoURL, options: [:])
      let request = VNGenerateForegroundInstanceMaskRequest()
      try handler.perform([request])

      guard
        let observation = request.results?.first,
        !observation.allInstances.isEmpty
      else {
        complete(
          result,
          value: payload(
            photoURL: savedPhotoURL,
            stickerURL: nil,
            status: "no_subject"
          )
        )
        return
      }

      let maskedBuffer = try observation.generateMaskedImage(
        ofInstances: observation.allInstances,
        from: handler,
        croppedToInstancesExtent: true
      )
      let cutoutImage = CIImage(cvPixelBuffer: maskedBuffer)
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        ?? CGColorSpaceCreateDeviceRGB()
      let context = CIContext(options: [.cacheIntermediates: false])
      try context.writePNGRepresentation(
        of: cutoutImage,
        to: stickerURL,
        format: .RGBA8,
        colorSpace: colorSpace
      )

      complete(
        result,
        value: payload(
          photoURL: savedPhotoURL,
          stickerURL: stickerURL,
          status: "processed"
        )
      )
    } catch {
      complete(
        result,
        value: payload(
          photoURL: savedPhotoURL,
          stickerURL: nil,
          status: "processing_failed"
        )
      )
    }
  }

  private func stickerDirectory() throws -> URL {
    let root = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = root.appendingPathComponent(
      "DrinkStickers",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private func payload(
    photoURL: URL,
    stickerURL: URL?,
    status: String
  ) -> [String: Any] {
    return [
      "photoPath": photoURL.path,
      "stickerPath": (stickerURL?.path as Any?) ?? NSNull(),
      "status": status,
    ]
  }

  private func complete(_ result: @escaping FlutterResult, value: Any) {
    DispatchQueue.main.async {
      result(value)
    }
  }
}
