# Sipon UI 适配改造方案:iOS 液态玻璃 + 鸿蒙风格

## 1. 目标与原则

- iOS:靠近 iOS 26 Liquid Glass(半透明折射材质、胶囊形控件、浮动导航、弹性动效)。
- 鸿蒙:靠近 HarmonyOS 的 HarmonyOS Sans、大圆角、轻量模糊(系统"通透"材质)、克制阴影。
- Android / 其他:保持现有 Material 3。
- 不推翻现有业务和路由,仅重构视觉层;不整体改成 CupertinoApp。
- 统一"平台设计语言"抽象,业务页面不再直接写 `defaultTargetPlatform`。

## 2. 现状盘点(基于代码)

| 位置 | 现状 | 改造方向 |
|---|---|---|
| `lib/app/sipon_app.dart` | `MaterialApp` + 手动 SystemUiOverlay | 注入平台设计语言、页面转场、滚动物理 |
| `lib/app/theme/sipon_theme.dart` | 单一 `ThemeData`,各组件主题 | 按平台生成差异化 ThemeData + ThemeExtension |
| `lib/app/widgets/shell_components.dart` | 自建悬浮底栏,`BackdropFilter(sigma 22)` | 抽成统一 `SiponGlass` 材质组件 |
| `lib/app/shell/sipon_shell.dart` | 底栏高度、间距按平台硬编码 | 读取 ThemeExtension 里的布局参数 |
| `home_page.dart` | 单独的 BackdropFilter 遮罩 | 复用 `SiponGlass`,统一性能策略 |
| 各页 AlertDialog/BottomSheet/SnackBar/DatePicker | Material 样式 | 用统一封装的自适应入口 |

## 3. 总体架构

```
lib/app/design/
  sipon_platform.dart      // 平台识别:ios / ohos / android / other
  sipon_design.dart        // ThemeExtension:材质、圆角、动效、布局参数
  glass/
    sipon_glass.dart       // 通用玻璃容器
    sipon_glass_button.dart
    sipon_glass_bar.dart   // 顶栏/底栏
  adaptive/
    adaptive_dialog.dart
    adaptive_sheet.dart
    adaptive_switch.dart
    adaptive_loading.dart
    adaptive_toast.dart
    adaptive_date_picker.dart
```

### 3.1 平台识别(唯一入口)

```dart
enum SiponPlatform { ios, ohos, android, other }

SiponPlatform get siponPlatform {
  if (kIsWeb) return SiponPlatform.other;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:     return SiponPlatform.ios;
    case TargetPlatform.android: return SiponPlatform.android;
    default:                     return SiponPlatform.other;
  }
}
```

注意:鸿蒙 Flutter(OpenHarmony 适配分支)中 `defaultTargetPlatform` 的取值取决于所用引擎分支,
可能是 `android`、`ohos` 或 `fuchsia`。需在真机打印确认后,再补充 `ohos` 的判断
(可用 `Platform.operatingSystem == 'ohos'`,或通过 MethodChannel / `device_info` 获取)。
这个判断集中在这一个文件里,其他代码全部读 `SiponDesign`。

### 3.2 SiponDesign(ThemeExtension)

承载所有"风格参数",页面只读取、不判断平台:

```dart
class SiponDesign extends ThemeExtension<SiponDesign> {
  final double blurSigma;         // iOS 24~30,OHOS 16~20,Material 0
  final double glassOpacity;      // 玻璃底色透明度
  final double glassBorderOpacity;// 高光描边
  final double radiusCard, radiusControl, radiusSheet;
  final bool   useCapsuleControls;// iOS/OHOS 胶囊按钮
  final double navBarHeight, navBarBottomGap;
  final Duration pageTransition;
  final ScrollPhysics scrollPhysics;
  final String? fontFamily;
}
```

在 `sipon_theme.dart` 中:`_build(brightness, platform)` 里挂 `extensions: [SiponDesign.of(platform, brightness)]`。

## 4. iOS 液态玻璃实现

### 4.1 技术路线(按成本从低到高)

1. **纯 Flutter 模拟(推荐首选,跨版本稳定)**
   `ClipRRect + BackdropFilter(blur + saturation) + 渐变高光描边 + 内阴影`。
2. **原生 Liquid Glass 嵌入(iOS 26+ 才有 `glassEffect`)**
   通过 `UiKitView` / PlatformView 嵌入 SwiftUI `.glassEffect()`,仅用于底栏、浮动按钮等少量关键控件;
   iOS < 26 自动回退到方案 1。成本高,且 PlatformView 与 Flutter 手势/合成有边界问题。
3. 可评估社区包(如 `liquid_glass_renderer` 等基于 shader 的折射实现),
   需评估 Impeller 兼容性、性能和维护活跃度,不建议一次性全量使用。

建议:**方案 1 打底 + 仅在底栏/主按钮上选配方案 2**。

### 4.2 SiponGlass 材质配方

```dart
class SiponGlass extends StatelessWidget {
  // child, borderRadius, tint, elevation(强度档位: thin/regular/thick)
  @override
  Widget build(BuildContext context) {
    final d = Theme.of(context).extension<SiponDesign>()!;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: d.blurSigma, sigmaY: d.blurSigma),
          inner: const ColorFilter.matrix(_saturate1_8), // 提高饱和度,玻璃更"透亮"
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: tint.withOpacity(d.glassOpacity),
            gradient: LinearGradient(  // 顶部高光 -> 底部通透
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Colors.white.withOpacity(.28), Colors.white.withOpacity(.04)],
            ),
            border: Border.all(color: Colors.white.withOpacity(d.glassBorderOpacity), width: .8),
          ),
          child: child,
        ),
      ),
    );
  }
}
```

要点:
- 深浅色分别调参;深色模式白色高光降到 0.12~0.18。
- 玻璃下方内容要有层次(图片/地图/渐变),否则看不出效果。
- 性能:玻璃区域不要大面积嵌套 BackdropFilter;列表中的卡片不要每项都做 blur,
  卡片用"半透明纯色 + 描边"即可,仅底栏、顶栏、浮层、Sheet 使用真实模糊。
  现有 `home_page.dart` 里"progress 归零移除 BackdropFilter"的做法保留,并沉淀到 SiponGlass 的可选参数。
- 用 `RepaintBoundary` 隔离玻璃层。

### 4.3 具体改造清单(iOS)

| 组件 | 做法 |
|---|---|
| 底部导航 | 保持悬浮,改成胶囊玻璃;选中项使用"滑动的玻璃气泡"(`AnimatedPositioned` + 弹簧曲线 `Curves.easeOutBack`/`SpringSimulation`) |
| 顶部 AppBar | 透明 + 滚动后渐显玻璃(`SliverPersistentHeader` 或监听 offset) |
| 按钮 | 主按钮胶囊(`StadiumBorder`)、次按钮玻璃;按下缩放 0.96 + 轻触觉 `HapticFeedback.selectionClick` |
| Dialog | `CupertinoAlertDialog` 或自建玻璃圆角 28 弹窗 |
| BottomSheet | 顶部大圆角 32、玻璃背景、抓手条,`showCupertinoModalPopup` 风格 |
| Switch / Loading / DatePicker | `CupertinoSwitch` / `CupertinoActivityIndicator` / `CupertinoDatePicker`(滚轮) |
| 页面转场 | `CupertinoPageTransitionsBuilder`(边缘右滑返回) |
| 滚动 | `BouncingScrollPhysics` |
| 字体 | 系统 SF(不指定 fontFamily),字重偏轻,字距略紧 |
| 状态栏 | 沉浸式,按亮暗自动切图标色 |

## 5. 鸿蒙风格实现

HarmonyOS 的特点:圆角更大且统一(卡片 16~24)、阴影弱、分隔线细、
系统"通透材质"模糊较轻、动效偏"跟手 + 弹性"(responsive spring)、字体 HarmonyOS Sans。

| 项 | 做法 |
|---|---|
| 字体 | 打包 HarmonyOS Sans(注意字体授权,可商用但需遵循其协议),或使用系统默认字体 |
| 材质 | `SiponGlass` 参数:`blurSigma≈16~20`,`glassOpacity≈0.72`,弱描边,无顶部高光渐变 |
| 圆角 | 卡片 20、控件 12~16、Sheet 24;**不使用胶囊底栏**,用通栏半透明底栏 + 顶部细线 |
| 底栏 | 图标+文字,选中项颜色变化 + 轻微缩放,不做气泡 |
| 转场 | 自定义 `PageTransitionsBuilder`:从右侧平移 + 淡入,时长 300ms,曲线 `Cubic(0.2,0,0,1)`(接近鸿蒙标准曲线) |
| 返回手势 | 鸿蒙有系统侧滑返回,需确认 `PopScope`/`onPopInvoked` 与系统返回事件已正确对接 |
| 滚动 | `ClampingScrollPhysics` 或带轻微回弹 |
| 控件 | Switch/Loading 使用自绘或保留 Material 但换成品牌色、更细线条 |
| 系统栏 | 沉浸式,状态栏/导航条透明;注意 `ohos` 侧 `EntryAbility` 窗口沉浸式设置与安全区(avoid area)取值 |

另外需要处理 `ohos/` 工程层:
- 窗口 `setWindowLayoutFullScreen(true)`,并把顶部/底部 avoid area 通过 Channel 传给 Flutter(如引擎分支尚未映射到 `MediaQuery.padding`)。
- 检查所用插件是否都有 ohos 实现(`sign_in_with_apple` 在鸿蒙无意义,应隐藏;
  `url_launcher`、`shared_preferences`、`cached_network_image` 依赖需用 `ohos` 适配版本/override)。
- 登录入口:鸿蒙改用"华为账号一键登录"(Account Kit)替代 Apple 登录,当前 `sms_login_page.dart` 里
  `_supportsAppleSignIn` 已有平台判断入口,可扩展。

## 6. 自适应组件封装

统一入口,内部按平台分发,业务代码只调用:

```dart
showSiponDialog(context, title:, content:, actions:)
showSiponSheet(context, builder:)
SiponSwitch(value:, onChanged:)
SiponLoading()
showSiponToast(context, message)     // iOS:顶部玻璃胶囊;OHOS:底部圆角条;Android:SnackBar
showSiponDatePicker(context, ...)    // iOS:Cupertino 滚轮;其余:Material DatePicker
```

迁移方式:全局搜索 `showDialog / AlertDialog / showModalBottomSheet / SnackBar / Switch /
CircularProgressIndicator / showDatePicker`,逐个替换为上述入口。

## 7. 动效规范

- iOS:弹簧动画(`SpringDescription(mass:1, stiffness:300, damping:25)`),按压反馈 + 触觉。
- OHOS:标准曲线 `Cubic(0.2, 0, 0, 1)`,时长 250~350ms;避免过度弹性。
- 降低动态效果:读取 `MediaQuery.disableAnimations`,开启时关闭模糊动画和弹簧。
- 透明度/模糊动画使用 `TweenAnimationBuilder` + `RepaintBoundary`,避免整页重绘。

## 8. 性能与兼容

- BackdropFilter 成本高:一屏最多 2~3 个;低端 Android/鸿蒙设备提供"降级为半透明纯色"开关
  (`SiponDesign.blurSigma = 0`),可根据设备性能或用户设置切换。
- 地图页(MapKit/天地图)上叠加玻璃要实测帧率,PlatformView 上的 BackdropFilter 可能不生效(无法模糊原生视图),
  此处应改为高不透明度的纯色玻璃。
- 深浅色模式需分别验收(现有 `SiponThemeController` 已支持)。
- 无障碍:玻璃上文字对比度 ≥ 4.5:1;尊重"降低透明度"系统设置
  (iOS 可通过 Channel 读取 `isReduceTransparencyEnabled`)。

## 9. 实施步骤(建议分期)

**阶段 0:基础设施(1~2 天)**
1. 新增 `design/` 目录:`sipon_platform.dart`、`SiponDesign`、`SiponGlass`。
2. `sipon_theme.dart` 接入 `SiponDesign`;`sipon_app.dart` 设置 pageTransitionsTheme、scrollBehavior。
3. 真机验证鸿蒙平台识别值。

**阶段 1:壳层(2~3 天)**
4. 重写 `shell_components.dart` 中的底栏,使用 `SiponGlass`,iOS 胶囊气泡、OHOS 通栏。
5. `sipon_shell.dart` 间距参数改读 `SiponDesign`。
6. `home_page.dart` 遮罩模糊改用 `SiponGlass`。

**阶段 2:通用控件(2~3 天)**
7. Dialog / Sheet / Toast / Switch / Loading / DatePicker 自适应封装,并全局替换。
8. 按钮、输入框、Chip 主题(胶囊/圆角)按平台差异化。

**阶段 3:页面细节(3~5 天)**
9. 登录页、首页、酒单、记录页、地图页逐页走查:顶栏渐显玻璃、卡片圆角、阴影、字体。
10. 地图页叠层玻璃降级策略。

**阶段 4:鸿蒙工程与验收(2~3 天)**
11. 沉浸式/安全区、返回手势、字体、登录方式、插件兼容。
12. 三端 × 深浅色 × 低端设备性能验收(DevTools 看 raster 耗时)。

## 10. 风险

| 风险 | 应对 |
|---|---|
| 鸿蒙 Flutter 引擎分支差异大,`BackdropFilter`/Impeller 表现不一致 | 阶段 0 就在真机验证,必要时 OHOS 默认降级 |
| 原生 Liquid Glass 仅 iOS 26+ | 以 Flutter 模拟为基线,原生仅作增强 |
| 玻璃过多导致掉帧 | 限制数量、RepaintBoundary、提供降级开关 |
| 一次性全量替换风险高 | 按阶段合入,每阶段可独立回滚 |
| 字体授权 | 使用 HarmonyOS Sans 前核对授权条款 |

## 11. 验收标准

- iOS 底栏/顶栏/弹层具备玻璃质感,深浅色均清晰可读,返回手势正常。
- 鸿蒙真机沉浸式正确,转场/返回手势符合系统习惯,无 Apple 登录入口。
- Android 视觉与现状一致,无回归。
- 业务页面代码中不再出现直接的平台风格判断(登录能力等功能性判断除外)。
- 中端设备滚动保持 60fps(raster 线程无持续超时)。
