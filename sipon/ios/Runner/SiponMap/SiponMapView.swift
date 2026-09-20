import Flutter
import MapKit
import UIKit

// =============================================================================
// SiponMapView —— PlatformView 薄壳。
//
// 把 MKMapView 直接作为返回视图（不再包一层 UIView，省一层布局传递），
// delegate、手势、channel 全部转发给同文件里的业务引擎 SiponMapEngine。
// =============================================================================

final class SiponMapView: NSObject, FlutterPlatformView {

  private let mapView = MKMapView()
  private let engine: SiponMapEngine
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: SiponMapProtocol.channelName(viewId: viewId),
      binaryMessenger: messenger
    )
    engine = SiponMapEngine(
      mapView: mapView,
      sendEvent: { [weak channel] name, arguments in
        // Dart 侧宿主在注册监听前到达的事件由缓存补发机制兜住。
        channel?.invokeMethod(name, arguments: arguments)
      }
    )
    super.init()

    // 处理器在创建时就挂上：setup 命令到达前不能有空窗。
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "sipon_map", message: "view released", details: nil))
        return
      }
      if call.method == SiponMapProtocol.Command.drawRoute {
        // 路径规划是异步的（MKDirections 方向服务），把 result 交给引擎，
        // 规划完成后再回调 Dart。
        self.engine.planRoute(arguments: call.arguments, result: result)
        return
      }
      result(self.engine.handle(method: call.method, arguments: call.arguments))
    }
  }

  func view() -> UIView { mapView }
}
// =============================================================================
// SiponMapEngine —— MKMapView 的唯一业务负责人。
//
// 渲染走「整帧下发、按 id diff」的约定（指南 §3i）；分级显隐的决策由 Dart
// 算好，原生只负责执行地图内容。
// =============================================================================

final class SiponMapEngine: NSObject {

  private unowned let mapView: MKMapView
  private let sendEvent: (String, Any?) -> Void

  /// 收到 setup 并完成初始配置之后才接受后续指令。
  private var configured = false
  /// 平台视图被拆掉后（detach/dispose）拒绝一切渲染类指令。
  private var alive = true

  private var styleId = "standard"

  private var lastFrameArguments: Any?

  // 各池：协议约定全量下发、原生按 id diff。
  private var circlesById: [String: CirclePointAnnotation] = [:]
  private var markersByVenueId: [String: MarkerAnnotation] = [:]
  private var selectionAnnotation: SelectionAnnotation?
  /// 路径规划出的路线折线（单独成池，不受 renderFrame 的 id diff 影响）。
  private var routeOverlay: MKPolyline?

  /// 路线版本：每次开始/取消规划都递增，旧回调据此作废。
  private var routeRevision = 0
  /// 当前在途的 MKDirections。
  private var activeDirections: MKDirections?
  /// 等待返回 Dart 的结果回调（只完成一次）。
  private var pendingRouteResult: FlutterResult?

  /// marker 图标资产缓存（category → UIImage）。
  private var markerIcons: [String: UIImage] = [:]

  /// 最近一次显式设置的相机 padding。每次移动都带上折算值，
  /// 不依赖引擎记住状态（§5.2 与旧版「padding 粘滞」修法一致）。
  private var appliedBottomPadding: Double = 0

  /// delegate 集中在 proxy 上；手势识别器共享同一个 target。
  private lazy var proxy = EngineDelegateProxy(engine: self)

  init(mapView: MKMapView, sendEvent: @escaping (String, Any?) -> Void) {
    self.mapView = mapView
    self.sendEvent = sendEvent
    super.init()
    mapView.delegate = proxy
  }

  deinit {
    // 视图释放时兜底清理：只碰自己持有的资源，不碰 unowned mapView。
    let directions = activeDirections
    activeDirections = nil
    directions?.cancel()
    let completion = pendingRouteResult
    pendingRouteResult = nil
    completion?(false)
  }

  // ------------------------------------------------------------------ 指令入口

  func handle(method: String, arguments: Any?) -> Any? {
    switch method {
    case SiponMapProtocol.Command.setup:
      handleSetup(SiponMapProtocol.dict(arguments) ?? [:])
      return nil
    case SiponMapProtocol.Command.setStyle:
      if let args = SiponMapProtocol.dict(arguments),
         let incoming = SiponMapProtocol.string(args, "styleId") {
        apply(styleId: incoming)
        // 切配置可能移除 overlays（iOS16 配置切换行为）；重放上一帧，
        // 让幂等的 id-diff 把地图内容建回来。
        if lastFrameArguments != nil {
          DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            _ = self.handle(
              method: SiponMapProtocol.Command.renderFrame,
              arguments: self.lastFrameArguments
            )
          }
        }
      }
      return nil
    case SiponMapProtocol.Command.setGestures:
      if let args = SiponMapProtocol.dict(arguments) {
        mapView.isRotateEnabled = SiponMapProtocol.double(args, "rotateEnabled", fallback: 1) != 0
        mapView.isZoomEnabled = SiponMapProtocol.double(args, "zoomEnabled", fallback: 1) != 0
        mapView.isScrollEnabled = SiponMapProtocol.double(args, "panEnabled", fallback: 1) != 0
      }
      return nil
    case SiponMapProtocol.Command.readViewport:
      return readViewportPayload()
    case SiponMapProtocol.Command.flyToCity, SiponMapProtocol.Command.focusOn:
      if let args = SiponMapProtocol.dict(arguments) {
        moveCamera(SiponMapProtocol.CameraMove(dict: args), animated: true)
      }
      return nil
    case SiponMapProtocol.Command.applyStage:
      if let args = SiponMapProtocol.dict(arguments) {
        applyStage(bottomPadding: SiponMapProtocol.double(args, "bottomPadding", fallback: appliedBottomPadding))
      }
      return nil
    case SiponMapProtocol.Command.renderFrame:
      handleRenderFrame(arguments)
      return nil
    case SiponMapProtocol.Command.registerAssets:
      registerMarkerAssets(SiponMapProtocol.dict(arguments) ?? [:])
      return nil
    case SiponMapProtocol.Command.clearRoute:
      // 两个动作：取消在途规划 + 移除已绘制折线。
      cancelRoutePlanning()
      clearRouteOverlay()
      return nil
    case SiponMapProtocol.Command.dispose:
      resetPools()
      return nil
    default:
      return nil
    }
  }

  // ------------------------------------------------------------------ 路径规划

  /// flutter 端调用：按站点顺序逐段 MKDirections 规划，把各段折线拼成一条
  /// 并绘制到地图上，完成后通过 [result] 回调 Bool（成功/失败）。
  func planRoute(arguments: Any?, result: @escaping FlutterResult) {
    guard alive, configured else {
      result(false)
      return
    }

    guard let args = SiponMapProtocol.dict(arguments),
          let rawPoints = args["points"] as? [[String: Any]] else {
      result(FlutterError(code: "sipon_route", message: "invalid points payload", details: nil))
      return
    }

    var coordinates: [CLLocationCoordinate2D] = []
    for raw in rawPoints {
      let lat = SiponMapProtocol.double(raw, "lat", fallback: .nan)
      let lng = SiponMapProtocol.double(raw, "lng", fallback: .nan)
      guard lat.isFinite, lng.isFinite else { continue }
      coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
    }
    guard coordinates.count >= 2 else {
      result(FlutterError(code: "sipon_route", message: "need at least 2 stops", details: nil))
      return
    }

    // 取消上一次规划，再保存本次版本与结果回调。
    cancelRoutePlanning()
    let revision = routeRevision
    pendingRouteResult = result

    planNextLeg(builder: RouteLegBuilder(coordinates: coordinates), revision: revision)
  }

  /// 逐段规划下一段；[RouteLegBuilder] 是引用类型，回调里累加各段折线。
  /// 递归改为实例方法，回调里用弱引用取得 self 后再继续，避免局部函数
  /// 隐式强捕获抵消 [weak self] 的意图。
  private func planNextLeg(builder: RouteLegBuilder, revision: Int) {
    guard alive, configured, revision == routeRevision else { return }
    guard builder.hasNext else {
      finishRoute(legs: builder.legs, revision: revision)
      return
    }

    let request = MKDirections.Request()
    request.source = builder.nextStart
    request.destination = builder.nextEnd
    request.transportType = .automobile
    request.requestsAlternateRoutes = false

    let directions = MKDirections(request: request)
    activeDirections = directions
    directions.calculate { [weak self] response, error in
      guard let self = self else { return }
      guard self.alive, self.configured, revision == self.routeRevision else { return }

      if error != nil {
        // 单段规划失败（离线/无路网/坐标异常）→ 整体视为失败。
        self.completeRoutePlanning(false, revision: revision)
        return
      }
      guard let leg = response?.routes.first?.polyline else {
        self.completeRoutePlanning(false, revision: revision)
        return
      }
      builder.advance(with: leg)
      self.planNextLeg(builder: builder, revision: revision)
    }
  }

  /// 取消正在规划的任务，并把旧回调以失败完成（幂等）。
  private func cancelRoutePlanning() {
    routeRevision += 1

    // 先取走结果，避免 cancel 引起的旧回调重复完成。
    let completion = pendingRouteResult
    pendingRouteResult = nil

    let directions = activeDirections
    activeDirections = nil
    directions?.cancel()

    completion?(false)
  }

  /// 统一完成函数：只有版本仍匹配才会返回结果，保证每次请求只完成一次。
  private func completeRoutePlanning(_ succeeded: Bool, revision: Int) {
    guard revision == routeRevision else { return }

    activeDirections = nil
    let completion = pendingRouteResult
    pendingRouteResult = nil
    completion?(succeeded)
  }

  /// 路线分段构建器：持有坐标与已算出的折线段。引用类型方便在异步回调里
  /// 累加结果，而不需要把 inout 参数带进 escaping 闭包。
  private final class RouteLegBuilder {
    private let coordinates: [CLLocationCoordinate2D]
    private(set) var legs: [MKPolyline] = []
    private var index = 0

    init(coordinates: [CLLocationCoordinate2D]) {
      self.coordinates = coordinates
    }

    var hasNext: Bool { index < coordinates.count - 1 }

    var nextStart: MKMapItem {
      MKMapItem(placemark: MKPlacemark(coordinate: coordinates[index]))
    }

    var nextEnd: MKMapItem {
      MKMapItem(placemark: MKPlacemark(coordinate: coordinates[index + 1]))
    }

    func advance(with leg: MKPolyline) {
      legs.append(leg)
      index += 1
    }
  }

  /// 把各段折线拼成一条并绘制、取景。
  private func finishRoute(legs: [MKPolyline], revision: Int) {
    guard alive, configured, revision == routeRevision else { return }

    var all: [CLLocationCoordinate2D] = []
    for (legNumber, leg) in legs.enumerated() {
      let points = leg.points()
      // 跳过与上一段重复的衔接点（首段从 0 开始）。
      let start = legNumber == 0 ? 0 : 1
      for i in start..<Int(leg.pointCount) {
        all.append(points[i].coordinate)
      }
    }
    guard all.count >= 2 else {
      completeRoutePlanning(false, revision: revision)
      return
    }

    // 只替换屏幕上的旧折线，不调用 cancelRoutePlanning()，否则会把刚完成的
    // 本次规划也作废。
    clearRouteOverlay()
    let polyline = MKPolyline(coordinates: &all, count: all.count)
    routeOverlay = polyline
    mapView.addOverlay(polyline, level: .aboveRoads)
    mapView.setVisibleMapRect(
      polyline.boundingMapRect,
      edgePadding: UIEdgeInsets(top: 90, left: 60, bottom: 140, right: 60),
      animated: true
    )
    completeRoutePlanning(true, revision: revision)
  }

  /// 移除已绘制的路线折线。
  private func clearRouteOverlay() {
    if let route = routeOverlay {
      mapView.removeOverlay(route)
      routeOverlay = nil
    }
  }

  // ------------------------------------------------------------------ 初始配置

  private func handleSetup(_ args: [String: Any]) {
    configureBaseOptions()

    let city = SiponMapProtocol.string(args, "city") ?? "上海"
    styleId = SiponMapProtocol.string(args, "styleId") ?? "standard"
    apply(styleId: styleId)

    // 初始相机对齐旧版 attach 的语义：城市级视野一眼看到整片城区
    // （zoom 11.8 为城市级视野）。
    let center = SiponMapGeometry.cityCenter(named: city)
    moveCamera(
      SiponMapProtocol.CameraMove(dict: [
        "lng": center.longitude,
        "lat": center.latitude,
        "zoom": SiponMapGeometry.initialCityZoom,
        "pitch": 24,
        "bearing": -12,
        "bottomPadding": 0,
      ]),
      animated: false
    )

    mapView.addGestureRecognizer(proxy.blankTapRecognizer)

    configured = true
    // ready 即可画——MapKit 没有 styleLoaded 期（指南 §3.3）。
    sendEvent(SiponMapProtocol.Event.onMapReady, nil)
  }

  private func configureBaseOptions() {
    // 对齐旧版 CompassSettings(false) / ScaleBarSettings(false)；
    // MapKit 没有 logo / attribution，整段装饰物边距逻辑天然消失。
    mapView.showsCompass = false
    mapView.showsScale = false
    mapView.showsUserLocation = false
    mapView.isRotateEnabled = true
    mapView.isPitchEnabled = true
    mapView.isScrollEnabled = true
    mapView.isZoomEnabled = true

    // 底图 POI（餐厅、地铁、地标）的开关放在 apply(styleId:) 里，跟着
    // MKMapConfiguration 一起设。这里设 `mapView.pointOfInterestFilter` 在
    // iOS 16+ 上会被随后赋值的 preferredConfiguration 覆盖掉，等于没设。
    // 旧版 iOS 走 mapType 分支，那时才需要在这里兜底（见 apply(styleId:)）。
  }

  /// 底图三档切换。iOS 16+ 用 MKMapConfiguration（muted emphasis +
  /// 强制深色界面近似原 dark）；低版本降级到老 mapType 枚举，
  /// muted 退化为普通浅色（决策 D5）。
  func apply(styleId: String) {
    self.styleId = styleId
    mapView.overrideUserInterfaceStyle = .unspecified

    if #available(iOS 16.0, *) {
      // POI 过滤必须设在 configuration 上：在 iOS 16+ 里 mapView 自身那个
      // pointOfInterestFilter 会被 preferredConfiguration 顶掉，写在那里不生效，
      // 结果就是底图上连便利店、地铁站的名称都没有。
      switch styleId {
      case "satellite":
        let configuration = MKHybridMapConfiguration()
        configuration.pointOfInterestFilter = .includingAll
        mapView.preferredConfiguration = configuration
      case "muted":
        let configuration = MKStandardMapConfiguration()
        configuration.emphasisStyle = .muted
        configuration.pointOfInterestFilter = .includingAll
        mapView.preferredConfiguration = configuration
        mapView.overrideUserInterfaceStyle = .dark
      default:
        let configuration = MKStandardMapConfiguration()
        configuration.pointOfInterestFilter = .includingAll
        mapView.preferredConfiguration = configuration
      }
    } else {
      // 老版本没有配置对象，POI 开关就是 mapView 自己的属性。
      mapView.mapType = (styleId == "satellite") ? .hybrid : .standard
      mapView.pointOfInterestFilter = .includingAll
    }
  }

  private func registerMarkerAssets(_ args: [String: Any]) {
    guard let assets = args["assets"] as? [String: FlutterStandardTypedData] else {
      NSLog("[SiponMap] assets 参数解析失败：需要分类对应的图片字节")
      return
    }

    for (category, bytes) in assets {
      guard let image = UIImage(data: bytes.data, scale: 3) else {
        NSLog("[SiponMap] 图片解码失败：category=%@ bytes=%ld", category, bytes.data.count)
        continue
      }

      markerIcons[category] = image.withRenderingMode(.alwaysOriginal)

      NSLog(
        "[SiponMap] 图片加载成功：category=%@ size=%.0fx%.0f",
        category,
        Double(image.size.width),
        Double(image.size.height)
      )
    }

    for (_, annotation) in markersByVenueId {
      guard let view = mapView.view(for: annotation)
        as? MarkerAnnotationView else {
        continue
      }

      view.setIcon(markerIcons[annotation.category])
    }

    refreshDynamicStyling()
  }

  // ------------------------------------------------------------------ 相机

  private func viewportSize() -> CGSize {
    if mapView.bounds.width > 1, mapView.bounds.height > 1 {
      return mapView.bounds.size
    }
    return UIScreen.main.bounds.size
  }

  /// 当前缩放：用相机距离反算（与 `moveCamera` 的下发口径同源）。
  ///
  /// 不要退回 `region.span` 反推：region 含俯仰与朝向的外接放大，会低估半档以上，
  /// 直接导致圆点淡入与文字标注的显隐阈值全部被推迟。详见
  /// [SiponMapGeometry.zoom(distance:lat:viewportHeight:)]。
  private func currentZoomEstimate() -> Double {
    let size = viewportSize()

    let fromDistance = SiponMapGeometry.zoom(
      distance: mapView.camera.centerCoordinateDistance,
      lat: mapView.region.center.latitude,
      viewportHeight: size.height
    )
    if fromDistance.isFinite {
      return fromDistance
    }

    // 相机尚未装配（距离读不到）时的兜底：退回跨度反推，宁可偏保守也别给 NaN。
    let spanDelta = mapView.region.span.longitudeDelta
    guard spanDelta.isFinite, spanDelta > 0 else {
      return SiponMapGeometry.initialCityZoom
    }
    return SiponMapGeometry.zoom(longitudeDelta: spanDelta, width: size.width)
  }

  private func moveCamera(_ move: SiponMapProtocol.CameraMove, animated: Bool) {
    let size = viewportSize()
    let center = SiponMapGeometry.center(
      lat: move.latitude,
      lng: move.longitude,
      shiftingUpBy: move.bottomPadding,
      zoom: move.zoom
    )

    // MKMapCamera 一把出：中心点(含 padding 折算)、缩放(距离折算)、
    // heading(顺时针度)、pitch(保守钳制 60，MapKit 有效上限约 77)。
    // 动画时长不可控，忽略 durationMs（决策 D3）。
    let distance = SiponMapGeometry.cameraDistance(
      lat: center.latitude,
      zoom: move.zoom,
      viewportHeight: size.height
    )
    let camera = MKMapCamera(
      lookingAtCenter: center,
      fromDistance: distance,
      pitch: max(0, min(move.pitch, 60)),
      heading: move.bearing.truncatingRemainder(dividingBy: 360)
    )
    mapView.setCamera(camera, animated: animated)

    appliedBottomPadding = move.bottomPadding
  }

  /// 面板落定但无聚焦目标：内容不藏到面板后面的等效操作是按 padding 增量
  /// 把真实中心继续南移一截，跨度不变（每次显式带值，不留粘滞状态）。
  private func applyStage(bottomPadding newPadding: Double) {
    let delta = newPadding - appliedBottomPadding
    appliedBottomPadding = newPadding
    guard abs(delta) > 0.5 else { return }

    let current = mapView.region.center
    let shifted = SiponMapGeometry.center(
      lat: current.latitude,
      lng: current.longitude,
      shiftingUpBy: delta,
      zoom: currentZoomEstimate()
    )
    mapView.setRegion(
      MKCoordinateRegion(center: shifted, span: mapView.region.span),
      animated: true
    )
  }

  private func readViewportPayload() -> [String: Any] {
    SiponMapProtocol.viewportArguments(region: mapView.region, zoom: currentZoomEstimate())
  }

  // ------------------------------------------------------------------ 帧下发

  private func handleRenderFrame(_ arguments: Any?) {
    lastFrameArguments = arguments
    guard alive, configured,
          let frame = SiponMapProtocol.Frame.parse(arguments) else { return }

    // 同一地点若已有名称 Marker（本身带 PNG），不再叠加普通图标（§4）。
    let markerVenueIds = Set(frame.markers.map(\.venueId))
    let circles = frame.circles.filter { point in
      guard let venueId = point.venueId, !venueId.isEmpty else { return true }
      return !markerVenueIds.contains(venueId)
    }

    diffCircles(circles)
    diffMarkers(frame.markers)
    diffSelection(frame.selected)

    refreshDynamicStyling()
  }

  // MARK: 圆点 diff（byId 字典对比）

  private func diffCircles(_ incoming: [SiponMapProtocol.CirclePoint]) {
    var nextById: [String: SiponMapProtocol.CirclePoint] = [:]
    for point in incoming where nextById[point.id] == nil {
      nextById[point.id] = point
    }

    var toRemove: [MKAnnotation] = []
    var toAdd: [MKAnnotation] = []
    var refreshedViews: [VenueIconAnnotationView] = []

    for (id, annotation) in circlesById where nextById[id] == nil {
      toRemove.append(annotation)
      circlesById.removeValue(forKey: id)
    }

    for (id, point) in nextById {
      if let existing = circlesById[id] {
        var changed = false
        if existing.coordinate.latitude != point.coordinate.latitude
          || existing.coordinate.longitude != point.coordinate.longitude {
          existing.coordinate = point.coordinate
          changed = true
        }
        if existing.category != point.category {
          existing.category = point.category
          changed = true
        }
        // 业务 ID 变化也同步到 annotation，点击反查才能指向新酒吧。
        if existing.venueId != point.venueId {
          existing.venueId = point.venueId
        }
        if changed {
          if let view = mapView.view(for: existing) as? VenueIconAnnotationView {
            refreshedViews.append(view)
          }
        }
      } else {
        let annotation = CirclePointAnnotation(id: id, coordinate: point.coordinate)
        annotation.category = point.category
        annotation.venueId = point.venueId
        circlesById[id] = annotation
        toAdd.append(annotation)
      }
    }

    // 批量增删各一次调用，避免多次 delegate 风暴（指南 §3i）。
    if !toRemove.isEmpty { mapView.removeAnnotations(toRemove) }
    if !toAdd.isEmpty { mapView.addAnnotations(toAdd) }

    for view in refreshedViews {
      if let annotation = view.annotation as? CirclePointAnnotation {
        view.apply(icon: markerIcons[annotation.category], selected: false)
      }
    }
  }

  // MARK: marker diff（venueId 为键；label 变化原地刷）

  private func diffMarkers(_ incoming: [SiponMapProtocol.MarkerSpec]) {
    var nextByVenueId: [String: SiponMapProtocol.MarkerSpec] = [:]
    for spec in incoming where nextByVenueId[spec.venueId] == nil {
      nextByVenueId[spec.venueId] = spec
    }

    var toRemove: [MKAnnotation] = []
    var toAdd: [MKAnnotation] = []

    for (venueId, annotation) in markersByVenueId where nextByVenueId[venueId] == nil {
      toRemove.append(annotation)
      markersByVenueId.removeValue(forKey: venueId)
    }

    for (venueId, spec) in nextByVenueId {
      if let existing = markersByVenueId[venueId] {
        let moved = existing.coordinate.latitude != spec.coordinate.latitude
          || existing.coordinate.longitude != spec.coordinate.longitude
        // 文字标签翻译导致的文案变化原地刷新即可，不必重建 annotation。
        existing.label = spec.label
        existing.category = spec.category
        existing.sequence = spec.sequence
        if moved { existing.coordinate = spec.coordinate }
        // 坐标的 KVO 更新不能替代自定义 UIImageView/UILabel 的内容更新，
        // 即使视图一直留在屏幕内也应显示新的图标、文字与编号。
        if let view = mapView.view(for: existing) as? MarkerAnnotationView {
          view.setLabel(spec.label)
          view.setSequence(spec.sequence)
          view.setIcon(markerIcons[spec.category])
        }
      } else {
        let annotation = MarkerAnnotation(venueId: venueId, coordinate: spec.coordinate)
        annotation.label = spec.label
        annotation.category = spec.category
        annotation.sequence = spec.sequence
        markersByVenueId[venueId] = annotation
        toAdd.append(annotation)
      }
    }

    if !toRemove.isEmpty { mapView.removeAnnotations(toRemove) }
    if !toAdd.isEmpty { mapView.addAnnotations(toAdd) }
  }

  // MARK: 选中高亮 diff（单例更新或移除）

  private func diffSelection(_ selected: SiponMapProtocol.SelectedSpec?) {
    if let selected = selected {
      if let existing = selectionAnnotation {
        let moved = existing.coordinate.latitude != selected.coordinate.latitude
          || existing.coordinate.longitude != selected.coordinate.longitude
        let recolored = existing.category != selected.category
        existing.category = selected.category
        existing.venueId = selected.venueId
        if moved {
          existing.coordinate = selected.coordinate
        }
        if moved || recolored,
           let view = mapView.view(for: existing) as? VenueIconAnnotationView {
          view.apply(icon: markerIcons[existing.category], selected: true)
        }
      } else {
        let annotation = SelectionAnnotation(id: selected.id, coordinate: selected.coordinate)
        annotation.category = selected.category
        annotation.venueId = selected.venueId
        selectionAnnotation = annotation
        mapView.addAnnotation(annotation)
      }
    } else if let existing = selectionAnnotation {
      selectionAnnotation = nil
      mapView.removeAnnotation(existing)
    }
  }

  // ------------------------------------------------------- 动态样式（缩放联动）

  private func circlesCurrentlyHidden() -> Bool {
    false
  }

  private func markersCurrentlyHidden() -> Bool {
    false
  }

  /// 捏合过程中的连续淡入淡出 + 分界线以下硬摘除。只在视野变化回调里执行；
  /// 决策仍全部来自 Dart 已同步的模式与区间常量，原生不做规则判断。
  ///
  /// 图标在淡出阈值之下直接 `isHidden`：隐藏的图标照样命中点击，
  /// 始终保持点位可见并可点击。
  func refreshDynamicStyling() {
    guard alive, configured else { return }

    let circlesHidden = circlesCurrentlyHidden()

    for (_, annotation) in circlesById {
      guard let view = mapView.view(for: annotation) as? VenueIconAnnotationView else { continue }
      view.isHidden = circlesHidden
      if !circlesHidden {
        view.apply(icon: markerIcons[annotation.category], selected: false)
      }
    }

    let markersHidden = markersCurrentlyHidden()
    for (_, annotation) in markersByVenueId {
      (mapView.view(for: annotation) as? MarkerAnnotationView)?.isHidden = markersHidden
    }

    // 选中点位用放大 PNG 呈现，不跟模式隐藏（它是详情卡片指向的唯一锚点）。
    if let annotation = selectionAnnotation,
       let view = mapView.view(for: annotation) as? VenueIconAnnotationView {
      view.apply(icon: markerIcons[annotation.category], selected: true)
    }
  }

  // ------------------------------------------------------------------ 内务

  private func resetPools() {
    alive = false
    mapView.removeGestureRecognizer(proxy.blankTapRecognizer)
    mapView.delegate = nil
    cancelRoutePlanning()
    mapView.removeAnnotations(Array(circlesById.values))
    mapView.removeAnnotations(Array(markersByVenueId.values))
    if let selection = selectionAnnotation {
      mapView.removeAnnotation(selection)
    }
    if let route = routeOverlay {
      mapView.removeOverlay(route)
    }

    circlesById.removeAll()
    markersByVenueId.removeAll()
    selectionAnnotation = nil
    routeOverlay = nil
    lastFrameArguments = nil
  }

  // ---- 给同文件内的 delegate proxy 的内部访问面（file-scope 可见）----

  fileprivate var currentZoomSnapshot: Double { currentZoomEstimate() }
  fileprivate var circlesHiddenSnapshot: Bool { circlesCurrentlyHidden() }
  fileprivate var markersHiddenSnapshot: Bool { markersCurrentlyHidden() }
  fileprivate var shouldProcessEvents: Bool { alive && configured }
  fileprivate var hostMapView: MKMapView { mapView }

  fileprivate func icon(for category: String) -> UIImage? { markerIcons[category] }

  fileprivate func emitVenueTapped(_ venueId: String) {
    sendEvent(
      SiponMapProtocol.Event.onVenueTapped,
      SiponMapProtocol.venueTappedArguments(venueId: venueId)
    )
  }

  fileprivate func emitBlankTapped() {
    sendEvent(SiponMapProtocol.Event.onBlankTapped, nil)
  }

  fileprivate func emitViewportSettled(region: MKCoordinateRegion) {
    sendEvent(
      SiponMapProtocol.Event.onViewportSettled,
      SiponMapProtocol.viewportArguments(region: region, zoom: currentZoomSnapshot)
    )
    DispatchQueue.main.async { [weak self] in
      self?.refreshDynamicStyling()
    }
  }
}
// =============================================================================
// EngineDelegateProxy —— MKMapViewDelegate / UIGestureRecognizerDelegate。
// 单独一层是为了让引擎类型保持干净；所有系统回调都从这里转进引擎。
// =============================================================================

final class EngineDelegateProxy: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {

  private unowned let engine: SiponMapEngine

  init(engine: SiponMapEngine) {
    self.engine = engine
    super.init()
  }

  lazy var blankTapRecognizer: UITapGestureRecognizer = {
    let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleBlankTap(_:)))
    recognizer.delegate = self
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesBegan = false
    recognizer.delaysTouchesEnded = false
    return recognizer
  }()

  // MARK: annotation view 复用池

  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    switch annotation {
    case let circle as CirclePointAnnotation:
      let identifier = "sipon.venueIcon.\(circle.category)"
      let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        as? VenueIconAnnotationView)
        ?? VenueIconAnnotationView(annotation: circle, reuseIdentifier: identifier)
      view.annotation = circle
      view.apply(icon: engine.icon(for: circle.category), selected: false)
      // 新建的视图同样可能落在分界线以下——「透明仍可点」在这里同样成立。
      view.isHidden = engine.circlesHiddenSnapshot
      view.displayPriority = .defaultHigh
      return view
    case let marker as MarkerAnnotation:
      let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "sipon.marker")
        as? MarkerAnnotationView)
        ?? MarkerAnnotationView(annotation: marker, reuseIdentifier: "sipon.marker")
      view.annotation = marker
      view.setIcon(engine.icon(for: marker.category))
      view.setLabel(marker.label)
      view.setSequence(marker.sequence)
      view.isHidden = engine.markersHiddenSnapshot
      return view
    case let selection as SelectionAnnotation:
      let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "sipon.selection")
        as? VenueIconAnnotationView)
        ?? VenueIconAnnotationView(annotation: selection, reuseIdentifier: "sipon.selection")
      view.annotation = selection
      view.apply(icon: engine.icon(for: selection.category), selected: true)
      // 高亮必须置顶，保证详情状态清晰可见。
      view.displayPriority = .required
      return view
    default:
      return nil
    }
  }

  func mapView(
    _ mapView: MKMapView,
    rendererFor overlay: MKOverlay
  ) -> MKOverlayRenderer {
    if let polyline = overlay as? MKPolyline {
      let renderer = MKPolylineRenderer(polyline: polyline)
      renderer.strokeColor = UIColor(
        red: 0x9A / 255.0,
        green: 0x3D / 255.0,
        blue: 0x78 / 255.0,
        alpha: 1
      )
      renderer.lineWidth = 5
      renderer.lineCap = .round
      renderer.lineJoin = .round
      return renderer
    }
    return MKOverlayRenderer(overlay: overlay)
  }

  // MARK: 选中回调

  func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
    // 立刻取消选中态：否则重复点击同一个点不会再触发 didSelect，
    // 「再点一次 = 打开详情」的交互会失效（§3e）。
    defer { mapView.deselectAnnotation(view.annotation, animated: false) }

    if engine.shouldProcessEvents,
       let selecting = view.annotation as? VenueSelecting,
       let venueId = selecting.venueId,
       !venueId.isEmpty {
      engine.emitVenueTapped(venueId)
    }
  }

  // MARK: 相机停稳 → 上报（去抖在 Dart，惯性滚动连发无妨）

  func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    guard engine.shouldProcessEvents else { return }
    engine.emitViewportSettled(region: mapView.region)
  }

  // MARK: 空白点击

  @objc func handleBlankTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended, engine.shouldProcessEvents else { return }
    engine.emitBlankTapped()
  }

  // 空白点击只观察触摸，不与 MapKit 的平移、缩放、选中手势互斥。
  // cancelsTouchesInView 只影响视图接收事件，不能替代识别器之间的同时识别策略。
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    gestureRecognizer === blankTapRecognizer || otherGestureRecognizer === blankTapRecognizer
  }

  /// 放过落在任何可见 annotation view 上的触摸，让它走系统 didSelect（§3a）。
  ///
  /// 不依赖 MKMapView 第一层子视图就是 MKAnnotationView：先沿 touch.view 的
  /// 父视图链向上找，再用公开的 view(for:) + 坐标转换做补充命中判断。
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldReceive touch: UITouch
  ) -> Bool {
    let mapView = engine.hostMapView

    var candidate: UIView? = touch.view
    while let view = candidate {
      if view is MKAnnotationView {
        return false
      }
      if view === mapView {
        break
      }
      candidate = view.superview
    }

    let point = touch.location(in: mapView)
    for annotation in mapView.annotations {
      guard let view = mapView.view(for: annotation),
            !view.isHidden,
            view.alpha > 0.01,
            view.isUserInteractionEnabled else {
        continue
      }

      let localPoint = view.convert(point, from: mapView)
      if view.point(inside: localPoint, with: nil) {
        return false
      }
    }

    return true
  }
}

// =============================================================================
// Annotation 模型层
// =============================================================================

/// 能反查酒吧的 annotation 协议：didSelect 统一读 venueId。
protocol VenueSelecting {
  var venueId: String? { get }
}

final class CirclePointAnnotation: NSObject, MKAnnotation, VenueSelecting {
  let id: String
  @objc dynamic var coordinate: CLLocationCoordinate2D
  @objc dynamic var category: String = "pub"
  var venueId: String?

  init(id: String, coordinate: CLLocationCoordinate2D) {
    self.id = id
    self.coordinate = coordinate
    super.init()
  }
}

final class MarkerAnnotation: NSObject, MKAnnotation, VenueSelecting {
  let venueId: String?
  @objc dynamic var coordinate: CLLocationCoordinate2D
  @objc dynamic var label: String = ""
  @objc dynamic var category: String = "pub"
  var sequence: Int?

  init(venueId: String, coordinate: CLLocationCoordinate2D) {
    self.venueId = venueId
    self.coordinate = coordinate
    super.init()
  }
}

final class SelectionAnnotation: NSObject, MKAnnotation, VenueSelecting {
  let id: String
  @objc dynamic var coordinate: CLLocationCoordinate2D
  @objc dynamic var category: String = "pub"
  var venueId: String?

  init(id: String, coordinate: CLLocationCoordinate2D) {
    self.id = id
    self.coordinate = coordinate
    super.init()
  }
}

// =============================================================================
// 自绘 annotation 视图
// =============================================================================

/// 普通点位与选中点位共用的图标视图：显示分类 PNG，图片底部对齐地图坐标。
/// 普通态 22×28，选中态放大到 30×38（§1/§2）。
final class VenueIconAnnotationView: MKAnnotationView {

  private enum Metrics {
    static let normalSize = CGSize(width: 22, height: 28)
    static let selectedSize = CGSize(width: 30, height: 38)
  }

  private let iconView = UIImageView(frame: .zero)

  override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
    super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    addSubview(iconView)
    iconView.contentMode = .scaleAspectFit
    isUserInteractionEnabled = true
    if #available(iOS 11.0, *) {
      collisionMode = .circle
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func apply(icon: UIImage?, selected: Bool) {
    let size = selected ? Metrics.selectedSize : Metrics.normalSize
    iconView.image = icon

    UIView.performWithoutAnimation {
      bounds = CGRect(origin: .zero, size: size)
      iconView.frame = bounds
      // 锚点 = 图标底边中点（对应旧 iconAnchor BOTTOM）：
      // 视图中心上移半个高度 ⇒ centerOffset.y = -height/2。
      centerOffset = CGPoint(x: 0, y: -size.height / 2)
    }
  }
}

/// 文字标签 marker：资产图标在上、白描边文案在下，锚点对准图标底尖。
/// MapKit 没有文字碰撞 API（决策 D4），靠 Dart 抽样限流 + defaultLow 兜底。
final class MarkerAnnotationView: MKAnnotationView {

  private enum Metrics {
    static let iconSize = CGSize(width: 22, height: 28)
    static let sequenceHeight: CGFloat = 21
    static let sequenceMinimumWidth: CGFloat = 21
    static let sequenceHorizontalPadding: CGFloat = 8
    static let gap: CGFloat = 2
    static let maxLabelWidth: CGFloat = 170
  }

  private let iconView = UIImageView(frame: .zero)
  private let sequenceBadge = UILabel(frame: .zero)
  private let label = UILabel(frame: .zero)

  override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
    super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    addSubview(iconView)
    addSubview(sequenceBadge)
    addSubview(label)
    iconView.contentMode = .scaleAspectFit
    sequenceBadge.backgroundColor = UIColor.white
    sequenceBadge.textColor = UIColor(red: 0x9A / 255, green: 0x3D / 255, blue: 0x78 / 255, alpha: 1)
    sequenceBadge.font = UIFont.systemFont(ofSize: 12, weight: .black)
    sequenceBadge.textAlignment = .center
    sequenceBadge.layer.masksToBounds = true
    sequenceBadge.layer.borderColor = UIColor(red: 0x9A / 255, green: 0x3D / 255, blue: 0x78 / 255, alpha: 1).cgColor
    sequenceBadge.layer.borderWidth = 1
    label.numberOfLines = 1
    label.lineBreakMode = .byTruncatingTail
    isUserInteractionEnabled = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func setIcon(_ image: UIImage?) {
    iconView.image = image
    setNeedsLayout()
  }

  func setLabel(_ text: String) {
    // 白描边模拟旧版 textHalo（负 strokeWidth = 同时填充和描边）。
    label.attributedText = NSAttributedString(
      string: text,
      attributes: [
        .font: UIFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: UIColor(red: 0x0F / 255, green: 0x17 / 255, blue: 0x2A / 255, alpha: 1),
        .strokeColor: UIColor.white,
        .strokeWidth: -3.0,
      ]
    )
    setNeedsLayout()
  }

  func setSequence(_ value: Int?) {
    if let value = value, value > 0 {
      sequenceBadge.text = "\(value)"
      sequenceBadge.isHidden = false
      // 路线 marker 与高优先级圆点在同一坐标。设为必显并跳过碰撞
      // 淘汰，否则 MapKit 可能只保留圆点，把编号一起隐藏。
      displayPriority = .required
      collisionMode = .rectangle
    } else {
      sequenceBadge.text = nil
      sequenceBadge.isHidden = true
      displayPriority = .defaultLow
      collisionMode = .rectangle
    }
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    let attributedText = label.attributedText
    var textSize = CGSize.zero
    if let attributedText = attributedText, attributedText.length > 0 {
      textSize = (attributedText.string as NSString).size(
        withAttributes: attributedText.attributes(at: 0, effectiveRange: nil)
      )
    }
    let labelSize = CGSize(
      width: min(ceil(textSize.width) + 3, Metrics.maxLabelWidth),
      height: ceil(textSize.height)
    )

    let totalHeight = Metrics.iconSize.height + Metrics.gap + labelSize.height
    let totalWidth = max(Metrics.iconSize.width, min(labelSize.width, Metrics.maxLabelWidth))

    if bounds.size != CGSize(width: totalWidth, height: totalHeight) {
      bounds = CGRect(origin: .zero, size: CGSize(width: totalWidth, height: totalHeight))
    }

    UIView.performWithoutAnimation {
      // 1–9 显示为圆形；10、11… 根据数字位数扩展为胶囊形，
      // 路线点数量增加时不会出现数字挤压或截断。
      let sequenceWidth = max(
        Metrics.sequenceMinimumWidth,
        ceil(sequenceBadge.intrinsicContentSize.width) + Metrics.sequenceHorizontalPadding
      )
      sequenceBadge.layer.cornerRadius = Metrics.sequenceHeight / 2
      iconView.frame = CGRect(
        x: (totalWidth - Metrics.iconSize.width) / 2,
        y: 0,
        width: Metrics.iconSize.width,
        height: Metrics.iconSize.height
      )
      sequenceBadge.frame = CGRect(
        x: iconView.frame.maxX - sequenceWidth + 5,
        y: -5,
        width: sequenceWidth,
        height: Metrics.sequenceHeight
      )
      label.frame = CGRect(
        x: 0,
        y: Metrics.iconSize.height + Metrics.gap,
        width: totalWidth,
        height: labelSize.height
      )

      // 锚点 = 图标底尖（对应旧 iconAnchor BOTTOM + label 在下方）：
      // 第 anchorRow 行压住坐标点 ⇒ offset.y = midY - anchorRow。
      let anchorRow = Metrics.iconSize.height
      centerOffset = CGPoint(x: 0, y: bounds.midY - anchorRow)
    }
  }
}


