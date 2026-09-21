# sipon

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

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
