# Android 花瓣地图 SDK 配置与联调

Android 现在使用华为 HMS Core Map Kit 原生 SDK `com.huawei.hms:maps:6.15.1.322`，
同时集成同版本 `maps-basic`，支持未安装 HMS Core APK 的非华为 Android 手机。
通过 `sipon/petal` PlatformView 和每实例 `sipon/petal_<viewId>` 通道接入 Flutter。
原生使用 `TextureMapView`，避免地图的独立 Surface 遮住 Flutter 搜索栏和底部面板。
鸿蒙继续使用系统 Map Kit；iOS 继续使用 MapKit。

## 应用授权

在 AppGallery Connect 创建 Android 应用，登记实际应用包名（当前为
`com.example.sipon`）及安装包的 SHA-256 签名指纹，开通 Map Kit。
路线规划另外需要开通 Directions API。调试签名与发布签名均需登记。
按照[华为 Android Map Kit 接入指南](https://developer.huawei.com/consumer/cn/codelab/HMSMapKit/index.html)
核对应用授权及设备环境。按[SDK 集成说明](https://developer.huawei.com/consumer/en/doc/HMSCore-Guides/android-sdk-integrating-sdk-0000001061671869)，
`maps` 与 `maps-basic` 必须使用相同版本；后者让地图无需额外安装 HMS Core APK。

把以下配置放在本机用户目录的 `.gradle/gradle.properties`，或使用同名环境变量：

也支持项目的 `android/local.properties`（已被 Git 忽略）。优先级为 Gradle 属性、
环境变量、本地配置。下载的 `agconnect-services*.json` 同样已被 Git 忽略；
该文件不会自动导入，需把其中的应用凭据写入上述配置。

```properties
PETAL_MAP_KEY=你的华为地图API密钥
PETAL_APP_ID=AppGalleryConnect里的Android应用APPID
# 可选：路线单独配置；省略时沿用 PETAL_MAP_KEY。
PETAL_ROUTE_KEY=你的DirectionsAPI密钥
```

此接入采用 SDK 的显式配置接口，APP ID 通过 `MapsInitializer.setAppId` 设置，
无需把 `agconnect-services.json` 提交到仓库或额外引入 AGC 构建插件。
代码在创建原生 MapView 前调用 `MapsInitializer.setApiKey`；缺少 Key 时显示
配置错误及重试入口，不请求天地图。原有 `TDT_KEY/TDT_SK/TDT_ROUTE_KEY/TDT_ROUTE_SK`
不再使用。不要把真实密钥提交到仓库。客户端地图 Key 随 APK 分发，需在控制台
约束应用包名、签名、权限与配额；路线若使用服务端专用密钥，应改接后端路线代理。

## 坐标与功能

- 共享业务坐标保持 GCJ-02。Android SDK 开启 `setGcj02CoordinateEnabled(true)`，
  酒吧标注、相机、地图选点和视野直接使用 GCJ-02。
- Android 系统定位为 WGS-84，在个人位置层转换成 GCJ-02 后再投影显示。
- Directions API 使用 WGS-84：逐段按站点顺序规划驾车道路，返回道路点转换为
  GCJ-02 后绘制。失败不绘制站点直线；关闭页面或重新规划时取消旧请求。
- 支持标准、暗色、混合卫星底图，类别图标、评分、路线序号、选中态和标签避让。
- 标准底图随应用外观切换（默认跟随系统）：浅色样式 `2061929205284932992`，
  深色样式 `2061948823579912320`；手动选择暗色底图时固定使用深色样式。
  首次加载和运行中切换均应用对应样式，底图 POI 显隐由发布的自定义样式管理。
- 地点搜索维持此前 Android 行为（不提供供应商地点搜索），业务酒吧搜索仍走
  Sipon 接口。外部导航维持已有地图应用选择。

## 验证

```powershell
flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos
flutter test --no-pub tool/tests
cd android
.\gradlew.bat :app:testDebugUnitTest :app:assembleDebug --console=plain
```

配置真实 Key 后在真机检查：地图加载和缺少授权、首页与详情小地图、半屏和全屏、
定位授权/拒绝授权、旋转缩放、新增地点准星回传、暗色与卫星切换、按序驾车路线、
重试、多实例及页面关闭后回调。核对 SDK 来源标识没有被遮挡，底部面板展开后
地图焦点仍在可见区域。自动测试和编译无法代替真实授权及设备联调。

旧 `android-tianditu-*.md` 文档仅记录迁移前的实现，不再用于当前分支配置。

## 2026-10-15 真机联调记录

- 真我 GT7 Pro（RMX5010，Android 17）已安装当前调试包。
- 补齐同版本 `maps-basic` 后，无需安装 HMS Core APK 即可启动地图引擎。
  当前固定 `maps` / `maps-basic` 为 `6.15.1.322`；`6.15.1.324` 的基础组件
  引用了当时华为公开仓库尚不可下载的 `security-base/security-intent:2.1.0.300`。
- 使用 `TextureMapView` 后，Flutter 搜索栏、酒吧卡片和底栏可正常覆盖地图。
- 控制台登记当前调试证书 SHA-256 后，SDK 返回 `identityResult :0`，
  底图及酒吧标注已显示。此结果确认当前调试签名的地图鉴权成功。
- 开发机调用 Directions REST 仍返回 HTTP 400、`010008 / INVALID_REQUEST`。
  手机端完整路线规划尚未验收，需继续确认路线服务的请求与权限配置。
  地图鉴权成功不能替代路线服务联调。
- 原生坐标与路线解析的 7 项单元测试通过，Debug APK 构建通过。

## Android POI 密度与显示

- 关闭 SDK 自动聚合，同时为业务标记关闭聚合，不再显示带数量的聚合点。
- 地理网格先筛选屏内候选，普通点最多投影 96 个；随后按屏幕坐标避让，
  仅为最终可见点创建或更新 SDK 标记。相机移动期间合并刷新，停下后再布局。
- 普通名称为 13 dp 中等字重，评分为 13 dp。使用实际文字宽高避让，
  缓存文字布局与位图，已有标记保持复用。
- 评分胶囊按缩放设置每屏 6 / 8 / 9 / 10 个的上限，选中点计入该上限；
  目标是一般视野显示约 5–10 个。地点不足、彼此重叠或面板遮挡时可以更少，
  路线站点优先保留。其余地点以稀疏圆点呈现。
