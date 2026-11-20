# 目录与提交清单

源码、固定依赖和可复验说明由 Git 管理；本机工具链、凭据、草稿和构建输出使用忽略目录。调整目录前先检查引用，已发布模块原包和仍被索引引用的历史版本必须保留。

<a id="github-提交范围"></a>

## 当前工程目录

| 路径 | 职责与入口 |
| --- | --- |
| `client/` | Flutter 宿主、平台工程和测试。导航、渲染、存储与安装入口见[客户端代码说明](../client/README.md#代码入口)。 |
| `packages/modules/` | JavaScript 业务模块和声明式界面包，每个模块以自己的 `module.json` 声明版本和宿主兼容范围。 |
| `packages/modules/app.import.shiguang/warehouse/` | 拾光适配器使用的固定上游快照，来源和更新方式见[上游说明](../packages/modules/app.import.shiguang/UPSTREAM.md)。 |
| `packages/schemas/`、`packages/examples/` | 模块、页面和包格式的 Schema 与协议示例，使用方法见[模块 SDK](MODULE_SDK.md)。 |
| `packages/xquickjs/` | 宿主依赖的 QuickJS 绑定、原生构建钩子及固定版本引擎。[依赖说明](../packages/xquickjs/README.md) |
| `assets/brand/` | 品牌原图和平台图标生成工具。[品牌资源](../assets/brand/README.md) |
| `client/assets/modules/` | 随 APK 安装的模块包与清单。`catalog.json` 固定预装包，`retired.json` 声明退出分发的模块。[预装资源规则](MODULE_HOST.md#构建和验证) |
| `packages/catalog/` | 可独立发布的模块商店目录、收录格式及校验工具。[目录说明](../packages/catalog/README.md) |
| `module-index/`、`releases/modules/` | 作者版本索引及其引用的全部不可变发布包。[发布包保留规则](../releases/README.md) |
| `scripts/`、`.github/workflows/` | 本地开发、检查与 CI。`scripts/module_host/` 提供宿主和打包工具，`scripts/module_catalog/` 管理作者发布，`scripts/tests/` 保存工具回归。 |
| `scripts/verification/` | 课表与拾光导入的设备复验脚本。各脚本适用的版本、样例数据和运行方式见[设备复验脚本索引](../scripts/verification/README.md)。 |
| `design/` | 现行选稿、视觉来源和稿件存放规则见[设计入口](../design/README.md)。原稿与批次留在本机。 |
| `docs/` | [专题导航](README.md)。`features/` 说明各项功能的使用与行为，`ui/` 保存界面、动画与反馈规范，`sdk/` 按能力说明接口，`design/` 保存精选参考图，`releases/` 与 `verification/` 保存最新发布和验收记录。 |

`app_database.g.dart`、Android Gradle wrapper、运行所需的上游源码和资源仍由构建直接读取，应保留。图片不按扩展名一律忽略，应用图标和精选文档参考图可以提交。

## 本机目录

| 路径 | 用途与整理规则 |
| --- | --- |
| `.tools/` | 已安装 Flutter／Android SDK 与开发工具，通常保留 |
| `.cache/gradle/`、`.cache/pub/` | 可复用的依赖缓存，通常保留以免重复下载 |
| `.cache/config/` 等开发配置 | 包含本机开发签名和配置，不整体清空 `.cache/` |
| `.cache/emulator-update/` | 更新锁、最近状态、构建缓存 APK 及模块更新状态；详细验收证据放 `dist/verification/` |
| `client/.dart_tool/flutter_build/` | 可重建的编译缓存，可保留最近目录后清理旧目录；保留依赖配置和其余 `.dart_tool` 状态 |
| `client/build/` | 可重建的 APK 和编译中间产物，整理前先保留当前验收 APK |
| `.cache/downloads/` | 已安装工具链的重复下载归档，确认工具已安装后可清理指定文件 |
| `dist/modules/` | 可重新打包的本机候选包；使用前核对源码版本和摘要，不能仅凭路径认定为最新 |
| `dist/bundle-archive/` | 打包工具使用的旧预装包归档，保留既有工具入口 |
| `dist/releases/app/<版本>/` | 本机 APK 发布暂存，包括原包、摘要、来源提交与报告 |
| `dist/releases/modules/<发布标签>/` | 本机模块发布暂存，每个标签独立目录，不代替 Git 中的不可变发布包 |
| `dist/verification/<时间>-<主题>/` | 每轮完整结果、日志、截图与必要快照；既有专题／批次目录按历史路径保留 |
| `design/<功能名>/`、`design/styles/` | 本机页面稿按功能直属 `design/`（如 `settings/`、`timetable/`），风格稿集中在 `styles/`。按页面名称找图见[页面与设计稿映射表](../design/PAGES.md)，归档见[设计稿规范](../design/README.md#稿件存储与校验) |
| `dist/design/<主题>/<批次>/` | 保留历史批次和旧清单，新 UI 使用根目录 design，见 [稿件存储与校验](../design/README.md#稿件存储与校验) |
| `dist/archive/` | 历史交付目录、旧整理备份与旧目录仓库检出，保留各自上下文 |
| `tasks/active/<任务名>/` | 当前任务的本机材料。例如，课表导入排查使用 `tasks/active/schedule-import/`，下次会话继续使用同一目录 |
| `tasks/archive/<归档日期>-<任务名>/` | 完成后整目录归档，例如 `tasks/archive/2026-11-19-schedule-import/`。同日重名时在新归档名末尾追加序号 |
| `tmp/`、`output/` | 工具的本机临时输出，Git 忽略这两个目录 |

归档前，将值得长期复用的脚本整理进 `scripts/`，将需要保留的结论写入对应专题文档。整个 `tasks/` 目录由 Git 忽略。独立任务需要同时修改同一组源码时，可使用独立分支和 Git worktree。新工作树以所选提交为起点，当前工作区的未提交修改只在原工作区可见。

固定发布签名保存在仓库外，不能作为缓存清理。其他本机凭据目录和用户数据也不属于构建缓存。

## 文档与记录只维护一处

- 当前规则在对应专题维护，实现与设备验收待办统一在 [BACKLOG](BACKLOG.md)，页面设计缺口在[设计稿映射表](../design/PAGES.md)；规则或状态未变时无需为每轮工作改写它们。根目录不另建交接记录。
- [版本与验证记录](VERIFICATION.md)保留当前公开发布和最近一次设备验收。发布时更新本版说明、结构化报告和[文档导航](README.md)的版本入口。常规文档、测试和目录检查的结果记在当次交付说明或 CI 中。
- 设备验收记录写明日期、实装版本与摘要、实测操作、结果、已知限制和证据路径。公开记录使用仓库相对路径，省去用户业务数据及账号密钥。
- 更新脚本将本轮设备验收结果写入 `dist/verification/<UTC时间>-emulator-update/results.json`。商店截图和报告在同目录的 `catalog/` 下。可通过 `.cache/emulator-update/latest-*.json` 的 `evidenceDir` 找到详细记录。

## 清理与验证

1. 保存清理明细和当前有效 APK／状态，核对清理路径不包含 Git 跟踪文件，不沿符号链接删除目标。
2. 清理明确可重建的旧缓存；缓存 APK 需保留 debug／release 状态文件引用和必要回退包。重复分发 APK 只有在另一个副本摘要完全一致、且原路径未被版本化文档或脚本引用时才清理，并记录恢复来源。
3. 设计稿的移动、删除及来源记录见[设计稿整理规则](../design/README.md#历史删除与验收)。保留应用运行资源和已发布模块。
4. 运行 `python3 scripts/check_repository.py`、相关测试和 `git diff --check`；该检查会拒绝强制加入的 `output/` 文件，`.gitignore` 只负责日常忽略。
5. 按 `AGENTS.md` 的改动范围验收：本机产物、文档或测试整理未改变运行产物时无需安装；工具改动实际验证受影响流程。宿主或 APK 输入改变时运行 `scripts/update-emulator.sh`；纯模块改动使用 `--modules-only --module <ID>` 并递增模块版本。默认复用有效缓存，发布验收、排查缓存或明确要求时再加 `--force`。

清理明细放在本机 `dist/verification/`。目录职责或清理规则有变化时，更新对应文档。纯目录整理沿用已有 App 和模块版本。
