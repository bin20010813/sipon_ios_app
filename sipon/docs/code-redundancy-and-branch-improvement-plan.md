# Sipon 冗余代码、分支差异与改进方案

审查日期：2026-10-17。项目目录：`sipon/`；Git 仓库根目录为其上一级。

## 1. 结论与审查边界

建议以当前 Android 花瓣地图分支为集成基线，先恢复可复现的测试基线，再收敛重复数据处理，最后分批吸收磨砂玻璃功能和拆分大文件。不要把所有历史分支直接合并，也不要按同名文件批量删除。

当前基线：`codex/migrate-android-petal-sdk @ 05e8f57`。本次完成分支历史/文件差异分析、源码重复片段扫描、资源内容哈希检查、静态分析及现有测试运行；未修改业务代码、切换分支或执行合并。本报告为实施方案，不代表已完成改造。

限制与口径：

- `git fetch origin --prune` 因连接重置失败。远端分支数据来自本地缓存，不能视为服务器最新状态；实施前必须重新刷新。
- 分支提交数按整个 Git 仓库计算；差异文件数限定 `sipon/`，为两端快照差异，不能解读为待合并文件数。
- 源码检查和测试针对工作区，包含未提交及被忽略的本地测试；分支矩阵仅针对已提交快照。
- 检查过程中工作区继续发生变化，例如新增贴纸运动测试、修改鸿蒙构建脚本，说明这不是冻结快照。实施前应记录最终提交和工作区差异，重新验证。
- 未执行 iOS、Android、HarmonyOS 完整打包或真机回归；静态/模拟测试不能证明原生地图与传感器实际表现。
- 重复扫描以连续 12 行去首尾空白片段作为线索，结合人工阅读确认；不是完整 AST 死代码分析，也未测得可靠的包体节省值。

## 2. 分支差异全景

“当前独有 / 对方独有”来自 `git rev-list --left-right --count HEAD...分支`。

| 分支 | 提交 | 当前独有 / 对方独有 | 差异文件数 | 处理建议 |
|---|---|---:|---:|---|
| codex/migrate-android-petal-sdk | 05e8f57 | 0 / 0 | 0 | 当前集成候选基线 |
| codex/integrate-three-platforms-gcj02 | 40c7b6c | 2 / 0 | 52 | 已被当前历史包含；其 origin 引用相同 |
| codex/sipon-frosted-glass | 2df505f | 5 / 4 | 129 | 存在独有功能，分批移植 |
| feat/android-tianditu | b670b65 | 11 / 0 | 147 | 已包含；origin 同提交，作为历史参考 |
| feat/harmonyos-petal-map | f8ece48 | 17 / 0 | 149 | 已包含，且比缓存远端多 1 个提交 |
| feat/liquid-glass | a9659f3 | 106 / 3 | 312 | 早期 UI 实验，逐项评估，不整体覆盖 |
| feat/mapkit-map | b579a1e | 47 / 0 | 296 | 本地旧分支已包含 |
| integration/three-platforms | d315e6f | 7 / 0 | 99 | 已包含，可作为整合里程碑 |
| main | 18cf701 | 196 / 0 | 319 | 主干明显落后；origin/main 同提交 |
| refactor/component-organization | 82d8bb0 | 42 / 0 | 259 | 已包含；origin 同提交 |
| origin/feat/dark-mode-liquid-glass | d7dd9e6 | 116 / 0 | 315 | 已包含，无独有提交 |
| origin/feat/harmonyos-petal-map | 5b32c77 | 18 / 0 | 172 | 已包含，晚于本地刷新仍需重核 |
| origin/feat/mapkit-map | 1fafe3a | 35 / 0 | 303 | 比本地同名分支更新，但也已包含 |
| origin/mapkit-map-zjb | fd8faf1 | 194 / 0 | 321 | 已包含，无需重复合入 |

“已包含”指提交可达，不等于该分支所有旧行为都应恢复；后续迁移可能有意替换过旧实现。

### 2.1 磨砂玻璃分支：真正需要评审的四个提交

与当前分支共同祖先为 `9377877`。`git log --left-right --cherry-mark` 未标记补丁等价提交。

| 提交 | 内容 | 建议 |
|---|---|---|
| 45c2ce7 | 公共磨砂材质与无障碍降级 | 优先评审基础层：材质主题、surface、glass policy、accessibility scope |
| 2b4f1f1 | 多页面统一材质 | 按首页、地图、个人页分批适配；保留当前功能行为 |
| e4d5994 | 鸿蒙 debug 包 JIT kernel 校验 | 独立评审构建修复，与当前未提交脚本变化对照 |
| 2df505f | 实施及验证文档 | 在功能实际接入并重新验证后更新，不直接沿用旧验收结论 |

重点重叠文件包括 `app/widgets/shell_components.dart`、`home_top_and_prompts.dart`、`drink_record_page.dart`、动态信息流和主题文件。当前未提交修改也触及这些位置，应先稳定工作区。

两端完整快照还显示旧天地图控制器与新花瓣控制器的差别：这属于各分支演进差异，不是磨砂玻璃功能必须带入的依赖。应审查共同祖先到功能提交的补丁，不能把旧分支整目录复制到当前分支。

### 2.2 早期液态玻璃分支：三项独有工作

- `a68eb18`：组件迁移收尾、深色模式适配。
- `8410c17`：iOS 26 液态玻璃 PoC，包含依赖与锁文件变更。
- `a9659f3`：共享玻璃图层和菜单弹层，使用旧 `lib/pages/` 结构。

该分支与当前结构差异很大，建议作为设计与实验参考。若采用磨砂玻璃公共层，应明确唯一材质策略，避免同时引入两套 Glass API；只有当前实现缺失且产品仍需要的行为才重做或移植。独有测试也需迁移到现行目录与接口。

### 2.3 推荐分支收敛流程

1. 刷新远端，记录最终 SHA；将现有修改按贴纸运动、地图、导航通知、图片缓存、构建脚本等主题整理成可复现提交。
2. 从确认后的当前基线创建短期集成分支，例如 `codex/consolidate-quality-baseline`；先修复测试与忽略规则。
3. 独立处理鸿蒙构建校验，再引入磨砂公共层，再按页面迁移 UI。每批一个可回退提交/PR。
4. 完成三端验收后通过 PR 更新 main，使 main 成为实际发布主线；不要继续让平台分支承担长期主干职责。
5. 对已包含的旧分支先标记归档候选、保留里程碑引用，再按团队流程删除。存在独有提交的两条 UI 分支须先完成取舍记录。
6. `git worktree list` 显示磨砂分支仍关联 worktree，液态玻璃 worktree 标记 prunable。清理前核对所有者和未提交文件；本次未删除任何 worktree。

## 3. 冗余与维护性问题清单

### R1 · P1：图片上传协议处理散落在五个页面【已确认】

证据：`review_page.dart:229/240`、`check_in_page.dart:849/860`、`profile_edit_page.dart:199/234`、`add_venue_page.dart:420/430`、`venue_contribution_page.dart:191/201` 分别存在 `_extractMediaId`、`_mimeTypeFor`；前三处 MIME 处理有相同连续片段。

风险：后端上传返回结构、HEIC/PNG 支持或 MIME 规则改变时，各页面容易出现不一致。

方案：建立 `shared/services/media_upload_service.dart` 和明确的上传结果类型。集中维护 MIME 推断、mediaId 提取与失败结果；先保留现有各解析分支，统一契约后再收紧。页面继续负责选择图片、进度、取消、表单状态，不把所有 UI 流程强行合并。

验收：五个入口使用同一协议处理；覆盖顶层/嵌套 mediaId、数字与字符串 ID、缺失 ID、未知扩展名、上传失败及页面销毁场景；成功结果与改造前一致。

### R2 · P1：酒吧/路线字段兼容解析重复【已确认】

证据：`public_profile_page.dart:1552`、`profile_lists.dart:152`、`route_detail_map_page.dart:119` 存在相同 `_pickCoordinate`；前两处还重复媒体和嵌套酒吧数据处理。

方案：将基础字段读取集中到解析工具，将酒吧、打卡、路线站点分别映射为带类型模型；优先级规则写进对应 mapper，不能只做一个万能 Map 工具。特别保留 `profile_lists.dart:227` 附近关于打卡 ID 不能当酒吧 ID 的处理。

验收：同一 payload 在个人主页、公开主页、路线页解析一致；覆盖嵌套 bar/barInfo、缺失坐标、0 值、数字字符串、不同 ID 域及媒体字段兼容。坐标转换仍由既有 GCJ-02 边界负责，字段解析不重复转换。

### R3 · P1：两条 API 访问路径职责重叠【结构事实，需契约核对】

`SiponApiService` 与 `SiponDataRepository` 均直接使用 `SiponApiClient`，且都涉及 `/api/bars`、`/api/bars/nearby`、`/api/bars/map`。后者包含类型化解析及过滤，前者偏动态返回，因此不能简单删掉任意一层。

方案：明确 `ApiClient（传输/鉴权）→ 领域 API（端点/DTO）→ Repository（缓存/业务映射）→ 页面`。先收敛 Bars 领域，保留旧 facade 委托新实现，再逐调用点迁移；不要一次重写全部接口。

验收：每个端点的参数、超时和错误转换只有一个主要实现；迁移前后请求次数、参数和过滤结果保持一致，防止新增双重请求。

### R4 · P1：大文件与 part 文件耦合【已确认】

工作区统计：`lib/` 共 114 个 Dart 文件（含本地文件，非仅跟踪文件）。重点热点：

| 文件 | 行数 | 推荐拆分边界 |
|---|---:|---|
| map/widgets/venue_detail_view.dart | 2992 | 数据/互动状态、营业信息、媒体画廊、评价区 |
| profile/pages/settings_support_page.dart | 2359 | 设置首页、账户安全、帮助反馈、协议展示 |
| ios/Runner/SiponMap/SiponMapView.swift | 2007 | 通道分派、相机、标注、路线绘制 |
| drinks/records/pages/drink_record_page.dart | 1673 | 表单状态、位置选择、图片贴纸、提交 |
| profile/pages/public_profile_page.dart | 1658 | 资料加载、关注行为、内容列表与解析 |
| profile/widgets/profile_lists.dart | 1625 | 条目映射、卡片、分页列表 |
| profile/widgets/budget_bill.dart | 1340 | 账单状态、日期筛选、行组件 |

路径省略部分均在 `lib/features/` 下，Swift 除外。行数表示维护成本线索，不代表其中都是冗余。

首页/个人页多个 widget 文件使用 `part of`，仍共享宿主 library 私有状态。建议先抽纯函数和无状态组件，再用显式参数/回调隔离状态。避免只移动代码却保持隐式依赖。以职责清晰为标准，可将超过 800 行作为审查提醒而非强制门禁。

### R5 · P2：四个兼容导出文件【不是重复实现】

`lib/pages/home_page.dart`、`lib/pages/profile_page.dart`、`lib/widgets/home_moments_section.dart`、`lib/features/map/pages/moments_page.dart` 均为两行兼容 export。

当前 lib 引用主要已使用新路径。删除前仍要扫描跟踪文件、本地测试和待整合分支中的 package/相对 import。清理收益较小，应放在分支迁移完成后；不能把它们计入“大量冗余页面”。

### R6 · P2：Mock 数据策略不一致【已确认】

动态页的 Mock 受 `kDebugMode && SIPON_MOCK_MOMENTS` 控制；酒吧详情 API 则在非数字 ID 时默认退回 Mock（`api_venue_detail_repository.dart:68`），`VenueDetailView` 未注入仓库时也默认 Mock。

建议在应用装配层明确数据模式。正式环境遇到非法/缺失 ID 展示错误或空态，演示环境显式注入 Mock；若产品确实要求展示演示酒吧，应清晰标识来源。不要把所有 Mock 删除：保留为测试与演示数据。`_MockListCard` 之类名称本身也不能证明卡片未使用，应按实际数据源重命名。

### R7 · P2：资源、模板与已停用依赖候选【部分确认】

- `sip_on_1/` 含 SwiftUI/SwiftData 默认 Item 示例，与 `ios/Runner` 并存。候选归档对象，先确认是否仍有独立交付用途。
- `assest/首页/图片素材_原始备份/` 与导出倍率/SVG 素材需要区分设计源、运行资源；按 pubspec、原生引用、脚本引用和动态路径联合核对，不依据文件名删除。
- 哈希相同项主要是平台图标及 Android v31 日/夜 styles。平台目录通常有各自资源要求，不能据此直接删文件。建议维护单一源图和生成脚本，而保留需要打包的各平台产物。
- `assest/` 拼写可在单独 PR 改为 `assets/`，同步 pubspec、代码、脚本及大小写敏感构建验证；与业务改造分开。
- 主 pubspec 已注释虚拟饮酒音频/WebView 依赖，鸿蒙的 `dependencies.yaml`、`plugins.lock.json`、`pubspec_overrides.yaml` 仍有相关插件条目。先核对生成脚本与最终依赖图，再决定条件化或移除，不能仅凭声明断言包内仍含插件。
- 不要随意解除 `path_provider_foundation: 2.5.1` 固定：README 已记录现有 iOS 兼容性理由，需有验证证据才能调整。

验收：干净克隆可构建；资源清单无丢失；对比 release 包资产和大小后才报告节省值。

### R8 · P2：地图控制器存在相似生命周期，但有平台差异【抽象候选】

`MapkitSceneController` 与 `PetalAndroidSceneController` 都处理 host、ready、attach/detach、视野去抖和资源注册，但 ready 超时、路由及样式恢复行为不同。

保留已有 `MapSceneController`、`SiponMapHost`、协议编码与 `BusinessCoordinates`。可以抽出附件代次/取消、去抖等纯机制；不要统一为一个充满平台判断的控制器。先补生命周期契约测试，再判断抽取是否实际减少复杂度。

`SiponNetworkImage` 与 `CocktailImageCache` 也不能因为都加载图片而直接合并：后者有预取、尺寸与命名空间隔离需求。共享 URL/鉴权策略即可，缓存生命周期仍可分开。

## 4. 优先解决的质量基线

### Q1 · P0：测试未全部进入版本控制

`sipon/.gitignore:75-80` 包含 `test` 和 `/test/*`，只显式放行两个文件；已经跟踪的文件不受后续忽略规则影响，因此实际 Git 中仍有 5 个 Dart 测试，而本地有 11 个。

本地额外 6 个：`add_venue_page_test.dart`、`cocktail_detail_layout_test.dart`、`cocktail_image_preload_test.dart`、`drink_record_place_picker_test.dart`、`recipe_ingredient_animation_test.dart`、`sipon_api_client_debug_test.dart`。`git check-ignore -v` 已确认布局/动画测试被 `/test/*` 忽略。

处理：移除泛化的测试目录忽略规则，仅忽略输出/临时文件；逐一审查并修复值得保留的测试后纳入版本控制。不要盲目强制添加旧断言。统一执行 `test/` 和 `tool/tests/`，避免普通 `flutter test` 遗漏后者。

验收：全新检出的测试文件和执行数量与开发机一致；没有仅存在本机的关键回归测试。

### Q2 · P0：现有测试失败属于需求/断言不一致

`flutter test --no-pub`：68 通过、2 失败，均在本地被忽略的 `add_venue_page_test.dart`：

1. 期待“酒馆名称（可选）”，实际没有该文本。
2. 期待空名称通过验证，实际被 `formValidation` 拦截。

实现 `add_venue_page.dart:492-494` 明确要求酒馆名称。应先确认当前需求：若必填是正确行为，更新旧测试验证空值被拒绝；若应可选，才调整实现及接口约束。不要为变绿而取消校验。

### Q3 · P1：分析问题与自动化入口

`flutter analyze --no-pub` 退出码 1，共 4 项，未报告 error：

| 等级 | 位置 | 内容/处理 |
|---|---|---|
| info | route_planning_page.dart:549 | onReorder 已弃用；迁移时验证索引语义，不能只替换名称 |
| warning | test/cocktail_detail_layout_test.dart:23 | 测试替身 override 不再匹配接口；核对是否仍拦截真实调用 |
| warning | test/recipe_ingredient_animation_test.dart:46 | 同上 |
| info | tool/tests/petal_android_map_test.dart:33 | if 添加花括号 |

未在已跟踪 YAML 中发现 GitHub/GitLab pipeline 配置；不排除外部 CI。建议将静态分析、两组 Flutter 测试、Node 测试及平台构建接入统一流水线，并明确上游 Flutter 与 Flutter OH 两套 SDK 的固定版本。

### Q4 · P1：地图聚合契约待核实

`sipon_data_repository.dart:17-37` 明确过滤 `cluster == true`，且保留 TODO 等待接口验证。这不是已复现故障，但服务端若在低 zoom 返回聚合点，列表可能丢失展示内容。

先采集不同 zoom 的真实响应并固化脱敏 fixture；若返回聚合点，新增聚合模型与点击放大行为；若始终返回普通点，记录并测试服务端契约。不要将聚合 ID 作为酒吧 ID。

## 5. 本次验证结果

| 检查 | 结果 | 解释 |
|---|---|---|
| Flutter 静态分析 | 2 warning + 2 info | 退出码 1，问题见 Q3 |
| 默认 Flutter 测试 | 68 通过 / 2 失败 | 含本地忽略文件，非干净克隆基线 |
| tool/tests 下三个 Dart 测试文件 | 21 通过 | 坐标边界、Android/Harmony 地图协议和生命周期 |
| tool/tests 下四个 Node 测试文件 | 31 通过 | 含本次审查期间出现的未跟踪 sticker_motion_test.cjs |
| 分支远端刷新 | 失败 | GitHub 连接重置，使用缓存 refs |
| 原生打包/真机验收 | 未执行 | 需要对应 SDK、macOS/iOS 与三端设备 |

Node 首次使用通配符作为参数未被展开，已改为 PowerShell 枚举文件后重跑并通过。测试结果均为工作区当时状态，不作为任何已发布版本的质量声明。

## 6. 分阶段实施与交付

工期是单人熟悉代码情况下的粗估，不含设备排期、后端契约修改及需求等待。

| 阶段 | 建议工作量 | 交付内容 | 依赖/完成条件 |
|---|---:|---|---|
| A：冻结并修复基线 | 1–2 人日 | 最终 SHA、测试纳管、失败断言裁定、分析清零、统一测试入口 | 先整理现有未提交变化；干净克隆可复现 |
| B：收敛重复处理 | 2–4 人日 | 上传协议服务、类型化解析/mapper、Bars API 渐进统一 | A 完成；兼容输入与错误场景回归通过 |
| C：吸收有价值分支 | 3–5 人日 | 鸿蒙构建修复、材质公共层、按页迁移、旧 UI 分支取舍记录 | A 完成；与 B 错开共同页面修改 |
| D：拆分热点文件 | 4–6 人日 | 酒吧详情、设置页、个人列表等职责分离 | B/C 相关页面稳定后实施；视觉和行为保持 |
| E：资源与主干治理 | 1–2 人日 | 模板归档、资源清单、依赖核对、main 更新 PR、旧分支归档清单 | 三端构建及回归完成；保留回退点 |

总量约 11–19 人日；若只推进首轮高收益工作，先完成 A+B。无需为抽象而全面替换状态管理方案或重写原生地图。

建议 PR 边界：①测试基线；②上传协议；③酒吧/路线 mapper；④Bars 访问层；⑤鸿蒙构建校验；⑥材质公共层与无障碍；⑦各页面适配；⑧热点拆分；⑨资源和文档清理。出现重叠时串行整合，避免多个 PR 同时重写大页面。

## 7. 验收与回退

发布前必须完成：

- 干净克隆静态分析、全部 Flutter/Node 测试通过；新增测试不被忽略。
- iOS/Android/HarmonyOS 各完成 debug 与 release 构建；鸿蒙使用对应 SDK 验证实际包内容。
- 地图：城市切换、定位拒绝与恢复、GCJ-02 一次转换、路线方向、标注碰撞、半屏/全屏拖动、失败重试、旧视图回调失效。
- 图片/贴纸：五个上传入口、HEIC/JPEG/PNG、失败重试、退出页面、缓存清理、离线抠图、前后台与旋转后的传感器订阅释放。
- UI：明暗模式、减少动态效果/透明度降级、大字体、键盘遮挡、动态页与底栏、通知跳转。
- 数据：打卡/酒吧 ID 分离、空态/错误态、分页无重复、正式数据源无意外 Mock 回退、聚合契约明确。

每项提交记录行为基线和回归结果；通过 revert 独立 PR 回退，不用重置共享分支。材质策略可保留单一配置切换用于渐进启用；避免长期维护两套页面。资源删除另起提交，保留源文件历史；mapper 迁移期间保留 facade，全部调用迁移后再删除旧入口。

量化目标：五处上传协议收敛到一处；三处坐标字段解析统一基础规则；6 个本地测试逐项处置；当前 4 项分析问题清零；两条有独有提交的 UI 分支完成去留记录。文件行数和包体优化只在改造后实测报告，不预先承诺百分比。

## 8. 可复核命令

在 `sipon/` 下运行；分支命令需要刷新后的 refs，并保存执行时 SHA。

```powershell
git status --short --untracked-files=all
git rev-parse HEAD
git for-each-ref --format='%(refname:short)|%(objectname:short)' refs/heads refs/remotes/origin
git rev-list --left-right --count HEAD...codex/sipon-frosted-glass
git log --left-right --cherry-mark --oneline HEAD...codex/sipon-frosted-glass
git diff --name-only HEAD codex/sipon-frosted-glass -- .
git diff 9377877 codex/sipon-frosted-glass -- lib tool docs
git ls-files test tool/tests
git check-ignore -v test/cocktail_detail_layout_test.dart
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub tool/tests/business_coordinates_test.dart tool/tests/harmony_map_test.dart tool/tests/petal_android_map_test.dart
$siponTestFiles = @(Get-ChildItem tool/tests/*.cjs | ForEach-Object FullName)
node --test @siponTestFiles
```

全新克隆需要先按项目文档准备 SDK 和依赖，再使用 `--no-pub`。本报告行号和统计均可能随正在进行的工作变化，定位以符号名和记录的基线共同确认。
