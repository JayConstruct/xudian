# 开发指南

从项目根目录执行以下命令。Linux / WSL 使用项目 SDK；Windows 使用本机 Flutter 与 Android Studio。平台配置见 [Windows Android](docs/WINDOWS_ANDROID_DEVELOPMENT.md)、[VPS / WSL](docs/MULTI_MACHINE_DEVELOPMENT.md) 和 [远程 Android 预览](docs/REMOTE_ANDROID_DEVELOPMENT.md)。

## 准备环境

```bash
source scripts/dev-env.sh
flutter doctor -v
cd client
flutter pub get
cd ..
```

环境脚本设置 `.tools/flutter`、`.tools/android-sdk`、Java 21 和 `.cache/` 内的依赖路径。首次搭建 Linux 工作机需安装 Git、curl、unzip、GCC/C++ 构建工具及 Java 21，再准备 Flutter、Android 平台/Build Tools 和工程要求的 NDK，以 `flutter doctor -v` 和构建配置为准。项目没有 Linux 桌面目标。

修改 `pubspec.yaml` 后重新执行 `flutter pub get`；`--no-pub` 用于依赖已经准备好的环境。SDK、缓存、凭据和构建输出不应进入提交。

## 日常更新

| 改动 | 命令 |
| --- | --- |
| Flutter 页面，保持热重载 | `scripts/update-emulator.sh --dev` |
| 只更新课表脚本 | `scripts/update-emulator.sh --modules-only --module app.schedule` |
| 只更新拾光脚本 | `scripts/update-emulator.sh --modules-only --module app.import.shiguang` |
| Release 验收 | `scripts/update-emulator.sh` |

脚本按改动选择测试，自动复用有效缓存，覆盖安装后核对版本和摘要，保留应用数据。提交指定文件、设备参数、权限审核和失败处理统一见 [模拟器更新流程](docs/EMULATOR_UPDATE.md)。

## 检查与模块打包

```bash
source scripts/dev-env.sh
python3 scripts/module_host/check_architecture.py
python3 -m unittest discover -s scripts/tests -v
cd client
flutter analyze --no-pub
flutter test --no-pub --concurrency=2
```

按功能选择相关测试；涉及数据、生命周期、权限和依赖时扩大回归范围。网络冒烟另可运行 `dart test/openai_compatible_provider_network_smoke.dart`。测试结果和平台范围见 [验证记录](docs/VERIFICATION.md)，Widget 测试不代表真机帧率。

独立模块打包使用 `python3 scripts/module_host/build_packages.py`，输出到 `dist/modules/`。修改内容时提升 `module.json` 版本。仅需改变首次安装资源时加 `--defaults`，审阅 `client/assets/modules/catalog.json` 及资源差异，再重建 APK；该资源更新不会自动升级用户已安装的模块。目录发布使用 [作者发布流程](docs/MODULE_CATALOG.md)。

## 客户端构建与分享

在 `client/` 执行：

```bash
flutter build apk --release --split-per-abi --no-pub
```

输出在 `client/build/app/outputs/flutter-apk/`，多数手机使用 ARM64 包。覆盖已有应用时，构建号与 ABI 偏移后的 Android versionCode 必须满足设备版本要求，并保持签名一致；模拟器脚本自动处理构建号。当前 release 使用 debug 签名，正式发布签名仍待配置。

临时下载从仓库根目录运行 `scripts/share-apk.sh`；调试包用 `--debug`。需要 `python3` 与 `cloudflared`，默认端口 8765，可设置 `APK_SHARE_PORT`。终端打印 HTTPS 地址，按 `Ctrl+C` 关闭；重启隧道会更换域名，持有地址的人可下载当前 APK。SSH 长会话可用 `screen` 保持服务。

## 数据库生成

数据库为 `xudian_v9.sqlite`，Drift schema 为 **2**，schema 1 升级会先备份并执行旧数据迁移。修改表定义后进入 `client/` 运行：

```bash
dart run build_runner build
```

生成绑定代码同时审阅迁移、备份及数据恢复测试。迁移细节统一见 [模块宿主](docs/MODULE_HOST.md#迁移更新和恢复)。

## Windows 桌面

在 Windows 安装兼容的 Flutter、Visual Studio C++ 桌面开发组件及 Windows SDK，通过 `flutter doctor -v` 后进入 `client/`：

```powershell
flutter pub get
flutter build windows --release
```

生成的程序和依赖资源须一起分发。安装包制作、系统凭据、导入、键盘和窗口缩放需在 Windows 验证。历史环境版本、远程验收及性能说明见 [开发记录归档](docs/archive/DEVELOPMENT_20261009.md)。
