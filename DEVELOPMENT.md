# 开发环境

本项目已使用 Flutter 开发 Android 和 Windows 客户端，云端计划采用 Node.js/TypeScript，尚无服务端工程。当前工作机是 Debian Linux，可在这里开发和测试共享 Dart 代码、生成 Android APK；Windows 构建、平台验证和安装包制作需在 Windows 主机完成。

## 已配置的工具

- Flutter stable 3.47.5 / Dart 3.13.4，放在 `.tools/flutter`（本地 SDK，不提交）。
- OpenJDK 21。
- Android SDK 命令行工具 19.0、Android 36 平台、Build Tools 36.0.0、Platform Tools 和 NDK 28.2.13676358，放在 `.tools/android-sdk`（不提交）。
- Node.js 24、npm 11、Git 和 Docker 已由工作机提供。

新终端先运行：

```bash
source scripts/dev-env.sh
flutter doctor -v
```

`scripts/dev-env.sh` 设置 Flutter、Android SDK、Java、Pub、Gradle 和 XDG 路径，并关闭 Flutter/Dart 分析数据发送。项目依赖缓存放在 `.cache/`，SDK 放在 `.tools/`，不会进入版本控制。命令应使用该脚本提供的 SDK，避免使用其他全局 Flutter 环境。

客户端工程位于 `client/`。从项目根目录验证并构建 Android 调试包：

```bash
source scripts/dev-env.sh
cd client
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

调试包输出到 `client/build/app/outputs/flutter-apk/app-debug.apk`。首次构建会下载 Gradle 和 Android 依赖。

`--no-pub` 适用于已完成 `flutter pub get` 的环境；修改 `pubspec.yaml` 后先更新依赖。当前工程没有 Linux 桌面运行目标；`flutter run` 需要可用的 Android 设备/模拟器，或在 Windows 主机连接 Windows 桌面目标。

## 当前验证基线

- 2026-10-03 查询与字段一致性优化：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 84 项全部通过（本轮新增 12 项），Android release 分架构 APK 构建通过。验证包含 SQL/Dart 过滤语义一致性、1 万条额外任务下的按需返回行数与单次查询、字段/模块启停订阅刷新、跨日/恢复前台与订阅释放、字段类型/权限校验、批量回滚、模板失败事件抑制和规则循环保护。此数据规模用例验证查询行为，不代表真机耗时或帧率基准；Windows 与真机运行尚未验证。

- 2026-10-02 任务操作与模块恢复优化后：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 72 项全部通过（新增 10 项），Android release 分架构 APK 构建通过。新增覆盖项目任务创建/归属、手机与桌面尺寸下的基础编辑与日期清除、校验/取消/无改动保存、重复提交与草稿保留、依赖顺序/循环/失败隔离及恢复提示。
- 2026-09-30 底栏改版后：当前 Linux 工作区运行 `flutter test --no-pub`，51 项测试全部通过；`flutter analyze --no-pub` 无问题。
- 此前已验证 Android release 分架构 APK 可构建；本次底栏改版通过 Flutter 调试连接更新手机，未重新构建 APK。
- 本机 Flutter 测试不替代 Windows 构建、安全存储、安装、键盘/缩放行为和 Android 真机验证。

## 通过 SSH 远程预览 Android

VPS 负责构建与 Dart 编译，手机通过 USB 连接身边的 Windows/Mac/Linux 电脑；电脑负责 ADB 和 SSH 隧道。电脑无需安装 Flutter，只需 Android SDK Platform-Tools 与 SSH 客户端。无线调试也可先在电脑完成配对，再复用此流程。

APK 使用独立 HTTPS 链接下载，在手机或手机旁电脑安装。VPS 使用 `flutter attach` 连接已安装的调试版；预览脚本不执行 `flutter run`、远程 `adb install` 或 APK push，避免 APK 大文件占用 SSH 调试隧道。SSH 仅转发 ADB 控制与 VM Service；Dart 编译结果和热重载增量仍通过调试连接传输。

### 1. 构建、下载与安装调试版

当前手机已安装 arm64 release 包，versionCode 为 2001。通过浏览器覆盖安装时，新包版本号不能低于已安装版本。以下为当前可用示例；后续需按实际安装版本调整 build-number：

```bash
source scripts/dev-env.sh
cd client
flutter build apk --debug --target-platform android-arm64 --build-number=2002 --no-pub
cd ..
bash scripts/share-apk.sh --debug
```

分享脚本提供 `client/build/app/outputs/flutter-apk/app-debug.apk` 的临时 HTTPS 链接。使用手机浏览器下载、确认安装并打开“序点”，或在手机旁电脑下载后，使用该电脑自己的 ADB 经 USB 安装：

```powershell
.\adb.exe -s DEVICE_SERIAL install -r C:\下载目录\xudian.apk
```

此命令仅在手机旁电脑运行，APK 从该电脑通过 USB 传输。不要从 VPS 的远程 ADB 执行 install/push。覆盖更新需签名一致；签名冲突时先核对 debug keystore，不自动卸载或清除数据。只有 debug 包支持此热重载流程，release 包即使使用 debug 签名也无法热重载。

### 2. 手机旁电脑建立调试隧道

安装与 VPS 兼容的新版 Platform-Tools（当前 VPS 为 37.0.1 / ADB 1.0.41），启用手机 USB 调试并确认授权。在 Windows PowerShell 中执行，路径以实际 adb.exe 所在目录为准：

```powershell
cd C:\platform-tools
.\adb.exe start-server
.\adb.exe devices -l
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 127.0.0.1:15037:127.0.0.1:5037 -R 127.0.0.1:8181:127.0.0.1:8181 用户名@VPS地址
```

Mac/Linux 使用对应平台的 `adb`。将 SSH 目标替换为实际地址，非默认 SSH 端口加 `-p 端口`。手机状态应为 `device`；`unauthorized` 需手机授权，列表为空时检查连接。若找不到 ssh，在 Windows 可选功能安装 OpenSSH 客户端。

保持 SSH 终端运行，两个转发绑定 VPS loopback，无需公网开放 ADB/调试端口。SSH 服务需允许反向转发，保持 `GatewayPorts no`；两端相关端口需空闲。

| VPS 端口 | 电脑端目标 | 用途 |
| --- | --- | --- |
| `127.0.0.1:15037` | `127.0.0.1:5037` | 远程 ADB 控制 |
| `127.0.0.1:8181` | `127.0.0.1:8181` | Dart VM Service 与热重载 |

### 3. VPS 连接已安装的应用

从项目根目录启动，替换 DEVICE_SERIAL：

```bash
bash scripts/preview-android.sh DEVICE_SERIAL
```

脚本默认使用 ADB 15037、VM Service 8181，并执行：

```bash
flutter attach --debug -d DEVICE_SERIAL --app-id=dev.taskapp.task_app --no-dds --host-vmservice-port=8181
```

若尚未打开应用，attach 会等待；在手机打开刚安装的调试版。使用 `--no-dds` 关闭 DDS，确保底层 VM Service 使用固定端口。当前 Flutter 的旧参数 `--disable-dds` 未让端口选择逻辑关闭 DDS，会产生随机转发端口，应使用 `--no-dds`。

保持 SSH 隧道、手机连接及 attach 会话。保存 Dart 修改后，在 Flutter 终端按 `r` 热重载、`R` 热重启、`q` 退出；命令行模式不会自动在保存时刷新。新会话可能先传输初始 Dart 编译结果，后续传输增量。原生代码、插件、依赖或打包资源变化需重新构建并通过 HTTPS 下载更新 APK，随后重新 attach。

如果能列出设备但一直等待调试服务，检查是否安装并打开 debug 包，以及 8181 转发与 `--no-dds`。隧道或手机断开后恢复连接并重启 attach。脚本支持 `XUDIAN_ADB_PORT` 与 `XUDIAN_VM_SERVICE_PORT`，WSL 配置见 [VPS 与 WSL 开发配置](docs/MULTI_MACHINE_DEVELOPMENT.md)。

2026-09-30 已验证：PHY120 通过 15037 连接；独立 HTTPS 下载并安装 debug 版本 2002；`flutter attach --no-dds` 经固定 8181 连接成功，初始 Dart 同步约 22 秒。执行无源码变更的 `r` 热重载成功，耗时约 2.2 秒（0 libraries，完成 reassemble）。这验证了调试连接与重组流程；后续实际代码变更的传输耗时取决于增量大小和网络。

## 手机临时下载 APK

构建体积较小的 Android release 分架构包：

```bash
source scripts/dev-env.sh
cd client
flutter build apk --release --split-per-abi --no-pub
cd ..
```

大多数 Android 手机可使用 `app-arm64-v8a-release.apk`。从项目根目录运行 `scripts/share-apk.sh`，脚本会打印完整的临时 HTTPS 下载地址；用手机浏览器打开即可。脚本需要 PATH 中有 `python3` 与 `cloudflared`，默认使用本地端口 8765，可通过 `APK_SHARE_PORT` 更改。保持脚本运行，下载完按 `Ctrl+C`，临时服务会自动关闭。此方式使用 Cloudflare Quick Tunnel，持有链接的人可以下载 APK；隧道需能从服务器访问 Cloudflare，且没有长期可用性保证。

脚本仅提供 `/xudian.apk`，每次请求都会读取当前构建输出，并发送禁止缓存的响应。保持脚本和隧道运行时，重新构建 APK 后原链接即会下载新版。构建过程中若目标文件暂时不可用，请等构建完成后重试。Cloudflare Quick Tunnel 重启后会生成新域名；若要服务器重启后仍保持同一链接，需要自有域名与固定隧道或其他固定托管地址。

通过 SSH 操作时，建议在 `screen` 中启动，断线后可恢复到原来的输出：

```bash
cd /opt/my_app
screen -S xudian-apk scripts/share-apk.sh
```

按 `Ctrl+A`、再按 `D` 可主动离开而不中断下载。SSH 重连后运行 `screen -D -r xudian-apk` 返回脚本界面；运行 `screen -ls` 可检查会话是否仍在。下载完成后在 `screen` 中按 `Ctrl+C` 关闭分享。如果最初未使用 `screen`，旧终端界面无法恢复，重新运行上述启动命令即可生成新的链接。

当前 release 构建仍使用 Android debug 密钥签名，仅供侧载试用，正式发布前须配置独立的发布签名。

## 数据库与代码生成

当前数据库在应用支持目录保存为 `xudian_v9.sqlite`，Drift `schemaVersion` 为 1；v9 是文件名的一部分，不是迁移版本。当前不导入旧数据库，AI API Key 由系统安全存储保存。

修改 `client/lib/data/app_database.dart` 中的 Drift 表后，在加载开发环境并进入 `client/` 后运行：

```bash
dart run build_runner build
```

这会更新 `lib/data/app_database.g.dart`。修改已有表结构时还需增加数据库版本和迁移，并验证已有数据升级；不能只重新生成绑定代码。后续正式版本的数据迁移前需制定备份与恢复方案。

## 在新 Linux 工作机上重建

安装 Git、curl、unzip、Java 21 后，将 Flutter stable 克隆到 `.tools/flutter`。Android 命令行工具安装到 `.tools/android-sdk/cmdline-tools/latest`，使用 `sdkmanager --licenses` 接受许可证，再安装 `platform-tools`、`platforms;android-36`、`build-tools;36.0.0` 和 `ndk;28.2.13676358`。最后运行上面的环境脚本和 `flutter doctor -v`。Flutter 版本以项目的实际兼容性检查为准，升级时同时更新本文档。

## Windows 构建

Windows 上需要单独安装与项目兼容的 Flutter、Visual Studio 的 C++ 桌面开发组件以及 Windows SDK，然后运行 `flutter doctor -v`。项目的 `scripts/dev-env.sh` 是 Linux 环境脚本，Windows 使用自己的 SDK 配置。

在 Windows 主机进入 `client/` 后运行：

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release
```

构建后应同时分发生成的可执行文件及其依赖资源；当前工程尚未定义安装包流程。Windows 安全凭据、文件导入、键盘操作与窗口缩放需在真实 Windows 环境验证，Linux 不能直接验证 Windows 安装包。
