# Sipon 地图引擎迁移指南:Mapbox Maps → Apple MapKit(PlatformView 自封装)

> 适用仓库:`sipon`(Flutter 项目,iOS 为唯一目标平台)
> 迁移对象:`mapbox_maps_flutter ^2.23.0`(底层 MapboxMaps v11)→ 自封装 MKMapView
> 文档基于 2026-08 的代码现状写成,引用的文件与行号以当时为准。

---

## 0. TL;DR

- **改造面高度收敛**:全项目只有 4 个文件直接 import `mapbox_maps_flutter`:
  - `lib/main.dart`(token 注入)
  - `lib/pages/map_page.dart`(页面组装,持 `MapWidget`)
  - `lib/services/map/map_scene_controller.dart`(**核心**,686 行,唯一持有 `MapboxMap` 的类)
  - `lib/services/map/map_display_options.dart`(底图样式枚举引用 `MapboxStyles.*`)
- **零改动面**:`map_models.dart` / `map_viewport.dart` / `map_data_controller.dart` /
  `venue_sheet_controller.dart` / 两个 repository / `widgets/map/*` 全部 UI(约 4000 行)。
  这层是刻意做过的防腐设计(见 `map_models.dart:1-4` 的注释),坐标全是裸 double。
- **没有导航、路线规划、轨迹、离线地图、定位蓝点**(定位走独立的 `geolocator`),
  这些恰是 MapKit 最弱的部分,因此本次迁移的最大风险天然不存在。
- **策略**:保持 `MapSceneController` 对外契约不变,底层换实现;迁移期双引擎共存、
  开关切换(仿照 `map_page.dart:24` 现成的 `_useMockMapData` 模式),验收后删除 Mapbox。
- **四个必须重新设计的能力**:① 热力图(MapKit 无原生);② 多套底图样式;
  ③ zoom 表达式驱动的分级渲染/淡入淡出;④ `queryRenderedFeatures` 命中测试
  (这条反而变简单,MKMapView 有原生 didSelect)。

---

## 1. 现状盘点

### 1.1 现有调用关系

```
MapPage (map_page.dart)
  ├─ MapDataController      数据:有哪些酒吧/选中谁/筛了什么     [不动]
  ├─ VenueSheetController   面板 extent 与吸附档位               [不动]
  └─ MapSceneController     样式/图层/annotation/相机/装饰物     [重写内核]
        │  attach(MapboxMap)
        │  setStyle / readViewport / handleMapIdle / applyStage
        │  focusOn / flyToCity / render(MapSceneFrame)
        ▼
     MapWidget + MapboxMaps v11 (Pigeon 桥)
```

### 1.2 `MapSceneController` 实际用到的 Mapbox 能力 → MapKit 对应物

| 能力 | 现实现位置 | MapKit 方案 |
|---|---|---|
| 地图容器与就绪回调 | `attach` (116) | `UiKitView` + 原生 `onMapReady` |
| 5 套底图 `setStyleURI` (171) | LIGHT/STANDARD/STREETS/SATELLITE_STREETS/DARK | `MKStandardMapConfiguration` / `MKImageryMapConfiguration` / hybrid;iOS<16 用 `mapType` 降级;DARK 用 muted emphasis + 强制暗色近似 |
| GeoJSON source 整帧更新 (`_upsertSource`, 742) | `GeoJsonSource.setData` | 无对应:annotation/overlay 由原生侧按 id diff |
| 圆点 CircleLayer + zoom 插值表达式 (409) | 半径 9→4px、13→7、16→11;按 category 染色 | 每点一个复用池里的 `MKAnnotationView`(自绘圆点),半径插值搬到原生按 zoom 重算 |
| 热力图 HeatmapLayer 全套表达式 (459) | weight/intensity/radius/color | **降级**:网格聚合密度圆圈(MKCircle + 径向渐变 renderer),参数需视觉调优 |
| 选中高亮 halo+core 双层 (536) | 双 CircleLayer | 一个常驻 selection annotation,自绘 halo view;displayPriority 置顶;仍可点击 |
| marker 图标+文字标签 `PointAnnotationManager` (594) | iconImage 'marker-15' + textField/halo | 自绘 annotation view:UIImage(kind 资产)+ UILabel(stroke 白描边模拟 halo) |
| 相机 `setCamera/easeTo/flyTo` + padding (253/307/323) | pitch/bearing/padding 一把出 | `setRegion` 定缩放 + `setCamera(MKMapCamera)` 叠 heading/pitch;padding 折算成中心点纬度偏移(见 §5.2) |
| 视野读取 `getCameraState` + bounds (193) | 异步两次往返 | 同步读 `region` / `visibleMapRect`,一次 channel 往返 |
| idle 去抖 220ms (74, 222) | `onMapIdleListener` | `regionDidChangeAnimated` 上报,Dart 侧保留同一 Timer |
| 点击命中 `queryRenderedFeatures` 18px 方框 (336) | 读 feature.properties.venueId | `didSelect` 直接拿 venueId;空白 tap 用手势识别器 + hitTest 排除 annotation view |
| 手势开关 `GesturesSettings` (134) | rotate/pinch/scroll | `isRotateEnabled` 等属性一一对应 |
| 装饰物 Compass/ScaleBar/Logo/Attribution (123–141, 282) | 边距随面板档位动态调 | Logo/版权**不再存在**;compass/scale 各一个 bool,边距逻辑整体删除 |

### 1.3 明确不受影响的东西

- `test/map_test.dart` 全部用例只测防腐层(`MapDataController` 等),不 import Mapbox,
  迁移全程应当保持绿色——这就是回归底线。
- `geolocator` 定位链路、城市匹配(`sipon_city_controller.dart`)不动。
- Info.plist 干净(无 MGLMapboxAccessToken),无需改动;定位权限描述已存在。

---

## 2. 目标架构

### 2.1 迁移期目录规划

```
lib/
├─ main.dart                                  # 删 token 注入
├─ pages/
│  └─ map_page.dart                           # 换 Widget 与接线,逻辑不变
└─ services/map/
   ├─ map_display_options.dart                # MapboxStyle → MapBaseStyle(去 mapbox import)
   ├─ map_scene_controller.dart               # 改成抽象基类(公开签名不变)
   ├─ mapbox_scene_controller.dart            # 【新】现 686 行实现搬进来,迁移期共存
   ├─ mapkit_scene_controller.dart            # 【新】MapKit 实现
   ├─ sipon_map_host.dart                     # 【新】双端通信句柄抽象(Dart 侧)
   └─ sipon_map_widget.dart                   # 【新】UiKitView 封装(替代 MapWidget)

ios/Runner/
├─ AppDelegate.swift                          # 注册 factory
└─ SiponMap/                                  # 【新】原生地图模块
   ├─ SiponMapFactory.swift                   # PlatformView 工厂
   ├─ SiponMapView.swift                      # UIView 容器:MKMapView + delegate + channel
   ├─ SiponMapChannel.swift                   # 协议编解码(方法名集中一处)
   └─ SiponMapGeometry.swift                  # zoom↔span 换算、padding 折算等纯函数
```

> 验收完成后:`pubspec.yaml` 删 `mapbox_maps_flutter`,`mapbox_scene_controller.dart`
> 删除,`map_scene_controller.dart` 里工厂只剩一个分支。

### 2.2 关键设计决策

1. **去抖留在 Dart**。原 `idleDebounce = 220ms`(`map_scene_controller.dart:74`)语义不变:
   原生上报"相机可能停了"(高频),Dart 计时后读一次 viewport。这样两个引擎行为一致,
   页面无感。
2. **指纹机制原样保留**。`MapSceneFrame.signature`、`_markerSignature` 等五套指纹
   (98–107 行)是性能核心,MapKit 版本继续用它决定要不要真的下发 channel 消息——
   channel 往返比 Pigeon 更贵,这层闸门更重要。
3. **分级显隐的决策在 Dart,执行在原生**。原注释里写过"真正的保证在 Dart 侧"
   (696 行),沿用:`effectiveLayerMode` 已由 `mapEffectiveLayerMode()` 在 Dart 算好
   (`map_display_options.dart:46`),直接把最终模式 + 淡入 alpha 下发,原生不做规则判断。
4. **圆点用 annotation view 复用池起步**(不是 overlay 自绘):圆点可点(didSelect 免费获得),
   与现有 18px 命中容差语义最接近;量级(单城数百点)在复用池下无压力。
   若日后上万点,再切"单 overlay 自绘 + 手写命中"方案,接口不用变。

---

## 3. MethodChannel 协议

通道名:`sipon/mapkit`。所有消息 JSON 编码,字段名 snake_case。

### 3.1 Dart → 原生

| 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `setup` | `{city, styleId}` | — | 创建后初始化:初始相机、装饰物开关、手势 |
| `setStyle` | `{styleId}` | — | 底图切换 |
| `setGestures` | `{rotateEnabled, zoomEnabled, panEnabled}` | — | |
| `readViewport` | — | `{west,south,east,north,zoom}` | 对应 `readViewport()`;原生同步组装 |
| `flyToCity` | `{lon,lat,zoom,pitch,bearing,bottomPadding,durationMs}` | — | 对应 `cameraForCity + flyTo` |
| `focusOn` | `{lon,lat,zoom,pitch,bearing,bottomPadding,durationMs}` | — | 与 `flyToCity` 同参,可共用原生实现 |
| `applyStage` | `{bottomPadding}` | — | 面板落定只动 padding 的 easeTo 等价物 |
| `renderFrame` | 见 §3.2 | — | 帧下发,原生自行 diff |
| `dispose` | — | — | detach 时调用 |

### 3.2 `renderFrame` 载荷(对应 `MapSceneFrame`)

```jsonc
{
  "layerMode": "pointsAndHeatmap",       // pointsAndHeatmap | pointsOnly | heatmapOnly
  "circleFade": 0.92,                    // handoff→restored 区间内 Dart 算好的透明度
  "circles":   [{"id":"point-xx","lat":31.2,"lng":121.4,"category":"craft"}],
  "heatmap":   [{"id":"heat-xx","lat":31.2,"lng":121.4,"weight":4.6}],
  "markers":   [{"venueId":"v1","label":"庙前冰室","lat":..,"lng":..,"category":"pub"}],
  "selected":  {"id":"selected-v1","lat":..,"lng":..,"category":"craft","venueId":"v1"} // 可为 null
}
```

约定:**列表传全量,原生按 id diff**。Dart 侧五套指纹保证没变的帧根本不会发出这条消息;
发了就是变了,原生老老实实 diff,不做二次猜测。

### 3.3 原生 → Dart

| 方法 | 参数 | 对应现有回调 |
|---|---|---|
| `onMapReady` | — | `onMapCreated` + `onStyleLoadedListener` 合并(MapKit 无样式加载期,ready 即可画) |
| `onViewportSettled` | `{west,south,east,north,zoom}` | `handleMapIdle` 的输入(原生只报"停了",去抖在 Dart) |
| `onVenueTapped` | `{venueId}` | `_resolveTap` 命中分支 / marker tapEvents |
| `onBlankTapped` | — | `_resolveTap` 未命中分支 |

> 原生侧 `onViewportSettled` 直接携带数据,省掉一次 `readViewport` 往返;
> Dart 侧 `readViewport()` 仍保留(首帧、样式切换后要用)。

---

## 4. 施工步骤

### 第 1 步:底座去 Mapbox 化

**1a. `lib/services/map/map_display_options.dart`**

`MapboxStyle` 更名 `MapBaseStyle`,去掉 mapbox import,枚举值收敛为产品确认后的档位:

```dart
/// 可切换的底图样式。MapKit 只有三种真实配置,档位从 5 收敛到 3(+暗色近似)。
enum MapBaseStyle {
  standard('标准'),   // MKStandardMapConfiguration(emphasisStyle: .default)
  muted('暗色'),      // MKStandardMapConfiguration(emphasisStyle: .muted) + 强制暗色
  satellite('卫星'),  // MKHybridMapConfiguration(带路名,对应原 SATELLITE_STREETS 观感)
}
```

- 原 light/streets 都映射到 `standard`;dark 用 muted + `overrideUserInterfaceStyle`
  近似(见 §5.1)。`MapLayerMode`、`mapEffectiveLayerMode`、`mapHeatmapHandoffZoom`、
  `mapPointsRestoredZoom` 原样保留。
- 连带修改引用方:`map_data_controller.dart:28,43,249`(`_style` 类型)、
  `map_page.dart:212`、`widgets/map/map_tools_sheet.dart` 的参数类型。
  UI 组件只消费 `.label`,展示不变。

**1b. `lib/main.dart`**

删除 16–24 行的 `_mapboxAccessToken` 与 `mapbox.MapboxOptions.setAccessToken(...)`,
以及第 2 行 import。`.env.example.json` 里的 `MAPBOX_ACCESS_TOKEN` 一并删。

**1c. 抽象化 `map_scene_controller.dart`**

把现有类拆两半:

```dart
// map_scene_controller.dart —— 只剩契约 + 常量 + MapSceneFrame
abstract class MapSceneController {
  MapSceneController({
    required this.onViewportSettled,
    required this.onVenueTapped,
    required this.onBlankTapped,
  });
  // ...三个回调字段、全部 static const(cityZoom/defaultZoom/handoff 等)原样上移...

  bool get isAttached;
  Future<void> attach(SiponMapHost host, {required String city});
  void detach();
  Future<void> setStyle(MapBaseStyle style);
  Future<MapViewport?> readViewport();
  void handleViewportSettled();          // 原 handleMapIdle,改名更贴切
  Future<void> applyStage({required double cameraBottomPadding,
      required double ornamentBottomMargin, MapLatLng? focus});
  Future<void> focusOn({required double longitude, required double latitude});
  Future<void> flyToCity(String city, {required double zoom});
  Future<void> render(MapSceneFrame frame);

  /// 工厂:迁移期开关,仿 map_page.dart 的 _useMockMapData 模式。
  static MapSceneController create({required callbacks...}) =>
      const bool.fromEnvironment('USE_MAPKIT_MAP', defaultValue: true)
          ? MapkitSceneController(...)
          : MapboxSceneController(...);
}
```

- 现 686 行实现整体搬到 `mapbox_scene_controller.dart`,
  `class MapboxSceneController extends MapSceneController`,内容基本不动,
  仅 `attach` 参数从 `MapboxMap` 换成 `SiponMapHost`(内部取其 `.mapbox`)。
- 注意 `MapboxStyle` 引用要跟着 1a 改名;`cameraForCity` 从私有提升为受保护方法
  (两个实现都要用 `mapCenterForCity`)。

### 第 2 步:PlatformView 双端骨架

**2a. Dart 侧 host 抽象 `sipon_map_host.dart`**

```dart
/// 双引擎共用的地图句柄。MapKit 实现=channel 封装;Mapbox 实现=包一层 MapboxMap。
abstract class SiponMapHost {
  Future<void> invoke(String method, [Map<String, Object?> args]);
}
```

**2b. `sipon_map_widget.dart`**(替代 `MapWidget`)

```dart
class SiponMapWidget extends StatefulWidget {
  const SiponMapWidget({super.key, required this.onHostReady});
  final void Function(SiponMapHost host) onHostReady;
  ...
}

class _SiponMapWidgetState extends State<SiponMapWidget> {
  MethodChannel? _channel;

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: 'sipon/mapkit',
      onPlatformViewCreated: (id) {
        final channel = MethodChannel('sipon/mapkit_$id');
        channel.setMethodCallHandler(_onNativeCall);
        setState(() => _channel = channel);
        widget.onHostReady(ChannelMapHost(channel));
      },
    );
  }
  // _onNativeCall:分发 §3.3 的四个反向方法到注入的回调
}
```

要点:
- 通道带 viewId 后缀,避免多实例串台;
- `setMethodCallHandler` 必须在 `onPlatformViewCreated` 里立刻挂上,
  否则原生首发 `onMapReady` 会丢;
- 反向调用的回调通过构造参数注入(widget 持有,转发给 `MapPage` 传入的 handler)。

**2c. iOS 侧骨架**

```swift
// SiponMapFactory.swift
final class SiponMapFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger; super.init() }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
              arguments: Any?) -> FlutterPlatformView {
    SiponMapView(frame: frame, viewId: viewId, messenger: messenger)
  }
  // 老版本 Flutter 需要 implements ->NSObjectProtocol 的 createArgsCodec,
  // 返回 FlutterStandardMessageCodec.sharedInstance() 即可。
}

// AppDelegate.swift —— didFinishLaunchingWithOptions 里注册:
let registrar = self.registrar(forPlugin: "SiponMapPlugin")!
registrar.register(SiponMapFactory(messenger: registrar.messenger()),
                   forView: "sipon/mapkit")
```

`SiponMapView` 结构:

```swift
final class SiponMapView: NSObject, FlutterPlatformView, MKMapViewDelegate, UIGestureRecognizerDelegate {
  private let mapView = MKMapView()
  private var channel: FlutterMethodChannel?
  private lazy var engine = SiponMapEngine(mapView: mapView)   // 业务渲染都收在这
  ...
  func view() -> UIView { mapView }
}
```

> 把 MKMapView 直接作为返回视图(不再包一层 UIView),省一层布局传递;
> delegate、手势、channel 都挂在 NSObject 子类上。

**验证点**:跑通空地图显示 + `flutter logs` 能看到 `setup` 到达。

### 第 3 步:iOS 原生实现(逐能力对照)

以下按 `SiponMapEngine` 内部职责分块,给出关键代码形态。

**3a. 初始配置(对应 `attach`)**

```swift
mapView.delegate = self
mapView.showsCompass = false                 // 原 CompassSettings(enabled:false)
mapView.showsScale = false                   // 原 ScaleBarSettings(enabled:false)
mapView.isRotateEnabled = true               // GesturesSettings 三项
mapView.isPitchEnabled = true                // Mapbox 默认允许 pitch
mapView.pointOfInterestFilter = .includingAll
// MapKit 没有 logo/attribution:整段 _pushOrnaments 逻辑消失

let blank = UITapGestureRecognizer(target: self, action: #selector(handleBlankTap(_:)))
blank.delegate = self
mapView.addGestureRecognizer(blank)
```

空白点击与 annotation 选择并存的关键:手势代理里放过落在 annotation view 上的触摸,
让它走系统 didSelect:

```swift
func gestureRecognizer(_ g: UIGestureRecognizer,
                       shouldReceive touch: UITouch) -> Bool {
  let p = touch.location(in: mapView)
  return !mapView.subviews.contains {           // 命中任何可见 annotation view 就不抢
    $0 is MKAnnotationView && $0.frame.contains(p) && !$0.isHidden && $0.alpha > 0.01
  }
}

@objc private func handleBlankTap(_ g: UITapGestureRecognizer) {
  channel?.invokeMethod("onBlankTapped", arguments: nil)
}
```

**3b. 底图切换(对应 `setStyle`)**

```swift
func apply(style: String) {
  if #available(iOS 16.0, *) {
    switch style {
    case "satellite":
      mapView.preferredConfiguration = MKHybridMapConfiguration()
    case "muted":
      let c = MKStandardMapConfiguration(); c.emphasisStyle = .muted
      mapView.preferredConfiguration = c
      mapView.overrideUserInterfaceStyle = .dark   // 强制深色观感
    default:
      mapView.preferredConfiguration = MKStandardMapConfiguration()
      mapView.overrideUserInterfaceStyle = .unspecified
    }
  } else {
    // iOS 14/15 降级:老 mapType 枚举
    mapView.mapType = (style == "satellite") ? .hybrid : .standard
    // muted 无法降级,退回 standard
  }
}
```

**注意**:切配置会移除 overlays 但保留 annotations;若发现丢失,在
`didChangePreferredConfiguration`(iOS16+)或切换后重发当前帧兜底。

**3c. 圆点图层(对应 `_renderCircles`)**

- 每个 circle point 一个常驻 `MKPointAnnotation`(子类 `CircleAnnotation { venueId, category, fadeAlpha }`),view 复用池 identifier 按 category 分 5 个(颜色固定,免重绘)。
- 圆点 view 自绘:实心 category 色 + 1.5pt 白描边,`cornerRadius` 方案即可。
- **半径插值**(原 zoom 表达式 9→4、13→7、16→11)搬进原生纯函数:

```swift
static func circleRadius(zoom: Double) -> CGFloat {
  let z = min(max(zoom, 9), 16)
  if z < 13 { return 4 + (z - 9) / 4 * 3 }      // 4→7
  return 7 + (z - 13) / 3 * 4                   // 7→11
}
```

- **淡入淡出**(原 opacity 表达式):Dart 已把 `circleFade`(0→0.92)算好放进帧,
  `regionDidChangeAnimated` 时只需把各 view `alpha = fade`。`minzoom` 硬摘除对应
  `isHidden`:armed 且 fade≈0 时隐藏(防"透明仍可点"的老问题,见原 668 行注释)。
- **命中尺寸**:view 的 hit 区域比视觉圆大——`frame` 取 max(视觉直径, 22pt),
  视觉层用小一号的内层 layer 画。这替代了原来 18px 方框查询的 tapSlop。

**3d. 热力图(对应 `_renderHeatmap`)——降级方案**

网格聚合密度圆圈:

1. 原生收到 `heatmap` 全量点后,按格网聚合:cell 边长 ≈ `300m × (12/zoom)`;
2. 每格产出 `DensityCellOverlay`(MKCircle 子类,带 density 归一值);
3. renderer 用径向渐变画(预生成一张 radial-gradient UIImage,按 density 映射色带
   ——色带抄原 `heatmapColorExpression` 的 6 档 RGB,`draw(_:in:)` 里 tint);
4. overlay 列表同样按格 key diff,避免每次帧全删全加;
5. `maxZoom: 16` 的退场规则由 Dart 的 `layerMode` 决策承担,原生不管。

> 该方案视觉与 GPU 热力图有差距(硬边界、无核密度平滑),属于**需要产品过目的降级项**
> (见 §6 决策点 D1)。参数(cellSize、渐变半径)留成常量便于调优。

**3e. marker 文字标签(对应 `_renderMarkers`)**

- `MarkerAnnotation` 子类携带 `venueId/label/category`;view 复用池 identifier `"marker"`。
- 图标:启动时由 Dart 通过 channel `registerAssets` 把 5 个 kind 图标传过来
  (`FlutterDartProject.lookupKey(forAsset:)` 读主 bundle 内 Flutter 资产路径,
  转 UIImage 缓存字典);比每帧传 bytes 省。
- 标签:UILabel + attributed string,白描边模拟 halo:

```swift
NSAttributedString(string: label, attributes: [
  .font: UIFont.systemFont(ofSize: 12, weight: .medium),
  .foregroundColor: UIColor(red: 0x0F/255, green: 0x17/255, blue: 0x2A/255, alpha: 1),
  .strokeColor: UIColor.white, .strokeWidth: -3.0,   // 负数=填充同时描边
])
```

- 锚点:`iconAnchor: BOTTOM` + `textOffset [0,1.15]` ≈ icon 底尖对准坐标、label 在下方
  → `centerOffset` 与 label 约束摆位;icon 用项目资产替代 'marker-15'(品牌一致性更好)。
- **重叠控制**:Mapbox 的 `iconAllowOverlap=true/textAllowOverlap=false` 在 MapKit
  没有对等物。近似:label 数量本来就由 Dart 抽样限流(`sampleVenuesForMarkers`,
  `map_models.dart:251`),再给 view 设 `displayPriority = .defaultLow` 让系统挑着显示。
  文字互相压盖时观感略差,接受或后续做碰撞剔除。
- 点击:`didSelect` 里读 `venueId` 回传,**随后立刻
  `mapView.deselectAnnotation(annotation, animated: false)`**——否则重复点击同一个
  marker 不再触发 didSelect,"再点一次=打开详情"的交互(map_page.dart:190)会失效。

**3f. 选中高亮(对应 `_renderSelection`)**

- 常驻单个 `SelectionAnnotation`(id 固定),`selected == null` 时从地图摘下;
- view 双层 CALayer:外圈 halo(半径 8–12pt 随 zoom,opacity 0.22 + blur 用径向渐变模拟)、
  内核(半径 3.5–7.5,白描边 3pt),颜色跟 selected.category;
- `displayPriority = .required` 保证置顶;它也响应 didSelect(venueId 在手),
  保住"热力层级下选中的点仍能点开详情"的设计(原 352 行注释)。

**3g. 相机(对应 `cameraForCity/easeTo/flyTo/applyStage`)**

```swift
func moveCamera(lon: Double, lat: Double, zoom: Double, pitch: Double,
                bearing: Double, bottomPadding: Double, durationMs: Int) {
  // 1. zoom → region span(公式见 §5.1)
  let span = SiponMapGeometry.span(zoom: zoom, in: mapView.bounds.size)
  let center = SiponMapGeometry.center(lat: lat, lng: lon,
                                       shiftingUpBy: bottomPadding, zoom: zoom)
  mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: true)
  // 2. 叠 pitch/heading(iOS13+,MKMapCamera 可变属性)
  let cam = mapView.camera.copy() as! MKMapCamera
  cam.heading = bearing            // 单位与 Mapbox bearing 同为顺时针度
  cam.pitch = min(pitch, 60)       // MapKit 有效上限约 77,保守 60
  mapView.setCamera(cam, animated: true)
}
```

- 动画时长不可控(MapKit 没有自定义时长 API):420ms focus / 780ms flyTo 都落到系统
  默认时长(~0.3–0.5s),差异可感知但不影响语义。接受之,别自己造 CADisplayLink 插值。
- `applyStage` 无 focus 分支 = 只重算 padding 折算的中心(setRegion 微调)。

**3h. idle 与视野上报(对应 `handleMapIdle/readViewport`)**

```swift
func mapView(_ m: MKMapView, regionDidChangeAnimated animated: Bool) {
  // 惯性滚动会连发多次,和 Mapbox idle 多连发同构 → Dart 去抖兜住
  let v = SiponMapGeometry.viewport(of: m)   // region + zoom 公式,一次组装
  channel?.invokeMethod("onViewportSettled", arguments: v)
}
```

`viewport(of:)` 组装 bounds(直接用 `region.span`)与 zoom(§5.1 反推)。
跨 180° 经线、极区畸变本项目用不到,不做处理(中国境内业务)。

**3i. 帧 diff(对应五套指纹的执行端)**

`renderFrame` 到达后按四组分别 diff:

```
circles:  byId 字典对比 → 新增 addAnnotation / 移除 removeAnnotation / 其余改属性
heatmap:  先聚合 → 格 key 对比 → overlay 增删
markers:  byId(venueId) 对比;label 变化只刷 view 内容不重建 annotation
selected: 单例更新 coordinate/color 或移除
```

MKMapView 批量增删请包在 `addAnnotations`/`removeAnnotations`(数组版)一次调用,
避免多次 delegate 风暴。

### 第 4 步:Dart 侧 `MapkitSceneController`

结构对照 `MapboxSceneController` 逐方法翻译,几个差异点:

- `attach(host)`:发 `setup`,然后**立即**认为样式就绪——MapKit 没有 styleLoaded,
  所以 attach 成功后主动补一发 `onMapReady` 语义(直接调页面的 `_pushFrame()` 等价流程,
  即把 `handleStyleLoaded()` 的职责合并进来);
- `setStyle`:发 `setStyle` 后**手动触发一次重下发帧**(原实现靠 styleLoaded 事件驱动
  `map_page._handleStyleLoaded`,MapKit 版没有该事件,由控制器自己补齐,页面不改);
- `readViewport`:一次 `host.invoke('readViewport')` 解析成 `MapViewport`
  (`MapBoundsBox.china()` 兜底逻辑保留);
- `handleViewportSettled`:Timer 去抖 220ms 原样保留,但 viewport 数据直接取
  `onViewportSettled` 附带值,不再二次 `readViewport`;
- `render`:五套指纹判断原样照搬,过了闸门才拼 `renderFrame` 载荷;
- `_cameraBottomPadding/_ornamentBottomMargin`:`ornament` 相关删除(MapKit 无装饰物),
  padding 进 `applyStage/focusOn/flyTo` 的参数。

### 第 5 步:页面接线 `map_page.dart`

改动集中在 import 与三处类型,逻辑零变化:

1. `import 'package:mapbox_maps_flutter...'` → `import '../services/map/sipon_map_widget.dart';`
2. build 里的 `MapWidget(styleUri:, onMapCreated:, onStyleLoadedListener:, onMapIdleListener:)`
   (292–300 行)→
   ```dart
   SiponMapWidget(
     onHostReady: (host) => _handleMapCreated(host),
     onViewportSettled: ...,   // 由 widget 转发 channel 反向调用
     onVenueTapped: ...,
     onBlankTapped: ...,
   )
   ```
   原 `onStyleLoadedListener`/`onMapIdleListener` 两行消失(职责并入 controller)。
3. `_handleMapCreated(MapboxMap map)` → `(SiponMapHost host)`;
   `_handleStyleChanged(MapboxStyle)` → `(MapBaseStyle)`;
   `_scene.setStyle` 后不再等 styleLoaded,controller 内部已处理。

### 第 6 步:清理(验收通过后)

1. `pubspec.yaml`:删 `mapbox_maps_flutter: ^2.23.0` → `flutter pub get`;
2. 删 `lib/services/map/mapbox_scene_controller.dart`,`MapSceneController.create`
   工厂收敛为直接返回 Mapkit 版;
3. `ios/Podfile`:顶部注释与 `platform :ios, '14.0'`——MapKit 方案最低可用 iOS 14
   (MKMapConfiguration 走运行时降级),如产品同意抬底线到 16 则顺手改 16.0 并删降级分支;
4. `pod install`(MapboxMaps/MapboxCoreMaps/MapboxCommon/Turf 四个 pod 自动消失);
   `.env.example.json`、`.vscode/launch.json` 里 MAPBOX_ACCESS_TOKEN 相关条目清理;
5. 全仓搜索 `mapbox`(忽略大小写)确认归零。

---

## 5. 关键算法与换算

### 5.1 zoom ↔ MKCoordinateSpan(Web Mercator 标准)

MapKit 没有 zoom level,以下公式放在 `SiponMapGeometry`(纯函数,配 XCTest):

```swift
// zoom → 经度跨度。256 是墨卡托基准 tile 尺寸,W 是视口宽(pt)
static func longitudeDelta(zoom: Double, width: CGFloat) -> Double {
    360.0 * Double(width) / (256.0 * pow(2, zoom))
}
// region → zoom(读视野时反推)
static func zoom(spanLongitudeDelta d: Double, width: CGFloat) -> Double {
    log2(360.0 * Double(width) / (256.0 * d))
}
// latDelta 近似按纵横比给(低纬度地区够用)
static func span(zoom: Double, size: CGSize) -> MKCoordinateSpan {
    let lon = longitudeDelta(zoom: zoom, width: size.width)
    return MKCoordinateSpan(latitudeDelta: lon * Double(size.height / size.width),
                            longitudeDelta: lon)
}
```

> 校准提示:Mapbox zoom 与该公式的结果在低纬度基本一致(±0.05),
> `mapHeatmapHandoffZoom = 12` 这条分界线无需调整;上线后若手感偏移,
> 以"聚焦城区后正好看到热力图"为准微调常量即可,分界逻辑在 Dart,一行改。

### 5.2 相机 padding → 中心点折算

Mapbox 的 `padding.bottom` 让目标点出现在屏幕"去掉底部 padding 后的区域"中心。
MapKit 无此概念,折算成把真实中心向南移:

```swift
static func center(lat: Double, lng: Double,
                   shiftingUpBy bottomPx: Double, zoom: Double) -> CLLocationCoordinate2D {
    guard bottomPx > 0 else { return .init(latitude: lat, longitude: lng) }
    let metersPerPixel = 40075016.686 * cos(lat * .pi / 180) / (256.0 * pow(2, zoom))
    let deltaLat = bottomPx * metersPerPixel / 111_320.0
    return .init(latitude: lat - deltaLat, longitude: lng)  // 南移 → 目标点上移
}
```

这与 `applyStage` 里"padding 粘滞"问题的处理方式吻合:每次移动显式带上折算值,
不依赖引擎记住状态。

### 5.3 圆点半径/淡入曲线速查(供原生实现对照)

| zoom | 圆点半径 pt | 选中 halo 半径 | 选中 core 半径 |
|---|---|---|---|
| 9 | 4 | 6 | 3.5 |
| 13 | 7 | 8 | 5 |
| 16 | 11 | 12 | 7.5 |

淡入区间 `[handoff=12, restored=13.2]` 线性 0→0.92(描边 0→1);
`circleFade < 0.02` 时整组 `isHidden = true`。

---

## 6. 产品决策点(开工前必须拍板)

| # | 问题 | 建议 |
|---|---|---|
| D1 | **热力图降级为密度圆圈是否接受?** 视觉必有差距(无平滑核密度) | 接受则按 §3d 实施;不接受则热力档位先下线,只留点位模式 |
| D2 | **底图档位从 5 收敛到 3**(标准/暗色/卫星),light 与 streets 合并 | 接受;工具面板 `MapToolsSheet` 的样式选择器随之减项 |
| D3 | 相机动画时长不可控(420/780ms → 系统 ~350ms) | 接受 |
| D4 | marker 文字标签无自动避让(MapKit 无 collision API) | 靠既有抽样限流 + displayPriority 兜底;压盖明显再加剔除 |
| D5 | iOS 最低版本维持 14(MKMapConfiguration 走运行时降级,muted/dark 在 14/15 上退化为普通浅色)还是抬到 16 | 建议维持 14 + 降级分支,观察用户分布后再抬 |

---

## 7. 测试清单

**自动化(迁移全程保持绿)**

- [ ] `flutter test test/map_test.dart` —— 防腐层全量回归,不碰引擎,必须始终通过;
- [ ] 新增 `test/mapkit_frame_codec_test.dart`:`renderFrame` 载荷编解码 round-trip;
- [ ] 新增 `SiponMapGeometryTests`(XCTest):§5.1/§5.2 换算正反一致性
      (`zoom→span→zoom` 误差 < 1e-6;padding 折算在 zoom 11.8/15.05/15.4 三档抽查)。

**手工验收脚本(对照旧版逐条过)**

- [ ] 冷启动:城市级热力图视野(≈ zoom 11.8 < handoff 12),往里推进到街区,圆点+标签淡入登场;
- [ ] 点圆点/marker → 卡片弹出且地图高亮 halo 跟随;再点同一点 → 详情展开;
- [ ] 点空白 → 面板收起;拖动面板 → 相机 padding 平滑跟随、logo 区无残留(MapKit 本无 logo);
- [ ] 「回到总览」「聚焦城区」、右下角定位按钮、切城市飞行;
- [ ] 底图三档切换:切换后圆点/marker 不丢(§3b 的兜底生效);
- [ ] 分类筛选、图层三模式(全部/点位/热力)、手动"点位"模式下缩小地图点不消失;
- [ ] 语言切换 → 标签文案即时刷新(重下发帧生效);
- [ ] 弱网/取数失败横幅、空视野态;
- [ ] iPhone SE 小屏 + 灵动岛机型布局;iOS 14.x 真机过一遍降级分支。

---

## 8. 分期建议

| 期 | 内容 | 出口标准 |
|---|---|---|
| P1 骨架 | 第 1、2 步:抽象基类 + PlatformView 通了 + 空地图显示 | 双开关都能编译运行,`flutter test` 绿 |
| P2 相机闭环 | §3g/§3h + MapkitSceneController 相机方法 | 视野变化→取数→渲染管线打通(marker 先不上) |
| P3 渲染全量 | §3c–§3f + render/diff | 手工清单前 8 条通过 |
| P4 打磨与切换 | 热力降级调参、样式切换兜底、真机矩阵 | 全清单通过,产品验收 |
| P5 清理 | 第 6 步,删 Mapbox | `grep -i mapbox` 归零,包体积瘦身(预期 ipa 减 30MB+) |

工作量预估:P1–P2 约 2–3 人日,P3 约 3–5 人日(大头在 marker 自绘与 diff),
P4 调参弹性最大(取决于 D1/D4 的验收标准)。
