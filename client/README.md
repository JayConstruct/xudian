# 序点 Flutter 客户端

面向 Android 与 Windows，共用 Dart 业务逻辑。当前采用 v2 模块架构：Riverpod 管理状态与依赖，Drift/SQLite 保存本地数据，`ModuleRegistry` 组合模块和导航。实现进度见 [项目首页](../README.md)，产品目标见 [交接文档](../PROJECT_HANDOFF.md)。

## 代码入口

| 路径 | 职责 |
| --- | --- |
| `lib/main.dart` | 初始化 Flutter，启动 Riverpod `ProviderScope` |
| `lib/app/app.dart` | 创建内置模块注册表，配置 Material 3 浅色/深色主题 |
| `lib/app/app_shell.dart` | 自适应导航、快速添加、AI 面板与动态模块恢复 |
| `lib/app/design_system.dart` | 共享视觉规则和任务信息行 |
| `lib/core/modules/` | 模块清单、上下文、注册表 |
| `lib/core/contracts/`、`lib/core/events/` | 命令/查询路由与领域事件 |
| `lib/core/security/`、`lib/core/ui/` | 能力、权限、页面组合、槽位解析与 UI 标注 |
| `lib/core/declarative/` | JSON 解析、模块存储、自定义字段、规则/模板引擎和包验证 |
| `lib/data/app_database.dart` | Drift 表定义、数据库打开与索引 |
| `lib/features/tasks/` | 任务命令/查询服务、存储、变更日志、Bus 绑定与通用列表 |
| `lib/features/declarative_runtime/` | 内置今天/收件箱定义、声明式页面与模块生命周期 |
| `lib/features/projects/` | 项目创建和项目任务列表 |
| `lib/features/module_manager/` | 模块启停、版本、模板、规则日志及文件导入 |
| `lib/features/ai/` | 模型配置、设备直连、候选模块提案与确认 |
| `lib/features/ui_examples/` | 无真实数据读写的交互组件示例，通过模块页打开 |
| `lib/features/settings/` | 本机偏好、双屏配置的入口与页面布局草稿 |
| `test/` | 单元、契约和 Widget 测试 |

## 数据与扩展流程

- 任务写入：`CommandBus` 按 `ModuleContext` 检查权限，调用 `TaskCommandService`；任务变更与 `ChangeJournal` 在同一数据库事务中提交，提交后发布 `DomainEvent`。
- 声明式任务读取：`QueryBus` 检查 `tasks.read`，通过 `task.list` 订阅稳定 DTO；`TaskSnapshotQuery` 单次关联任务与激活字段，`TaskFilterSql` 将可保持原语义的基础过滤 AST 下沉 SQLite，其余交由原 Dart 过滤器。字段值与定义变化会自动刷新列表，午夜/恢复前台重新订阅以更新 `$today`。规则用 `task.get` 获取单个任务。
- 自定义字段：通过 `field.set / field.clear / field.setMany` 检查 `fields.write` 与模块命名空间；`FieldCommandService` 组织字段写入和 ChangeJournal 的事务，成功后发布 `task.updated`，并继承自动化链与模板外层提交的事件延迟。批量编辑失败整体回滚，相同值不重复写日志。`FieldValueStore` 校验字段激活、任务存在/未删除、日期、时间、枚举、重复多选和有限数字。直接 Store 调用为底层接口，业务写入必须走 CommandBus。
- 动态模块启动按依赖顺序恢复，注册表校验依赖循环；失败模块停用并保留数据，工作台展示详细原因与管理入口。
- 动态模块：候选 JSON 经解析、运行时与注册表校验，展示资源和权限差异；用户确认后安装。模块启停与版本回退同步更新导航、字段、规则和模板。
- UI 组合：`UiPageRegistration`、`UiEntryRegistration`、`PageSlotDefinition` 与 `UiMount` 分离页面、打开方式和位置；`UiPageHost` 渲染入口、页签及纵向内容。公开槽位允许跨模块贡献，但查询和命令仍使用贡献模块自己的权限，`PageContext` 只传递任务／项目上下文。
- 布局：设置按 820px 分界编辑窄屏和宽屏配置，独立存入 `AppSettings` 的 `ui.layout`；切换配置保留草稿，保存成功后生效，取消不应用。主导航直显上限不计“更多”，窄屏结合空间／文字缩放计算安全容量，宽屏使用侧栏；底栏不作为可卸载模块。
- 页面状态：`retainPosition` 显式开启局部页签／滚动位置保留，缓存仅本次运行有效。8 层嵌套提醒不是硬上限，循环内容嵌套停止对应分支；上下文、槽位或宿主失效保留配置，可暂时保持或通过布局页补充上下文、调整及移除挂载。
- 标注与示例：标注默认关闭，`U` 编号仅为会话编号，复制使用稳定 UI ID 与静态元数据，不读取正文／输入／密钥，不上传。原生“UI 示例”与“UI 示例贡献”可单独开关，不读写真实业务数据，也不扩张声明式控件支持范围。
- 内置模块：`BuiltinModuleRegistration` 保存随客户端发布的目录，`BuiltinModuleController` 将开关写入 AppSettings 的 `modules.builtin.<id>` 并在启动时先于动态模块恢复。项目、AI、今天/收件箱可关闭；基础管理入口受保护，启停会检查活跃依赖，关闭保留数据，重新开启恢复导航顺序。停用的内置 ID 仍被保留，扩展模块不能占用。
- AI：设备直接调用用户配置的 Chat Completions 兼容端点；默认模式通过类型化工具辅助任务、导航、外观和布局，高级模式生成候选模块 JSON。端点和模型保存在 SQLite，API Key 通过 `flutter_secure_storage` 保存。
- AI 网络边界：默认总请求 60 秒、连接 10 秒、响应体读取 30 秒，响应最多 1 MiB（按字节计）；超时、超限或取消会终止请求并释放客户端和响应订阅。总期限覆盖连接、响应头及响应体，不随阶段或零星数据到达重新计时。

旧架构的 `TaskHome / TaskDetail / TaskEditor / TaskRepository` 已移除。当前任务命令为 `project.create`、`task.create`、`task.updateFields`、`task.setCompleted`；字段命令为 `field.set`、`field.clear`、`field.setMany`（批量编辑使用，当前规则白名单仍为 set/clear）。`task_editor.dart` 提供标题、优先级、计划日和截止日编辑，经 `task.updateFields` 保存改动字段；窄屏使用底部面板，宽屏使用右侧模态面板。`quick_task_input.dart` 复用快速添加逻辑，防重复提交并保留失败/新输入草稿；项目页自动关联当前项目。备注、标签、移动和子任务等完整编辑能力仍待实现。

数据库文件为应用支持目录下的 `xudian_v9.sqlite`，当前 Drift `schemaVersion` 为 1。文件名中的 v9 不代表迁移版本；当前不迁移旧本地数据库。修改表定义后需重新生成 `app_database.g.dart`，已有数据库的结构变化还需增加版本并编写迁移，见 [开发环境](../DEVELOPMENT.md)。

## 开发与验证

Windows 11 的 Android Studio 与模拟器配置见 [Windows 模拟器调试指南](../docs/WINDOWS_ANDROID_DEVELOPMENT.md)。用 Android Studio 打开本目录（包含 `pubspec.yaml`），并选择 `lib/main.dart` 作为启动入口。

- 2026-10-03 查询与字段一致性优化：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 84 项全部通过（本轮新增 12 项），Android release 分架构 APK 构建通过。验证包含 SQL/Dart 过滤语义一致性、1 万条额外任务下的按需返回行数与单次查询、字段/模块启停订阅刷新、跨日/恢复前台与订阅释放、字段类型/权限校验、批量回滚、模板失败事件抑制和规则循环保护。此数据规模用例验证查询行为，不代表真机耗时或帧率基准；Windows 与真机运行尚未验证。

2026-10-02 任务操作与模块恢复优化后：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 72 项全部通过（新增 10 项），Android release 分架构 APK 构建通过。新增覆盖项目任务创建/归属、手机与桌面尺寸下的基础编辑与日期清除、校验/取消/无改动保存、重复提交与草稿保留、依赖顺序/循环/失败隔离及恢复提示。

以下命令从项目根目录运行，使用项目内的 SDK 与依赖缓存：

```bash
source scripts/dev-env.sh
cd client
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
dart test/openai_compatible_provider_network_smoke.dart
```

网络单元回归通过注入客户端验证协议、超时、取消、响应限制和资源释放；真实 localhost 请求由上述独立 Dart 脚本覆盖，包括 UTF-8、HTTP 错误、取消和读取超时。当前环境的 Flutter 运行器在无 provider 的独立 socket-bind 用例中也出现停滞，而原生 Dart 请求可通过；其底层原因尚未确定，不能据此归因于代理或模型服务。两层验证分开执行，不跳过真实网络冒烟，也不通过延长测试超时掩盖问题。

本轮编排器优化验证：静态检查无问题，完整 Flutter 回归 200 项通过，独立 Dart localhost 网络冒烟 7 项通过，Android x86_64 debug `0.1.0+7` 构建成功。覆盖草稿隔离、双配置变更对比、搜索与技术标识、失效入口定位、上下文继承、槽位容量及小屏大字预览；不代表真机帧率、内存或 Windows 平台已完成验证。

2026-09-30 内置模块启停改版后，在当前 Linux 工作区运行 `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 62 项全部通过；新增内置状态恢复、数据保留、导航回退/顺序、依赖与基础入口保护、保存失败、内置 ID 保留、AI 请求取消和待审核提案取消验证。既有窄屏大字/深色布局、任务/设置/AI 配置、事务、Bus 权限、声明式解析与运行时、模块版本和来源、规则及模板测试继续通过。

构建 Android 侧载包：

```bash
flutter build apk --release --split-per-abi --no-pub
```

输出位于 `build/app/outputs/flutter-apk/`。当前 release 使用 debug 签名。Windows 构建、安装与平台行为需在 Windows 主机验证；在配置好 Flutter 的 Windows 环境中进入 `client/`，运行 `flutter pub get` 和 `flutter build windows --release`。本工程尚未提供 Windows 安装包制作流程。

## 当前边界

当前可运行的是本地任务与声明式扩展。端到端加密、账号、自有云同步和市场服务端尚未实现；`ChangeOperations.synced` 只是为后续同步预留的状态。模块包验证和文件导入已实现，但 `assets/trusted_publishers.json` 当前没有信任公钥，市场包会被拒绝。

声明式版本 1 保持所有页面进入导航且 `layouts` 省略或为空；版本 2 支持 `view / container` 页面、页面槽位与 `layouts` 贡献，任务视图仍使用统一任务列表。v2 只有显式 `entry: {}` 或入口对象才注册入口，省略／`null`／`false` 均无入口；需声明 `ui.composition`、`ui.registry` 与 `ui.register`。公开 [v2 Schema](../packages/schemas/declarative-module-v2.schema.json) 保留 v1 并复用其业务资源定义，引用、权限和挂载有效性以解析器／运行时为准。

使用说明及可运行 JSON source 见 [UI 组合](../docs/UI_COMPOSITION.md)。source 可粘贴到 AI 高级模式的 JSON 编辑器中审核安装，文件导入则必须先按原有协议封装为模块包：外层 `packageFormat: 1` 不变，内层 `module.formatVersion: 2`，不能把 source 直接当 package 导入。

全局助手已支持任务、页面、外观与布局工具、逐组审批／限时委托、本地对话记录及条件撤销。运行时 `assistant_runtime.dart` 负责授权、轮次、审批和记录，`assistant_actions.dart` 负责工具白名单和目标校验，`assistant_model.dart` 负责模型协议；核心 `GlobalOverlayHost` 和 `AppNavigation` 分别提供悬浮槽位与根导航。实现边界及整合计划见 [全局 AI 助手](../docs/AI_ASSISTANT.md)。精确发送内容预览、可靠后台恢复、通用撤销、搜索、看板和完整任务详情仍属后续工作。

新生产入口使用通用 JavaScript 模块宿主，独立模块包位于 `../dist/modules`；课表不随客户端预装。构建、迁移、恢复与运行时限制见 [模块宿主](../docs/MODULE_HOST.md)。

课表1.2的单顶栏与设置组件见 [课表界面](../docs/SCHEDULE_UX.md)；最新包需宿主API1.2.0。

课表1.3的自动收缩工具栏需要宿主API1.3，详见 [滚动工具栏](../docs/SCHEDULE_CHROME.md)。

[课表悬浮底栏与滚动余量](../docs/SCHEDULE_GLASS.md)。
