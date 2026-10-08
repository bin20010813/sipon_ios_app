# 原生 HarmonyOS 适配

目标为 HarmonyOS 6.0.0（API 20）及以上的 HAP，地图通过系统 `@kit.MapKit`
的 `MapComponent` 展示。“出发”通过 `petalMaps.openMapRoutePlan` 打开花瓣地图。
标准、暗色、混合卫星底图、点位、选中高亮、地点搜索、逐站步行路线均由原生实现。

## 工具链与构建

安装 DevEco Studio 及 HarmonyOS SDK，配置 Flutter OH 所需的 Node、OHPM、
Hvigor、HDC 和 `DEVECO_SDK_HOME`。采用
[CPF-Flutter Flutter OH](https://gitcode.com/CPF-Flutter/flutter_flutter)
标签 `3.41.10-ohos-1.0.1`（Dart 3.11），上游 Flutter 不提供 `OhosView` 或 HAP 构建。
先通过该 SDK 的 `flutter doctor -v` 确认环境。

```powershell
$env:FLUTTER_OHOS_HOME = 'D:\flutter_ohos'
$env:SIPON_HUAWEI_CLIENT_ID = '<该鸿蒙应用的 OAuth Client ID>'
.\tool\build_harmony.ps1 -Mode debug
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

`ohos/AppScope/app.json5` 默认包名是 `com.sipon.app`，版本为 `1.0.6`。
请与华为开发者后台的真实应用包名保持一致，在该应用中开通 Map Kit。
从 AppGallery Connect 的应用信息取得 OAuth Client ID，通过 `SIPON_HUAWEI_CLIENT_ID`
或 `-MapClientId` 传给构建脚本。脚本会替换生成工程 `entry/src/main/module.json5`
中 `metadata.client_id` 的占位符；未配置时会阻止正式构建，`-PrepareOnly` 只发出提示。
若直接用 DevEco 构建源工程，需要先将该占位符替换成真实 Client ID。
这是应用的客户端标识，不是 Client Secret，也不是 Android 地图 API Key。
通过 DevEco Studio 配置调试或发布签名，并同步到源工程的
`ohos/build-profile.json5`，设置对应产品的 `signingConfig`。
签名文件放入被忽略的 `ohos/signing/`，不要提交证书私钥或密码。
构建脚本会将此目录复制到生成工程的 `ohos/signing/`；签名配置建议使用相对此目录的路径。
当前工程没有预置真实签名，也没有声称已完成地图服务开通。

原生工程声明网络、前台精确/模糊定位和相机权限。定位继续使用现有业务的权限申请流程；
相册选择使用系统图片选择器。Apple 登录保持仅在 Apple 平台显示。

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

```powershell
flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos
flutter test tool/tests/harmony_map_test.dart
```

共享 Dart 代码可用上游 Flutter 检查；`ohos/flutter/main.dart` 必须使用 Flutter OH 分析。
`build_harmony.ps1` 会在 HAP 编译之前运行地图回归测试，包括初始化失败重试、
关闭页面时取消初始化、重试隔离旧地图回调及事件队列清理。
原生 ArkTS 编译与 HAP 安装必须使用 HarmonyOS SDK 和签名配置完成。
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
