import Foundation
import MapKit

/// 纯函数几何换算：Web Mercator 的 zoom ↔ span、padding 折算、圆点/高亮半径
/// 插值。全部无状态、无 UIKit 依赖（除 MapKit 坐标类型外），
/// 配 RunnerTests 里的 SiponMapGeometryTests 覆盖（迁移指南 §5）。
enum SiponMapGeometry {

  /// Web Mercator 基准 tile 尺寸（pt）。
  static let tileSize = 256.0

  /// 赤道周长（米），meters-per-pixel 换算基准。
  static let earthEquatorMeters = 40_075_016.686

  /// 与 Dart 的 MapSceneController.cityZoom 保持一致。
  static let initialCityZoom = 11.8

  /// 与 Dart 的 mapCircleFullOpacity 保持一致。
  static let fullOpacity = 0.92

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

  /// 相机距离 → zoom（[cameraDistance] 的逆运算），读视野时用它反算缩放。
  ///
  /// **不要用 `region.span` 反推 zoom。** `region` 是「透视 + 旋转之后」的外接
  /// 矩形：相机带 pitch 24 / heading -12 时（进页与「聚焦城区」都是这个姿态），
  /// 它的跨度比真实可见跨度大约 1.4 倍，反推出的 zoom 系统性偏低半档以上。
  /// 这样相机距离与命令下发口径保持一致。
  /// [cameraDistance] 本身不受俯仰与朝向影响，用它反算与命令下发口径自洽。
  ///
  /// 注：[cameraDistance] 在极小距离上有 50m 下限，那一档反算会有偏差，
  /// 但远低于本项目用到的 9~17 层级区间。
  static func zoom(distance: Double, lat: Double, viewportHeight: CGFloat) -> Double {
    guard distance.isFinite, distance > 0, viewportHeight > 0 else { return .nan }
    let clampedLat = max(-85.05, min(85.05, lat.isFinite ? lat : 0))
    let mpp = distance / Double(viewportHeight)
    guard mpp.isFinite, mpp > 0 else { return .nan }
    return log2(earthEquatorMeters * cos(clampedLat * .pi / 180) / (tileSize * mpp))
  }

  // MARK: - padding → 中心点折算（§5.2）

  /// 让目标点出现在「去掉底部 padding 后的区域」中心；MapKit 无此概念，
  /// 折算成把真实中心向南移。`bottomPx` 是本次相机调用显式携带的 padding
  /// 下边距。
  static func center(
    lat: Double,
    lng: Double,
    shiftingUpBy bottomPx: Double,
    zoom: Double
  ) -> CLLocationCoordinate2D {
    // 允许负的 padding 增量：面板收起时 delta 为负，需要反向恢复偏移。
    guard bottomPx.isFinite, bottomPx != 0 else {
      return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    let mpp = metersPerPixel(lat: lat, zoom: zoom)
    guard mpp.isFinite, mpp > 0 else {
      return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    let deltaLat = bottomPx * mpp / 111_320.0
    return CLLocationCoordinate2D(latitude: lat - deltaLat, longitude: lng)
  }

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
    CGFloat(interpolate([(9, 4), (13, 7), (16, 11)], at: zoom))
  }

  static func selectionHaloRadius(zoom: Double) -> CGFloat {
    CGFloat(interpolate([(9, 6), (13, 8), (16, 12)], at: zoom))
  }

  static func selectionCoreRadius(zoom: Double) -> CGFloat {
    CGFloat(interpolate([(9, 3.5), (13, 5), (16, 7.5)], at: zoom))
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
