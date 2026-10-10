> 历史归档：保留当时的方案、状态与验证结果。当前文档见 [文档导航](../README.md)，历史构建和截图可能只存在于原验收工作区。

# 序点

面向 Android 与 Windows 的模块化个人任务管理 App，使用 Flutter/Dart、Riverpod 和 Drift/SQLite。当前采用 v2 模块架构，已实现本地任务、声明式扩展、入口编排与全局 AI 助手。

状态核对日期：2026-10-09。产品目标包含跨设备端到端加密同步和公开模块市场；当前仓库尚无同步或签名审核服务端。模块分发采用统一目录与作者各自发布的 GitHub Releases，接入协议、发布工具和目录仓库内容见 [模块目录](../MODULE_CATALOG.md)。

## 文档与目录

| 入口 | 内容 |
| --- | --- |
| [开发环境](../../DEVELOPMENT.md) | SDK、测试、Android 构建与临时 APK 分享 |
| [Windows 模拟器调试](../WINDOWS_ANDROID_DEVELOPMENT.md) | Windows 11 环境、Android Studio、模拟器与 Git 同步 |
| [VPS 与 WSL 开发配置](../MULTI_MACHINE_DEVELOPMENT.md) | WSL 原生 ADB 连接与 APK 安装、共享手机调试、端口与开发签名 |
| [客户端说明](../../client/README.md) | 代码入口、数据流和当前实现边界 |
| [目标与交接](../../PROJECT_HANDOFF.md) | 已确认产品选择、当前状态和后续交接 |
| [设计方案](../DESIGN.md) | 架构、同步/加密设计与验收目标 |
| [界面设计系统](../UI_DESIGN_SYSTEM.md) | 视觉规则及模块/AI 页面约束 |
| [设置层级](../SETTINGS_HIERARCHY.md) | 分类首页、二级设置、模块设置与常用入口 |
| [UI 组合与模块示例](../UI_COMPOSITION.md) | 入口编排、公开页面槽位、标注模式与 v2 JSON 协议 |
| [全局 AI 助手整合方案](../AI_ASSISTANT.md) | 悬浮插件、限时授权、任务与布局工具、冲突保护及后续边界 |

```text
client/             Flutter 客户端、Android/Windows 工程与测试
packages/schemas/   声明式模块和模块包的 JSON Schema
docs/               架构与界面设计
scripts/            开发环境、APK 本地服务与临时分享
assets/brand/       品牌图标源文件与生成工具
```

`.tools/` 与 `.cache/` 存放本机 SDK 和缓存。未来云端拟采用 TypeScript/Fastify + PostgreSQL，尚未创建 `server/` 工程。

## 快速开始

源码仓库为 [JayConstruct/xudian](https://github.com/JayConstruct/xudian)，当前源码和作者索引发布在 [module-catalog 分支](https://github.com/JayConstruct/xudian/tree/module-catalog)。Windows 11 本地调试请先按 [Windows 模拟器调试指南](../WINDOWS_ANDROID_DEVELOPMENT.md) 安装 SDK，克隆并切换到该分支后，用 Android Studio 打开 `client/`。

当前 WSL 工作区使用 Linux 版 `adb` 直连 Windows ADB server，后续不通过 Windows 命令调用 ADB 客户端；连接与安装流程见 [WSL 原生 ADB](../MULTI_MACHINE_DEVELOPMENT.md#wsl-原生-adb连接与安装-apk)。Windows Android Studio 仅负责模拟器运行，WSL 的本机 SDK 与构建产物需单独配置。

使用当前 Linux 工作区已配置的 SDK，从项目根目录运行：

```bash
source scripts/dev-env.sh
cd client
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --split-per-abi --no-pub
```

APK 输出到 `client/build/app/outputs/flutter-apk/`；多数 Android 手机使用 `app-arm64-v8a-release.apk`。当前 release 使用 debug 密钥签名，供侧载试用。Windows 需在 Windows 构建机上构建和验证，安装包流程尚未完成。首次环境配置和分享方法见 [开发环境](../../DEVELOPMENT.md)。

VPS 开发使用独立 HTTPS 链接下载调试 APK，在手机旁安装后，通过 ADB/VM Service 的 SSH 转发运行 `flutter attach`；保存 Dart 修改后按 `r` 热重载。预览脚本不经 SSH 传输 APK。配置见 [远程预览](DEVELOPMENT_20261009.md#通过-ssh-远程预览-android)，命令为 `bash scripts/preview-android.sh DEVICE_SERIAL`；2026-09-30 已在 PHY120 验证 attach 连接和无源码变更的热重载，耗时约 2.2 秒。

## 当前实现

### 模块与界面

- `ModuleManifest`、`AppModule`、`ModuleContext` 和可监听的 `ModuleRegistry` 组成基础运行时。注册表检查模块 ID、版本格式、依赖存在及所需 capability；使用候选副本验证后替换，失败时保留原注册状态。
- `requiresCapabilities` 表示运行环境需提供的能力，`permissions` 表示模块获准使用的权限。命令、查询和 UI 注册在各自边界校验权限。
- `UiRegistry` 统一注册页面、入口和页面槽位，支持入口区、页签区及纵向内容区的嵌套；公开槽位可接受其他模块贡献，私有槽位仅供本模块使用。旧全局 `UiSlot` 继续兼容，不意味着所有预留槽位都已接入渲染。
- 默认主导航为“今天、收件箱、项目、模块”。设置中可分别编排手机／窄屏和电脑／宽屏入口，以 820px 为分界，支持主导航、顶部、更多、设置常用入口、隐藏及兼容的页面槽位。主导航直显上限只计普通入口，不计“更多”；窄屏默认 4 个，宽屏默认不限制，窄屏根据空间与文字缩放动态减少直显数量。底栏仍是核心壳层组件。AI 默认位于顶部，打开方式与入口位置分离。
- “今天”和“收件箱”由内置声明式配置运行；“项目”复用通用任务列表。界面采用轻量标题、分组内容、统一连续圆角与悬浮底栏，任务列表显示数量与统一空状态。
- 移动底栏已整合快速输入与导航，支持毛玻璃悬浮、滑动选中胶囊、实心选中图标和按压/轻触反馈；列表末项可滚动至底栏上方，键盘弹出时保留输入并隐藏导航。
- 设置页面提供主题、减少动画、导航触感、入口与页面布局、界面标注、AI 连接、模块管理和关于信息；“关于序点”显示项目与模块仓库地址，支持浏览器打开、复制地址和直接打开模块商店。商店支持搜索名称、作用、作者或模块 ID，组合分类、推荐与安装状态筛选，并显示兼容稳定版本的更新。布局草稿在保存成功后应用，配置存入本机 `ui.layout`。AI 工作区与设置页共用独立连接配置页面。设置和恢复入口不因自定义布局而失去访问途径。
- “模块管理”同时列出内置功能与扩展模块。项目、AI、今天和收件箱支持开关；关闭状态在启动时恢复，保留数据与配置。关闭当前页面会回退，AI 关闭时隐藏入口并取消待完成的请求与提案；模块管理和设置始终可用。
- 内置“UI 示例”和“UI 示例贡献”是可开关的原生模块，只申请 UI 注册权限，不读取或写入真实任务。示例从模块页打开，默认不占主导航，演示组件、公开／私有槽位、跨模块页签与内容、上下文失效和局部位置保留；演示状态可重置。原生示例不代表声明式模块已支持全部控件。
- 页面仅在声明 `retainPosition` 后保留局部页签／滚动位置，且只在本次运行有效。嵌套达到 8 层会提醒调整，无深度硬上限；循环内容嵌套阻止对应分支。上下文或宿主失效时保留挂载并提示，可暂时保持现状或进入布局设置处理；公开槽位中的贡献仍以自己的模块权限执行。
- 界面标注模式默认关闭，为已登记的可见区域显示 `U` 会话编号；可查看和复制稳定 UI ID、模块、页面路径、槽位及作用。仅复制静态元数据，不读取业务正文、输入值或密钥，不自动截图或上传。
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

- 格式契约提供 [v1 Schema](../../packages/schemas/declarative-module-v1.schema.json) 和 [兼容 v1 的 v2 Schema](../../packages/schemas/declarative-module-v2.schema.json)。客户端以手写解析器和运行时语义校验为准；v2 严格校验页面、槽位、入口和挂载字段，拒绝未知组合字段。Schema 不替代引用存在性、ID 唯一性、槽位兼容及权限检查，客户端未接入通用 Schema 执行器。
- 版本 1 保持全页导航，`layouts` 必须省略或为空。版本 2 新增 `view / container` 页面与 `layouts` 槽位贡献；页面必须显式声明 `entry: {}` 或入口对象才注册入口，省略、`null` 或 `false` 均无入口。v2 要求 `ui.composition`、`ui.registry` capability 与 `ui.register` 权限；`task.list` 视图另需 `tasks.query` 与 `tasks.read`。不接受任意视觉样式或可执行代码。
- [宿主](../../packages/examples/ui-slot-host-v2.json)与[贡献模块](../../packages/examples/ui-slot-contributor-v2.json)示例是模块 source，可通过 AI 高级 JSON 提案审核安装，或按既有模块包协议封装后导入；不能直接把 raw source 当模块包导入。外层 `packageFormat: 1` 不变，内层 `module.formatVersion` 可为 2，详见 [UI 组合说明](../UI_COMPOSITION.md)。
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

- AI 助手是应用内全局悬浮插件：默认模式在授权后辅助任务、导航、外观和入口编排；高级模式保留声明式模块开发及人工安装确认。支持逐组审批或限时委托、本地对话／执行记录及条件撤销，具体范围见 [整合方案](../AI_ASSISTANT.md)。
- AI 工作区支持用户填写 OpenAI Chat Completions 兼容端点、模型和 API Key，由设备直连；远程端点要求 HTTPS，本机 loopback 可使用 HTTP。
- 端点与模型持久化到 `AppSettings`；API Key 通过 `flutter_secure_storage` 写入系统安全存储，不进入 SQLite。
- 高级模式的模块生成请求发送功能需求和已安装动态模块的 ID/版本，返回候选模块 JSON；也可手动粘贴 JSON。两种方式均经解析、权限/能力/语义校验、资源与权限 Diff、用户确认，再热安装。
- Proposal 阻止覆盖内置模块 ID、拒绝未知权限与不升版更新，并用 expected current version 拒绝过期提案覆盖。规则/模板在确认前由对应引擎校验。
- [module-package-v1.schema.json](../../packages/schemas/module-package-v1.schema.json) 定义包协议，验证器支持 canonical JSON、SHA-256 摘要和 Ed25519 签名。
- “模块”页支持从文件导入。未签名本地开发包显示未审核警告；市场包要求发布者、发布时间、approved 审核信息（reviewId、reviewedAt、policyVersion）及受信任签名，校验失败即拒绝。通过校验后仍需 Diff 确认。
- 信任公钥随客户端发布在 `client/assets/trusted_publishers.json`，当前清单为空，因此市场包默认拒绝；服务器不能运行时增加信任根。模块卡片和版本历史显示来源。

## 尚未实现与后续方向

- 完整任务编辑、备注/标签/移动/归档/删除命令、子任务界面、搜索、看板及键盘交互。
- 账号、端到端加密、恢复码、自有云同步、离线队列传输、冲突处理和数据导出；AI 凭证跨设备同步也未实现。
- 精确发送内容预览、可靠后台执行／检查点恢复、跨资源补偿与通用撤销、更多任务工具；自由画布式视觉布局尚未实现，当前使用入口与页面槽位编排。
- 签名市场的人工审核服务、离线签名发布工具、后台自动更新及撤销/吊销元数据。分布式模块目录与作者发布工具另见 [接入文档](../MODULE_CATALOG.md)。
- 规则日志分页/导出、更多声明式 UI 组件、coreApi 兼容范围与完整生命周期接口。
- Windows 构建与真机交互验证、Windows 安装包和正式 Android 发布签名。

后续方向沿用 [设计方案](../DESIGN.md) 与 [交接文档](../../PROJECT_HANDOFF.md)。现有本地基础和声明式扩展可继续迭代；同步与公开市场仍需各自完成端到端实现和验收。

## 验证记录

- 2026-10-06 全局助手与布局编辑优化：静态分析无问题，357项 Flutter 测试和19项原生 Dart 网络场景通过；Android x86_64 调试 APK 构建通过，模拟器检查悬浮面板和布局列表。未向真实模型发送请求；Windows 和物理手机本轮未验证。范围与后续计划见 [整合方案](../AI_ASSISTANT.md)。

- 2026-10-03 查询与字段一致性优化：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 84 项全部通过（本轮新增 12 项），Android release 分架构 APK 构建通过。验证包含 SQL/Dart 过滤语义一致性、1 万条额外任务下的按需返回行数与单次查询、字段/模块启停订阅刷新、跨日/恢复前台与订阅释放、字段类型/权限校验、批量回滚、模板失败事件抑制和规则循环保护。此数据规模用例验证查询行为，不代表真机耗时或帧率基准；Windows 与真机运行尚未验证。

- 2026-10-02 任务操作与模块恢复优化后：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 72 项全部通过（新增 10 项），Android release 分架构 APK 构建通过。新增覆盖项目任务创建/归属、手机与桌面尺寸下的基础编辑与日期清除、校验/取消/无改动保存、重复提交与草稿保留、依赖顺序/循环/失败隔离及恢复提示。
- 2026-09-30 内置模块启停改版后：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 62 项测试全部通过，覆盖内置模块关闭/重启恢复、数据保留、导航回退/顺序、依赖保护、保存失败和 AI 请求/提案取消，以及已有设置与任务功能。
- 此前已验证 Android release 分架构 APK 可构建；本次内置模块启停改版已通过 Flutter 调试连接更新 PHY120，并完成模块管理页截图检查，未重新构建 APK。
- Windows 平台构建、安全存储、安装与键盘/窗口行为尚未在 Windows 主机验证。

脚本模块宿主、独立课表包和迁移恢复文档： [模块宿主](../MODULE_HOST.md) · [JavaScript SDK](../MODULE_SDK.md) · [验收记录](MODULE_HOST_VERIFICATION.md)。

课表1.2单顶栏、分组设置、12节作息与详情预览交付见 [课表界面与验收](SCHEDULE_UX.md)。

课表1.3支持纵向滚动自动收缩顶栏与底部导航，交付见 [滚动工具栏](SCHEDULE_CHROME.md)。

[课表悬浮底栏与滚动余量](SCHEDULE_GLASS.md)。

正方通用脚本可通过独立的 [拾光导入兼容模块](../SHIGUANG_IMPORT.md) 运行；Android 支持内置教务浏览器，桌面端支持拾光 JSON 文件导入。

拾光模块内置学校搜索及正方、青果、URP、超星通用入口；原独立正方导入模块已移除。其他学校模块仍可通过 [拾光适配模块接口](../SHIGUANG_ADAPTER_API.md) 接入公共导入流程。

统一目录仓库内容位于 [packages/catalog](../../packages/catalog/README.md)，作者版本索引位于 `module-index/`，首批与历史原始包位于 `dist/module-releases/`。元数据更新使用新版本，未签名包的 SHA-256 只作为完整性校验；发布状态和验证范围见 [模块目录接入文档](../MODULE_CATALOG.md)。
