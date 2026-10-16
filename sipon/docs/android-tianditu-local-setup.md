# Android 天地图初版：本地配置与联调

> 历史文档：当前分支已迁移到花瓣地图 SDK，请使用 [Android 花瓣地图配置](android-petal-local-setup.md)。以下保留迁移前记录。

## 填写天地图 Key

Android 构建从 Gradle 属性 `TDT_KEY` 读取瓦片 Key；环境变量 `TDT_KEY` 也可用，Gradle 属性优先。请把真实值放在本机用户级 `~/.gradle/gradle.properties`，添加一行：

```properties
TDT_KEY=你的天地图WMTS瓦片Key
```

这里填写控制台的**应用密钥**（WMTS 请求中的 `tk`），不要把 `tk` 和“安全密钥”拼成一个值。修改该文件后须重新构建并安装 APK；已安装的包不会从本机配置文件动态读取 Key。

### 控制台开启了“安全密钥”（返回 403 / 301020）

如果请求瓦片返回 `403`，且响应体为 `{"code":301020,"msg":"安全核验异常","resolve":"安全核验sk码错误或丢失!"}`，说明该应用在天地图控制台绑定了**安全密钥（sk）**，服务端要求每个请求除 `tk` 外还携带 `sk`。两种解决方式任选其一：

1. 控制台取消绑定：天地图控制台 → 应用管理 → 编辑该应用 → 关闭/清空“安全密钥”，重新构建安装。
2. 配置 sk：把安全密钥填进本机 `~/.gradle/gradle.properties` 的另一行，重新构建安装：

```properties
TDT_KEY=你的天地图应用密钥
TDT_SK=你的天地图安全密钥
```

`TDT_SK` 留空时不拼接 `sk` 参数，行为与原来一致。环境变量 `TDT_SK` 同样可用，Gradle 属性优先。MapLibre 日志只打印 HTTP 状态码，看不到响应体；排查时可用 curl 请求同一个瓦片 URL 查看真实错误码（`301001 非法key` 表示 `tk` 无效，`301020` 表示缺少或错误的 `sk`）。

### 浏览器端 Key 的 UA 校验（返回 403 / 301012）

携带正确的 `tk` + `sk` 后仍返回 403，响应体为 `{"code":301012,"msg":"权限类型错误","resolve":"Key权限类型错误！浏览器端，请使用浏览器访问！"}`，说明天地图对**浏览器端类型 Key** 强制校验 User-Agent：必须是浏览器 UA。MapLibre 默认发送 `User-Agent: MapLibre Android/...`，会被拒绝。

实现已在 `SiponTiandituView` 中通过 `HttpRequestUtil.setOkHttpClient(...)` 注入 OkHttp 拦截器，对 `*.tianditu.gov.cn` 域名的请求覆写为浏览器 UA，其余请求保持默认。验证方法：用 curl 对比 `-A "Mozilla/5.0 (Linux; Android 14) ..."`（返回 200 图片）与默认 UA（返回 403/301012）。

注意：这是对官方"浏览器端 Key 仅限浏览器访问"策略的规避。正式发布前应与天地图确认原生 App 直连 WMTS 的授权方式，或改用其认可的接入方式。

Windows 上通常是 `C:\Users\你的用户名\.gradle\gradle.properties`。不要把真实 Key 写进仓库文件、`android/local.properties` 或命令行记录。Android 客户端中的 Key 最终可被提取，这个做法仅避免把 Key 提交到源码。

当前实现由 Android 内的 MapLibre 直接请求天地图 WMTS，并未调用天地图 Android SDK。申请时优先选择支持 WMTS 图层服务的“浏览器端/Web 端”应用 Key；天地图省级节点的服务接入说明也采用浏览器端许可。控制台若对浏览器端 Key 强制校验网页域名，需与天地图确认原生 App 直连 WMTS 的授权方式，不能依赖未验证的空白名单设置。构建后还需确认该 Key 允许 Android 客户端访问 `vec_w`、`cva_w`、`img_w`、`cia_w`。缺少 Key 时地图显示配置错误；有 Key 后仍需真机验证图层授权、瓦片级别、注记及来源标识。

如果还要启用腾讯地图外部导航，Flutter 构建另传 `--dart-define=SIPON_TENCENT_MAP_KEY=你的腾讯地图Key`；未配置时腾讯选项不会展示。高德和百度导航不使用这个 Key。

## 道路路线

当前默认由 Android 原生 `TiandituDrivingService` 请求天地图驾车服务。共享层传入
GCJ-02 站点，原生边界转换为天地图显示坐标；返回道路几何转回 GCJ-02，通道响应
标记 `crs: GCJ02`。绘制和样式重放均从业务坐标转换，避免累积偏移。

若注入 `RoutePlanner`，则调用拟议后端接口 `POST /api/map/routes/plan`，请求和响应
均要求 `crs: GCJ02`，站点为 `{lng, lat}`，`legs[].coordinates` 为 `[lng, lat]`。
该代理不在本仓库内，不能仅修改响应标签冒充转换；接入前需同步后端契约。

## 当前验证边界

当前 `MapCoordinateAdapter` 使用 `gcj02-to-cgcs2000-v1`，移除 GCJ-02 偏移并将
WGS-84/CGCS2000 数值近似用于地图显示，不宣称测绘精度。详见
[三端整合与坐标契约](three-platform-integration.md)。正式发布前仍需 Android
真机验证点位、道路、选点回传、无 GMS 定位、外部导航、授权失败和 release 包。
