# 序点

面向 Android 与 Windows 的模块化个人任务管理 App，使用 Flutter/Dart、Riverpod 和 Drift/SQLite。当前采用 v2 模块架构，已实现本地任务基础能力、声明式扩展与 AI 模块提案。

状态核对日期：2026-10-03。产品目标包含跨设备端到端加密同步和公开模块市场；当前仓库尚无服务端，相关能力仍待实现。

## 文档与目录

| 入口 | 内容 |
| --- | --- |
| [开发环境](DEVELOPMENT.md) | SDK、测试、Android 构建与临时 APK 分享 |
| [VPS 与 WSL 开发配置](docs/MULTI_MACHINE_DEVELOPMENT.md) | 源码同步、共享手机调试、端口与开发签名 |
| [客户端说明](client/README.md) | 代码入口、数据流和当前实现边界 |
| [目标与交接](PROJECT_HANDOFF.md) | 已确认产品选择、当前状态和后续交接 |
| [设计方案](docs/DESIGN.md) | 架构、同步/加密设计与验收目标 |
| [界面设计系统](docs/UI_DESIGN_SYSTEM.md) | 视觉规则及模块/AI 页面约束 |

```text
client/             Flutter 客户端、Android/Windows 工程与测试
packages/schemas/   声明式模块和模块包的 JSON Schema
docs/               架构与界面设计
scripts/            开发环境、APK 本地服务与临时分享
assets/brand/       品牌图标源文件与生成工具
```

`.tools/` 与 `.cache/` 存放本机 SDK 和缓存。未来云端拟采用 TypeScript/Fastify + PostgreSQL，尚未创建 `server/` 工程。

## 快速开始

使用当前 Linux 工作区已配置的 SDK，从项目根目录运行：

```bash
source scripts/dev-env.sh
cd client
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --split-per-abi --no-pub
```

APK 输出到 `client/build/app/outputs/flutter-apk/`；多数 Android 手机使用 `app-arm64-v8a-release.apk`。当前 release 使用 debug 密钥签名，供侧载试用。Windows 需在 Windows 构建机上构建和验证，安装包流程尚未完成。首次环境配置和分享方法见 [开发环境](DEVELOPMENT.md)。

VPS 开发使用独立 HTTPS 链接下载调试 APK，在手机旁安装后，通过 ADB/VM Service 的 SSH 转发运行 `flutter attach`；保存 Dart 修改后按 `r` 热重载。预览脚本不经 SSH 传输 APK。配置见 [远程预览](DEVELOPMENT.md#通过-ssh-远程预览-android)，命令为 `bash scripts/preview-android.sh DEVICE_SERIAL`；2026-09-30 已在 PHY120 验证 attach 连接和无源码变更的热重载，耗时约 2.2 秒。

## 当前实现

### 模块与界面

- `ModuleManifest`、`AppModule`、`ModuleContext` 和可监听的 `ModuleRegistry` 组成基础运行时。注册表检查模块 ID、版本格式、依赖存在及所需 capability；使用候选副本验证后替换，失败时保留原注册状态。
- `requiresCapabilities` 表示运行环境需提供的能力，`permissions` 表示模块获准使用的权限。命令、查询和 UI 注册在各自边界校验权限。
- `UiSlot + UiRegistry` 定义固定插槽，当前主导航消费 `navigationPrimary`。其他插槽名称已定义，完整渲染接入仍需逐项实现。
- 默认主导航为“今天、收件箱、项目、模块”。窄屏使用底栏，宽屏使用侧栏；移动端超过四个导航项时提供“更多”。AI 保留模块身份，入口在顶部，宽屏可显示侧面板，窄屏显示浮层。
- “今天”和“收件箱”由内置声明式配置运行；“项目”复用通用任务列表。界面采用轻量标题、分组内容、统一连续圆角与悬浮底栏，任务列表显示数量与统一空状态。
- 移动底栏已整合快速输入与导航，支持毛玻璃悬浮、滑动选中胶囊、实心选中图标和按压/轻触反馈；列表末项可滚动至底栏上方，键盘弹出时保留输入并隐藏导航。
- 设置页面提供主题、减少动画、导航触感、AI 连接、模块管理和关于信息；偏好保存到本机并即时生效。AI 工作区与设置页共用独立连接配置页面。
- “模块管理”同时列出内置功能与扩展模块。项目、AI、今天和收件箱支持开关；关闭状态在启动时恢复，保留数据与配置。关闭当前页面会回退，AI 关闭时隐藏入口并取消待完成的请求与提案；模块管理和设置始终可用。
- 旧架构的 `TaskHome / TaskDetail / TaskEditor / TaskRepository` 已移除；当前任务编辑通过 CommandBus 接入。

### 本地任务与数据

- 任务领域拆为 `TaskCommandService`、`TaskQueryService`、`TaskStore`、`ChangeJournal` 和 `EventBus`。内置页面通过 Riverpod 接入查询，声明式模块通过受权 `QueryBus` 获取 DTO。
- 项目详情提供专属任务输入栏，自动写入当前 projectId；快速添加防重复提交，失败保留草稿，提交期间新输入的草稿不会被清空。点击任务可修改标题、优先级、计划日和截止日；窄屏使用底部详情面板，宽屏使用右侧模态编辑面板，支持清除日期、校验与保存失败重试。
- 当前任务命令为 `project.create`、`task.create`、`task.updateFields` 和 `task.setCompleted`；支持创建项目和任务、创建同项目子任务、更新标题/优先级/计划日/截止日、完成与重新打开。
- 任务写入经 `CommandBus` 检查 `tasks.write`；实体变更与日志在同一事务中提交，提交后发布领域事件，失败命令不留下部分任务或日志写入。
- `QueryBus` 检查 `tasks.read`，提供 `task.list / task.get / project.list`。`task.list` 支持带权限检查的订阅，将任务与激活字段合并为 DTO；规则通过 `task.get` 按 ID 查询快照，不向声明式模块暴露 Drift 实体。
- 数据库为新的 `xudian_v9.sqlite`，Drift `schemaVersion` 为 1，不迁移旧本地数据库。`ChangeOperations` 保存本机操作与未同步标记，尚无网络同步、因果合并或冲突处理。
- 标签、备注、归档和删除已有部分数据结构；对应完整命令与编辑流程仍待实现。当前列表主要呈现顶层任务，子任务管理、搜索、看板及完整任务详情尚未完成。

### 声明式扩展与生命周期

- 格式契约位于 [declarative-module-v1.schema.json](packages/schemas/declarative-module-v1.schema.json)。客户端使用手写 `DeclarativeModuleParser` 与运行时语义校验，拒绝未知顶层/manifest 字段、错误格式版本、非法 manifest、重复资源 ID 和不支持的资源能力；尚未接入通用 Schema 执行器，完整契约一致性仍待补齐。
- 当前可执行资源为 `pages / views / fields / templates / rules`。视图数据源为 `task.list`，页面由统一任务列表渲染；`layouts` 必须省略或为空，禁止任意样式和可执行代码。
- 通用过滤 AST 支持 `all / any / not`、比较、空值判断、列表 `contains` 与 `$today`。常用基础字段筛选下沉 SQLite；含自定义字段或暂不支持的表达式保留 Dart 筛选语义，声明式排序与分页尚未实现。项目列表在 SQL 中按项目筛选与排序。声明式页面订阅任务/字段/定义变化，午夜及应用恢复前台时重新计算日期条件，避免重复全量读取。
- `ModuleInstallations` 区分 installed/enabled 并保存当前来源；安装、启用、停用可即时更新导航，无需重启。启动按依赖顺序恢复模块，注册表拒绝循环依赖；真正恢复失败的动态模块会自动停用并保留数据，工作台显示原因和模块管理入口。
- `ModuleVersions` 保存不可变源码快照及版本来源（origin、publisher、package digest、review、signature key）。源码以 canonical JSON 比较；同一 ID + version 的源码和来源不可覆写。回退同步恢复配置与来源。
- `FieldDefinitions / FieldValues` 按模块命名空间保存自定义字段并校验值类型。编辑器支持文本、数字、布尔、单选、多选、日期和日期时间；写入经 `field.set / field.clear / field.setMany` 检查 `fields.write` 和字段归属，校验真实日期/时间、选项、重复多选值和有限数字。字段与日志同事务提交，成功后发布 `task.updated`；批量编辑失败全部回滚，无变化时不追加日志或事件。
- 字段停用或卸载后变为 inactive，任务 DTO 不再返回；重新启用/安装时恢复当前定义和保留值。视图 `showFields` 与 filter 支持本模块字段短名。
- “模块”页支持动态模块启停、版本历史、回退、卸载保留数据、重新安装和彻底删除。普通卸载保留版本、字段数据及规则日志。
- 页面支持 `quickAddDefaults`；例如“今天”快速添加会写入 `$today` 的 plannedDate。

### 规则与模板

- 规则引擎支持 `task.created / updated / completed / reopened` 和 `project.created`。条件通过 QueryBus 读取当前快照，动作只调用安全 Command 白名单。
- 自动化链携带 depth 与 rule trace，同一规则在一条链内至多执行一次，默认最大深度为 8。运行记录保存 `triggered / skipped / success / failure`，失败信息截断保存，不阻塞后续规则。
- 变量支持 `$event.*`、`$task.*`、`$today` 和 `$module.field.<id>`，无任意脚本求值。
- 模板通过 CommandBus 创建项目、父子任务树及本模块字段，支持优先级、计划/截止日，以及 `$today / $today±Nd` 日期表达式。
- 模板参数支持 `text / number / boolean / date / datetime / select / multiSelect`，通过 `$param.<id>` 引用，执行前检查必填、默认值、类型、选项与未知参数。
- “模块”页可应用启用模块的模板，参数化模板先显示动态表单。规则日志支持全部/失败/跳过/成功筛选与单条失败重试；保存原事件 payload，通过 `sourceExecutionId` 关联重试记录，重试条件读取当前快照。
- 模块停用/卸载时同步移除规则与模板；彻底删除才清理保留的规则日志。

### AI 与模块包

- AI 工作区支持用户填写 OpenAI Chat Completions 兼容端点、模型和 API Key，由设备直连；远程端点要求 HTTPS，本机 loopback 可使用 HTTP。
- 端点与模型持久化到 `AppSettings`；API Key 通过 `flutter_secure_storage` 写入系统安全存储，不进入 SQLite。
- 当前 AI 请求发送功能需求和已安装动态模块的 ID/版本，返回候选模块 JSON；也可手动粘贴 JSON。两种方式均经解析、权限/能力/语义校验、资源与权限 Diff、用户确认，再热安装。
- Proposal 阻止覆盖内置模块 ID、拒绝未知权限与不升版更新，并用 expected current version 拒绝过期提案覆盖。规则/模板在确认前由对应引擎校验。
- [module-package-v1.schema.json](packages/schemas/module-package-v1.schema.json) 定义包协议，验证器支持 canonical JSON、SHA-256 摘要和 Ed25519 签名。
- “模块”页支持从文件导入。未签名本地开发包显示未审核警告；市场包要求发布者、发布时间、approved 审核信息（reviewId、reviewedAt、policyVersion）及受信任签名，校验失败即拒绝。通过校验后仍需 Diff 确认。
- 信任公钥随客户端发布在 `client/assets/trusted_publishers.json`，当前清单为空，因此市场包默认拒绝；服务器不能运行时增加信任根。模块卡片和版本历史显示来源。

## 尚未实现与后续方向

- 完整任务编辑、备注/标签/移动/归档/删除命令、子任务界面、搜索、看板及键盘交互。
- 账号、端到端加密、恢复码、自有云同步、离线队列传输、冲突处理和数据导出；AI 凭证跨设备同步也未实现。
- AI 发送前上下文预览与确认、任务命令提案、对话持久化、通用撤销；任意布局与恢复默认布局仍待实现。
- 市场目录、投稿、人工审核服务、离线签名发布工具、客户端浏览、更新检查及撤销/吊销元数据。
- 规则日志分页/导出、更多声明式 UI 组件、coreApi 兼容范围与完整生命周期接口。
- Windows 构建与真机交互验证、Windows 安装包和正式 Android 发布签名。

后续方向沿用 [设计方案](docs/DESIGN.md) 与 [交接文档](PROJECT_HANDOFF.md)。现有本地基础和声明式扩展可继续迭代；同步与公开市场仍需各自完成端到端实现和验收。

## 验证记录

- 2026-10-03 查询与字段一致性优化：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 84 项全部通过（本轮新增 12 项），Android release 分架构 APK 构建通过。验证包含 SQL/Dart 过滤语义一致性、1 万条额外任务下的按需返回行数与单次查询、字段/模块启停订阅刷新、跨日/恢复前台与订阅释放、字段类型/权限校验、批量回滚、模板失败事件抑制和规则循环保护。此数据规模用例验证查询行为，不代表真机耗时或帧率基准；Windows 与真机运行尚未验证。

- 2026-10-02 任务操作与模块恢复优化后：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 72 项全部通过（新增 10 项），Android release 分架构 APK 构建通过。新增覆盖项目任务创建/归属、手机与桌面尺寸下的基础编辑与日期清除、校验/取消/无改动保存、重复提交与草稿保留、依赖顺序/循环/失败隔离及恢复提示。
- 2026-09-30 内置模块启停改版后：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 62 项测试全部通过，覆盖内置模块关闭/重启恢复、数据保留、导航回退/顺序、依赖保护、保存失败和 AI 请求/提案取消，以及已有设置与任务功能。
- 此前已验证 Android release 分架构 APK 可构建；本次内置模块启停改版已通过 Flutter 调试连接更新 PHY120，并完成模块管理页截图检查，未重新构建 APK。
- Windows 平台构建、安全存储、安装与键盘/窗口行为尚未在 Windows 主机验证。
