import MapKit
import XCTest
@testable import Runner

/// zoom ↔ span 换算与 padding 折算的正反一致性抽查（迁移指南 §7）。
final class SiponMapGeometryTests: XCTestCase {

  func testZoomSpanRoundTrip() {
    let width: CGFloat = 390
    for zoom in stride(from: 9.0, through: 17.0, by: 0.7) {
      let delta = SiponMapGeometry.longitudeDelta(zoom: zoom, width: width)
      let recovered = SiponMapGeometry.zoom(longitudeDelta: delta, width: width)
      XCTAssertEqual(recovered, zoom, accuracy: 1e-6, "zoom \(zoom) 往返失真")
    }
  }

  func testKnownLongitudeDeltas() {
    // zoom 0 时整个赤道（360°）铺满视口宽；zoom 11.8 ≈ 0.128° @390pt，
    // 数量级对齐上海城市视野。
    let wide = SiponMapGeometry.longitudeDelta(zoom: 0, width: 256)
    XCTAssertEqual(wide, 360, accuracy: 1e-6)

    let city = SiponMapGeometry.longitudeDelta(zoom: 11.8, width: 390)
    XCTAssertEqual(city, 0.1278, accuracy: 1e-3)
  }

  func testSpanKeepsAspectRatio() {
    let size = CGSize(width: 390, height: 700)
    let span = SiponMapGeometry.span(zoom: 14, size: size)
    let expectedHeightRatio = Double(size.height / size.width)
    XCTAssertEqual(
      span.latitudeDelta / span.longitudeDelta,
      expectedHeightRatio,
      accuracy: 1e-9
    )
  }

  func testPaddingShiftMovesCenterSouth() {
    // 南移为负纬度差：目标点被「顶」进面板以上的可视中心。
    let shifted = SiponMapGeometry.center(
      lat: 31.2227,
      lng: 121.4712,
      shiftingUpBy: 184,
      zoom: 15.4
    )
    XCTAssertLessThan(shifted.latitude, 31.2227)
    XCTAssertEqual(shifted.longitude, 121.4712)

    // 三档抽查：zoom 越小地面分辨率越大，同样的 padding 偏移越大。
    for zoom in [11.8, 15.05, 15.4] {
      let value = SiponMapGeometry.center(
        lat: 31.2227,
        lng: 121.4712,
        shiftingUpBy: 250,
        zoom: zoom
      )
      XCTAssertTrue(value.latitude < 31.2227, "zoom \(zoom) 应向南偏移")
    }
  }

  func testPaddingShiftIsLinearInPixels() {
    let small = SiponMapGeometry.center(lat: 30, lng: 120, shiftingUpBy: 100, zoom: 15)
    let large = SiponMapGeometry.center(lat: 30, lng: 120, shiftingUpBy: 200, zoom: 15)
    let driftSmall = 30 - small.latitude
    let driftLarge = 30 - large.latitude
    XCTAssertEqual(driftLarge / driftSmall, 2, accuracy: 1e-6)
  }

  func testCircleRadiusStops() {
    // §5.3 速查表：圆点 9→4pt、13→7pt、16→11pt。
    XCTAssertEqual(SiponMapGeometry.circleRadius(zoom: 9), 4, accuracy: 1e-9)
    XCTAssertEqual(SiponMapGeometry.circleRadius(zoom: 13), 7, accuracy: 1e-9)
    XCTAssertEqual(SiponMapGeometry.circleRadius(zoom: 16), 11, accuracy: 1e-9)
  }

  func testSelectionRadiiStops() {
    XCTAssertEqual(SiponMapGeometry.selectionHaloRadius(zoom: 9), 6, accuracy: 1e-9)
    XCTAssertEqual(SiponMapGeometry.selectionCoreRadius(zoom: 13), 5, accuracy: 1e-9)
    XCTAssertEqual(SiponMapGeometry.selectionHaloRadius(zoom: 16), 12, accuracy: 1e-9)
  }

  /// 命令下发（zoom → 相机距离）与视野回读（相机距离 → zoom）必须同一口径。
  /// 两侧一旦不一致，圆点淡入与文字标注的阈值就会被推迟到「怎么放大都不出来」。
  func testZoomCameraDistanceRoundTrip() {
    let height: CGFloat = 700
    let lat = 31.2227
    for zoom in stride(from: 9.0, through: 17.0, by: 0.5) {
      let distance = SiponMapGeometry.cameraDistance(
        lat: lat,
        zoom: zoom,
        viewportHeight: height
      )
      let recovered = SiponMapGeometry.zoom(
        distance: distance,
        lat: lat,
        viewportHeight: height
      )
      XCTAssertEqual(recovered, zoom, accuracy: 1e-6, "zoom \(zoom) 距离往返失真")
    }
  }

  /// 俯仰 + 朝向会让 `region.span` 变成外接矩形（约 1.4×），用跨度反推 zoom
  /// 会系统性偏低——这正是「地图明明放大了，标注却还不出来」的根因。
  /// 这条测试把两个口径的差值钉死，防止有人把实现改回跨度反推。
  func testRotatedRegionFormulaUnderreportsZoom() {
    let width: CGFloat = 390
    let zoom = 11.8
    let flat = SiponMapGeometry.longitudeDelta(zoom: zoom, width: width)
    let fromRotatedRegion = SiponMapGeometry.zoom(longitudeDelta: flat * 1.4, width: width)

    XCTAssertEqual(fromRotatedRegion, zoom - log2(1.4), accuracy: 1e-9)
    XCTAssertLessThan(fromRotatedRegion, zoom - 0.4, "跨度反推至少要低 0.4 档")

    // 相机距离口径则与下发值严格一致。
    let height: CGFloat = 700
    let distance = SiponMapGeometry.cameraDistance(lat: 31.2227, zoom: zoom, viewportHeight: height)
    XCTAssertEqual(
      SiponMapGeometry.zoom(distance: distance, lat: 31.2227, viewportHeight: height),
      zoom,
      accuracy: 1e-6
    )
  }

  func testCityCenterFallback() {
    let shanghai = SiponMapGeometry.cityCenter(named: "上海")
    XCTAssertEqual(shanghai.longitude, 121.4712, accuracy: 1e-9)
    // 未知城市退回上海中心。
    let unknown = SiponMapGeometry.cityCenter(named: "未知城市")
    XCTAssertEqual(unknown.longitude, shanghai.longitude, accuracy: 1e-9)
    XCTAssertEqual(unknown.latitude, shanghai.latitude, accuracy: 1e-9)
  }
}
