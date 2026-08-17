# Windows Server 2022 云服务器部署指南

本文档针对你的云服务器系统：

```text
Windows Server 2022 DataCenter 64bit CN
```

服务器类型：

```text
腾讯云轻量应用服务器 Lighthouse
```

目标：

- 把当前 `sip-data-api` 后端部署到 Windows Server。
- 把本地酒吧数据迁移到云服务器 PostgreSQL + PostGIS。
- 开放开发端口给 Flutter iOS App 调用。

## 1. 推荐方案

推荐使用“原生 Windows 部署”：

```text
Flutter iOS App
      |
      | http://106.53.119.216:8081
      v
Windows Server 2022
      |
      | Java 11 runs sip-data-api jar
      v
PostgreSQL + PostGIS Windows service
```

原因：

- 当前后端本身是 Java jar，Windows Server 可以直接运行。
- PostgreSQL 和 PostGIS 有 Windows 安装包。
- 不需要处理 Windows Server 上 Linux Docker 容器、WSL2 网络转发、端口代理这些额外问题。
- 数据库端口 `5432` 可以只留在服务器本机，App 只访问 API 端口 `8081`。

不建议在 Windows Server 上直接照 Linux Docker Compose 方案跑，因为项目依赖 `postgis/postgis` Linux 镜像。Windows Server 原生 Docker 面向 Windows 容器；Linux 容器需要额外虚拟化或 WSL2 网络配置，部署复杂度明显更高。

## 2. 查看公网 IP 和开放端口

### 2.1 查看轻量应用服务器公网 IP

腾讯云控制台入口：

```text
腾讯云控制台 -> 轻量应用服务器 Lighthouse -> 服务器
```

进入你的 Windows Server 实例详情，在实例基础信息中查看：

```text
公网 IP：106.53.119.216
```

注意：

- 轻量应用服务器不是从 `云服务器 CVM -> 实例` 里看。
- Windows 服务器里执行 `ipconfig` 通常只能看到内网 IP，公网 IP 需要在腾讯云轻量应用服务器控制台查看。

### 2.2 开放轻量应用服务器防火墙端口

轻量应用服务器使用自己的防火墙规则，作用类似 CVM 安全组。不要去 CVM 安全组里配置。

腾讯云控制台入口：

```text
腾讯云控制台 -> 轻量应用服务器 Lighthouse -> 服务器 -> 你的实例 -> 防火墙
```

需要放行：

| 端口 | 是否开放 | 说明 |
|---:|---:|---|
| `3389` | 是 | Windows 远程桌面 RDP，建议只允许你的 IP |
| `8081` | 开发阶段开放 | Flutter iOS App 调用 API |
| `80` | 可选 | 后续配置 HTTPS 证书时使用 |
| `443` | 推荐 | 生产或稳定测试使用 HTTPS |
| `5432` | 不开放 | PostgreSQL 不要暴露公网 |

添加开发 API 端口规则：

| 配置项 | 值 |
|---|---|
| 应用类型 | 自定义 |
| 协议 | TCP |
| 端口 | `8081` |
| 来源 | `0.0.0.0/0`，开发阶段可用；更安全做法是只填你的公网 IP |
| 策略 | 允许 |
| 备注 | `sip-data-api` |

Windows 防火墙也需要放行 `8081` 入站。

管理员 PowerShell 执行：

```powershell
New-NetFirewallRule `
  -DisplayName "sip-data-api 8081" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort 8081
```

## 3. 安装 Java 11

安装 Temurin/OpenJDK 11 x64。

安装后在 PowerShell 验证：

```powershell
java -version
```

预期能看到 Java 11，例如：

```text
openjdk version "11.x.x"
```

## 4. 安装 PostgreSQL + PostGIS

当前云服务器 PostgreSQL 安装路径：

```text
C:\Program Files\PostgreSQL\17
```

推荐安装：

- PostgreSQL 17 x64 Windows
- PostGIS 3.x for PostgreSQL 17

安装完成后，记住 PostgreSQL 的超级用户 `postgres` 密码。

打开 PostgreSQL 的 `psql`，或者在 PowerShell 中进入 PostgreSQL bin 目录后执行：

```powershell
& "C:\Program Files\PostgreSQL\17\bin\psql.exe" -U postgres
```

创建业务用户和数据库：

```sql
CREATE USER sip_data WITH PASSWORD '换成强数据库密码';
CREATE DATABASE sip_data OWNER sip_data;
\c sip_data
CREATE EXTENSION IF NOT EXISTS postgis;
SELECT postgis_version();
```

注意：

- `CREATE EXTENSION postgis` 必须成功。
- App 只连本机数据库，所以 PostgreSQL 不需要开放公网。

## 5. 上传后端项目或 jar

你的云服务器后端部署目录：

```text
C:\Program Files\sip-data-api
```

该目录位于 `Program Files` 下，需要用管理员 PowerShell 创建和写入：

```powershell
New-Item -ItemType Directory -Force -Path "C:\Program Files\sip-data-api"
New-Item -ItemType Directory -Force -Path "C:\Program Files\sip-data-api\data"
```

### 方式 A：本地打包后上传 jar

在你本机项目目录执行：

```powershell
cd D:\code\sip-data-api
.\mvnw.cmd test
.\mvnw.cmd package
```

上传这个文件到服务器：

```text
D:\code\sip-data-api\target\sip-data-api-0.1.0-SNAPSHOT.jar
```

放到服务器：

```text
C:\Program Files\sip-data-api\sip-data-api-0.1.0-SNAPSHOT.jar
```

同时上传这些文件：

```text
.env.windows.example
scripts\windows\start-api.ps1
scripts\windows\install-startup-task.ps1
```

建议保持服务器目录结构：

```text
C:\Program Files\sip-data-api
  ├─ sip-data-api-0.1.0-SNAPSHOT.jar
  ├─ .env.windows
  ├─ data\
  └─ scripts\
     └─ windows\
        ├─ start-api.ps1
        └─ install-startup-task.ps1
```

### 方式 B：服务器上拉代码并打包

如果服务器安装了 Git，可以直接：

```powershell
cd "C:\Program Files"
git clone <your-repo-url> sip-data-api
cd "C:\Program Files\sip-data-api"
.\mvnw.cmd test
.\mvnw.cmd package
Copy-Item .\target\sip-data-api-0.1.0-SNAPSHOT.jar .\sip-data-api-0.1.0-SNAPSHOT.jar -Force
```

## 6. 配置环境变量

在服务器：

```powershell
cd "C:\Program Files\sip-data-api"
Copy-Item .env.windows.example .env.windows
notepad .env.windows
```

修改为你的真实值：

```env
SERVER_PORT=8081

DB_HOST=localhost
DB_PORT=5432
DB_NAME=sip_data
DB_USER=sip_data
DB_PASSWORD=你的数据库密码

APP_ADMIN_TOKEN=换成强随机管理员Token
APP_AUTH_TOKEN_SECRET=换成强随机JWT密钥
APP_AUTH_TOKEN_ISSUER=sip-data-api
APP_AUTH_TOKEN_EXPIRATION_MINUTES=10080
APP_CORS_ALLOWED_ORIGIN=*

GEOJSON_PATH=C:\Program Files\sip-data-api\data\bar_basic_info_all_cities.geojson
IMPORT_ON_STARTUP=false
```

生成随机密钥可以在 PowerShell 中执行：

```powershell
[System.Guid]::NewGuid().ToString("N") + [System.Guid]::NewGuid().ToString("N")
```

说明：

- `APP_ADMIN_TOKEN` 用于导入数据和刷新地图预计算。
- `APP_AUTH_TOKEN_SECRET` 用于签发和验证 App 登录 Token。
- 云端换了 `APP_AUTH_TOKEN_SECRET` 后，本地旧 Token 不能继续用，App 重新登录即可。

## 7. 启动后端

先手动启动一次，确认没有报错：

```powershell
cd "C:\Program Files\sip-data-api"
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\start-api.ps1 -AppDir "C:\Program Files\sip-data-api"
```

看到 Spring Boot 启动完成后，另开一个 PowerShell 测试：

```powershell
Invoke-RestMethod http://127.0.0.1:8081/api/health
```

预期：

```json
{
  "status": "ok",
  "service": "sip-data-api",
  "time": "2026-07-19T05:00:00Z"
}
```

从你本机或 Apifox 测试：

```http
GET http://106.53.119.216:8081/api/health
```

如果服务器本机能访问，但外部访问不了，检查：

- 腾讯云轻量应用服务器防火墙是否开放 `8081`。
- Windows 防火墙是否开放 `8081`。
- 后端是否真的监听在 `8081`。

## 8. 设置开机自启动

用管理员 PowerShell 执行：

```powershell
cd "C:\Program Files\sip-data-api"
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\install-startup-task.ps1 -AppDir "C:\Program Files\sip-data-api"
```

查看任务：

```powershell
Get-ScheduledTask -TaskName sip-data-api
```

重启后检查：

```powershell
Invoke-RestMethod http://127.0.0.1:8081/api/health
```

如果要停止：

```powershell
Stop-ScheduledTask -TaskName sip-data-api
```

如果要删除开机任务：

```powershell
Unregister-ScheduledTask -TaskName sip-data-api -Confirm:$false
```

## 9. 迁移数据

### 方式 A：上传 GeoJSON 重新导入

适合：

- 只迁移酒吧数据。
- 用户账号可以重新注册。
- 你有原始 `bar_basic_info_all_cities.geojson` 文件。

上传 GeoJSON 到服务器：

```text
C:\Program Files\sip-data-api\data\bar_basic_info_all_cities.geojson
```

确认 `.env.windows`：

```env
GEOJSON_PATH=C:\Program Files\sip-data-api\data\bar_basic_info_all_cities.geojson
```

调用导入接口：

```powershell
Invoke-RestMethod `
  -Method Post `
  -Uri "http://127.0.0.1:8081/api/admin/import/bars" `
  -Headers @{ "X-Admin-Token" = "<你的APP_ADMIN_TOKEN>" }
```

导入成功会自动刷新地图预计算数据。响应类似：

```json
{
  "sourcePath": "C:\\Program Files\\sip-data-api\\data\\bar_basic_info_all_cities.geojson",
  "totalFeatures": 12000,
  "imported": 12000,
  "skipped": 0,
  "durationMillis": 26000
}
```

### 方式 B：完整迁移本地数据库

适合：

- 需要保留本地已注册用户。
- 需要完整迁移所有表和数据。
- 当前本地 PostgreSQL 就是真实数据源。

如果本地 PostgreSQL 是 Docker 容器，先在本机导出：

```powershell
docker exec sip-data-postgres pg_dump -U sip_data -d sip_data -Fc -f /tmp/sip_data.dump
docker cp sip-data-postgres:/tmp/sip_data.dump D:\code\sip-data-api\sip_data.dump
```

上传 `sip_data.dump` 到服务器：

```text
C:\Program Files\sip-data-api\sip_data.dump
```

在服务器恢复：

```powershell
& "C:\Program Files\PostgreSQL\17\bin\pg_restore.exe" `
  -U sip_data `
  -d sip_data `
  --clean `
  --if-exists `
  --no-owner `
  "C:\Program Files\sip-data-api\sip_data.dump"
```

恢复后刷新地图预计算：

```powershell
Invoke-RestMethod `
  -Method Post `
  -Uri "http://127.0.0.1:8081/api/admin/map/clusters/refresh" `
  -Headers @{ "X-Admin-Token" = "<你的APP_ADMIN_TOKEN>" }
```

然后重启后端：

```powershell
Stop-ScheduledTask -TaskName sip-data-api
Start-ScheduledTask -TaskName sip-data-api
```

如果你还没有设置开机任务，就关闭手动启动的后端窗口，然后重新执行启动命令。

## 10. Apifox 云端测试

环境变量：

| 变量 | 示例 |
|---|---|
| `baseUrl` | `http://106.53.119.216:8081` |
| `accessToken` | 登录后保存 |
| `adminToken` | `.env.windows` 中的 `APP_ADMIN_TOKEN` |

健康检查：

```http
GET {{baseUrl}}/api/health
```

登录：

```http
POST {{baseUrl}}/api/auth/login
Content-Type: application/json
Accept: application/json

{
  "username": "apifox_user",
  "password": "password123"
}
```

后置脚本保存 Token：

```javascript
const json = pm.response.json();
pm.environment.set("accessToken", json.accessToken);
```

地图接口：

```http
GET {{baseUrl}}/api/bars/map?west=73&south=18&east=135&north=54&zoom=5
Authorization: Bearer {{accessToken}}
Accept: application/json
```

预期：

- HTTP `200`
- `mode = "bars"`
- `items[].cluster = false`
- `items[].count = 1`
- `items[].id` 是真实酒吧 ID
- `zoom=5` 最多返回 50 条

## 11. Flutter iOS App 调用

开发阶段先用：

```dart
const baseUrl = 'http://106.53.119.216:8081';
```

地图接口只传：

```dart
queryParameters: {
  'west': west,
  'south': south,
  'east': east,
  'north': north,
  'zoom': zoom.clamp(0, 22),
}
```

不要传 `limit`。后端会按 `zoom` 自动决定返回数量。

登录后保存 Token，请求时带：

```http
Authorization: Bearer <accessToken>
```

## 12. iOS HTTP 与 HTTPS

如果 Flutter iOS 真机访问公网 HTTP：

```text
http://106.53.119.216:8081
```

iOS 可能被 ATS 拦截。Debug 阶段可以临时在 `ios/Runner/Info.plist` 加：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

这只适合开发。生产包不要这样配置。

长期测试和生产建议：

- 绑定域名，例如 `api.example.com`。
- 云服务器开放 `80/443`。
- 用 IIS ARR、Nginx for Windows，或者换 Linux 反向代理配置 HTTPS。
- Flutter 使用 `https://api.example.com`。

如果只是你自己开发联调，先用 `http://公网IP:8081` 跑通接口更快。

## 13. 常见问题

### 13.1 服务器本机能访问，手机访问不了

检查：

- 腾讯云轻量应用服务器防火墙是否开放 `8081`。
- Windows 防火墙是否开放 `8081`。
- Flutter baseUrl 是否写成公网 IP，而不是 `localhost`。
- App 是否被 iOS ATS 拦截 HTTP。

### 13.2 登录成功，但地图接口 401

检查：

- 请求头是不是 `Authorization: Bearer <accessToken>`。
- `Bearer` 后面有一个空格。
- App 是否保存了旧环境的 Token。云端换了 `APP_AUTH_TOKEN_SECRET` 后，需要重新登录。

### 13.3 地图接口没有数据

检查：

```powershell
& "C:\Program Files\PostgreSQL\17\bin\psql.exe" `
  -U sip_data `
  -d sip_data `
  -c "SELECT COUNT(*) FROM bars;"
```

如果 `bars` 是 0，说明还没导入或恢复数据。

再检查预计算表：

```powershell
& "C:\Program Files\PostgreSQL\17\bin\psql.exe" `
  -U sip_data `
  -d sip_data `
  -c "SELECT COUNT(*) FROM bar_map_clusters;"
```

如果低层级地图没数据，调用刷新：

```powershell
Invoke-RestMethod `
  -Method Post `
  -Uri "http://127.0.0.1:8081/api/admin/map/clusters/refresh" `
  -Headers @{ "X-Admin-Token" = "<你的APP_ADMIN_TOKEN>" }
```

### 13.4 8081 被占用

查看占用：

```powershell
netstat -ano | findstr :8081
```

如果需要换端口，改 `.env.windows`：

```env
SERVER_PORT=8082
```

然后 Windows 防火墙和腾讯云轻量应用服务器防火墙也要开放新端口，Flutter `baseUrl` 同步改成新端口。

## 14. 上线检查清单

| 检查项 | 预期 |
|---|---|
| Java | `java -version` 是 11 |
| PostGIS | `SELECT postgis_version();` 成功 |
| 数据库 | `bars` 表有数据 |
| API | `http://127.0.0.1:8081/api/health` 正常 |
| 公网 | `http://106.53.119.216:8081/api/health` 正常 |
| 轻量服务器防火墙 | `8081` 已开放，`5432` 未开放 |
| Token | 登录后可以访问 `/api/auth/me` |
| 地图 | `/api/bars/map?west=73&south=18&east=135&north=54&zoom=5` 返回具体酒吧 |
| Flutter | baseUrl 使用公网 IP 或 HTTPS 域名，不使用 `localhost` |
| iOS | Debug HTTP 已配置 ATS，生产使用 HTTPS |

Invoke-RestMethod `
  -Method Post `
  -Uri "http://127.0.0.1:8081/api/admin/import/bars" `
  -Headers @{ "X-Admin-Token" = "adf5a45fafd34b36946e163392910ad0123" }
