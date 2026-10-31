# 目录与提交清单

源码、固定依赖和可复验说明由 Git 管理；本机工具链、凭据、草稿和构建输出使用忽略目录。调整目录前先检查引用，已发布模块原包和仍被索引引用的历史版本必须保留。

## 当前工程目录

当前唯一工程采用 Flutter/Dart 宿主与 JavaScript/QuickJS 模块，宿主放 `client/`，独立模块及协议放 `packages/`。构建、CI 和模拟器脚本继续使用这些路径，保留既有用户数据与不可变发布包。

根目录 `design/` 保存 UI 方案、清单与浅层稿件。选稿和实际实现范围统一见 [设计入口](../design/README.md)。

## GitHub 提交范围

| 路径 | 保留内容 |
| --- | --- |
| `design/` | 入口、UI 清单及 styles/screens 顶层使用说明，不含原图/提示词/批次 |
| `client/` | Flutter／平台源码、测试、依赖锁、图标、默认模块及 SDK 资源 |
| `packages/` | 模块源码、Schema、目录工具，以及固定版本的 QuickJS vendor 和拾光 warehouse |
| `assets/` | 品牌资源与模块退役清单 |
| `scripts/`、`.github/` | 构建、校验、模拟器流程与工作流 |
| `module-index/`、`releases/modules/` | 作者版本索引及其引用的全部不可变模块包 |
| `docs/` | 当前说明、精选设计参考、版本说明、精简验收记录和必要历史归档 |
| 根目录 Markdown／Git 配置 | 项目入口、开发／协作约定、交接说明、忽略及换行规则 |

`app_database.g.dart`、Android Gradle wrapper、运行所需的上游源码和资源仍由构建直接读取，应保留。`docs/verification/` 只提交步骤、版本、摘要和结果；完整日志、截图、下载包和设备数据留在本机。图片不按扩展名一律忽略，应用图标和精选文档参考图可以提交。

新一轮 UI 获选且需要随文档保存时，副本放 `docs/design/selected/`，附原路径、批次、SHA-256 与选择说明。原始风格稿直接放浅层 `design/styles/`；目录入口见 [design/](../design/README.md)。

## 本机目录

| 路径 | 用途与整理规则 |
| --- | --- |
| `.tools/` | 已安装 Flutter／Android SDK 与开发工具，通常保留 |
| `.cache/gradle/`、`.cache/pub/` | 可复用的依赖缓存，通常保留以免重复下载 |
| `.cache/config/` 等开发配置 | 包含本机开发签名和配置，不整体清空 `.cache/` |
| `.cache/emulator-update/` | 保留状态 JSON、其引用的 APK、最近回退包及模块验收状态；清理未引用的旧缓存 APK |
| `client/.dart_tool/flutter_build/` | 可重建的编译缓存，可保留最近目录后清理旧目录；保留依赖配置和其余 `.dart_tool` 状态 |
| `client/build/` | 可重建的 APK 和编译中间产物，整理前先保留当前验收 APK |
| `.cache/downloads/` | 已安装工具链的重复下载归档，确认工具已安装后可清理指定文件 |
| `dist/modules/` | 可重新打包的本机候选包；使用前核对源码版本和摘要，不能仅凭路径认定为最新 |
| `dist/bundle-archive/` | 打包工具使用的旧预装包归档，保留既有工具入口 |
| `dist/releases/app/<版本>/` | 本机 APK 发布暂存，包括原包、摘要、来源提交与报告 |
| `dist/releases/modules/<发布标签>/` | 本机模块发布暂存，每个标签独立目录，不代替 Git 中的不可变发布包 |
| `dist/verification/<专题>/<批次>/` | 当前与关键历史验收证据；保留性能基线、原始报告、截图和成组的数据快照 |
| `design/styles/`、`design/screens/ui-XX/` | 新原图与同名提示词直接放本层，批次记录在 .batches/；原稿和批次不提交 |
| `dist/design/<主题>/<批次>/` | 保留历史批次和旧清单，新 UI 使用根目录 design，见 [设计稿规范](DESIGN_ARTIFACTS.md) |
| `dist/archive/` | 历史交付目录、旧整理备份与旧目录仓库检出，保留各自上下文 |
| `output/`、`tmp/` | 工具的临时输出；整体忽略，用于文档的内容应精选后移入对应目录 |

新 UI 在实际设计时运行 `new styles` 或 `new ui-01` 至 `new ui-22`，原图文件以返回的完整时间批次为前缀；不向旧 app-ui-* 或历史批次追加。元数据与图片存放位置分开，避免为查找风格稿进入多层目录。

固定发布签名保存在仓库外，不能作为缓存清理。其他本机凭据目录和用户数据也不属于构建缓存。

## 清理与验证

1. 保存清理明细和当前有效 APK／状态，核对清理路径不包含 Git 跟踪文件，不沿符号链接删除目标。
2. 清理明确可重建的旧缓存；缓存 APK 需保留 debug／release 状态文件引用和必要回退包。重复分发 APK 只有在另一个副本摘要完全一致、且原路径未被版本化文档或脚本引用时才清理，并记录恢复来源。
3. 新 UI 按 [设计稿规范](DESIGN_ARTIFACTS.md) 创建浅层原图与独立批次记录；获选文档图复制到 docs/design/selected/ 并同步引用。历史移动保留原路径/新路径/SHA-256；明确删除的稿件只保留精简删除记录，不复制留存图片。不要移动应用运行资源或改写已发布模块。
4. 运行 `python3 scripts/check_repository.py`、相关测试和 `git diff --check`；该检查会拒绝强制加入的 `output/` 文件，`.gitignore` 只负责日常忽略。
5. 按 `AGENTS.md` 的改动范围验收：本机产物、文档或测试整理未改变运行产物时无需安装；工具改动实际验证受影响流程。宿主或 APK 输入改变时运行 `scripts/update-emulator.sh`；纯模块改动使用 `--modules-only --module <ID>` 并递增模块版本。默认复用有效缓存，发布验收、排查缓存或明确要求时再加 `--force`。

清理执行清单和详细验收结果放在 `dist/verification/`；只将精简结果和必要目录规则提交 GitHub。纯整理不递增独立模块版本，也不重新发布已有 App 或模块版本。

2026-10-29 的迁移映射、逐项摘要和删除恢复来源保存在本机 `dist/verification/repository/dist-organization-20261029/`。历史记录按专题归类，散落文件以 `legacy-20261029` 批次保留，日期表示归档时间。原始证据内容不改写；其中的旧路径可从 `plan.json` 查找，文档与现用脚本引用同步更新。完整下载 APK 保留，已核验的下载分片清理；旧 build50 交付 ZIP 的全部成员保存在 `dist/releases/app/0.1.0-build50/`，重建 ZIP 不保证复现原压缩包摘要。
