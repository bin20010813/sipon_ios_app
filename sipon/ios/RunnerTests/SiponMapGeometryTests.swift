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

  func testCircleFadeCurve() {
    // 区间外截断：分界线以下全透明，恢复线以上满透明度，中间线性。
    XCTAssertEqual(SiponMapGeometry.circleFade(zoom: 12, heatmapArmed: true), 0, accuracy: 1e-9)
    XCTAssertEqual(
      SiponMapGeometry.circleFade(zoom: 13.2, heatmapArmed: true),
      0.92,
      accuracy: 1e-9
    )
    XCTAssertEqual(
      SiponMapGeometry.circleFade(zoom: 12.6, heatmapArmed: true),
      0.46,
      accuracy: 1e-9
    )
    // 手动锁「点位」时永不淡出。
    XCTAssertEqual(
      SiponMapGeometry.circleFade(zoom: 5, heatmapArmed: false),
      0.92,
      accuracy: 1e-9
    )
  }

  func testHeatmapAggregationGroupsNearbyPoints() {
    let cellMetersReferenceZoom = 12.0
    let degreesPerCell = 300.0 / 111_320.0
    let base = (lng: 121.4712, lat: 31.2227)

    var samples: [SiponMapGeometry.HeatSample] = []
    for index in 0..<4 {
      samples.append(SiponMapGeometry.HeatSample(
        coordinate: CLLocationCoordinate2D(
          latitude: base.lat + degreesPerCell * 0.1 * Double(index),
          longitude: base.lng + degreesPerCell * 0.1 * Double(index)
        ),
        weight: 2
      ))
    }
    // 远处的孤点
    samples.append(SiponMapGeometry.HeatSample(
      coordinate: CLLocationCoordinate2D(latitude: base.lat + 1, longitude: base.lng + 1),
      weight: 2
    ))

    let cells = SiponMapGeometry.aggregateHeatmap(
      samples,
      zoom: cellMetersReferenceZoom
    )

    // 前 4 个点落在同一格，最后 1 个独立成格。
    XCTAssertEqual(cells.count, 2)

    let densest = cells.values.max { $0.density < $1.density }
    XCTAssertNotNil(densest)
    XCTAssertEqual(densest?.density ?? 0, 1, accuracy: 1e-9, reason: "4 × weight2 = 8 达到归一化上限")
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
