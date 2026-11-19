# 开发指南

宿主在 `client/`，独立模块在 `packages/modules/`。先看 [客户端代码入口](client/README.md) 与 [架构边界](docs/ARCHITECTURE.md)，待办状态统一见 [BACKLOG](docs/BACKLOG.md)。

## 准备环境

Linux / WSL 在项目根目录执行：

```bash
source scripts/dev-env.sh
flutter doctor -v
cd client
flutter pub get
cd ..
```

环境脚本使用 `.tools/flutter`、`.tools/android-sdk`、Java 21 和 `.cache/` 内的依赖缓存。首次搭建还需 Git、curl、unzip、GCC/C++ 构建工具及工程要求的 Android 平台、Build Tools、NDK，以构建配置和 `flutter doctor -v` 为准；项目没有 Linux 桌面目标。修改 `pubspec.yaml` 后重新执行 `flutter pub get`，依赖就绪后才使用 `--no-pub`。

Windows、WSL 或 VPS 的 Android 工具链、ADB 和远程调试步骤见 [Android 开发环境](docs/ANDROID_DEVELOPMENT.md)。SDK、缓存、凭据和本机配置不提交。

## 日常更新

先运行 `scripts/start-emulator.sh`，复用已运行的模拟器或启动后等待就绪，再按改动选择：

| 场景 | 根目录命令 |
| --- | --- |
| 宿主 UI 调试与热重载 | `scripts/update-emulator.sh --dev` |
| 仅更新独立模块 | `scripts/update-emulator.sh --modules-only --module app.schedule` |
| 宿主与模块一起更新 | `scripts/update-emulator.sh --module app.schedule` |
| Release 效果与相关回归 | `scripts/update-emulator.sh --test test/相关文件.dart` |
| 商店、离线与冷启动验收 | `scripts/update-emulator.sh --verify-catalog --catalog-offline` |

更新脚本复用有效缓存，覆盖安装并核对版本、摘要及启动，保留现有数据。模块内容改变须递增版本；更新 APK 不会自动升级已安装模块。冷启动、高刷、测试选择、签名不匹配与失败处理见 [模拟器流程](docs/EMULATOR_UPDATE.md)。提交与发布按 [发布流程](docs/RELEASE_WORKFLOW.md) 执行；不要在更新脚本前重复其分析与相同测试，发布验收、排查缓存或明确要求重建时加 `--force`。

## 常用检查与构建

以下命令用于独立检查或排查；将 `test/相关文件.dart` 替换为本轮相关测试，运行改动的最终验收仍使用上面的更新流程。

| 目的 | 目录与命令 |
| --- | --- |
| 仓库与文档边界 | 根目录：`python3 scripts/check_repository.py`、`python3 scripts/check_docs.py` |
| 生产依赖边界 | 根目录：`python3 scripts/module_host/check_architecture.py` |
| Python 工具回归 | 根目录：`python3 -m unittest discover -s scripts/tests -v` |
| 打包模块到 `dist/modules/` | 根目录：`python3 scripts/module_host/build_packages.py`；[预装资源规则](docs/MODULE_HOST.md#构建和验证) |
| Flutter 分析与相关测试 | `client/`：`flutter analyze --no-pub`、`flutter test --no-pub --concurrency=2 test/相关文件.dart` |
| Android 分 ABI 构建 | `client/`：`flutter build apk --release --split-per-abi --no-pub` |
| Drift 绑定生成 | `client/`：`dart run build_runner build`；同时审阅迁移、备份和恢复测试 |
| 临时 APK 下载链接 | 根目录：`scripts/share-apk.sh`，调试包加 `--debug`；[分享参数](docs/ANDROID_DEVELOPMENT.md#临时-apk-分享) |

涉及数据、生命周期、权限和依赖时扩大回归；HTTP／AI 的真实网络测试须按 [客户端测试约束](client/README.md#测试约束) 使用独立服务器子进程。Widget 测试不代表真机帧率。

`check_docs.py` 检查 Git 跟踪与未忽略的新 Markdown 文件、相对链接、图片、锚点及 SDK 当前 API，不联网。默认跳过明确的本机产物链接；`--check-local` 要求它们存在，`--json <报告路径>` 保存结果。提交前另查 `git status --short` 和 `git diff --check`。

工作流修改须校验 Actions 表达式上下文；仅解析 YAML 不够。已安装 Go 时运行 `go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 -shellcheck= -pyflakes= .github/workflows/*.yml packages/catalog/.github/workflows/*.yml`，工具缓存不提交。

Android APK 输出到 `client/build/app/outputs/flutter-apk/`，多数手机使用 ARM64。覆盖安装须保持签名一致并满足设备 versionCode 要求；本机开发签名不能替换公开固定证书包。版本、资产和签名规则见 [发布版本与资产](docs/RELEASE_WORKFLOW.md#android-发布版本与资产) 与 [签名保管](docs/ANDROID_SIGNING.md)。

## Windows 桌面

在 Windows 安装 Flutter、Visual Studio C++ 桌面开发组件与 Windows SDK，通过 `flutter doctor -v` 后进入 `client/` 执行 `flutter pub get`、`flutter build windows --release`。程序与依赖资源须一起分发；安装、凭据、导入、键盘和窗口缩放按 [平台验收矩阵](docs/PLATFORM_VERIFICATION.md#platform-01windows) 验证。

## 专题入口

- 源码、固定依赖、生成文件与本机产物：[目录与提交规范](docs/REPOSITORY_LAYOUT.md)。
- UI 选稿与实现范围：[设计入口](design/README.md)；原图、提示词与批次：[设计稿规范](design/README.md#稿件存储与校验)。
- 模块接口、迁移及发布：[SDK](docs/MODULE_SDK.md)、[模块宿主](docs/MODULE_HOST.md)、[模块目录](docs/MODULE_CATALOG.md)。
- 当前能力、待办与最新验收：[项目首页](README.md)、[统一待办](docs/BACKLOG.md)、[验证索引](docs/VERIFICATION.md)。
