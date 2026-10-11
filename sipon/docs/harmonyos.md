# 原生 HarmonyOS 适配

目标为 HarmonyOS 6.0.0（API 20）及以上的 HAP，地图通过系统 `@kit.MapKit`
的 `MapComponent` 展示。“出发”通过 `petalMaps.openMapRoutePlan` 打开花瓣地图。
标准、暗色、混合卫星底图、点位、选中高亮、地点搜索、逐站步行路线均由原生实现。

鸿蒙普通标注使用 SDK 字号 `12`，不再额外执行像素缩放。名称最多保留 14 个字符，
按屏幕空间避让并限制为约 3～10 个；筛选栏与底部面板区域预留空间。
选中点优先显示，路线站点只显示编号；其他酒吧保留可点击圆点。
相机停下、地图尺寸和面板留白变化时，重新计算标注可见性。

## 工具链与构建

安装 HarmonyOS Command Line Tools（或 DevEco Studio 自带的 SDK），配置 Flutter OH
所需的 Node、OHPM、Hvigor、HDC 和 `DEVECO_SDK_HOME`。本机已使用 `D:\hms` 下的
命令行工具链，无需安装 DevEco Studio 或本地模拟器。采用
[CPF-Flutter Flutter OH](https://gitcode.com/CPF-Flutter/flutter_flutter)
标签 `3.41.10-ohos-1.0.1`（Dart 3.11），上游 Flutter 不提供 `OhosView` 或 HAP 构建。
先通过该 SDK 的 `flutter doctor -v` 确认环境。

```powershell
$env:FLUTTER_OHOS_HOME = 'D:\hms\flutter_ohos'
.\tool\build_harmony.ps1 -Mode release
```

脚本在 `build/harmony_workspace` 生成独立工作目录，复制业务代码与鸿蒙工程、
加入直接引用的鸿蒙平台插件、应用锁定的依赖覆盖，然后执行依赖解析、Dart 分析和
`flutter build hap --target ohos/flutter/main.dart`。每次执行会重新生成此目录；
请在源工程的 `ohos` 中维护修改。iOS/Android 的主 `pubspec.yaml` 不需要切换依赖。
仅生成工作目录可执行：

```powershell
.\tool\build_harmony.ps1 -PrepareOnly
```

构建时会按 `plugins.lock.json` 浅拉取指定提交和插件子目录，缓存在
`build/harmony_plugin_cache`，再放入工作目录作为本地依赖，避免 Pub 下载多插件仓库的
全部历史。需要同时准备插件源码时使用 `-PrepareOnly -ResolvePlugins`。

## 应用与签名

`ohos/AppScope/app.json5` 包名是 `cn.hangzhoutanji.sipon`，版本为 `1.0.6`。
AppGallery Connect 中对应的 APP ID 为 `6917618507642289146`，申请 Profile 时请选择这个应用。
请与华为开发者后台的真实应用包名保持一致，在该应用中开通 Map Kit。
本工程最低支持 API 20。根据[Map Kit 开发准备](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/map-config-agc)，
从 HarmonyOS 5.0.2（API 14）开始，无需配置公钥指纹和 Client ID。
请在 AppGallery Connect 的“开发与服务”中选择对应项目和应用，进入“开放能力管理”，开启“地图服务”。
必须在开通地图服务后申请签名 Profile；若已有 Profile 早于服务开通，请重新申请并下载。
如使用 DevEco Studio，可配置签名并同步到源工程的 `ohos/build-profile.json5`。
当前命令行流程先构建未签名 Release HAP，再使用官方 `hap-sign-tool.jar` 签名。
首次双击
`tool/Create-Harmony-Signing.cmd`，使用 JDK 的 keytool 交互生成
`ohos/signing/sipon-release.p12` 和 `sipon-release.csr`，密钥别名为 `sipon_release`。
脚本优先选择 `JAVA_HOME` 下的 keytool，密码在本机弹窗中输入并显示掩码，
仅通过临时进程环境变量传给 keytool，结束时清理；不写入口令文件或命令行参数。
将 CSR 上传到 AGC 申请发布证书，再为对应应用申请发布 Profile，下载 `.cer` 和 `.p7b`。
下载的证书与 Profile 各保留一份在 `ohos/signing/`，执行 Release 构建后，双击
`tool/Sign-Harmony-Release.cmd`，在本机弹窗输入创建密钥时的口令。
脚本检查 Profile 的发布类型、应用包名和地图权限，再检查 HAP 的 Release 标记，
签名并执行官方验签。签名密码通过临时进程环境变量传给 Java 包装程序，
包装程序在内存中调用官方签名工具，不将口令写入进程命令行或文件。
最终上传文件位于 `build/harmony_release/sipon-release-<时间>-signed.hap`。
进入华为云调试上传此签名 HAP，选择 HarmonyOS API 20 及以上的云真机。
签名文件放入被忽略的 `ohos/signing/`，不要提交证书私钥或密码。
构建脚本会将此目录复制到生成工程的 `ohos/signing/`；签名配置建议使用相对此目录的路径。
签名配置不包含口令。下载的发布 Profile 必须包含 `com.huawei.service.mapkit` 服务能力。

原生工程声明网络、前台精确/模糊定位和相机权限。定位继续使用现有业务的权限申请流程；
相册选择使用系统图片选择器。Apple 登录保持仅在 Apple 平台显示。
定位和相机说明分别在默认、简体中文和英文资源中维护，保存为 UTF-8。
`tool/check_harmony_resources.ps1` 在构建前检查权限说明缺失、连续问号或替换字符，
避免无效内容再次进入系统权限弹窗。

## 锁定的插件

`ohos/flutter/dependencies.yaml` 使用以下标签对应的完整提交号，直接选择 federated
鸿蒙实现；`ohos/flutter/pubspec_overrides.yaml` 另锁定裁切插件和必要的平台接口。

| 功能 | 仓库 | 标签 |
| --- | --- | --- |
| 偏好存储 | CPF-Flutter/flutter_packages | shared_preferences-v2.5.3-ohos-1.0.1 |
| 缓存路径 | CPF-Flutter/flutter_packages | provider-v2.1.5-ohos-1.0.1 |
| 图片选择/拍照 | CPF-Flutter/flutter_packages | image_picker-v1.2.1-ohos-1.0.1 |
| URL 唤起 | CPF-Flutter/flutter_packages | url_launcher_v6.3.2-ohos-1.0.2 |
| WebView | CPF-Flutter/flutter_packages | webview_flutter-v4.13.1-ohos-1.0.2 |
| 定位 | CPF-Flutter/fluttertpc_geolocator | 14.0.2-ohos-1.0.0 |
| 音频 | CPF-Flutter/flutter_audioplayers | 6.5.1-ohos-1.0.0 |
| 图片裁切 | CPF-Flutter/fluttertpc_image_cropper | 12.2.1-ohos-1.0.0 |

## 坐标边界

沿用现有 Android 代码对业务坐标采用 GCJ-02 的约定：大陆及港澳的业务点位、
搜索结果和视野直接传递给 Map Kit。系统 GPS 定位通过
`sipon/harmony.convertDeviceLocation` 转换一次，再进入城市控制器和地图。
原始 GPS 仍用于定位缓存与城市距离计算。台湾及海外采用 Map Kit 对应的 WGS-84 坐标。
地图上线前需要将真实服务端点位与花瓣地图地点搜索结果交叉核对；
现有 Android 注释将后端坐标系标为试验假设，仓库内没有服务端坐标系声明。

## 验证

「记一笔」通过 `sipon/sticker_cutout.generateSticker` 调用鸿蒙 Core Vision Kit 的
`subjectSegmentation.init/doSegmentation/release`，输出全部主体的透明 PNG 贴纸。
原照片先复制到应用 `filesDir/drink_stickers`，抠图失败、无主体或设备不支持时仍返回持久化原图。
识别图片最长边限制为 1600 像素，并根据 EXIF 调整方向。原生请求串行执行，结束时释放
分割服务、PixelMap、编码器及文件句柄，避免并行请求提前释放共享服务。
不需要额外安装本地模拟器，继续使用云真机验收。

华为的[主体分割与透明图片保存示例](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-core-vision-2)
指出 JPEG 会丢失透明通道；这里直接以 `image/png` 编码前景 PixelMap。
云真机请分别选一张酒杯、一张酒瓶和一张无明显主体的照片，确认贴纸背景透明、方向正确，
并在关闭重开应用后确认记录照片与贴纸仍能显示。端侧识别效果取决于照片与设备的系统能力。

当前 Flutter OH 内嵌库引用 API 26 的密码自动填充接口，而本机 SDK 为 API 24。
`ohos/hvigor/flutter_sdk_compat.ts` 在构建目录生成兼容副本，保留不支持自动填充时的回退，
不修改全局 SDK；此构建不提供系统密码自动填充。SDK 提供对应接口后会自动使用原始内嵌库。

```powershell
flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos
flutter test tool/tests/harmony_map_test.dart
node --test tool/tests/petal_marker_layout_test.cjs
node --test tool/tests/petal_marker_artwork_test.cjs
node --test tool/tests/harmony_sticker_test.cjs
```

共享 Dart 代码可用上游 Flutter 检查；`ohos/flutter/main.dart` 必须使用 Flutter OH 分析。
标注布局测试使用命令行工具链自带的 TypeScript，覆盖拥挤标注、选中点优先、路线编号、
控件留白、紧凑地图、数量上限、无效坐标和名称截断。
鸿蒙标注使用 `PetalMarkerArtwork.ets` 绘制完整 PixelMap：28vp 高的白底紫边评分胶囊，
选中时紫底白字和白色类别图标，店名在下方以 12vp 显示、最多两行。
画布统一按设备密度输出像素，布局和避让始终使用逻辑尺寸；店名与评分不再使用同一条地图注记。
地理位置锚定在胶囊中心，避让包括下方店名，选中点和路线编号优先保留。
路线站点采用独立样式：28vp 白色圆形内放类别图标，下方仅显示路线序号（1、2、3……），
不显示评分或店名；选中时加粗主题色描边，圆形内部仍保持白色。
`petal_marker_artwork_test.cjs` 覆盖颜色、图标着色、字号与密度、两行截断、路线编号及暗色模式。
`build_harmony.ps1` 会在 HAP 编译之前运行地图回归测试，包括初始化失败重试、
关闭页面时取消初始化、重试隔离旧地图回调及事件队列清理。
原生 ArkTS 编译与 HAP 安装必须使用 HarmonyOS SDK 和签名配置完成。
构建脚本同时运行原生抠图的模拟接口回归测试，覆盖透明 PNG、失败保留原图、EXIF 方向、
资源释放、串行请求、只读前景和 Flutter 通道协议；这些测试不能代替真机 AI 识别验收。
真机验收需覆盖地图拖动/缩放、半屏与全屏切换、点位点击、城市切换、定位授权与拒绝、
搜索和路线失败、地图重试、多地图同时存在、关闭页面后异步回调、花瓣地图唤起，
以及登录存储、头像裁切、图片上传、音频和 WebView。

## 接口参考

- [MapComponent](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/map-mapcomponent)
- [地图服务开通与 client_id 配置示例](https://developer.huawei.com/consumer/cn/doc/doccenter-scenario/bpta-shared-bicycle)
- [地图控制器](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/map-map-mapcomponentcontroller)
- [事件管理](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/map-map-mapeventmanager)
- [坐标转换](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/map-map-convertcoordinatesync)
- [路径规划](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/map-navi-api)
- [唤起花瓣地图](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/map-petal-maps)
