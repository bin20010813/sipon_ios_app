# 三端整合与 GCJ-02 业务坐标契约

2026-10-11：项目负责人确认，Sipon 业务坐标统一为 **GCJ-02**。
本文取代旧 Android 设计中的 WGS-84 业务约定。

## 分支与开发方式

本次整合分支为 `codex/integrate-three-platforms-gcj02`，包含本地已有 iOS MapKit、
Android 花瓣地图和鸿蒙花瓣地图提交。三端共享 `lib` 业务；平台实现分别位于
`ios`、`android`、`ohos`，由 `MapEngine` 和公共地图协议衔接。

整合验收后合入 `main`。此后功能和平台修复均从统一主线建立短期分支并回归主线；
不再分别维护三套业务分支。虚拟饮酒模块继续停用，仅保留本地忽略的源码。

## 坐标边界

API 请求/响应、酒馆与打卡、附近查询、搜索结果、地图中心/视野、路线站点和
共享道路几何统一为 GCJ-02。显式 CRS 标签为 `GCJ02`；字段使用 `lng/lat` 或
`longitude/latitude`，数组固定 `[longitude, latitude]`。

| 来源或用途 | 处理规则 |
| --- | --- |
| 三端系统 GPS、定位缓存 | 保留原始 WGS-84 `Position`，每次交给业务层时通过 `BusinessCoordinates.fromWgs84` 转换一次 |
| 内置行政区城市表 | 原始表仍是 WGS-84；查询锚点、城市选项和地图落点在入口转换；最近城市计算仍使用原始 GPS 与原始城市表 |
| API 酒馆和行政区坐标 | 已按 GCJ-02 契约解释，直接使用，不能再次转换 |
| 历史精选地图城市中心 | 明确为 GCJ-02 地图落点，直接使用 |
| iOS MapKit、鸿蒙 Map Kit | 大陆点位、搜索和视野沿用 SDK 地图坐标，适配层按 GCJ-02 交付；系统原生个人点留在 SDK 内部 |
| Android 花瓣地图展示 | SDK 开启 `setGcj02CoordinateEnabled(true)`；显示、选点和视野直接使用 GCJ-02；设备 WGS-84 定位经 `toBusiness` 转换 |
| Android 回中兜底 | Dart 已交付 GCJ-02，原生不得再当作 GPS 转换 |
| Android 道路服务 | 国内 Directions API 请求站点与返回几何直接使用 GCJ-02；SDK 按 GCJ-02 绘图，禁止重复转换 |
| 可选后端道路代理 | 请求与响应必须为 `GCJ02`；供应商转换由代理实现，拒绝 WGS84/CGCS2000 响应，禁止只换标签 |
| 外部导航 | 高德 `dev=0`，百度 `coord_type=gcj02`，腾讯 `coord_type=2`；Apple/花瓣沿用各自大陆地图坐标 |

本次不对服务器历史数据做批量转换；服务器不在此仓库中。已有数据若混用坐标系，
必须按数据来源核对后单独迁移，不能根据经纬度数值猜测类型。

当前 Dart GPS 转换与 Android 使用相同的区域矩形和计算方法；矩形外不偏移。
该矩形不是国界，不能用它证明港澳台、邻国边境或海外 SDK 的坐标语义一致。
本次验收范围以大陆业务城市为主，扩大地域前应补充准确区域判定与供应商转换。
WGS-84 与 CGCS2000 的近似用于地图显示，不承诺测绘精度。

## 构建与回归

iOS/Android 使用主 `pubspec.yaml`；鸿蒙继续使用 Flutter OH、独立入口及
`ohos/flutter` 的锁定依赖覆盖，通过 `tool/build_harmony.ps1` 生成构建工作目录。
修改源工程，不修改生成的 `build/harmony_workspace`。共享层不得引用 `OhosView`。

自动检查：

```powershell
flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos
flutter test --no-pub tool/tests
flutter test --no-pub test
node --test tool/tests/petal_marker_layout_test.cjs tool/tests/petal_marker_artwork_test.cjs tool/tests/harmony_sticker_test.cjs
flutter build apk --debug
.\tool\build_harmony.ps1 -Mode release -FlutterSdk D:\hms\flutter_ohos
```

iOS 构建和原生测试需在安装 Xcode 的 macOS 上执行。三端以同一批真实酒馆验证：
定位与拒绝授权、附近查询、搜索选点、提交后再次展示、半屏/全屏、路线贴路与站点
对齐、外部导航、退出重进。新增地图命令时同时检查三端实现；不支持的能力必须
显式返回状态。构建成功和数学往返测试不能替代真机点位核对。

导航参数参考：[高德 iOS 路线](https://lbs.amap.com/api/amap-mobile/guide/ios/route)、
[百度地图调起](https://lbs.baidu.com/docs/webapi?title=mapadjustment/uri/ios)、
[腾讯 URI 路线](https://lbs.qq.com/uri_v1/guide-route.html)。

## 本次验证记录（2026-10-11）

- 成功获取 `origin` 最新引用；整合分支包含远端 iOS `1fafe3a`、Android
  `b670b65`、鸿蒙 `5b32c77`，以及本地鸿蒙提交 `f8ece48`。
- 上游 Flutter 全量测试：53 项通过、4 项页面测试失败。4 项均在未修改的
  整合基线 `d315e6f` 上复现，涉及新增酒馆表单旧文案与动态图片旧尺寸预期；
  其中新增酒馆测试为本地已有的忽略文件。未将这些页面断言改成无条件通过。
- Flutter OH：7 项地图回归、9 项坐标/导航回归通过；ArkTS 的 26 项标注和
  图片处理测试通过。鸿蒙共享代码及独立入口分析无问题。
- Android Debug APK 构建成功；`MapCoordinateAdapterTest` 的 3 项原生测试通过。
- HarmonyOS Release 构建成功，生成未签名 HAP。签名、安装与真机验证仍需执行。
- Windows 环境未执行 iOS 构建与 Xcode 原生测试，也未替代三端真实点位验收。

## 路线方向标记（2026-10-12）

三端规划路线沿道路点序重复显示白色箭头，外沿采用路线色。Android 使用同一路线
数据源的线随附图标并关闭自动翻正；iOS 在路线渲染器中按屏幕距离采样，跳过重复
坐标并保留跨线段的间距；鸿蒙使用沿折线重复的方向纹理。方向由站点规划的道路
点序决定，不修改业务坐标。清除路线、重新规划、切换底图沿用原有路线生命周期。

这些改动位于原生层，需重新构建运行，Flutter 热重载无法更新。

验证记录（2026-10-13）：Android Debug APK 构建成功；鸿蒙 Release 构建成功，
生成未签名 HAP，共享代码分析通过，16 项 Flutter 回归及 27 项 Node 测试通过。
iOS 新增正反方向、重复点与转弯、短路线与可见区域采样测试；当前 Windows 环境
未执行 Xcode 测试或 iOS 构建。三端箭头的真机显示仍需验收。
