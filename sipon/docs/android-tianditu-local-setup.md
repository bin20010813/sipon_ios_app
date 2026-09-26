# Android 天地图初版：本地配置与联调

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

## 道路路线代理

Android 路线调用 Sipon 后端的拟议接口 `POST /api/map/routes/plan`。客户端发送 `requestId`、`crs: WGS84`、`mode: driving` 和有序的 `{lng, lat}` 站点；期望响应为 `crs: WGS84` 及每一对相邻站点对应的一段 `legs[].coordinates`，坐标格式 `[lng, lat]`。该接口不在本仓库内，部署和供应商密钥需要在后端完成。接口未部署或校验失败时，客户端明确提示路线失败，不会画直线冒充道路规划。

## 当前验证边界

WGS-84 与 CGCS2000 目前在 Android 地图边界采用 `approximate-identity-v1` 显示近似。它只用于首版联调；Android 新增地点提交默认关闭。按适配方案第 6.1 节使用可信同名点实测、达到业务精度门槛后，构建时传 `--dart-define=SIPON_ANDROID_COORDINATE_VERIFIED=true` 才可开放提交。正式发布前还需 Android 真机验证地图合成、无 GMS 定位、导航 App URI、授权失败和 release 包。
