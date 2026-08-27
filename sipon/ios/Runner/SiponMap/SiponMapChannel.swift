import Foundation
import MapKit

/// MethodChannel 协议的唯一登记处：通道名、方法名、载荷解析与组装。
/// 与 Dart 侧 `sipon_map_protocol.dart` 一一对应（迁移指南 §3），
/// 字段一律 snake_case，JSON 标准编解码。
enum SiponMapProtocol {

  // 通道
  static let viewType = "sipon/mapkit"
  static func channelName(viewId: Int64) -> String { "sipon/mapkit_\(viewId)" }

  // Dart → 原生
  enum Command {
    static let setup = "setup"
    static let setStyle = "setStyle"
    static let setGestures = "setGestures"
    static let readViewport = "readViewport"
    static let flyToCity = "flyToCity"
    static let focusOn = "focusOn"
    static let applyStage = "applyStage"
    static let renderFrame = "renderFrame"
    static let registerAssets = "registerAssets"
    static let dispose = "dispose"
  }

  // 原生 → Dart
  enum Event {
    static let onMapReady = "onMapReady"
    static let onViewportSettled = "onViewportSettled"
    static let onVenueTapped = "onVenueTapped"
    static let onBlankTapped = "onBlankTapped"
  }

  // -------------------------------------------------------------- 参数解析

  static func dict(_ any: Any?) -> [String: Any]? {
    any as? [String: Any]
  }

  static func string(_ dict: [String: Any], _ key: String) -> String? {
    if let value = dict[key] as? String { return value }
    if let number = dict[key] as? NSNumber { return number.stringValue }
    return nil
  }

  static func double(_ dict: [String: Any], _ key: String, fallback: Double) -> Double {
    if let value = dict[key] as? Double { return value }
    if let value = dict[key] as? Int { return Double(value) }
    if let value = dict[key] as? NSNumber { return value.doubleValue }
    return fallback
  }

  /// 相机指令共用形状：lon/lat/zoom/pitch/bearing/bottomPadding
  /// （durationMs 随指令下发，MapKit 动画时长不可控，原生忽略——决策 D3）。
  struct CameraMove {
    let longitude: Double
    let latitude: Double
    let zoom: Double
    let pitch: Double
    let bearing: Double
    let bottomPadding: Double

    init(dict: [String: Any]) {
      longitude = SiponMapProtocol.double(dict, "lng", fallback: 121.4712)
      latitude = SiponMapProtocol.double(dict, "lat", fallback: 31.2227)
      zoom = SiponMapProtocol.double(dict, "zoom", fallback: 15.05)
      pitch = SiponMapProtocol.double(dict, "pitch", fallback: 24)
      bearing = SiponMapProtocol.double(dict, "bearing", fallback: -12)
      bottomPadding = SiponMapProtocol.double(dict, "bottomPadding", fallback: 0)
    }
  }

  /// renderFrame 里的一颗圆点。
  struct CirclePoint {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let category: String
    let venueId: String?

    static func parse(_ raw: [String: Any]) -> CirclePoint? {
      guard let id = SiponMapProtocol.string(raw, "id") else { return nil }
      return CirclePoint(
        id: id,
        coordinate: CLLocationCoordinate2D(
          latitude: SiponMapProtocol.double(raw, "lat", fallback: .nan),
          longitude: SiponMapProtocol.double(raw, "lng", fallback: .nan)
        ),
        category: SiponMapProtocol.string(raw, "category") ?? "pub",
        venueId: SiponMapProtocol.string(raw, "venueId")
      )
    }
  }

  /// renderFrame 里的一枚文字标签 marker。
  struct MarkerSpec {
    let venueId: String
    let label: String
    let coordinate: CLLocationCoordinate2D
    let category: String

    static func parse(_ raw: [String: Any]) -> MarkerSpec? {
      guard let venueId = SiponMapProtocol.string(raw, "venueId"),
            !venueId.isEmpty else { return nil }
      return MarkerSpec(
        venueId: venueId,
        label: SiponMapProtocol.string(raw, "label") ?? "",
        coordinate: CLLocationCoordinate2D(
          latitude: SiponMapProtocol.double(raw, "lat", fallback: .nan),
          longitude: SiponMapProtocol.double(raw, "lng", fallback: .nan)
        ),
        category: SiponMapProtocol.string(raw, "category") ?? "pub"
      )
    }
  }

  struct SelectedSpec {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let category: String
    let venueId: String?
  }

  /// 整帧解析结果。列表约定为全量下发，原生按 id diff。
  struct Frame {
    let showsPoints: Bool
    let showsHeatmap: Bool
    let circleFade: Double
    let circles: [CirclePoint]
    let heatSamples: [SiponMapGeometry.HeatSample]
    let markers: [MarkerSpec]
    let selected: SelectedSpec?

    static func parse(_ arguments: Any?) -> Frame? {
      guard let payload = SiponMapProtocol.dict(arguments) else { return nil }

      // 图层三档名与 Dart MapLayerMode.name 一致；
      // 决策在 Dart 算好，这里只认最终模式。
      let layerMode = SiponMapProtocol.string(payload, "layerMode") ?? "pointsAndHeatmap"

      var circles: [CirclePoint] = []
      if let rawList = payload["circles"] as? [[String: Any]] {
        circles = rawList.compactMap(CirclePoint.parse).filter {
          $0.coordinate.latitude.isFinite && $0.coordinate.longitude.isFinite
        }
      }

      var samples: [SiponMapGeometry.HeatSample] = []
      if let rawList = payload["heatmap"] as? [[String: Any]] {
        for raw in rawList {
          let lat = SiponMapProtocol.double(raw, "lat", fallback: .nan)
          let lng = SiponMapProtocol.double(raw, "lng", fallback: .nan)
          guard lat.isFinite, lng.isFinite else { continue }
          samples.append(SiponMapGeometry.HeatSample(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            weight: SiponMapProtocol.double(raw, "weight", fallback: 0)
          ))
        }
      }

      var markers: [MarkerSpec] = []
      if let rawList = payload["markers"] as? [[String: Any]] {
        markers = rawList.compactMap(MarkerSpec.parse).filter {
          $0.coordinate.latitude.isFinite && $0.coordinate.longitude.isFinite
        }
      }

      var selected: SelectedSpec?
      if let rawSelected = SiponMapProtocol.dict(payload["selected"]) {
        let lat = SiponMapProtocol.double(rawSelected, "lat", fallback: .nan)
        let lng = SiponMapProtocol.double(rawSelected, "lng", fallback: .nan)
        if lat.isFinite && lng.isFinite {
          selected = SelectedSpec(
            id: SiponMapProtocol.string(rawSelected, "id") ?? "selected",
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            category: SiponMapProtocol.string(rawSelected, "category") ?? "pub",
            venueId: SiponMapProtocol.string(rawSelected, "venueId")
          )
        }
      }

      return Frame(
        showsPoints: layerMode != "heatmapOnly",
        showsHeatmap: layerMode != "pointsOnly",
        circleFade: SiponMapProtocol.double(payload, "circleFade", fallback: 0),
        circles: circles,
        heatSamples: samples,
        markers: markers,
        selected: selected
      )
    }
  }

  // -------------------------------------------------------------- 返回组装

  /// readViewport / onViewportSettled 共用的视野字典。
  static func viewportArguments(
    region: MKCoordinateRegion,
    zoom: Double
  ) -> [String: Any] {
    [
      "west": region.center.longitude - region.span.longitudeDelta / 2,
      "south": region.center.latitude - region.span.latitudeDelta / 2,
      "east": region.center.longitude + region.span.longitudeDelta / 2,
      "north": region.center.latitude + region.span.latitudeDelta / 2,
      "zoom": zoom,
    ]
  }

  static func venueTappedArguments(venueId: String) -> [String: Any] {
    ["venueId": venueId]
  }
}
