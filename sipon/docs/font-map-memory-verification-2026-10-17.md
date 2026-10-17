# 字体与地图内存复核（2026-10-17）

范围：上一轮优化顺序第 2 项（微软雅黑）和第 3 项（地图初始化及生命周期）。本次没有修改应用源码、替换字体、重新安装或清理数据。

## 结论与证据等级

| 结论 | 证据 |
| --- | --- |
| 为三句固定文案打包完整 18.79 MiB 微软雅黑，确有优化空间 | 源码全局搜索、APK 内容哈希及条目字节数、字体子集实验 |
| 冷启动首页已创建隐藏的原生地图 | 真机 VM：Tab=0、active=false、地图 State mounted=true、viewId=0；原生视图树含 TextureMapView |
| 切回首页保留同一张地图 | 真机 VM：Tab=0、active=false、viewId 仍为 0、mounted=true；原生实例仍为 1 |
| Tab/路由可见性没有传入原生地图生命周期 | Dart→原生调用链、通道协议及 MainActivity 生命周期代码 |
| 多张地图可同时存活 | 路线规划页截图、两个 mounted 的地图 State（viewId=0/1）、原生 TextureMapView 数量=2 |
| 地图造成了多少可消除的 RAM 开销 | 尚未证明；需要同版本、同场景的改动前后对照 |
| 存在永久内存泄漏 | 尚未证明；保留页面不等于泄漏，已有销毁实现 |

## 字体

`pubspec.yaml:136` 注册 Microsoft YaHei；在应用主题中没有作为全局字体使用。

| 使用点 | 文案 | 字重 |
| --- | --- | --- |
| lib/app/pages/sipon_launch_page.dart:122 | 酒吧地图 | w700 |
| lib/app/pages/sipon_launch_page.dart:146 | 杭州探极科技有限公司 | w400 |
| lib/features/auth/pages/sms_login_page.dart:543 | 开饮   就现在 | w700 |

三句共 19 个不同汉字及空格。

- 源字体：19,701,556 B（18.7889 MiB）。
- 当前本地 Debug APK 内字体：与源码 SHA-256 相同，未做字符裁剪。
- APK 压缩条目：13,228,195 B（12.6154 MiB），约占当前 APK 的 6.1%。
- TTC 含 Microsoft YaHei Regular 与 Microsoft YaHei UI Regular 两个 face，每个 30,202 glyph；共享 19,470,334 B 表数据。
- 仅抽取第一个完整 face 得到 19,581,036 B，不能靠 TTC 转 TTF 将体积减半。

使用本机 fontTools 在内存中裁剪，不改工程文件：保留当前文案、hinting 和必要 glyph 后，单 face 子集为 **18,272 B（17.84 KiB）**，20/20 字符覆盖，21 glyph；ZIP deflate level 6 后 **12,227 B（11.94 KiB）**。这只是字体条目的实验值，未重新构建 APK。

建议优先按固定文案做子集以保留字形。新增文案时同步更新字符集合；安卓/iOS 均核对行高、间距、w400/w700 表现。现有两个 face 都是 Regular，代码请求 w700 不代表文件包含独立粗体字库。直接换系统字体也能删除该资源，但三处视觉会变。

存储收益明确；不能把 18.79 MiB 文件大小直接当成 RAM 降幅，字体映射、加载及 glyph 缓存需另测。

## 地图调用链

1. `lib/app/shell/sipon_shell.dart:180` 的 IndexedStack 包含直接创建的 MapPage（189 行），初始 Tab=0。只有动态 Tab 有首次访问占位，地图没有。
2. `lib/features/map/pages/map_page.dart:511` 无条件创建 SiponMapWidget；178 行的 `_handleMapCreated` 在 active=false 时也会执行 `_scene.attach`。
3. `lib/features/map/controllers/petal_android_scene_controller.dart` 的 attach 调用原生 setup。
4. `android/app/src/main/kotlin/com/example/sipon/map/SiponPetalView.kt:109` 创建 TextureMapView，115–117 行立即 onCreate/onStart/onResume。
5. MapPage 的 active 变为 false 时，158 行分支仅递增 `_locationRequest`。这会使部分异步定位结果失效，不会调用原生 onPause/onStop 或 dispose。
6. `SiponMapWidget` 无 active/visible 参数，`SiponMapCommands` 无可见性/暂停命令。当前没有将 Tab 和路由覆盖状态接入地图。

Flutter IndexedStack 本就保留各子页状态；本机 Flutter 源码也验证其隐藏子页仍在树中。Android 平台视图层的隐藏逻辑不等于调用业务 MapView 的 onDestroy。参见 [IndexedStack 官方文档](https://api.flutter.dev/flutter/widgets/IndexedStack-class.html)。

必须保留的准确边界：

- `MainActivity.kt:61` 起已转发 Activity 的 start/resume/pause/stop/lowMemory；应用整体进入后台有对应处理，不是完全没有生命周期。
- `SiponPetalView.kt:509` 的 dispose 会停止定位、销毁 MapView、清理标记缓存和通道。
- 地图退出页面时 controller.detach 会发送 dispose；但 IndexedStack 中隐藏页面没有退出。
- SDK 自身可能对不可见视图减少渲染；本次没有测连续帧率，不能断言隐藏地图一直全速渲染。
- `SiponUserLocationView` 有 onDetachedFromWindow 停止订阅逻辑；Tab 可见性仍未显式控制它，不宜无条件宣称所有隐藏场景都持续定位。

## 真机观察

设备 RMX5010，Android Debug 包 1.0.6，安装更新时间 2026-10-17 10:15:56。本次进程 PID=22364，约 14:36 启动。通过系统 meminfo、原生视图树和 Dart VM 读取状态，没有触发强制 GC、堆转储或修改应用状态字段。

| 采样场景 | 原生地图数 | PSS MiB | RSS MiB | Graphics MiB |
| --- | ---: | ---: | ---: | ---: |
| 冷启动首页、未点地图 | 1 | 610.5 | 765.5 | 159.0 |
| 地图 Tab，14:38:13 | 1 | 666.0 | 818.0 | 200.5 |
| 返回首页，14:38:28 | 1 | 663.4 | 814.4 | 200.5 |
| 观察到路线规划页，14:38:49 | 2 | 774.1 | 929.5 | 270.2 |

前三次 VM 核对地图 viewId 始终为 0，首页 active=false，地图页 active=true，State 始终 mounted。首页冷启动已存在原生 TextureMapView 的证据充分。返回首页并没有卸载它。

路线规划采样由截图确认页面，并非地点详情的受控复现：两个地图 State 均 mounted，viewId 为 0 和 1，同时有两个原生 TextureMapView。`lib/features/routes/pages/route_planning_page.dart:665` 有独立地图组件，119 行 dispose 会 detach，故这证明多实例叠加，不证明关闭后泄漏。

图形内存在地图打开并返回首页后比本次冷启动样本高约 41.5 MiB。采样受缓存、异步图片和 SDK 行为影响，这不是单个地图的独占开销，也不是优化后承诺节省值。路线规划样本也不能做简单差值归因。不能将 Graphics 与 TOTAL PSS 再相加。Debug 数据不作为 Release 性能预算。

原始脱敏采样在 `build/diagnostics/map_tab.json`、`return_home.json` 和 `observed_route_planning.json`；build 目录仅作临时诊断，不应提交发布。

## 建议实现顺序及验收

1. 字体按三句文案做子集；构建前后比较 APK 条目和整包，并验收三处文字显示。约 12.6 MiB 是现有压缩条目基线，最终整包收益以实测为准。
2. 地图第一次打开前用占位。除底栏点击外，首页“地图查看地点”等入口也必须触发创建并保留 requestedVenue。
3. 建立统一有效可见性：应用在前台、所属 Tab 可见、所在路由未被覆盖。将其传给原生，初始化异步完成时也检查最新期望状态，避免隐藏地图被 onMapReady 再次恢复。
4. 先实施隐藏暂停定位/渲染。onPause 不保证释放全部纹理；如目标是降低常驻 RAM，再对长时间隐藏或内存压力下的地图释放原生视图，并保留相机、选中地点、筛选及面板状态供恢复。
5. 同时覆盖主地图、地点半屏/全屏、路线预览，避免只处理底栏。展示性小地图可另评估静态预览，不能直接牺牲交互功能。

验收使用同版本 arm64 Profile/Release，固定流程并重复采样：冷启动不点地图 → 地图 → 首页 → 路线规划 → 返回 → 后台/前台，记录原生地图数、定位/传感器订阅、PSS/RSS/Graphics，以及恢复位置和首帧。单独验证地图延迟加载、隐藏暂停和销毁恢复，避免混合修改后无法归因。
