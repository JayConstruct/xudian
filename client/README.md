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
| `lib/core/security/`、`lib/core/ui/` | 能力、权限与 UI 插槽 |
| `lib/core/declarative/` | JSON 解析、模块存储、自定义字段、规则/模板引擎和包验证 |
| `lib/data/app_database.dart` | Drift 表定义、数据库打开与索引 |
| `lib/features/tasks/` | 任务命令/查询服务、存储、变更日志、Bus 绑定与通用列表 |
| `lib/features/declarative_runtime/` | 内置今天/收件箱定义、声明式页面与模块生命周期 |
| `lib/features/projects/` | 项目创建和项目任务列表 |
| `lib/features/module_manager/` | 模块启停、版本、模板、规则日志及文件导入 |
| `lib/features/ai/` | 模型配置、设备直连、候选模块提案与确认 |
| `test/` | 单元、契约和 Widget 测试 |

## 数据与扩展流程

- 任务写入：`CommandBus` 按 `ModuleContext` 检查权限，调用 `TaskCommandService`；任务变更与 `ChangeJournal` 在同一数据库事务中提交，提交后发布 `DomainEvent`。
- 声明式任务读取：`QueryBus` 检查 `tasks.read`，通过 `task.list` 订阅稳定 DTO；`TaskSnapshotQuery` 单次关联任务与激活字段，`TaskFilterSql` 将可保持原语义的基础过滤 AST 下沉 SQLite，其余交由原 Dart 过滤器。字段值与定义变化会自动刷新列表，午夜/恢复前台重新订阅以更新 `$today`。规则用 `task.get` 获取单个任务。
- 自定义字段：通过 `field.set / field.clear / field.setMany` 检查 `fields.write` 与模块命名空间；`FieldCommandService` 组织字段写入和 ChangeJournal 的事务，成功后发布 `task.updated`，并继承自动化链与模板外层提交的事件延迟。批量编辑失败整体回滚，相同值不重复写日志。`FieldValueStore` 校验字段激活、任务存在/未删除、日期、时间、枚举、重复多选和有限数字。直接 Store 调用为底层接口，业务写入必须走 CommandBus。
- 动态模块启动按依赖顺序恢复，注册表校验依赖循环；失败模块停用并保留数据，工作台展示详细原因与管理入口。
- 动态模块：候选 JSON 经解析、运行时与注册表校验，展示资源和权限差异；用户确认后安装。模块启停与版本回退同步更新导航、字段、规则和模板。
- 内置模块：`BuiltinModuleRegistration` 保存随客户端发布的目录，`BuiltinModuleController` 将开关写入 AppSettings 的 `modules.builtin.<id>` 并在启动时先于动态模块恢复。项目、AI、今天/收件箱可关闭；基础管理入口受保护，启停会检查活跃依赖，关闭保留数据，重新开启恢复导航顺序。停用的内置 ID 仍被保留，扩展模块不能占用。
- AI：设备直接调用用户配置的 Chat Completions 兼容端点，生成候选模块 JSON。端点和模型保存在 SQLite，API Key 通过 `flutter_secure_storage` 保存。

旧架构的 `TaskHome / TaskDetail / TaskEditor / TaskRepository` 已移除。当前任务命令为 `project.create`、`task.create`、`task.updateFields`、`task.setCompleted`；字段命令为 `field.set`、`field.clear`、`field.setMany`（批量编辑使用，当前规则白名单仍为 set/clear）。`task_editor.dart` 提供标题、优先级、计划日和截止日编辑，经 `task.updateFields` 保存改动字段；窄屏使用底部面板，宽屏使用右侧模态面板。`quick_task_input.dart` 复用快速添加逻辑，防重复提交并保留失败/新输入草稿；项目页自动关联当前项目。备注、标签、移动和子任务等完整编辑能力仍待实现。

数据库文件为应用支持目录下的 `xudian_v9.sqlite`，当前 Drift `schemaVersion` 为 1。文件名中的 v9 不代表迁移版本；当前不迁移旧本地数据库。修改表定义后需重新生成 `app_database.g.dart`，已有数据库的结构变化还需增加版本并编写迁移，见 [开发环境](../DEVELOPMENT.md)。

## 开发与验证

- 2026-10-03 查询与字段一致性优化：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 84 项全部通过（本轮新增 12 项），Android release 分架构 APK 构建通过。验证包含 SQL/Dart 过滤语义一致性、1 万条额外任务下的按需返回行数与单次查询、字段/模块启停订阅刷新、跨日/恢复前台与订阅释放、字段类型/权限校验、批量回滚、模板失败事件抑制和规则循环保护。此数据规模用例验证查询行为，不代表真机耗时或帧率基准；Windows 与真机运行尚未验证。

2026-10-02 任务操作与模块恢复优化后：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 72 项全部通过（新增 10 项），Android release 分架构 APK 构建通过。新增覆盖项目任务创建/归属、手机与桌面尺寸下的基础编辑与日期清除、校验/取消/无改动保存、重复提交与草稿保留、依赖顺序/循环/失败隔离及恢复提示。

以下命令从项目根目录运行，使用项目内的 SDK 与依赖缓存：

```bash
source scripts/dev-env.sh
cd client
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

2026-09-30 内置模块启停改版后，在当前 Linux 工作区运行 `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 62 项全部通过；新增内置状态恢复、数据保留、导航回退/顺序、依赖与基础入口保护、保存失败、内置 ID 保留、AI 请求取消和待审核提案取消验证。既有窄屏大字/深色布局、任务/设置/AI 配置、事务、Bus 权限、声明式解析与运行时、模块版本和来源、规则及模板测试继续通过。

构建 Android 侧载包：

```bash
flutter build apk --release --split-per-abi --no-pub
```

输出位于 `build/app/outputs/flutter-apk/`。当前 release 使用 debug 签名。Windows 构建、安装与平台行为需在 Windows 主机验证；在配置好 Flutter 的 Windows 环境中进入 `client/`，运行 `flutter pub get` 和 `flutter build windows --release`。本工程尚未提供 Windows 安装包制作流程。

## 当前边界

当前可运行的是本地任务与声明式扩展。端到端加密、账号、自有云同步和市场服务端尚未实现；`ChangeOperations.synced` 只是为后续同步预留的状态。模块包验证和文件导入已实现，但 `assets/trusted_publishers.json` 当前没有信任公钥，市场包会被拒绝。

声明式资源支持 `pages / views / fields / templates / rules`，页面使用统一任务列表，`layouts` 必须省略或为空。AI 任务变更提案、发送前上下文预览、对话持久化、通用撤销、搜索、看板和完整任务详情仍属后续工作。
