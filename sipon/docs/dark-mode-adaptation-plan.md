# Sipon 深色模式适配技术方案

日期：2026-09-25  
状态：第一阶段已实施；主题基础、外观设置、核心页面和 MapKit 同步已完成，剩余业务页面与启动资源按本文清单继续迁移。

## 实施进度（2026-09-25）

已完成：

- [x] `MaterialApp` 双主题、`ThemeMode` 控制器、SharedPreferences 持久化和主题感知系统栏。
- [x] 设置页「跟随系统 / 浅色 / 深色」入口及中英文文案。
- [x] 启动 Flutter 页面、登录、应用底栏、首页、个人中心主要容器、语言页、城市选择器和网络图片占位适配。
- [x] 地图搜索控件、筛选、结果面板与地点面板的主要表面适配。
- [x] Flutter → iOS MapKit 的 `setAppearance` 协议，初始亮度、动态切换、暗色标注和路线颜色同步。
- [x] 主题控制器和地图外观协议自动化测试。
- [x] 修复首页搜索胶囊继承全局输入框填充色后出现的内层黑色矩形。
- [x] 修复个人页昵称和辅助文字、快捷入口卡片、预算快捷按钮及「权益」标题在深色模式下的颜色与对比度。
- [x] 深色模式下对个人页快捷入口 PNG 使用主题色着色，避免图标深色线条融入背景。
- [x] 底栏加号弹窗保持固定 18 sigma 高斯模糊；面板以 10% 品牌主色混合主题表面色，并以 76% 不透明度呈现磨砂玻璃效果，浅色和深色模式共用同一模糊强度。

待完成：

- [ ] 评论、鸡尾酒、喝酒记录、路线、个人中心深层子页面和虚拟喝酒外围控件中的固定色迁移。
- [ ] 深色原生启动资源生成与检查。
- [ ] macOS/Xcode 编译、iOS 真机视觉与 MapKit 动态切换验收。

## 1. 目标与范围

提供「跟随系统 / 浅色 / 深色」三种外观模式，默认跟随系统，用户选择本地持久化。切换立即作用于当前页面、已打开的弹层、后续路由及原生地图，不丢失表单、滚动位置、登录态或地图选中状态。

以 `lib/main.dart` 启动的 Flutter 应用及 `ios/Runner` 为主要适配对象；仓库内独立的 `sip_on_1` SwiftUI 工程不纳入本次改造。Flutter 公共界面兼顾其他平台，iOS 原生地图及启动体验单独验收。无需后端接口、账号数据迁移或新增状态管理依赖。

保留当前品牌紫红色和浅色布局。图片浏览器、照片、酒液、贴纸和沉浸式场景具有内容自身的颜色，不做整屏反色。

## 2. 当前实现与影响

| 位置 | 当前实现 | 改造影响 |
| --- | --- | --- |
| `lib/app/sipon_app.dart` | 仅配置 `Brightness.light` 的 `ThemeData`，品牌种子色 `#9A3D78`，页面底色 `#FBF8F9`；启动等待页白底 | 增加双主题和模式控制，处理首帧 |
| `lib/main.dart` | 启用 edge-to-edge，导航栏图标固定 `Brightness.dark` | 系统栏外观跟随实际页面背景 |
| `lib/features/map/widgets/map_theme.dart` | `MapDesign` 使用静态常量色板 | 迁移为依赖主题上下文的语义色 |
| `lib/features/home`、`profile`、`reviews`、`drinks`、`routes` | 页面及组件散布白底、深文字、粉色渐变和固定阴影 | 逐模块迁移，单独增加 `darkTheme` 无法覆盖 |
| `lib/features/profile/pages/settings_support_page.dart` | 已有语言设置，页面本身使用固定渐变和私有色值 | 增加外观设置；同批处理内部子页面和弹窗 |
| `lib/shared/localization/language_transform.dart` | `ChangeNotifier` + `InheritedNotifier` 管理语言，支持中英文 | 沿用组织方式，新增外观相关双语文案 |
| `lib/features/map/models/map_display_options.dart` | `standard`、`muted`、`satellite` 三种底图；`muted` 标注为「暗色」 | 底图选择与应用外观需明确区分 |
| `ios/Runner/SiponMap/SiponMapView.swift` | `apply(styleId:)` 先设 `.unspecified`，iOS 16+ 的 `muted` 再设 `.dark`；标注胶囊、尾部及序号背景使用白色 | 新增外观同步并改造标注，避免切换底图覆盖外观 |
| `lib/features/drinks/virtual_drinking/widgets/virtual_three_glass.dart` | WebView 与 HTML 背景透明，加载 Three.js 场景 | 优先适配外围控件，不重载场景 |
| `pubspec.yaml` | 已依赖 `shared_preferences: 2.5.3`；原生启动配置为白底 | 复用本地存储；补充深色启动资源 |

## 3. 主题架构

### 3.1 新增文件与职责

建议新增 `lib/app/theme/`：

| 文件 | 职责 |
| --- | --- |
| `sipon_theme.dart` | 生成 `SiponTheme.light`、`SiponTheme.dark`，集中配置 Material 组件主题 |
| `sipon_theme_colors.dart` | `SiponThemeColors extends ThemeExtension<SiponThemeColors>`，承载品牌弱背景、渐变、浮层等扩展语义色，实现 `copyWith`、`lerp` |
| `sipon_theme_controller.dart` | 管理 `ThemeMode`、加载和保存偏好；允许测试注入存储 |
| `sipon_theme_scope.dart` | `InheritedNotifier`，向设置页面提供控制器 |
| `sipon_system_ui.dart` | 根据当前背景明暗构建系统栏样式 |

组件优先读取 `Theme.of(context).colorScheme`；仅标准色板无法表达的设计色放入扩展。不再创建各页面自己的浅色/深色判断表，也不使用全局可变静态颜色。

应用接入示意（新类型为拟新增接口）：

```dart
MaterialApp(
  theme: SiponTheme.light,
  darkTheme: SiponTheme.dark,
  themeMode: themeController.mode,
  home: _StartupGate(cityController: _cityController),
)
```

控制器通知时重建上述配置，保留同一个 `MaterialApp` 及其导航状态，不按模式更换根节点或地图的 Key。`themeMode` 决定浅色/深色主题，跟随系统时由 Flutter 响应系统亮度变化，依据见 [MaterialApp.theme 官方说明](https://api.flutter.dev/flutter/material/MaterialApp/theme.html)。

### 3.2 状态、持久化及启动顺序

1. 本地键建议为 `sipon.theme_mode.v1`，值为 `system`、`light`、`dark`，不存枚举索引。无值、非法值或读取失败时回退 `system`。
2. `main()` 初始化 binding 后读取偏好，再把已初始化控制器注入应用并调用 `runApp`；读取失败必须完成回退，不阻塞启动。只前置这一轻量读取，登录恢复、城市加载沿用现有流程。
3. 设置切换先更新内存并通知 UI，再串行持久化最新选择，避免快速操作导致旧值覆盖新值。保存失败保留当前会话外观并提示「外观已切换，但未能保存」，允许重试。
4. 偏好属于设备，不随登录退出清除；退出账号和清缓存逻辑不得误删该键。
5. 显式选择浅色/深色时忽略系统亮度变化；回到跟随系统后立即恢复系统外观。原生地图使用 Flutter 已解析的有效亮度，不自行建立另一套全局判定。

控制器放在现有语言、城市控制器相邻层级，拥有者负责释放。需要颜色的组件必须在 `build` 或 `didChangeDependencies` 读取主题，避免在 `initState` 缓存后失去更新。

## 4. 颜色与组件策略

下表为设计起点，不是已审核色板；浅色先映射现有视觉值，深色需经过页面截图和对比度检查后定稿。

| 语义 | 浅色参考 | 深色建议 | 用途 |
| --- | --- | --- | --- |
| 页面背景 | `#FBF8F9` | `#151216` | Scaffold、加载页 |
| surface | `#FFFFFF` | `#211C22` | 卡片、输入框 |
| elevatedSurface | `#FFFFFF` | `#2C252D` | 弹窗、浮层、悬浮底栏 |
| onSurface | `#252229` | `#F5EFF4` | 正文、主要图标 |
| onSurfaceVariant | 按现有页面映射 | `#C4B8C2` | 次要说明 |
| outlineVariant | `#F0E7EE` | `#4A3D48` | 分隔线与边框 |
| primary / onPrimary | `#9A3D78` / `#FFFFFF` | `#E8A0CC` / `#42132F` | 主按钮及其文字 |
| brandSurface | `#FFEDF7` | `#3B2535` | 标签、选中弱背景 |
| success | `#16A34A` | `#77D89B` | 营业、完成提示 |
| error | 现有红色按语义统一 | `#FFB4AB` | 错误、危险操作 |

迁移规则：

- `Colors.white` 按用途分别映射 surface、onPrimary 或内容固有色，禁止机械全局替换。文字与其背景成对迁移。
- 粉白渐变改为主题扩展中的渐变色组；半透明白底、毛玻璃、蒙层分别配置深色版本，并检查叠加后的可读性。
- 深色卡片主要通过背景层级、边框区分，减少依赖黑色阴影。禁用、选中、按压、错误、加载和空态都必须覆盖。
- 统一 AppBar、Card、Dialog、BottomSheet、SnackBar、按钮、输入框、分隔线、日期选择器、选择菜单及进度指示器的主题；页面显式颜色仍需逐项迁移。
- 使用主题值后，移除受影响对象的 `const`，保留布局等仍可常量化的部分；`part` 文件所需导入放在所属主 library 中。
- `MapDesign` 先改为 `MapDesign.of(context)` 兼容访问或直接转发至主题扩展，逐步删除旧静态视觉色。分类色等业务常量独立保留。

设定验收目标：普通正文对比度至少 4.5:1，较大文字和关键非文字控件至少 3:1；检查真实合成背景而非单个色值。状态同时以文字或图标表达，不仅依赖红绿区别。

## 5. 页面与资源迁移清单

| 批次 | 具体范围 | 检查重点 |
| --- | --- | --- |
| 基础 | `app/pages/sipon_launch_page.dart`、`app/shell/sipon_shell.dart`、`app/widgets/shell_components.dart`、`auth/pages/sms_login_page.dart` | 启动等待、登录、底栏、Plus 面板、搜索覆盖层 |
| 公共组件 | `shared/widgets/sipon_city_picker.dart`、`sipon_network_image.dart`、`shared/localization/language_page.dart` | 默认参数中的固定白色、占位/错误图、城市选择、语言切换 |
| 首页与个人 | `features/home/**`、`features/profile/**` | 首页渐变、会员卡、账单预算、个人列表、设置内部子页面、退出确认 |
| 地图与路线 | `features/map/pages/**`、`features/map/widgets/**`、`features/routes/pages/**` | 半屏/全屏面板、小地图、工具弹层、路线编号及原生标注 |
| 内容与记录 | `features/reviews/**`、`features/drinks/cocktails/**`、`features/drinks/records/**` | 评论、打卡、输入、日期弹窗、贴纸日历、上传裁剪界面 |
| 虚拟喝酒 | `features/drinks/virtual_drinking/**` | 选择器、设置弹层和覆盖控件；场景本色单独管理 |

资源目录实际名称为 `assest/`，本次不顺带改名。逐个检查首页、地图、个人中心的 PNG：单色透明图标可由主题着色；多彩图、Logo、带底色图片提供必要的深色变体或保持原图并调整承载背景。新增资源登记到 `pubspec.yaml`。照片及用户贴纸不反色，图片占位和失败状态随主题变化。

沉浸式虚拟喝酒保留用户选择的场景背景与酒液颜色，覆盖文字依据场景对比度选择样式。透明 WebView 继续透出场景背景；仅在实际 HTML 控件需要适配时增加外观消息，不重新加载 Three.js、不重建 WebViewController、不重启音频。

## 6. iOS MapKit 外观同步

### 6.1 底图与全局主题关系

沿用 `standard / muted / satellite` 协议值及用户选择：

| 底图 | 应用浅色 | 应用深色 |
| --- | --- | --- |
| standard | 浅色标准地图 | 深色标准地图 |
| muted（现有「暗色」） | 保留显式暗色底图 | 暗色底图 |
| satellite | 保留影像，标签及控件按浅色外观处理 | 保留影像，标签及控件按深色外观处理 |

卫星影像本身不承诺变暗。地图外部的 Flutter 面板始终使用应用主题；原生标注按地图有效外观选择颜色，保证显式暗色底图下仍可读。iOS 16 以下保留现有地图类型降级，但补齐可用的亮暗外观覆盖；最低支持版本以工程设置为准。

### 6.2 协议及生命周期

拟新增 `setAppearance` 命令，载荷为 `{"brightness":"light"}` 或 `{"brightness":"dark"}`。涉及文件：

- Dart：`platform/sipon_map_protocol.dart`、`widgets/sipon_map_widget.dart`。
- Swift：`ios/Runner/SiponMap/SiponMapChannel.swift`、`SiponMapFactory.swift`、`SiponMapView.swift`。
- 若统一由场景控制器发送命令，同时扩展 `map_scene_controller.dart` 与 `mapkit_scene_controller.dart`；宿主和控制器只能选一个作为发送方，避免重复更新。

推荐由 `SiponMapWidget` 宿主负责：初次通过 `creationParams` 传入有效亮度，在创建原生视图时应用；后续在依赖变化时比较亮度并发送命令。宿主未就绪期间只保留最新值，就绪后同步；同一通道顺序发送，销毁后不再发送。所有大地图、小地图及路线地图复用这条链路，不在每个页面复制逻辑。

Swift 保存 `appBrightness` 和 `styleId` 两个状态，通过统一 `applyEffectiveAppearance()` 计算外观。`apply(styleId:)` 和 `setAppearance` 均调用该函数，替换目前先 `.unspecified` 再局部覆盖的处理，防止切换底图后丢失用户主题。

视图级 `overrideUserInterfaceStyle` 可影响其子视图，具体行为依据 [Apple 官方外观覆盖说明](https://developer.apple.com/documentation/uikit/choosing-a-specific-interface-style-for-your-ios-app)。原生标注的胶囊、尾部、序号、文字、描边和阴影使用成对色板；已显示和复用后的 annotation view 都要刷新，保存为 `CGColor` 的图层颜色需重新赋值。保留分类色，但检查路线线条、选中点与底图的对比度。

外观命令不得调用相机移动、重新拉取地点、重建 MKMapView 或清除路线。切换前后保持中心、缩放、选中地点、路线与面板高度，协议重复调用应幂等。保留旧 `setup` 的兼容入口，缺省亮度按明确的兼容规则处理并记录日志。

## 7. 系统栏、原生弹窗和启动画面

- `main.dart` 保留 edge-to-edge 设置，将固定导航栏图标颜色迁移到主题感知的 `AnnotatedRegion<SystemUiOverlayStyle>`；有 AppBar 的页面使用对应 `systemOverlayStyle`，避免与根节点争夺控制。
- 普通深色页面用浅色系统栏图标，浅色页面用深色图标；iOS 状态栏亮度字段与 Android 图标亮度字段需分别处理。图片全屏和虚拟喝酒按实际背景局部覆盖，退出页面后恢复。
- `pubspec.yaml` 的 splash 配置补齐深色背景及必要资源，再用项目锁定版本的 `flutter_native_splash` 生成；核对 iOS `LaunchScreen.storyboard`、Assets 及 Android 夜间/Android 12 配置，不只修改 Flutter 启动页。
- 原生静态启动画面发生在 Dart 读取偏好之前，不能仅靠 `ThemeMode` 完全匹配手动模式。第一阶段采用跟随系统的原生启动画面，Flutter 首帧直接使用已保存偏好；系统外观与手动偏好相反时允许启动交接处存在一次配色差异，记录为明确边界。
- 图片选择、裁剪等原生模态界面逐项实机验证。若插件不跟随应用手动模式，增加 iOS 外观桥接：用户手动模式映射活动 Scene 的 window override，跟随系统映射 `.unspecified`；处理新 Scene 和启动恢复。不要无条件把跟随系统模式也锁定为当前解析亮度，以免妨碍后续系统变化。

## 8. 实施顺序与完成条件

1. **建立基础**：新增主题目录、持久化、外观设置及中英文文案；接入 MaterialApp；完成启动等待页、登录和系统栏。完成条件：三种模式切换及重启恢复正确。
2. **迁移公共视觉与主路径**：公共组件、首页、底栏、个人中心、设置及其弹窗。完成条件：核心页面双主题截图通过，浅色布局不变。
3. **完成原生地图**：协议、初次创建、动态更新、标注与多实例，再覆盖路线及各种地图面板。完成条件：切换外观不移动相机、不重建地图、不丢失选中状态。
4. **覆盖剩余业务与资源**：评论、记录、鸡尾酒、贴纸、虚拟喝酒、启动素材及插件模态界面。完成条件：加载、空态、失败、禁用、编辑态均可读。
5. **回归与发布**：运行静态检查、相关测试及真机矩阵；全部范围完成后再对用户开放模式入口，避免暴露只适配一半的全局深色模式。

按批次独立提交，先通过浅色回归再继续迁移。若上线需要临时回退，可用集中开关强制浅色并隐藏设置入口，保留用户存储偏好；Flutter 与原生桥接必须同步回退，不能只隐藏入口。

## 9. 测试与验收

### 9.1 自动化验证

- 控制器测试：默认值、三种枚举映射、非法值、读写异常、快速连续切换、重新创建后恢复。
- Widget 测试：系统亮暗变化只影响 `system`；显式模式稳定；弹窗已打开时更新；切换后表单内容、路由和滚动位置保留。
- 代表性截图：启动/登录、首页、个人中心、设置、账单、评论编辑、地图面板，各保留浅色和深色基线。平台地图不依赖纯 Flutter golden，使用模拟宿主检查协议并补充 iOS 截图。
- 地图测试：初始亮度、宿主就绪前切换、重复命令、多个实例、释放后更新、底图三档优先关系；断言外观变化不发送相机指令。原生侧测试外观计算和标注复用。
- 复用现有 `test/map_test.dart`、`route_map_test.dart`、`venue_detail_page_layout_test.dart`、`bill_page_bottom_inset_test.dart`、`virtual_drinking_page_test.dart` 等相关回归，避免改色引入行为和布局变化。

实施阶段运行 `flutter analyze` 与 `flutter test`；涉及 Swift 的改动在 macOS/Xcode 构建并执行 RunnerTests。当前文档交付不运行这些功能测试，也不视为通过了设备验收。

### 9.2 人工验收矩阵

| 维度 | 必测场景 |
| --- | --- |
| 模式 | 三种偏好 × 系统浅色/深色；手动偏好与系统相反 |
| 生命周期 | 冷启动、热切换、后台改系统外观再前台、退出登录、再次启动 |
| 页面状态 | 正常、加载、空态、网络失败、键盘、弹窗、日期选择、图片全屏 |
| 地图 | 三档底图、小地图、路线、多实例、半屏/全屏切换、已选地点 |
| 素材 | PNG 边缘、Logo、网络图片占位、贴纸、会员卡、透明 WebView |
| 设备 | 最低支持 iOS 与可用较新 iOS；小屏/大屏真机；其他发布平台验证公共主题及系统栏 |

最终通过条件：业务界面无遗漏的浅色容器或不可读文字；关键文字和控件达到对比度目标；所有外观偏好正确恢复；地图与 Flutter 按约定同步；切换不丢状态、不触发业务请求或场景重载；首帧及原生启动差异符合第 7 节边界。UI 固定色扫描中的残留项逐项登记用途，不能以简单要求所有颜色常量消失作为验收标准。

## 10. 风险与待确认项

| 项目 | 处理方式 |
| --- | --- |
| 页面固定色分散、私有组件和 `part` 文件较多 | 以页面清单逐项签收，先迁移公共组件，再检索剩余常量 |
| 「暗色底图」与「深色应用」名称易混淆 | 本方案保留原有选项；设置中注明它只影响底图，后续如改名需同步文案和测试 |
| 深色 Logo、会员卡等素材尚未审核 | 开发前确认资源清单；没有必要时保留原图并调整承载面 |
| 动态原生颜色和 Flutter 主题动画时机不同 | 保证最终外观一致；地图使用离散亮暗值，不逐帧跨通道传颜色 |
| 原生启动页不能直接读取 Dart 偏好 | 接受已列出的交接差异；若要求完全消除，另行评估原生启动恢复方案 |
| Windows 工作区无法完成 iOS 编译与实机验收 | 在 macOS/Xcode 和真机上完成原生验证，作为发布前必需环节 |

以上模式默认值、底图优先级、候选色板和启动边界为本方案建议；实施时以这些明确规则为基线，视觉调整集中收敛到主题和资源层。
