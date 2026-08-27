import Foundation
import MapKit

/// 纯函数几何换算：Web Mercator 的 zoom ↔ span、padding 折算、圆点/高亮半径
/// 插值、热力格网聚合。全部无状态、无 UIKit 依赖（除 MapKit 坐标类型外），
/// 配 RunnerTests 里的 SiponMapGeometryTests 覆盖（迁移指南 §5）。
enum SiponMapGeometry {

  /// Web Mercator 基准 tile 尺寸（pt）。
  static let tileSize = 256.0

  /// 赤道周长（米），meters-per-pixel 换算基准。
  static let earthEquatorMeters = 40_075_016.686

  // MARK: - zoom ↔ 视野跨度

  /// zoom → 经度跨度。256 是墨卡托基准 tile 尺寸，`width` 是视口宽（pt）。
  static func longitudeDelta(zoom: Double, width: CGFloat) -> Double {
    guard zoom.isFinite, zoom >= 0, width > 0 else { return .greatestFiniteMagnitude }
    return 360 * Double(width) / (tileSize * pow(2, zoom))
  }

  /// region → zoom（读视野时反推）。
  static func zoom(longitudeDelta delta: Double, width: CGFloat) -> Double {
    guard delta.isFinite, delta > 0, width > 0 else { return 0 }
    return log2(360 * Double(width) / (tileSize * delta))
  }

  /// latDelta 近似按纵横比给（业务只覆盖中国境内，低纬度够用，
  /// 不做极区畸变修正——见迁移指南 §3h）。
  static func span(zoom: Double, size: CGSize) -> MKCoordinateSpan {
    let lon = longitudeDelta(zoom: zoom, width: size.width)
    let heightRatio = size.width > 0 ? Double(size.height / size.width) : 1
    return MKCoordinateSpan(latitudeDelta: lon * heightRatio, longitudeDelta: lon)
  }

  // MARK: - 米每像素与相机距离

  /// 给定纬度与 zoom 的地面分辨率（米/pt）。纬度钳制在墨卡托有效范围内。
  static func metersPerPixel(lat: Double, zoom: Double) -> Double {
    guard lat.isFinite, zoom.isFinite else { return 1 }
    let clampedLat = max(-85.05, min(85.05, lat))
    return earthEquatorMeters * cos(clampedLat * .pi / 180) / (tileSize * pow(2, zoom))
  }

  /// MKMapCamera.fromDistance 的近似值：zoom 隐含的地面高度按视口高折算。
  /// 透视俯仰会让真实可见范围略大于该值，属于可感知但可接受的近似（决策 D3 同级）。
  static func cameraDistance(lat: Double, zoom: Double, viewportHeight: CGFloat) -> Double {
    let mpp = metersPerPixel(lat: lat, zoom: zoom)
    let height = viewportHeight > 0 ? Double(viewportHeight) : 400
    return max(mpp * height, 50)
  }

  // MARK: - padding → 中心点折算（§5.2）

  /// Mapbox 的 `padding.bottom` 让目标点出现在「去掉底部 padding 后的区域」中心；
  /// MapKit 无此概念，折算成把真实中心向南移。`bottomPx` 是本次相机调用
  /// 显式携带的 padding 下边距。
  static func center(
    lat: Double,
    lng: Double,
    shiftingUpBy bottomPx: Double,
    zoom: Double
  ) -> CLLocationCoordinate2D {
    guard bottomPx > 0, bottomPx.isFinite else {
      return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    let mpp = metersPerPixel(lat: lat, zoom: zoom)
    guard mpp.isFinite, mpp > 0 else {
      return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    let deltaLat = bottomPx * mpp / 111_320.0
    // 南移 → 目标点在屏幕上移进「面板以上」的区域中心。
    return CLLocationCoordinate2D(latitude: lat - deltaLat, longitude: lng)
  }

  // MARK: - 半径插值（对照原 zoom 表达式速查表 §5.3）

  /// 分段线性插值；超出两端钳制到端点。
  static func interpolate(_ stops: [(Double, Double)], at value: Double) -> Double {
    precondition(!stops.isEmpty)
    if value <= stops.first!.0 { return stops.first!.1 }
    if value >= stops.last!.0 { return stops.last!.1 }

    for index in 1..<stops.count {
      let (x0, y0) = stops[index - 1]
      let (x1, y1) = stops[index]
      if value <= x1 {
        let t = x1 > x0 ? (value - x0) / (x1 - x0) : 0
        return y0 + (y1 - y0) * t
      }
    }
    return stops.last!.1
  }

  static func circleRadius(zoom: Double) -> CGFloat {
    // 圆点：9→4pt、13→7pt、16→11pt。
    CGFloat(interpolate([(9, 4), (13, 7), (16, 11)], at: zoom))
  }

  static func selectionHaloRadius(zoom: Double) -> CGFloat {
    // 高亮光环：9→6pt、13→8pt、16→12pt。
    CGFloat(interpolate([(9, 6), (13, 8), (16, 12)], at: zoom))
  }

  static func selectionCoreRadius(zoom: Double) -> CGFloat {
    // 高亮实心核：9→3.5pt、13→5pt、16→7.5pt。
    CGFloat(interpolate([(9, 3.5), (13, 5), (16, 7.5)], at: zoom))
  }

  // MARK: - 淡入曲线（§5.3）

  static let handoffZoom = 12.0          // 对齐 Dart 的 mapHeatmapHandoffZoom
  static let restoredZoom = 13.2         // 对齐 mapPointsRestoredZoom
  static let fullOpacity = 0.92          // 对齐 mapCircleFullOpacity

  /// 进页的初始城市级视野（对齐 Dart MapSceneController.cityZoom）。
  static let initialCityZoom = 11.8

  /// handoff → restored 区间内圆点的当前透明度；区间外截断。
  /// 由 Dart 与原生各持同一份常量：Dart 在整帧下发时算一次（协议字段
  /// circleFade），原生在捏合过程中按最新缩放连续插值保证平滑。
  static func circleFade(zoom: Double, heatmapArmed: Bool) -> Double {
    guard heatmapArmed else { return fullOpacity }
    guard zoom.isFinite else { return 0 }
    if zoom <= handoffZoom { return 0 }
    if zoom >= restoredZoom { return fullOpacity }
    return (zoom - handoffZoom) / (restoredZoom - handoffZoom) * fullOpacity
  }

  // MARK: - 热力格网聚合（§3d 降级方案）

  /// 一条热力采样点（对应协议里的 heatmap 数组项）。
  struct HeatSample {
    let coordinate: CLLocationCoordinate2D
    let weight: Double
  }

  /// 聚合后的密度格标识（格网坐标）。
  struct GridKey: Hashable {
    let column: Int
    let row: Int
  }

  /// 单个密度格：聚合质心坐标 + 归一化密度（0...1）+ 视觉半径（米）。
  struct DensityCell {
    let coordinate: CLLocationCoordinate2D
    let density: Double
    let radiusMeters: Double
  }

  /// 把全量热力点按格网聚合成密度格。cell 边长 ≈ 300m × (12/zoom)，
  /// 密度归一化以旧版 weight 表达式 [0..8] → [0..1] 为基准。
  /// 参数留在常量里便于调优（决策 D1）。
  static func aggregateHeatmap(
    _ samples: [HeatSample],
    zoom: Double,
    baseCellMeters: Double = 300,
    maxWeight: Double = 8
  ) -> [GridKey: DensityCell] {
    guard !samples.isEmpty else { return [:] }

    let clampedZoom = max(6, min(16, zoom.isFinite ? zoom : 11.8))
    let cellMeters = baseCellMeters * (12 / clampedZoom)
    let degreesPerCell = cellMeters / 111_320.0

    var sumByCell: [GridKey: (latSum: Double, lngSum: Double, weightSum: Double, count: Int)] = [:]
    for sample in samples {
      guard sample.coordinate.latitude.isFinite,
            sample.coordinate.longitude.isFinite else { continue }
      let column = Int(floor(sample.coordinate.longitude / degreesPerCell))
      let row = Int(floor(sample.coordinate.latitude / degreesPerCell))
      let key = GridKey(column: column, row: row)
      var bucket = sumByCell[key] ?? (0, 0, 0, 0)
      bucket.latSum += sample.coordinate.latitude
      bucket.lngSum += sample.coordinate.longitude
      bucket.weightSum += sample.weight
      bucket.count += 1
      sumByCell[key] = bucket
    }

    var cells: [GridKey: DensityCell] = [:]
    for (key, bucket) in sumByCell {
      let denominator = Double(max(bucket.count, 1))
      cells[key] = DensityCell(
        coordinate: CLLocationCoordinate2D(
          latitude: bucket.latSum / denominator,
          longitude: bucket.lngSum / denominator
        ),
        density: max(0, min(1, bucket.weightSum / maxWeight)),
        // 视觉半径略大于格宽一半，相邻格轻微重叠以弱化网格感。
        radiusMeters: cellMeters * 0.75
      )
    }
    return cells
  }

  // MARK: - 城市中心表（与 Dart mapCityCenters 保持一致）

  static func cityCenter(named city: String) -> CLLocationCoordinate2D {
    switch city {
    case "北京": return CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
    case "深圳": return CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579)
    case "广州": return CLLocationCoordinate2D(latitude: 23.1291, longitude: 113.2644)
    case "成都": return CLLocationCoordinate2D(latitude: 30.5728, longitude: 104.0668)
    case "杭州": return CLLocationCoordinate2D(latitude: 30.2741, longitude: 120.1551)
    default: return CLLocationCoordinate2D(latitude: 31.2227, longitude: 121.4712) // 上海 + 兜底
    }
  }
}
