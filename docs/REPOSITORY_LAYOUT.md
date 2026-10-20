# 目录与提交清单

源码、固定依赖和可复验说明由 Git 管理；本机工具链、凭据、草稿和构建输出使用忽略目录。调整目录前先检查引用，已发布模块原包和仍被索引引用的历史版本必须保留。

## GitHub 提交范围

| 路径 | 保留内容 |
| --- | --- |
| `client/` | Flutter／平台源码、测试、依赖锁、图标、默认模块及 SDK 资源 |
| `packages/` | 模块源码、Schema、目录工具，以及固定版本的 QuickJS vendor 和拾光 warehouse |
| `assets/` | 品牌资源与模块退役清单 |
| `scripts/`、`.github/` | 构建、校验、模拟器流程与工作流 |
| `module-index/`、`releases/modules/` | 作者版本索引及其引用的全部不可变模块包 |
| `docs/` | 当前说明、精选设计参考、版本说明、精简验收记录和必要历史归档 |
| 根目录 Markdown／Git 配置 | 项目入口、开发／协作约定、交接说明、忽略及换行规则 |

`app_database.g.dart`、Android Gradle wrapper、运行所需的上游源码和资源仍由构建直接读取，应保留。`docs/verification/` 只提交步骤、版本、摘要和结果；完整日志、截图、下载包和设备数据留在本机。图片不按扩展名一律忽略，应用图标和精选文档参考图可以提交。

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
| `dist/modules/` | 当前模块候选包，不代替 Git 中的不可变发布包 |
| `dist/verification/` | 当前与关键历史验收证据；保留性能基线、原始报告及截图 |
| `dist/design/imagegen/` | 生成图、提示词及中间方案的本机归档 |
| `output/`、`tmp/` | 工具的临时输出；整体忽略，用于文档的内容应精选后移入对应目录 |

固定发布签名保存在仓库外，不能作为缓存清理。其他本机凭据目录和用户数据也不属于构建缓存。

## 清理与验证

1. 保存清理明细和当前有效 APK／状态，核对清理路径不包含 Git 跟踪文件，不沿符号链接删除目标。
2. 清理明确可重建的旧缓存；缓存 APK 需保留 debug／release 状态文件引用和必要回退包。重复分发 APK 只有在另一个副本摘要完全一致、且原路径未被版本化文档或脚本引用时才清理，并记录恢复来源。
3. 设计草稿归入 `dist/design/`，精选参考图放入 `docs/design/`，同步修正文档引用。不要移动应用运行资源或改写已发布模块。
4. 运行 `python3 scripts/check_repository.py`、相关测试和 `git diff --check`；该检查会拒绝强制加入的 `output/` 文件，`.gitignore` 只负责日常忽略。
5. 按协作约定通过 `scripts/update-emulator.sh --force` 重新编译、保留数据覆盖安装，核对版本、摘要和实际页面。

清理执行清单和详细验收结果放在 `dist/verification/`；只将精简结果和必要目录规则提交 GitHub。纯整理不递增独立模块版本，也不重新发布已有 App 或模块版本。
