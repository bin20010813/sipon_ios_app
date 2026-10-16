# sipon

A new Flutter project.

原生 HarmonyOS 构建、花瓣地图接入、插件版本及签名配置见 [鸿蒙适配说明](docs/harmonyos.md)。

三端统一开发流程、GCJ-02 业务坐标约定及回归要求见
[三端整合与坐标契约](docs/three-platform-integration.md)。

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android 贴纸抠图（U2NETP / 完全离线）

“记一笔”使用 `onnxruntime-android:1.22.0` 在 CPU 本地执行 U2NETP 通用前景分割。模型已内置于 `android/app/src/main/assets/models/u2netp.onnx`，首次使用也无需下载，无 GMS 设备同样可用。不再使用 ML Kit 或 Google Play 模型安装服务；应用其他业务的网络权限保持不变。

- 模型文件为 4,574,861 字节（约 4.36 MiB），另有 ONNX 原生推理库的包体开销。模型、来源和许可证一起随 APK 分发，详见同目录 `NOTICE.txt` 及 `*-LICENSE.txt`；请将实际 `.onnx` 文件纳入版本管理，不要仅提交 Git LFS 指针。
- 输入按 EXIF 校正方向，最长边限制 1600，缩放至 320×320 并按模型的 RGB mean/std 归一化；输出 soft-alpha 蒙版恢复至图片尺寸，裁去透明边缘并保存 PNG。
- 后台串行推理，session 惰性初始化并复用，Activity 销毁时按顺序释放。原图和贴纸存入应用私有 `files/drink_stickers`，无有效前景或处理失败保留原图；异常可通过 Logcat 的 `StickerCutout` 标签排查。
- 运行时不上传照片、不下载模型，不需要 API Key、Python 或 rembg 环境。开发构建首次解析 Maven 依赖仍可能需要网络，与应用离线抠图无关。
- iOS 仍使用 Vision，Flutter 通道及记录数据格式不变。修改原生实现或 assets 后须完整重建安装，不能只热重载。

模型来自 rembg 的固定发布地址，MD5 已与其上游记录核对：`8e83ca70e441ab06c318d82300c84806`；SHA-256：`309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8`。

回归命令：在 `android` 目录执行 `./gradlew :app:testDebugUnitTest --tests com.example.sipon.StickerMaskTest`；项目根目录执行 `flutter test test/sticker_cutout_service_test.dart`。
真机回归：安装后未联网即选图、无 GMS 设备、透明杯/瓶/吸管、复杂背景、EXIF 旋转及镜像照片、连续选图和保存重启。U2NETP 是显著性分割而非精细玻璃材质抠图，透明杯体及细小边缘需使用真实照片评估；算法测试不代表已验证真机画质。

## iOS 路径插件兼容性

`pubspec.yaml` 将 `path_provider_foundation` 固定为 `2.5.1`，使用原生插件实现。
`2.6.0` 改为 FFI 后，在当前 iOS 调试环境中出现 `DOBJC_initializeApi` /
`objective_c.framework/objective_c` 加载失败，图片缓存等间接调用路径插件的功能会受影响。
上游问题：https://github.com/flutter/flutter/issues/186794 。
待验证上游修复后再解除版本固定。

切换此依赖后，需要停止旧的 Flutter 调试会话，在 `sipon` 目录执行
`flutter pub get` 和 `flutter run`，让原生插件重新构建、安装；仅热重载或热重启不足以应用变更。

## 地图半屏 / 全屏移动诊断

Debug 构建启用 `[SiponMapMotion]` 日志。修改了原生 Swift 日志后，需停止 App 并重新 `flutter run`；热重载不能更新原生代码。

从 `sipon` 目录启动并保存 Flutter 日志：

```bash
flutter run 2>&1 | tee /private/tmp/sipon_flutter.log
```

另开终端保存原生地图诊断（仅启动一台模拟器时）：

```bash
xcrun simctl spawn booted log stream --style compact --level debug \
  --predicate 'process == "Runner" AND eventMessage CONTAINS "SiponMapMotion"' \
  2>&1 | tee /private/tmp/sipon_map_motion.log
```

复现顺序：选择酒吧 → 收起态展开到半屏 → 半屏拖到全屏 → 全屏回半屏 → 在露出的地图区域拖动。每一步松手后稍等相机停稳。

| 日志事件 | 含义 |
| --- | --- |
| `MAP_CREATED` | 将 Flutter 的 `page` 与原生 `view` 对应，`map=sipon/mapkit_N` 对应 `view=N` |
| `SHEET_EXTENT` | 面板高度变化，最多每 250ms 一条；其中 stage 是已确定的档位，不是当前拖动位置 |
| `SHEET_STAGE` | 档位切换：collapsed / half / full，并记录前一个档位 |
| `APPLY_STAGE` | 页面请求调整相机，记录触发原因、padding、是否聚焦选中地点 |
| `CAMERA_COMMAND` / `SET_CAMERA` / `PADDING` | 原生实际收到的命令及相机设置；`willMove=false` 表示 padding 分支不移动相机 |
| `MAP_POINTER_DOWN/UP/CANCEL` | 地图区域收到的原始触摸；`displacementPx` 是抬手位置相对按下位置的直线距离，不是累计路径 |
| `REGION_BEGIN/END` | MapKit 视野变化，`centerShiftM` 是此次开始至结束的中心位移米数，`distanceDelta` 是相机距离变化 |
| `VIEWPORT_SETTLED` | Flutter 去抖后收到的最终视野 |

判断方式：`SHEET_STAGE → APPLY_STAGE → CAMERA_COMMAND focusOn → SET_CAMERA → REGION_END` 表明切换触发了程序化取景。若拖面板的同时出现相同地图的 `MAP_POINTER_*`，需要检查触摸是否透传。原始触摸并不等同于原生拖动识别成功，需结合位移记录；没有新相机命令时也不能仅凭视野变化判定为手势穿透。

`REGION_END` 中的 `lastCommand` 只是最近一次命令，可能早已结束，不是本次变化的原因判定。`animated=true` 也不代表一定是用户操作。此次只增加观察日志，不改变半屏 / 全屏取景行为。
