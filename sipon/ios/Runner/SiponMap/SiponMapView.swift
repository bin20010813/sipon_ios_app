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

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    compassTopInset: Double?,
    appBrightness: String?
  ) {
    channel = FlutterMethodChannel(
      name: SiponMapProtocol.channelName(viewId: viewId),
      binaryMessenger: messenger
    )
    engine = SiponMapEngine(
      mapView: mapView,
      diagnosticID: viewId,
      appBrightness: appBrightness,
      sendEvent: { [weak channel] name, arguments in
        // Dart 侧宿主在注册监听前到达的事件由缓存补发机制兜住。
        channel?.invokeMethod(name, arguments: arguments)
      }
    )
    super.init()

    if let topInset = compassTopInset, topInset.isFinite {
      // 系统控件自动同步 heading，并在点击时将地图朝向恢复正北。
      // 使用独立控件以避开 Flutter 的搜索栏；隐藏 MKMapView 默认指北针。
      mapView.showsCompass = false
      let compass = MKCompassButton(mapView: mapView)
      compass.compassVisibility = .visible
      compass.translatesAutoresizingMaskIntoConstraints = false
      mapView.addSubview(compass)
      NSLayoutConstraint.activate([
        compass.topAnchor.constraint(equalTo: mapView.topAnchor, constant: CGFloat(max(0, topInset))),
        compass.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -18),
        compass.widthAnchor.constraint(equalToConstant: 44),
        compass.heightAnchor.constraint(equalToConstant: 44),
      ])
    }

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
  private let diagnosticID: Int64
  #if DEBUG
  private var diagnosticCommand = "none"
  private var diagnosticCommandSequence = 0
  private var diagnosticRegionStart: CLLocationCoordinate2D?
  private var diagnosticDistanceStart: CLLocationDistance?
  #endif

  fileprivate func traceMotion(_ message: @autoclosure () -> String) {
    #if DEBUG
    NSLog("[SiponMapMotion] view=%lld %@", diagnosticID, message())
    #endif
  }

  fileprivate func traceRegion(_ phase: String, animated: Bool) {
    #if DEBUG
    let center = mapView.centerCoordinate
    let distance = mapView.camera.centerCoordinateDistance
    if phase == "REGION_BEGIN" {
      diagnosticRegionStart = center
      diagnosticDistanceStart = distance
    }
    let shift: String
    if let start = diagnosticRegionStart {
      let meters = CLLocation(latitude: center.latitude, longitude: center.longitude)
        .distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude))
      shift = String(format: "%.2f", meters)
    } else {
      shift = "unknown"
    }
    traceMotion("\(phase) animated=\(animated) center=\(center.latitude),\(center.longitude) centerShiftM=\(shift) distance=\(distance) distanceDelta=\(distance - (diagnosticDistanceStart ?? distance)) lastCommand=\(diagnosticCommand)#\(diagnosticCommandSequence)")
    if phase == "REGION_END" {
      diagnosticRegionStart = nil
      diagnosticDistanceStart = nil
    }
    #endif
  }
  /// 平台视图被拆掉后（detach/dispose）拒绝一切渲染类指令。
  private var alive = true

  private var styleId = "standard"
  private var appBrightness: UIUserInterfaceStyle

  private var lastFrameArguments: Any?

  // 各池：协议约定全量下发、原生按 id diff。
  private var circlesById: [String: CirclePointAnnotation] = [:]
  private var markersByVenueId: [String: MarkerAnnotation] = [:]
  private var selectionAnnotation: SelectionAnnotation?
  /// 选中态直接切换对应 marker 的视图，不再额外覆盖一枚 annotation。
  private var selectedVenueId: String?
  /// 每对相邻站点各有一条道路折线；分开绘制，避免跨段出现直线连接。
  private var routeOverlays: [MKPolyline] = []

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

  init(
    mapView: MKMapView,
    diagnosticID: Int64,
    appBrightness: String?,
    sendEvent: @escaping (String, Any?) -> Void
  ) {
    self.mapView = mapView
    self.diagnosticID = diagnosticID
    self.appBrightness = appBrightness == "dark" ? .dark : .light
    self.sendEvent = sendEvent
    super.init()
    mapView.delegate = proxy
    applyEffectiveAppearance()
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
    #if DEBUG
    if [SiponMapProtocol.Command.setup, SiponMapProtocol.Command.applyStage,
        SiponMapProtocol.Command.focusOn, SiponMapProtocol.Command.flyToCity,
        SiponMapProtocol.Command.setStyle].contains(method) {
      diagnosticCommandSequence += 1
      diagnosticCommand = method
      traceMotion("CAMERA_COMMAND #\(diagnosticCommandSequence) method=\(method) args=\(String(describing: arguments))")
    }
    #endif
    switch method {
    case SiponMapProtocol.Command.setup:
      handleSetup(SiponMapProtocol.dict(arguments) ?? [:])
      return nil
    case SiponMapProtocol.Command.setAppearance:
      if let args = SiponMapProtocol.dict(arguments),
         let brightness = SiponMapProtocol.string(args, "brightness") {
        setAppearance(brightness: brightness)
      }
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
        mapView.isPitchEnabled = SiponMapProtocol.double(args, "pitchEnabled", fallback: 0) != 0
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
        let latitude = SiponMapProtocol.double(args, "lat", fallback: .nan)
        let longitude = SiponMapProtocol.double(args, "lng", fallback: .nan)
        let focus = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        applyStage(
          bottomPadding: SiponMapProtocol.double(args, "bottomPadding", fallback: appliedBottomPadding),
          focus: CLLocationCoordinate2DIsValid(focus) ? focus : nil
        )
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
      clearRouteOverlays()
      return nil
    case SiponMapProtocol.Command.dispose:
      resetPools()
      return nil
    default:
      return nil
    }
  }

  // ------------------------------------------------------------------ 路径规划

  /// 每对相邻站点都通过 MKDirections 取得驾车道路路线；全部成功后才绘制。
  func planRoute(arguments: Any?, result: @escaping FlutterResult) {
    guard alive, configured else {
      result(false)
      return
    }
    // A new request replaces the old route even when its payload is invalid.
    cancelRoutePlanning()
    clearRouteOverlays()

    guard let args = SiponMapProtocol.dict(arguments),
          let rawPoints = args["points"] as? [[String: Any]] else {
      result(FlutterError(code: "sipon_route", message: "invalid points payload", details: nil))
      return
    }

    var coordinates: [CLLocationCoordinate2D] = []
    for raw in rawPoints {
      let lat = SiponMapProtocol.double(raw, "lat", fallback: .nan)
      let lng = SiponMapProtocol.double(raw, "lng", fallback: .nan)
      let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
      guard CLLocationCoordinate2DIsValid(coordinate), (lat != 0 || lng != 0) else {
        result(false)
        return
      }
      coordinates.append(coordinate)
    }
    guard coordinates.count >= 2 else {
      result(FlutterError(code: "sipon_route", message: "need at least 2 stops", details: nil))
      return
    }

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
        self.completeRoutePlanning(false, revision: revision)
        return
      }
      guard let leg = response?.routes.first?.polyline, leg.pointCount >= 2 else {
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

  /// 分别绘制每段道路折线，避免不同路段端点之间被补上一条直线。
  private func finishRoute(legs: [MKPolyline], revision: Int) {
    guard alive, configured, revision == routeRevision else { return }
    guard !legs.isEmpty else {
      completeRoutePlanning(false, revision: revision)
      return
    }

    drawRoutePolylines(legs)
    completeRoutePlanning(true, revision: revision)
  }

  /// 添加各段导航路线，并让相机显示其完整范围。
  private func drawRoutePolylines(_ legs: [MKPolyline]) {
    clearRouteOverlays()
    routeOverlays = legs
    for leg in legs {
      mapView.addOverlay(leg, level: .aboveRoads)
    }
    let bounds = legs.dropFirst().reduce(legs[0].boundingMapRect) { rect, leg in
      rect.union(leg.boundingMapRect)
    }
    mapView.setVisibleMapRect(
      bounds,
      edgePadding: UIEdgeInsets(top: 90, left: 60, bottom: 140, right: 60),
      animated: true
    )
  }

  /// 移除已绘制的所有道路路线。
  private func clearRouteOverlays() {
    for route in routeOverlays {
      mapView.removeOverlay(route)
    }
    routeOverlays.removeAll()
  }

  // ------------------------------------------------------------------ 初始配置

  private func handleSetup(_ args: [String: Any]) {
    configureBaseOptions()

    let city = SiponMapProtocol.string(args, "city") ?? "上海"
    styleId = SiponMapProtocol.string(args, "styleId") ?? "standard"
    apply(styleId: styleId)

    // 初始相机对齐旧版 attach 的语义：城市级视野一眼看到整片城区
    // （zoom 11.8 为城市级视野）。
    let cityCenter = SiponMapGeometry.cityCenter(named: city)
    let latitude = SiponMapProtocol.double(args, "lat", fallback: .nan)
    let longitude = SiponMapProtocol.double(args, "lng", fallback: .nan)
    let location = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let center = CLLocationCoordinate2DIsValid(location) ? location : cityCenter
    let zoom = CLLocationCoordinate2DIsValid(location)
      ? SiponMapGeometry.initialCityZoom + 3.2
      : SiponMapGeometry.initialCityZoom
    moveCamera(
      SiponMapProtocol.CameraMove(dict: [
        "lng": center.longitude,
        "lat": center.latitude,
        "zoom": zoom,
        "pitch": 0,
        "bearing": 0,
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
    // Let MapKit render the system user-location indicator (blue dot). The
    // Flutter side still obtains the coordinate through geolocator so it can
    // position the initial camera and load nearby venues; this flag keeps the
    // user's position visible on the map after the initial camera move.
    mapView.showsUserLocation = true
    mapView.isRotateEnabled = true
    mapView.isPitchEnabled = false
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

    if #available(iOS 16.0, *) {
      // POI 过滤必须设在 configuration 上：在 iOS 16+ 里 mapView 自身那个
      // pointOfInterestFilter 会被 preferredConfiguration 顶掉，写在那里不生效，
      // 结果就是底图上连便利店、地铁站的名称都没有。
      switch styleId {
      case "satellite":
        let configuration = MKHybridMapConfiguration()
        configuration.elevationStyle = .flat
        configuration.pointOfInterestFilter = .includingAll
        mapView.preferredConfiguration = configuration
      case "muted":
        let configuration = MKStandardMapConfiguration()
        configuration.elevationStyle = .flat
        configuration.emphasisStyle = .muted
        configuration.pointOfInterestFilter = .includingAll
        mapView.preferredConfiguration = configuration
      default:
        let configuration = MKStandardMapConfiguration()
        configuration.elevationStyle = .flat
        configuration.pointOfInterestFilter = .includingAll
        mapView.preferredConfiguration = configuration
      }
    } else {
      // 老版本没有配置对象，POI 开关就是 mapView 自己的属性。
      mapView.mapType = (styleId == "satellite") ? .hybrid : .standard
      mapView.pointOfInterestFilter = .includingAll
    }
    applyEffectiveAppearance()
  }

  private func setAppearance(brightness: String) {
    guard brightness == "light" || brightness == "dark" else { return }
    appBrightness = brightness == "dark" ? .dark : .light
    applyEffectiveAppearance()
  }

  /// Muted remains dark. Other map styles follow Flutter's resolved theme.
  private func applyEffectiveAppearance() {
    let effectiveStyle: UIUserInterfaceStyle = styleId == "muted" ? .dark : appBrightness
    mapView.overrideUserInterfaceStyle = effectiveStyle

    let isDark = effectiveStyle == .dark
    for annotation in mapView.annotations {
      (mapView.view(for: annotation) as? MarkerAnnotationView)?
        .applyAppearance(isDark: isDark)
    }
    for overlay in routeOverlays {
      (mapView.renderer(for: overlay) as? MKPolylineRenderer)?.strokeColor = routeStrokeColor
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
    // heading(顺时针度)。产品统一使用俯视 2D，原生强制 pitch = 0，避免旧版
    // Dart 指令或热重载状态把地图重新切回 3D。
    // 动画时长不可控，忽略 durationMs（决策 D3）。
    let distance = SiponMapGeometry.cameraDistance(
      lat: center.latitude,
      zoom: move.zoom,
      viewportHeight: size.height
    )
    let camera = MKMapCamera(
      lookingAtCenter: center,
      fromDistance: distance,
      pitch: 0,
      heading: move.bearing.truncatingRemainder(dividingBy: 360)
    )
    traceMotion("SET_CAMERA animated=\(animated) padding=\(move.bottomPadding) target=\(center.latitude),\(center.longitude) zoom=\(move.zoom)")
    mapView.setCamera(camera, animated: animated)

    appliedBottomPadding = move.bottomPadding
  }

  /// 面板拖动时若带有选中点，就保留当前缩放/朝向并把该点放在可见地图
  /// 中心；不带选中点时则沿用 padding 增量平移，供普通档位变化使用。
  private func applyStage(
    bottomPadding newPadding: Double,
    focus: CLLocationCoordinate2D? = nil
  ) {
    let delta = newPadding - appliedBottomPadding
    appliedBottomPadding = newPadding
    traceMotion("PADDING new=\(newPadding) delta=\(delta) anchored=\(focus != nil) willMove=\(abs(delta) > 0.5)")

    if let focus {
      let shifted = SiponMapGeometry.center(
        lat: focus.latitude,
        lng: focus.longitude,
        shiftingUpBy: newPadding,
        zoom: currentZoomEstimate()
      )
      let currentCamera = mapView.camera
      let camera = MKMapCamera(
        lookingAtCenter: shifted,
        fromDistance: currentCamera.centerCoordinateDistance,
        pitch: 0,
        heading: currentCamera.heading
      )
      // 该调用与面板本身同帧发生；禁用 MapKit 自带动画可避免相机落后于手指。
      mapView.setCamera(camera, animated: false)
      return
    }

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

  // MARK: marker diff（venueId 为键；评分/label 变化原地刷）

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
        existing.rating = spec.rating
        existing.sequence = spec.sequence
        if moved { existing.coordinate = spec.coordinate }
        // 坐标的 KVO 更新不能替代自定义 UIImageView/UILabel 的内容更新，
        // 即使视图一直留在屏幕内也应显示新的图标、文字与编号。
        if let view = mapView.view(for: existing) as? MarkerAnnotationView {
          view.setLabel(spec.label)
          view.setRating(spec.rating)
          view.setSequence(spec.sequence)
          view.setIcon(markerIcons[spec.category])
          view.setHighlighted(venueId == selectedVenueId)
        }
      } else {
        let annotation = MarkerAnnotation(venueId: venueId, coordinate: spec.coordinate)
        annotation.label = spec.label
        annotation.category = spec.category
        annotation.rating = spec.rating
        annotation.sequence = spec.sequence
        markersByVenueId[venueId] = annotation
        toAdd.append(annotation)
      }
    }

    if !toRemove.isEmpty { mapView.removeAnnotations(toRemove) }
    if !toAdd.isEmpty { mapView.addAnnotations(toAdd) }
  }

  // MARK: 选中状态 diff（胶囊切换为单独图标）

  private func diffSelection(_ selected: SiponMapProtocol.SelectedSpec?) {
    // 清理旧实现可能遗留的独立选中图标。
    if let existing = selectionAnnotation {
      selectionAnnotation = nil
      mapView.removeAnnotation(existing)
    }

    let previousVenueId = selectedVenueId
    let nextVenueId = selected?.venueId
    selectedVenueId = nextVenueId

    if let previousVenueId = previousVenueId,
       previousVenueId != nextVenueId,
       let annotation = markersByVenueId[previousVenueId],
       let view = mapView.view(for: annotation) as? MarkerAnnotationView {
      view.setHighlighted(false)
    }
    if let nextVenueId = nextVenueId,
       let annotation = markersByVenueId[nextVenueId],
       let view = mapView.view(for: annotation) as? MarkerAnnotationView {
      view.setHighlighted(true)
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
    for (venueId, annotation) in markersByVenueId {
      guard let view = mapView.view(for: annotation) as? MarkerAnnotationView else { continue }
      view.isHidden = markersHidden
      view.setHighlighted(venueId == selectedVenueId)
    }

    // 兼容旧实现遗留的独立选中图标。
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
    clearRouteOverlays()

    circlesById.removeAll()
    markersByVenueId.removeAll()
    selectionAnnotation = nil
    selectedVenueId = nil
    lastFrameArguments = nil
  }

  // ---- 给同文件内的 delegate proxy 的内部访问面（file-scope 可见）----

  fileprivate var currentZoomSnapshot: Double { currentZoomEstimate() }
  fileprivate var circlesHiddenSnapshot: Bool { circlesCurrentlyHidden() }
  fileprivate var markersHiddenSnapshot: Bool { markersCurrentlyHidden() }
  fileprivate func isSelectedVenue(_ venueId: String?) -> Bool {
    venueId != nil && venueId == selectedVenueId
  }
  fileprivate var shouldProcessEvents: Bool { alive && configured }
  fileprivate var hostMapView: MKMapView { mapView }
  fileprivate var usesDarkAppearance: Bool {
    styleId == "muted" || appBrightness == .dark
  }
  fileprivate var routeStrokeColor: UIColor {
    usesDarkAppearance
      ? UIColor(red: 0xE8 / 255, green: 0xA0 / 255, blue: 0xCC / 255, alpha: 1)
      : UIColor(red: 0x9A / 255, green: 0x3D / 255, blue: 0x78 / 255, alpha: 1)
  }

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
      view.setRating(marker.rating)
      view.setSequence(marker.sequence)
      view.setHighlighted(engine.isSelectedVenue(marker.venueId))
      view.applyAppearance(isDark: engine.usesDarkAppearance)
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
      renderer.strokeColor = engine.routeStrokeColor
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

  func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
    engine.traceRegion("REGION_BEGIN", animated: animated)
  }

  func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    engine.traceRegion("REGION_END", animated: animated)
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

  /// 标记交给系统 didSelect；指北针等控件处理自己的点击，不触发空白收起。
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
      if view is MKAnnotationView || view is MKCompassButton || view is UIControl {
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
  var rating: Double?
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
/// 普通态和选中态均按原尺寸的 2/3 显示。
final class VenueIconAnnotationView: MKAnnotationView {

  private enum Metrics {
    static let normalSize = CGSize(width: 22 * 2 / 3, height: 28 * 2 / 3)
    static let selectedSize = CGSize(width: 30 * 2 / 3, height: 38 * 2 / 3)
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
    layer.zPosition = selected ? 1000 : 0
    if #available(iOS 14.0, *) {
      zPriority = selected ? .max : .defaultUnselected
    }

    UIView.performWithoutAnimation {
      bounds = CGRect(origin: .zero, size: size)
      iconView.frame = bounds
      // 锚点 = 图标底边中点（对应旧 iconAnchor BOTTOM）：
      // 视图中心上移半个高度 ⇒ centerOffset.y = -height/2。
      centerOffset = CGPoint(x: 0, y: -size.height / 2)
    }
  }
}

/// 地图 marker：未选中时显示缩小的「分类图标 + 评分」胶囊，选中时只显示分类图标。
/// 路线站点只显示顺序编号圆圈与地点圆点。MapKit 没有文字碰撞 API（决策 D4），
/// 普通 POI 靠 Dart 抽样限流，路线站点则设为 required 保证顺序始终可见。
final class MarkerAnnotationView: MKAnnotationView {

  private enum Metrics {
    static let scale: CGFloat = 2.0 / 3.0
    static let capsuleSize = CGSize(width: 104 * scale, height: 44 * scale)
    static let capsuleTotalHeight: CGFloat = 50 * scale
    static let capsuleCornerRadius: CGFloat = 22 * scale
    static let capsuleIconCircle: CGFloat = 36 * scale
    static let capsuleIconSize: CGFloat = 22 * scale
    static let capsuleIconInset: CGFloat = 4 * scale
    static let capsuleTailSize: CGFloat = 10 * scale
    static let selectedIconSize = CGSize(width: 30 * scale, height: 38 * scale)
    static let sequenceDiameter: CGFloat = 26
    static let routeDotDiameter: CGFloat = 14
    static let routeGap: CGFloat = 4
  }

  private let capsule = UIView(frame: .zero)
  private let capsuleTail = UIView(frame: .zero)
  private let iconCircle = UIView(frame: .zero)
  private let iconView = UIImageView(frame: .zero)
  private let ratingLabel = UILabel(frame: .zero)
  private let sequenceBadge = UILabel(frame: .zero)
  private let label = UILabel(frame: .zero)
  private var sourceIcon: UIImage?
  private var currentLabel = ""
  private var currentRatingText = "--"
  private var isRouteMarker = false
  private var isPoiHighlighted = false
  private var usesDarkAppearance = false

  override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
    super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    addSubview(capsuleTail)
    addSubview(capsule)
    addSubview(iconCircle)
    addSubview(iconView)
    addSubview(ratingLabel)
    addSubview(sequenceBadge)
    addSubview(label)

    capsule.backgroundColor = .white
    capsule.isUserInteractionEnabled = false
    capsule.layer.cornerRadius = Metrics.capsuleCornerRadius
    capsuleTail.backgroundColor = .white
    capsuleTail.isUserInteractionEnabled = false
    capsuleTail.transform = CGAffineTransform(rotationAngle: .pi / 4)
    iconCircle.backgroundColor = UIColor(
      red: 0x9A / 255,
      green: 0x3D / 255,
      blue: 0x78 / 255,
      alpha: 1
    )
    iconCircle.isUserInteractionEnabled = false
    iconCircle.layer.cornerRadius = Metrics.capsuleIconCircle / 2
    iconView.contentMode = .scaleAspectFit
    iconView.tintColor = .white
    ratingLabel.text = "--"
    ratingLabel.textColor = UIColor(
      red: 0x10 / 255,
      green: 0x10 / 255,
      blue: 0x10 / 255,
      alpha: 1
    )
    ratingLabel.font = UIFont.systemFont(ofSize: 16 * Metrics.scale, weight: .semibold)
    ratingLabel.textAlignment = .center
    ratingLabel.adjustsFontSizeToFitWidth = true
    ratingLabel.minimumScaleFactor = 0.85
    sequenceBadge.backgroundColor = UIColor.white
    sequenceBadge.textColor = UIColor(red: 0x9A / 255, green: 0x3D / 255, blue: 0x78 / 255, alpha: 1)
    sequenceBadge.font = UIFont.systemFont(ofSize: 12, weight: .bold)
    sequenceBadge.textAlignment = .center
    sequenceBadge.adjustsFontSizeToFitWidth = true
    sequenceBadge.minimumScaleFactor = 0.7
    sequenceBadge.layer.masksToBounds = true
    sequenceBadge.layer.borderColor = UIColor(red: 0x9A / 255, green: 0x3D / 255, blue: 0x78 / 255, alpha: 1).cgColor
    sequenceBadge.layer.borderWidth = 1.5
    label.numberOfLines = 1
    label.lineBreakMode = .byTruncatingTail
    isUserInteractionEnabled = true
    isAccessibilityElement = true
    accessibilityTraits = .button

    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.12
    layer.shadowRadius = 9
    layer.shadowOffset = CGSize(width: 0, height: 3)
    applyAppearance(isDark: false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func applyAppearance(isDark: Bool) {
    usesDarkAppearance = isDark
    let surface = isDark
      ? UIColor(red: 0x21 / 255, green: 0x1C / 255, blue: 0x22 / 255, alpha: 1)
      : .white
    let foreground = isDark
      ? UIColor(red: 0xF5 / 255, green: 0xEF / 255, blue: 0xF4 / 255, alpha: 1)
      : UIColor(red: 0x10 / 255, green: 0x10 / 255, blue: 0x10 / 255, alpha: 1)
    let outline = isDark
      ? UIColor(red: 0x4A / 255, green: 0x3D / 255, blue: 0x48 / 255, alpha: 1)
      : UIColor(red: 0x9A / 255, green: 0x3D / 255, blue: 0x78 / 255, alpha: 1)

    capsule.backgroundColor = surface
    capsuleTail.backgroundColor = surface
    ratingLabel.textColor = foreground
    sequenceBadge.backgroundColor = surface
    sequenceBadge.textColor = isDark
      ? UIColor(red: 0xE8 / 255, green: 0xA0 / 255, blue: 0xCC / 255, alpha: 1)
      : outline
    sequenceBadge.layer.borderColor = outline.cgColor
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = isDark ? 0.35 : 0.12
    updateLabelAppearance()
    setNeedsLayout()
  }

  private func updateLabelAppearance() {
    let foreground = usesDarkAppearance
      ? UIColor(red: 0xF5 / 255, green: 0xEF / 255, blue: 0xF4 / 255, alpha: 1)
      : UIColor(red: 0x0F / 255, green: 0x17 / 255, blue: 0x2A / 255, alpha: 1)
    let halo = usesDarkAppearance
      ? UIColor(red: 0x21 / 255, green: 0x1C / 255, blue: 0x22 / 255, alpha: 1)
      : UIColor.white
    label.attributedText = NSAttributedString(
      string: currentLabel,
      attributes: [
        .font: UIFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: foreground,
        .strokeColor: halo,
        .strokeWidth: -3.0,
      ]
    )
  }

  func setIcon(_ image: UIImage?) {
    sourceIcon = image
    updateIconRenderingMode()
    setNeedsLayout()
  }

  func setLabel(_ text: String) {
    currentLabel = text
    updateLabelAppearance()
    updateAccessibilityLabel()
    setNeedsLayout()
  }

  func setRating(_ value: Double?) {
    if let value = value, value.isFinite, value > 0 {
      currentRatingText = String(format: "%.1f", value)
    } else {
      currentRatingText = "--"
    }
    ratingLabel.text = currentRatingText
    updateAccessibilityLabel()
    setNeedsLayout()
  }

  func setSequence(_ value: Int?) {
    if let value = value, value > 0 {
      isRouteMarker = true
      sequenceBadge.text = "\(value)"
      sequenceBadge.isHidden = false
      // 路线 marker 自己包含编号与圆点，必须始终可见。
      displayPriority = .required
      collisionMode = .rectangle
    } else {
      isRouteMarker = false
      sequenceBadge.text = nil
      sequenceBadge.isHidden = true
      displayPriority = isPoiHighlighted ? .required : .defaultLow
      collisionMode = .rectangle
    }
    updateIconRenderingMode()
    updateAccessibilityLabel()
    setNeedsLayout()
  }

  /// 选中时切换为单独的分类图标，不显示胶囊和评分。
  func setHighlighted(_ highlighted: Bool) {
    guard isPoiHighlighted != highlighted else { return }
    isPoiHighlighted = highlighted

    layer.zPosition = highlighted ? 1000 : 0
    displayPriority = highlighted || isRouteMarker ? .required : .defaultLow
    if #available(iOS 14.0, *) {
      zPriority = highlighted ? .max : .defaultUnselected
    }
    if highlighted {
      accessibilityTraits.insert(.selected)
    } else {
      accessibilityTraits.remove(.selected)
    }
    updateIconRenderingMode()
    updateAccessibilityLabel()
    setNeedsLayout()
  }

  private func updateIconRenderingMode() {
    iconView.image = sourceIcon?.withRenderingMode(
      isPoiHighlighted ? .alwaysOriginal : .alwaysTemplate
    )
  }

  private func updateAccessibilityLabel() {
    if isRouteMarker {
      accessibilityLabel = "第\(sequenceBadge.text ?? "-")站，\(currentLabel)"
    } else if isPoiHighlighted {
      accessibilityLabel = currentLabel
    } else if currentLabel.isEmpty {
      accessibilityLabel = "评分 \(currentRatingText)"
    } else {
      accessibilityLabel = "\(currentLabel)，评分 \(currentRatingText)"
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if isRouteMarker {
      layoutRouteMarker()
    } else if isPoiHighlighted {
      layoutSelectedIcon()
    } else {
      layoutCapsule()
    }
  }

  private func layoutSelectedIcon() {
    capsule.isHidden = true
    capsuleTail.isHidden = true
    iconCircle.isHidden = true
    ratingLabel.isHidden = true
    sequenceBadge.isHidden = true
    label.isHidden = true
    iconView.isHidden = false
    layer.shadowPath = nil
    layer.shadowOpacity = 0

    let size = Metrics.selectedIconSize
    if bounds.size != size {
      bounds = CGRect(origin: .zero, size: size)
    }
    UIView.performWithoutAnimation {
      iconView.frame = bounds
      centerOffset = CGPoint(x: 0, y: -size.height / 2)
    }
  }

  private func layoutCapsule() {
    capsule.isHidden = false
    capsuleTail.isHidden = false
    iconCircle.isHidden = false
    iconView.isHidden = false
    ratingLabel.isHidden = false
    sequenceBadge.isHidden = true
    label.isHidden = true
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = usesDarkAppearance ? 0.35 : 0.12
    layer.shadowRadius = 9 * Metrics.scale
    layer.shadowOffset = CGSize(width: 0, height: 3 * Metrics.scale)

    let totalSize = CGSize(
      width: Metrics.capsuleSize.width,
      height: Metrics.capsuleTotalHeight
    )
    if bounds.size != totalSize {
      bounds = CGRect(origin: .zero, size: totalSize)
    }

    UIView.performWithoutAnimation {
      capsule.frame = CGRect(origin: .zero, size: Metrics.capsuleSize)
      capsuleTail.bounds = CGRect(
        x: 0,
        y: 0,
        width: Metrics.capsuleTailSize,
        height: Metrics.capsuleTailSize
      )
      capsuleTail.center = CGPoint(
        x: Metrics.capsuleSize.width / 2,
        y: Metrics.capsuleSize.height - Metrics.scale
      )
      iconCircle.frame = CGRect(
        x: Metrics.capsuleIconInset,
        y: Metrics.capsuleIconInset,
        width: Metrics.capsuleIconCircle,
        height: Metrics.capsuleIconCircle
      )
      iconCircle.layer.cornerRadius = Metrics.capsuleIconCircle / 2
      iconView.frame = CGRect(
        x: iconCircle.frame.midX - Metrics.capsuleIconSize / 2,
        y: iconCircle.frame.midY - Metrics.capsuleIconSize / 2,
        width: Metrics.capsuleIconSize,
        height: Metrics.capsuleIconSize
      )
      ratingLabel.frame = CGRect(
        x: iconCircle.frame.maxX + 4 * Metrics.scale,
        y: 0,
        width: Metrics.capsuleSize.width - iconCircle.frame.maxX - 8 * Metrics.scale,
        height: Metrics.capsuleSize.height
      )
      let shadowPath = UIBezierPath(
        roundedRect: capsule.frame,
        cornerRadius: Metrics.capsuleCornerRadius
      )
      shadowPath.move(to: CGPoint(
        x: bounds.midX - 6 * Metrics.scale,
        y: Metrics.capsuleSize.height - Metrics.scale
      ))
      shadowPath.addLine(to: CGPoint(x: bounds.midX, y: Metrics.capsuleTotalHeight))
      shadowPath.addLine(to: CGPoint(
        x: bounds.midX + 6 * Metrics.scale,
        y: Metrics.capsuleSize.height - Metrics.scale
      ))
      shadowPath.close()
      layer.shadowPath = shadowPath.cgPath

      // 胶囊尾尖落在 POI 坐标上。
      centerOffset = CGPoint(x: 0, y: -Metrics.capsuleTotalHeight / 2)
    }
  }

  private func layoutRouteMarker() {
    capsule.isHidden = true
    capsuleTail.isHidden = true
    iconCircle.isHidden = false
    iconView.isHidden = true
    ratingLabel.isHidden = true
    label.isHidden = true
    sequenceBadge.isHidden = false

    let diameter = Metrics.sequenceDiameter
    let height = diameter + Metrics.routeGap + Metrics.routeDotDiameter
    let size = CGSize(width: diameter, height: height)
    if bounds.size != size { bounds = CGRect(origin: .zero, size: size) }

    UIView.performWithoutAnimation {
      sequenceBadge.layer.cornerRadius = diameter / 2
      sequenceBadge.frame = CGRect(
        x: 0, y: 0, width: diameter, height: diameter
      )
      iconCircle.layer.cornerRadius = Metrics.routeDotDiameter / 2
      iconCircle.frame = CGRect(
        x: (diameter - Metrics.routeDotDiameter) / 2,
        y: diameter + Metrics.routeGap,
        width: Metrics.routeDotDiameter,
        height: Metrics.routeDotDiameter
      )

      layer.shadowPath = nil
      layer.shadowOpacity = 0
      // 最下方圆点的中心对准酒吧坐标。
      centerOffset = CGPoint(x: 0, y: -height / 2 + Metrics.routeDotDiameter / 2)
    }
  }
}
