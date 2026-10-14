# Sipon 三端图标外观

2026-10-13：iOS 和 HarmonyOS 保留深色图标 A 版及原有浅色图标，由系统外观选择。
用户随后取消 Android 深色图标适配；Android 在系统浅色、深色下均使用原有图标。
图标资源选择不跟随应用内单独选择的浅色/深色偏好。

## 资源

- `assets/branding/app_icon_dark_a_source.png`：用户确认的原始生图，1254 × 1254。
- `assets/branding/app_icon_dark.png`：1024 × 1024 RGB 生产资源，保留 A 版完整底色与路网。
- `assets/branding/app_icon_light.png`：原有浅色图标的副本。
- `tool/sync_app_icons.py`：仅缩放和转换 PNG 格式，不重新设计图案。
  只生成 iOS/HarmonyOS 深色资源；Android 保持原有资源。
  需要 Pillow；执行 `python tool/sync_app_icons.py` 生成，添加 `--check` 验证。

## 平台行为

### iOS

`ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` 使用单尺寸的
`universal / ios / 1024x1024` Any 和 Dark 槽位，系统生成所需小尺寸。
使用 Xcode 16 及以上构建。iOS/iPadOS 18 及以上支持原生深色桌面图标；
主屏幕图标外观设为“自动”时跟随系统，用户强制选择“浅色”或“深色”时遵循桌面设置。
旧系统使用浅色图标。不调用替代图标 API，不改变用户主屏幕设置。
旧尺寸 PNG 保留在资源目录中，但不再由当前单尺寸图标目录引用。

### Android

保留 Manifest 的 `@mipmap/ic_launcher` 和原有五种密度的图标 PNG。
此前新增的五个 `mipmap-night-*` 图标已撤回，生成脚本也不再生成 Android 深色图标。
系统外观切换时，应用提供的桌面图标保持原样；应用内界面深色模式继续按原有逻辑运行。
手机桌面主题、图标包或启动器自身着色仍由用户的桌面设置决定。
如果另一份工程曾解压旧资源包，更新时需移走旧的五份
`android/app/src/main/res/mipmap-night-*/ic_launcher.png`；新版资源 ZIP 不会自动删除旧文件。

### HarmonyOS

增加 `AppScope/resources/dark/media/app_icon.png` 和
`entry/src/main/resources/dark/media/icon.png`，与 base 中的现有名字一致。
应用元数据、桌面 Ability、启动窗口的引用保持一致，由系统资源限定词选择。
同时增加深色启动窗口背景，避免深色图标出现在白色启动窗口上。
编译检查只证明资源成功进入 HAP，桌面刷新仍需在 HarmonyOS 6 / API 20 以上真机核对。

## 验收

1. 系统浅色时安装、冷启动，查看桌面图标与原有浅色图标一致。
2. 应用退出后切系统深色：iOS/HarmonyOS 检查 A 版，Android 检查原有图标；再冷启动。
3. 应用运行时往返切换系统外观，检查图标与启动窗口，不出现重复桌面入口。
4. 应用内强制浅色/深色时，iOS/HarmonyOS 图标仍遵循系统/桌面外观设置，Android 保持原图标。
5. iOS 分别验证主屏幕“自动”“浅色”“深色”；Android 确认系统深浅色下均提供原图标；
   HarmonyOS 检查手机和平板桌面与启动窗口。

Windows 本机可构建 Android APK 和未签名 HarmonyOS Release HAP。
iOS IPA 与 Xcode 资源编译需要 macOS；鸿蒙安装包需完成发布签名后才能安装。

## 本次构建验证（2026-10-13）

- 首次构建时 9 份深色输出资源逐像素匹配 A 版缩放结果，iOS Any/Dark 配置检查通过。
- 初版 Android Release APK 构建成功。检查编译后的资源表，`ic_launcher` 包含 5 个浅色
  和 5 个 night 密度配置；解析编译后的实际文件路径，10 份图标均匹配源资源。
  该 Android 深色适配已按用户要求撤回，初版 APK 已由恢复原图标的新版包替换。
  当前项目仍使用 Android Debug 测试证书，不是商店发布签名。
- HarmonyOS 共享 Dart 分析通过；16 项 Flutter 回归和 27 项 Node 回归通过。
  Release HAP 编译成功，包内 base/dark 各包含 app_icon 和 icon；A 版像素校验通过。
  已使用现有发布证书完成签名，官方 `hap-sign-tool` 验签成功。
  Flutter OH 最后的 IDE 自动签名提示由已有构建脚本识别，发布签名使用独立流程完成。
- iOS 未执行 Xcode 构建。首次构建时没有连接的 Android 或鸿蒙设备，未执行桌面模式切换真机验收。
- 交付目录：`build/app_icon_delivery/`。包含测试签名 APK、发布签名 HAP、
  三端图标资源 ZIP 及 SHA-256 文件清单。资源 ZIP 不包含签名私钥或证书。

### Android 撤回深色图标后的复验

- 重新构建 Android Release APK，签名检查通过。编译后的 `ic_launcher` 仅有
  mdpi、hdpi、xhdpi、xxhdpi、xxxhdpi 五份原有图标，不含 night 配置；包内像素与原图一致。
- 原有 Android Manifest 与五份原图和 Git 基线完全一致。iOS/HarmonyOS 的四份
  深色输出及 iOS Any/Dark 配置检查通过；鸿蒙签名 HAP 保持原样。
- 资源生成脚本不再生成 Android 深色图标。更新了交付 APK、资源 ZIP 和 SHA-256 清单。
- 重打包时遇到旧的 Flutter 开发插件注册缓存，重新解析构建配置后构建通过，
  没有修改业务代码或依赖版本。未安装新版 APK 到手机。

## 生图来源

使用内置 imagegen 编辑上一版路网已提亮的图标，用户确认 Variant A。
最终提示词的变更部分：

> Variant A — soft charcoal: lighten the entire background to charcoal gray with a
> subtle plum undertone, exact target #302C33, clearly lighter than the current
> almost-black version. Set all roads to muted light gray-purple #83738C to retain
> obvious road/background contrast. Do not change anything else.

提示词同时要求保留杯形、圆点、液体、描边、路网位置和构图，输出单个不透明正方形图标。
实际批准图像是最终设计依据，色值是生图目标值。

参考：[Apple 图标目录](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)、
[Android 夜间资源](https://developer.android.com/develop/ui/views/theming/darktheme)、
[HarmonyOS 深色媒体资源](https://developer.huawei.com/consumer/cn/blog/topic/03212973185022433)。
