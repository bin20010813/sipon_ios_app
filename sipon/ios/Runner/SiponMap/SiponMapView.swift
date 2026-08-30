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
      result(self.engine.handle(method: call.method, arguments: call.arguments))
    }
  }

  func view() -> UIView { mapView }
}

// =============================================================================
// SiponMapEngine —— MKMapView 的唯一业务负责人。
//
// 渲染走「整帧下发、按 id diff」的约定（指南 §3i）；分级显隐的决策由 Dart
// 算好（layerMode / 淡入区间常量），原生只负责执行与捏合过程中的连续插值。
// =============================================================================

final class SiponMapEngine: NSObject {

  private unowned let mapView: MKMapView
  private let sendEvent: (String, Any?) -> Void

  /// 收到 setup 并完成初始配置之后才接受后续指令。
  private var configured = false
  /// 平台视图被拆掉后（detach/dispose）拒绝一切渲染类指令。
  private var alive = true

  private var styleId = "standard"

  /// 当前生效的图层模式（Dart 决策结果的镜像）。
  private var showsPoints = true
  private var showsHeatmap = true
  private var lastFrameArguments: Any?

  // 各池：协议约定全量下发、原生按 id diff。
  private var circlesById: [String: CirclePointAnnotation] = [:]
  private var markersByVenueId: [String: MarkerAnnotation] = [:]
  private var selectionAnnotation: SelectionAnnotation?
  private var heatOverlaysByKey: [SiponMapGeometry.GridKey: DensityCellOverlay] = [:]

  /// marker 图标资产缓存（kind.id → UIImage）与选中 halo 色环缓存。
  private var markerIcons: [String: UIImage] = [:]
  private var selectionHalos: [String: UIImage] = [:]

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
        // 让幂等的 id-diff 把热力等建回来（§3b 兜底）。
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
    case SiponMapProtocol.Command.dispose:
      resetPools()
      return nil
    default:
      return nil
    }
  }

  // ------------------------------------------------------------------ 初始配置

  private func handleSetup(_ args: [String: Any]) {
    configureBaseOptions()

    let city = SiponMapProtocol.string(args, "city") ?? "上海"
    styleId = SiponMapProtocol.string(args, "styleId") ?? "standard"
    apply(styleId: styleId)

    // 初始相机对齐旧版 attach 的语义：城市级视野一眼看到整片城区
    // （zoom 11.8 略低于热力分界线，进页即见整张热力图）。
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
    if #available(iOS 13.0, *) {
      mapView.pointOfInterestFilter = .includingAll
    }
  }

  /// 底图三档切换。iOS 16+ 用 MKMapConfiguration（muted emphasis +
  /// 强制深色界面近似原 dark）；低版本降级到老 mapType 枚举，
  /// muted 退化为普通浅色（决策 D5）。
  func apply(styleId: String) {
    self.styleId = styleId
    mapView.overrideUserInterfaceStyle = .unspecified

    if #available(iOS 16.0, *) {
      switch styleId {
      case "satellite":
        mapView.preferredConfiguration = MKHybridMapConfiguration()
      case "muted":
        let configuration = MKStandardMapConfiguration()
        configuration.emphasisStyle = .muted
        mapView.preferredConfiguration = configuration
        mapView.overrideUserInterfaceStyle = .dark
      default:
        mapView.preferredConfiguration = MKStandardMapConfiguration()
      }
    } else {
      mapView.mapType = (styleId == "satellite") ? .hybrid : .standard
    }
  }

  private func registerMarkerAssets(_ args: [String: Any]) {
    guard let assets = SiponMapProtocol.dict(args["assets"]) as? [String: String] else { return }

    for (category, assetKey) in assets {
      let bundleKey = FlutterDartProject.lookupKey(forAsset: assetKey)
      guard markerIcons[category] == nil,
            let path = Bundle.main.path(forResource: bundleKey, ofType: nil),
            let image = UIImage(contentsOfFile: path) else { continue }
      markerIcons[category] = image
    }

    // 图标后到的场景：把已上屏的 marker 视图补上图标。
    for (_, annotation) in markersByVenueId {
      (mapView.view(for: annotation) as? MarkerAnnotationView)?
        .setIcon(markerIcons[annotation.category])
    }
  }

  // ------------------------------------------------------------------ 相机

  private func viewportSize() -> CGSize {
    if mapView.bounds.width > 1, mapView.bounds.height > 1 {
      return mapView.bounds.size
    }
    return UIScreen.main.bounds.size
  }

  private func currentZoomEstimate() -> Double {
    let spanDelta = mapView.region.span.longitudeDelta
    guard spanDelta.isFinite, spanDelta > 0 else {
      return SiponMapGeometry.initialCityZoom
    }
    return SiponMapGeometry.zoom(
      longitudeDelta: spanDelta,
      width: viewportSize().width
    )
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

    showsPoints = frame.showsPoints
    showsHeatmap = frame.showsHeatmap

    diffCircles(frame.circles)
    diffMarkers(frame.markers)
    diffSelection(frame.selected)
    diffHeatmap(frame.heatSamples)

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
    var refreshedViews: [CirclePointAnnotationView] = []

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
        if changed {
          if let view = mapView.view(for: existing) as? CirclePointAnnotationView {
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

    let zoom = currentZoomEstimate()
    for view in refreshedViews {
      if let annotation = view.annotation as? CirclePointAnnotation {
        view.apply(
          category: annotation.category,
          radius: SiponMapGeometry.circleRadius(zoom: zoom),
          alpha: CGFloat(currentCircleFade())
        )
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
        if moved { existing.coordinate = spec.coordinate }
        if !moved {
          (mapView.view(for: existing) as? MarkerAnnotationView)?.setLabel(spec.label)
        }
      } else {
        let annotation = MarkerAnnotation(venueId: venueId, coordinate: spec.coordinate)
        annotation.label = spec.label
        annotation.category = spec.category
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
           let view = mapView.view(for: existing) as? SelectionAnnotationView {
          refreshSelection(view, annotation: existing)
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

  // MARK: 热力 diff（先聚合 → 格 key 对比 → overlay 增删）

  private func diffHeatmap(_ samples: [SiponMapGeometry.HeatSample]) {
    let aggregated = SiponMapGeometry.aggregateHeatmap(samples, zoom: currentZoomEstimate())

    // 手动锁「点位」时目标集合清空而不是删数据：下一帧带热力自然重建。
    let targetKeys = showsHeatmap ? Set(aggregated.keys) : Set<SiponMapGeometry.GridKey>()

    var toRemove: [MKOverlay] = []
    for (key, overlay) in heatOverlaysByKey where !targetKeys.contains(key) {
      toRemove.append(overlay)
      heatOverlaysByKey.removeValue(forKey: key)
    }

    var toAdd: [MKOverlay] = []
    for key in targetKeys.sorted(by: { $0.column < $1.column }) {
      guard let cell = aggregated[key], heatOverlaysByKey[key] == nil else { continue }
      let overlay = DensityCellOverlay(cell: cell)
      heatOverlaysByKey[key] = overlay
      toAdd.append(overlay)
    }

    if !toRemove.isEmpty { mapView.removeOverlays(toRemove) }
    if !toAdd.isEmpty { mapView.addOverlays(toAdd) }
  }

  // ------------------------------------------------------- 动态样式（缩放联动）

  /// 「热力图可接手」= 手动没锁「点位」，与 Dart _applyZoomHandoff(armed:) 同义：
  /// 分界线以下圆点退场的前提是有热力图来接手画面。
  private var heatmapArmed: Bool { showsHeatmap }

  private func currentCircleFade() -> Double {
    SiponMapGeometry.circleFade(zoom: currentZoomEstimate(), heatmapArmed: heatmapArmed)
  }

  private func circlesCurrentlyHidden() -> Bool {
    !showsPoints || currentCircleFade() <= 0.02
  }

  private func markersCurrentlyHidden() -> Bool {
    !showsPoints || (heatmapArmed && currentZoomEstimate() < SiponMapGeometry.handoffZoom)
  }

  private func refreshSelection(
    _ view: SelectionAnnotationView,
    annotation: SelectionAnnotation
  ) {
    let zoom = currentZoomEstimate()
    view.apply(
      haloImage: haloImage(for: annotation.category),
      categoryColor: SiponVenueStyle.color(for: annotation.category),
      coreRadius: SiponMapGeometry.selectionCoreRadius(zoom: zoom),
      haloRadius: SiponMapGeometry.selectionHaloRadius(zoom: zoom)
    )
  }

  private func haloImage(for category: String) -> UIImage {
    if let cached = selectionHalos[category] { return cached }
    let image = SelectionAnnotationView.makeHaloImage(color: SiponVenueStyle.color(for: category))
    selectionHalos[category] = image
    return image
  }

  /// 捏合过程中的连续淡入淡出 + 分界线以下硬摘除。只在视野变化回调里执行；
  /// 决策仍全部来自 Dart 已同步的模式与区间常量，原生不做规则判断。
  ///
  /// 圆点在淡出阈值之下直接 `isHidden`：透明度为 0 的圆点照样命中点击，
  /// 会「在热力图上点到看不见的酒吧」（原 668 行注释的同款问题）。
  func refreshDynamicStyling() {
    guard alive, configured else { return }

    let zoom = currentZoomEstimate()
    let fade = currentCircleFade()
    let circlesHidden = circlesCurrentlyHidden()

    for (_, annotation) in circlesById {
      guard let view = mapView.view(for: annotation) as? CirclePointAnnotationView else { continue }
      view.isHidden = circlesHidden
      if !circlesHidden {
        view.apply(
          category: annotation.category,
          radius: SiponMapGeometry.circleRadius(zoom: zoom),
          alpha: CGFloat(fade)
        )
      }
    }

    let markersHidden = markersCurrentlyHidden()
    for (_, annotation) in markersByVenueId {
      (mapView.view(for: annotation) as? MarkerAnnotationView)?.isHidden = markersHidden
    }

    // 选中高亮只随缩放调尺寸，不跟模式隐藏（它是详情卡片指向的唯一锚点）。
    if let annotation = selectionAnnotation,
       let view = mapView.view(for: annotation) as? SelectionAnnotationView {
      refreshSelection(view, annotation: annotation)
    }
  }

  // ------------------------------------------------------------------ 内务

  private func resetPools() {
    alive = false
    mapView.removeAnnotations(Array(circlesById.values))
    mapView.removeAnnotations(Array(markersByVenueId.values))
    if let selection = selectionAnnotation {
      mapView.removeAnnotation(selection)
    }
    mapView.removeOverlays(Array(heatOverlaysByKey.values))

    circlesById.removeAll()
    markersByVenueId.removeAll()
    selectionAnnotation = nil
    heatOverlaysByKey.removeAll()
    lastFrameArguments = nil
  }

  // ---- 给同文件内的 delegate proxy 的内部访问面（file-scope 可见）----

  fileprivate var currentZoomSnapshot: Double { currentZoomEstimate() }
  fileprivate var circleFadeSnapshot: Double { currentCircleFade() }
  fileprivate var circlesHiddenSnapshot: Bool { circlesCurrentlyHidden() }
  fileprivate var markersHiddenSnapshot: Bool { markersCurrentlyHidden() }
  fileprivate var shouldProcessEvents: Bool { alive && configured }
  fileprivate var hostMapView: MKMapView { mapView }

  fileprivate func icon(for category: String) -> UIImage? { markerIcons[category] }
  fileprivate func cachedHalo(for category: String) -> UIImage { haloImage(for: category) }

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
    return recognizer
  }()

  // MARK: annotation view 复用池

  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    let zoom = engine.currentZoomSnapshot
    let fade = CGFloat(engine.circleFadeSnapshot)

    switch annotation {
    case let circle as CirclePointAnnotation:
      let identifier = "sipon.circle.\(circle.category)"
      let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        as? CirclePointAnnotationView)
        ?? CirclePointAnnotationView(annotation: circle, reuseIdentifier: identifier)
      view.annotation = circle
      view.apply(
        category: circle.category,
        radius: SiponMapGeometry.circleRadius(zoom: zoom),
        alpha: fade
      )
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
      view.displayPriority = .defaultLow
      view.isHidden = engine.markersHiddenSnapshot
      return view
    case let selection as SelectionAnnotation:
      let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "sipon.selection")
        as? SelectionAnnotationView)
        ?? SelectionAnnotationView(annotation: selection, reuseIdentifier: "sipon.selection")
      view.annotation = selection
      view.apply(
        haloImage: engine.cachedHalo(for: selection.category),
        categoryColor: SiponVenueStyle.color(for: selection.category),
        coreRadius: SiponMapGeometry.selectionCoreRadius(zoom: zoom),
        haloRadius: SiponMapGeometry.selectionHaloRadius(zoom: zoom)
      )
      // 高亮必须置顶；热力层级下它仍是唯一可点击的点（原 352 行注释）。
      view.displayPriority = .required
      return view
    default:
      return nil
    }
  }

  // MARK: 热力渲染器

  func mapView(
    _ mapView: MKMapView,
    rendererFor overlay: MKOverlay
  ) -> MKOverlayRenderer {
    if let cell = overlay as? DensityCellOverlay {
      return DensityGradientRenderer(cell: cell)
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

  /// 放过落在任何可见 annotation view 上的触摸，让它走系统 didSelect（§3a）。
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldReceive touch: UITouch
  ) -> Bool {
    let mapView = engine.hostMapView
    let point = touch.location(in: mapView)
    let hitOnAnnotation = mapView.subviews.contains { subview in
      subview is MKAnnotationView
        && subview.frame.contains(point)
        && !subview.isHidden
        && subview.alpha > 0.01
    }
    return !hitOnAnnotation
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
// 分类配色（与 Dart MapVenueKind.circleRgb 一致；新增类型改这里一处）
// =============================================================================

enum SiponVenueStyle {
  static func color(for category: String) -> UIColor {
    switch category {
    case "craft":
      return UIColor(red: 0x0D / 255, green: 0x94 / 255, blue: 0x88 / 255, alpha: 1)
    case "bistro":
      return UIColor(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255, alpha: 1)
    case "party":
      return UIColor(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255, alpha: 1)
    case "livehouse":
      return UIColor(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255, alpha: 1)
    default:
      return UIColor(red: 0x9A / 255, green: 0x3D / 255, blue: 0x78 / 255, alpha: 1) // pub
    }
  }
}

// =============================================================================
// 自绘 annotation 视图
// =============================================================================

/// 圆点：frame 取 max(视觉直径+3pt 描边, 22pt) 保命中区，视觉是内嵌 layer。
/// 这替代了原来 18px 方框查询的 tapSlop（§3c）。
final class CirclePointAnnotationView: MKAnnotationView {

  static let minimumHitDiameter: CGFloat = 22
  private static let borderInset: CGFloat = 1.5

  private let dotLayer = CALayer()

  override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
    super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    layer.addSublayer(dotLayer)
    dotLayer.borderColor = UIColor.white.cgColor
    dotLayer.borderWidth = Self.borderInset * 2
    isUserInteractionEnabled = true
    if #available(iOS 11.0, *) {
      collisionMode = .circle
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func apply(category: String, radius: CGFloat, alpha: CGFloat) {
    let visualDiameter = max(radius * 2, 3)
    let hitDiameter = max(visualDiameter + Self.borderInset * 2, Self.minimumHitDiameter)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    bounds = CGRect(origin: .zero, size: CGSize(width: hitDiameter, height: hitDiameter))
    dotLayer.backgroundColor = SiponVenueStyle.color(for: category).cgColor
    self.alpha = max(0, min(alpha, 1))
    layoutDot(visualDiameter: visualDiameter)
    CATransaction.commit()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let visualDiameter = bounds.width - Self.borderInset * 2
    layoutDot(visualDiameter: visualDiameter)
  }

  private func layoutDot(visualDiameter: CGFloat) {
    dotLayer.frame = bounds.insetBy(
      dx: (bounds.width - visualDiameter) / 2,
      dy: (bounds.height - visualDiameter) / 2
    )
    dotLayer.cornerRadius = visualDiameter / 2
  }
}

/// 文字标签 marker：资产图标在上、白描边文案在下，锚点对准图标底尖。
/// MapKit 没有文字碰撞 API（决策 D4），靠 Dart 抽样限流 + defaultLow 兜底。
final class MarkerAnnotationView: MKAnnotationView {

  private enum Metrics {
    static let iconSize = CGSize(width: 22, height: 28)
    static let gap: CGFloat = 2
    static let maxLabelWidth: CGFloat = 170
  }

  private let iconView = UIImageView(frame: .zero)
  private let label = UILabel(frame: .zero)

  override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
    super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    addSubview(iconView)
    addSubview(label)
    iconView.contentMode = .scaleAspectFit
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
      iconView.frame = CGRect(
        x: (totalWidth - Metrics.iconSize.width) / 2,
        y: 0,
        width: Metrics.iconSize.width,
        height: Metrics.iconSize.height
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

/// 选中高亮：外圈径向渐变 halo + 白描边实心核；置顶且仍可点击。
final class SelectionAnnotationView: MKAnnotationView {

  private let haloLayer = CALayer()
  private let coreLayer = CALayer()

  override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
    super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    layer.addSublayer(haloLayer)
    layer.addSublayer(coreLayer)
    coreLayer.borderWidth = 3
    coreLayer.borderColor = UIColor.white.cgColor
    isUserInteractionEnabled = true
    if #available(iOS 11.0, *) {
      collisionMode = .circle
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func apply(
    haloImage: UIImage,
    categoryColor: UIColor,
    coreRadius: CGFloat,
    haloRadius: CGFloat
  ) {
    let haloDiameter = max(haloRadius * 2, 10)
    let coreDiameter = max(coreRadius * 2, 4)
    let diameter = max(haloDiameter, coreDiameter)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    bounds = CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter))

    haloLayer.contents = haloImage.cgImage
    haloLayer.contentsGravity = .resize
    haloLayer.frame = CGRect(x: 0, y: 0, width: haloDiameter, height: haloDiameter)
      .offsetBy(dx: (diameter - haloDiameter) / 2, dy: (diameter - haloDiameter) / 2)

    coreLayer.backgroundColor = categoryColor.cgColor
    coreLayer.frame = CGRect(x: 0, y: 0, width: coreDiameter, height: coreDiameter)
      .offsetBy(dx: (diameter - coreDiameter) / 2, dy: (diameter - coreDiameter) / 2)
    coreLayer.cornerRadius = coreDiameter / 2
    CATransaction.commit()
  }

  /// 径向渐变 halo（模拟旧版 opacity 0.22 + blur 0.35），按类别色缓存。
  static func makeHaloImage(color: UIColor) -> UIImage {
    let side: CGFloat = 96
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
    return renderer.image { context in
      let cgContext = context.cgContext
      let colors = [
        color.withAlphaComponent(0.5).cgColor,
        color.withAlphaComponent(0.22).cgColor,
        color.withAlphaComponent(0).cgColor,
      ] as CFArray
      guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 0.45, 1]
      ) else { return }
      let center = CGPoint(x: side / 2, y: side / 2)
      cgContext.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: side / 2,
        options: [.drawsBeforeStartLocation]
      )
    }
  }
}

// =============================================================================
// 热力密度格 overlay 与径向渐变渲染器（§3d 降级方案，参数留常量便于调优）
// =============================================================================

final class DensityCellOverlay: NSObject, MKOverlay {
  let density: Double
  let coordinate: CLLocationCoordinate2D
  let radiusMeters: Double
  let boundingMapRect: MKMapRect

  init(cell: SiponMapGeometry.DensityCell) {
    density = cell.density
    coordinate = cell.coordinate
    radiusMeters = cell.radiusMeters

    let center = MKMapPoint(coordinate)
    let metersPerMapPoint = MKMetersPerMapPointAtLatitude(coordinate.latitude)
    let radiusMapPoints = radiusMeters / metersPerMapPoint
    boundingMapRect = MKMapRect(
      x: center.x - radiusMapPoints,
      y: center.y - radiusMapPoints,
      width: radiusMapPoints * 2,
      height: radiusMapPoints * 2
    )

    super.init()
  }
}

/// 径向渐变填充：中心浓、边缘羽化到透明，替代 GPU 核密度平滑。
final class DensityGradientRenderer: MKOverlayRenderer {

  private let density: Double

  init(cell: DensityCellOverlay) {
    density = cell.density
    super.init(overlay: cell)
  }

  override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
    let rect = self.rect(for: overlay.boundingMapRect)
    guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
    let circlePath = CGPath(ellipseIn: rect, transform: nil)

    let base = SiponHeatPalette.color(for: density)
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    base.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

    // 低密度也保一点可见度，避免大量空格子隐形成斑驳噪点。
    let strength = max(density, 0.12)

    context.saveGState()
    context.addPath(circlePath)
    context.clip()

    let colors = [
      UIColor(red: red, green: green, blue: blue, alpha: 0.62 * strength).cgColor,
      UIColor(red: red, green: green, blue: blue, alpha: 0.34 * strength).cgColor,
      UIColor(red: red, green: green, blue: blue, alpha: 0).cgColor,
    ] as CFArray

    if let gradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: colors,
      locations: [0, 0.62, 1]
    ) {
      let center = CGPoint(x: rect.midX, y: rect.midY)
      context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: max(rect.width, rect.height) * 0.52,
        options: [.drawsAfterEndLocation]
      )
    }

    context.restoreGState()
  }
}

/// 原版 heatmapColorExpression 六档色带抄录（低密度冷蓝 → 高密度红）。
enum SiponHeatPalette {
  static func color(for t: Double) -> UIColor {
    let value = t.isFinite ? max(0, min(1, t)) : 0
    switch value {
    case ..<0.2:
      return lerp(from: stopRGB(33, 102, 172, alpha: 0), to: stopRGB(103, 169, 207), t: value / 0.2)
    case ..<0.4:
      return lerp(from: stopRGB(103, 169, 207), to: stopRGB(209, 229, 240), t: (value - 0.2) / 0.2)
    case ..<0.6:
      return lerp(from: stopRGB(209, 229, 240), to: stopRGB(253, 219, 199), t: (value - 0.4) / 0.2)
    case ..<0.8:
      return lerp(from: stopRGB(253, 219, 199), to: stopRGB(239, 138, 98), t: (value - 0.6) / 0.2)
    default:
      return lerp(from: stopRGB(239, 138, 98), to: stopRGB(178, 24, 43), t: (value - 0.8) / 0.2)
    }
  }

  private static func stopRGB(_ r: Int, _ g: Int, _ b: Int, alpha: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: alpha)
  }

  private static func lerp(from: UIColor, to: UIColor, t: Double) -> UIColor {
    var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
    var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
    from.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
    to.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
    let time = CGFloat(max(0, min(t, 1)))
    return UIColor(
      red: fr + (tr - fr) * time,
      green: fg + (tg - fg) * time,
      blue: fb + (tb - fb) * time,
      alpha: fa + (ta - fa) * time
    )
  }
}
