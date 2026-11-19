# Android 开发环境

按开发位置选择 [纯 Windows](#纯-windowsandroid-studio-与模拟器)、[WSL 原生 ADB](#wsl-原生-adb连接与安装-apk)或 [VPS 远程预览](#vps-远程预览)。日常本机模拟器以 [一键更新](EMULATOR_UPDATE.md) 为入口。

## 纯 Windows：Android Studio 与模拟器

Windows 负责本地 Flutter 编译和模拟器运行。客户端位于 `client/`，启动入口为 `lib/main.dart`。WSL 开发配合 Windows 模拟器时，使用本文的 WSL 原生 ADB 流程。

### 1. 安装开发工具

安装 [Git for Windows](https://git-scm.com/downloads/win) 和 [Flutter SDK](https://docs.flutter.dev/install)。当前项目验证版本为 Flutter stable **3.47.5 / Dart 3.13.4**，建议从 [Flutter SDK 归档](https://docs.flutter.dev/install/archive) 安装相同 Windows 版本；Dart 随 Flutter 提供。`client/pubspec.yaml` 要求 Dart `^3.13.4`。

将 Flutter SDK 解压到例如 `C:\dev\flutter`，在 Windows 用户环境变量 `Path` 中添加 `C:\dev\flutter\bin`。重新打开 PowerShell，运行：

```powershell
git --version
flutter --version
flutter doctor -v
```

Android Studio 中完成以下配置：

1. **Settings → Plugins → Marketplace** 安装 Flutter 插件，并按提示安装 Dart 插件，然后重启 IDE。
2. **SDK Manager → SDK Platforms** 安装 Android API 36 平台。
3. **SDK Manager → SDK Tools** 安装 Android SDK Command-line Tools、Platform-Tools、Android Emulator 和 Build-Tools 36.0.0。项目使用 NDK 28.2.13676358，首次构建可能自动下载；也可勾选 **Show Package Details** 后在 NDK (Side by side) 中选择该版本。
4. **Settings → Languages & Frameworks → Flutter** 指定 Flutter SDK 路径，例如 `C:\dev\flutter`。

在 PowerShell 接受 Android SDK 许可证并检查环境：

```powershell
flutter doctor --android-licenses
flutter doctor -v
```

Android toolchain 和 Android Studio 应通过检查。Flutter 通常使用 Android Studio 自带的 JDK，具体路径以 `flutter doctor -v` 为准；当前 VPS 使用 Java 21。仅调试 Android 时，`flutter doctor` 中缺少 Visual Studio 的提示不影响本流程；Windows 桌面构建另见 [开发环境](../DEVELOPMENT.md#windows-桌面)。

如果 Flutter 未识别 Android SDK，先在 SDK Manager 查明 SDK 安装位置，再指定实际路径，例如：

```powershell
flutter config --android-sdk "$env:LOCALAPPDATA\Android\Sdk"
flutter doctor -v
```

### 2. 克隆并打开客户端

首次下载源码，在 PowerShell 中运行：

```powershell
New-Item -ItemType Directory -Force C:\dev
cd C:\dev
git clone https://github.com/JayConstruct/xudian.git
cd .\xudian\client
flutter pub get
```

私有仓库按 Git 的提示完成 GitHub 登录。VPS 上配置的 SSH 密钥只负责 VPS 的认证；Windows 使用 HTTPS 登录，或另行配置自己的 SSH 密钥后使用 SSH 地址克隆。

Android Studio 选择 **Open**，打开 `C:\dev\xudian\client`（包含 `pubspec.yaml`）。如果克隆到其他位置，使用对应路径。项目的 `scripts/dev-env.sh` 配置 Linux SDK 和缓存；Windows 使用本机安装的 SDK，不执行该脚本。

### 3. 创建并启动模拟器

Android Studio 打开 **Device Manager → Create Device**：

1. 选择一个 Pixel 手机配置。
2. 选择 Android API 36 系统镜像；Intel/AMD Windows 电脑通常选择 x86_64 镜像，其他架构按 Device Manager 推荐选择。
3. 完成创建并点击启动，等待模拟器进入 Android 桌面。

在 `client/` 目录的 PowerShell 或 Android Studio Terminal 中确认设备：

```powershell
flutter devices
```

应看到 Android 模拟器，例如 `emulator-5554`。如果无法启动模拟器，按 Device Manager 的诊断提示检查 BIOS/UEFI 中的 CPU 虚拟化和 Windows Hypervisor Platform 配置；系统设置变化后可能需要重启电脑。

### 4. 运行、断点与热重载

Android Studio 顶部选择模拟器和 `lib/main.dart` 启动配置，点击 **Debug**。首次构建需要下载 Gradle、Android 依赖和可能缺少的 NDK，耗时通常比后续构建长。启动后可设置断点、查看变量和调试日志。

修改 Dart 文件并保存后，点击 **Hot Reload**（闪电图标）；需要重新执行应用初始化时点击 **Hot Restart**。原生代码或插件依赖变化后，应停止并重新运行应用；依赖变化时先执行 `flutter pub get`。

也可使用命令行启动，将设备 ID 替换为 `flutter devices` 输出的实际值：

```powershell
flutter run -d emulator-5554
```

命令行运行时按 `r` 热重载、`R` 热重启、`q` 退出。只有通过 IDE 的 Debug 或 `flutter run` 启动的 debug 版本支持这一调试流程。

## WSL 与 VPS 的工具和端口

### Linux 工具链

- 新 WSL 工作区可在配置 SSH 认证后执行 `git clone git@github.com:JayConstruct/xudian.git ~/projects/xudian`，也可使用 HTTPS 地址克隆。
- VPS 可继续使用 `/opt/my_app`；WSL 推荐 `~/projects/xudian`，将源码放在 WSL 的 Linux 文件系统，避免在 `/mnt/c` 上构建。
- 两端各自安装 Linux Flutter 3.47.5 / Dart 3.13.4、Java 21 和 Android SDK，布局沿用 `.tools/flutter` 与 `.tools/android-sdk`。`scripts/dev-env.sh` 根据自身位置计算项目根目录，不要求 WSL 使用 `/opt/my_app`；默认 Java 路径需在 WSL 存在或按实际安装调整。
- 保持 SDK 与 `client/pubspec.lock` 一致。两端各自执行 `flutter pub get`；`.tools/`、`.cache/`、`client/build/`、`.dart_tool/` 和 `client/android/local.properties` 保持本机生成，不在机器之间复制或共享。
- Android 调试安装使用相同的应用 ID。VPS 与 WSL 应使用同一开发用 debug keystore，并在私有渠道复制到各自的标准位置（通常为 `~/.android/debug.keystore`，若自定义 Android 用户目录则按实际位置配置）。不同签名无法覆盖已安装应用，卸载会清除应用数据；不要为切换开发机自动卸载。开发签名文件不进入源码仓库，正式发布签名单独管理。

### 手机连接与端口分配

Windows 安装新版 Platform-Tools，与 Linux SDK 的 ADB 协议保持兼容，并保持 Android Studio 的模拟器及其 ADB server 运行。从 WSL 查询设备、安装、启动和读取日志统一使用 Linux 版 `adb`，不通过 PowerShell、`cmd.exe` 或 `adb.exe` 调用 Windows ADB 客户端；Windows 只负责运行模拟器和 ADB server。连接 USB 手机时需在手机上确认调试授权，设备状态应为 `device`。

| 开发端 | 访问的 ADB 地址 | Flutter VM 端口 | 连接方式 |
| --- | --- | --- | --- |
| VPS | VPS `127.0.0.1:15037` → Windows `127.0.0.1:5037` | VPS 8181 → Windows 8181 | Windows 发起 SSH 反向转发 |
| WSL localhost 直连 | Windows `127.0.0.1:5037` | Windows 8182 | Linux ADB 通过 localhost 访问 Windows ADB server |
| WSL 使用 SSH 桥接 | WSL `127.0.0.1:5038` → Windows `127.0.0.1:5037` | WSL 8182 → Windows 8182 | Windows 发起到 WSL sshd 的反向转发 |

VM Service 转发由 Windows 的 ADB server 创建，因此不同开发端使用不同 VM 端口；只转发 ADB 端口不足以提供热重载。两个 SSH 隧道可同时存在，手机上的同一应用仍应依次调试。

## WSL 原生 ADB：连接与安装 APK

在当前工作区的 WSL 终端执行：

```bash
cd /path/to/my_app
source scripts/dev-env.sh
command -v adb
adb version
export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037
adb devices -l
```

环境脚本选择项目内 Linux SDK 的 `adb`，以 `command -v adb` 为准；WSL 不改用 Windows 的 `adb.exe`。`export` 仅对当前终端及其子进程生效，新终端需重新执行。临时指定服务地址也可使用 `adb -H 127.0.0.1 -P 5037 devices -l`。

准备好 APK 后，在 WSL 使用 Linux 路径安装、启动并查询应用：

```bash
adb -s emulator-5554 install -r client/build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell am start -W -n dev.taskapp.task_app/dev.taskapp.task_app.MainActivity
adb -s emulator-5554 shell pm path dev.taskapp.task_app
```

设备 ID 以 `adb devices -l` 为准。APK 若位于 Windows 磁盘，仍使用 WSL 路径，例如 `adb -s emulator-5554 install -r "/mnt/d/下载/序点.apk"`，不使用 `D:\...` 路径。当前模拟器为 x86_64，应选包含 x86_64 的调试包或对应 release 包，不要默认选择只含 arm64 的包。覆盖安装若报签名不一致，不要自动卸载应用，以免丢失数据。

先检查 localhost 连接，成功时无需修改网络配置或重启 WSL。若 Codex 沙箱阻止网络访问，应申请在沙箱外执行同一条 Linux ADB 命令，不回退为调用 Windows ADB 客户端。

### WSL 2 调试：镜像网络配置（连接失败时）

只有 localhost 直连失败并确认需要调整网络时，再考虑以下配置；当前连接成功不等于已核实当前网络模式。Windows 11 22H2 或更新版本及支持镜像网络的新版 WSL 可采用此方式。先在 PowerShell 执行 `wsl --update`，编辑 Windows 用户目录下的 `.wslconfig`（保留已有设置，在对应节中添加）：

```ini
[wsl2]
networkingMode=mirrored
```

保存 WSL 中的工作并停止运行的服务后，在 PowerShell 执行 `wsl --shutdown`，再进入 WSL；该命令会停止所有 WSL 发行版。镜像模式允许 WSL 经 `127.0.0.1` 访问 Windows 服务，详见 [Microsoft WSL 网络说明](https://learn.microsoft.com/windows/wsl/networking#mirrored-mode-networking)。

Windows 上保持 ADB server 与 USB 手机连接。WSL 中检查连接：

```bash
cd ~/projects/xudian
source scripts/dev-env.sh
export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037
adb devices -l
```

如果显示手机，使用 WSL 端口配置启动：

```bash
XUDIAN_ADB_PORT=5037 XUDIAN_VM_SERVICE_PORT=8182 bash scripts/preview-android.sh DEVICE_SERIAL
```

WSL 自身应使用 Linux 版 SDK/adb，USB 由 Windows 的 ADB server 管理，无需将 USB 设备附加到 WSL。连接失败时核对 WSL 版本、镜像模式、Windows ADB server 和本机防火墙；不要仅把 Windows NAT 地址填入脚本，因为 Windows ADB 默认只监听 loopback。

### WSL 调试：SSH 桥接备选

Windows 10 或无法使用镜像网络时，可以让 WSL 运行 OpenSSH server，再从 Windows 连接。该方案需用户在 WSL 安装/启用 sshd、设置 SSH 登录并确认 Windows 能访问它；这些系统配置尚未在本工作区执行。

在确认 Windows 能登录 WSL 后，Windows PowerShell 执行（替换 WSL 的用户名、地址与 sshd 端口）：

```powershell
ssh -N -p WSL_SSH_PORT -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 127.0.0.1:5038:127.0.0.1:5037 -R 127.0.0.1:8182:127.0.0.1:8182 WSL用户名@WSL地址
```

WSL 执行：

```bash
cd ~/projects/xudian
XUDIAN_ADB_PORT=5038 XUDIAN_VM_SERVICE_PORT=8182 bash scripts/preview-android.sh DEVICE_SERIAL
```

WSL 2 的 NAT 地址可能在重启后变化；使用实际可达的 SSH 地址。隧道绑定 loopback，SSH 服务需允许反向转发，保持 `GatewayPorts no`。Windows 同时负责 VPS 和 WSL 隧道，不需在公网开放 ADB 或 VM Service。

## VPS 远程预览

环境准备见 [开发指南](../DEVELOPMENT.md)，临时下载参数见下方 [APK 分享](#临时-apk-分享)。本流程用于 VPS 与身边电脑/手机之间的调试连接；本机模拟器优先使用 [一键更新](EMULATOR_UPDATE.md)。

VPS 负责构建与 Dart 编译，手机通过 USB 连接身边的 Windows/Mac/Linux 电脑；电脑负责 ADB 和 SSH 隧道。电脑无需安装 Flutter，只需 Android SDK Platform-Tools 与 SSH 客户端。无线调试也可先在电脑完成配对，再复用此流程。

APK 使用独立 HTTPS 链接下载，在手机或手机旁电脑安装。VPS 使用 `flutter attach` 连接已安装的调试版；预览脚本不执行 `flutter run`、远程 `adb install` 或 APK push，避免 APK 大文件占用 SSH 调试隧道。SSH 仅转发 ADB 控制与 VM Service；Dart 编译结果和热重载增量仍通过调试连接传输。

### 1. 构建、下载与安装调试版

先查询手机已有 versionCode，再选择覆盖安装所需构建号。将下方 BUILD_NUMBER 替换为满足设备版本要求的整数，保持签名一致：

```bash
source scripts/dev-env.sh
cd client
flutter build apk --debug --target-platform android-arm64 --build-number=BUILD_NUMBER --no-pub
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

如果能列出设备但一直等待调试服务，检查是否安装并打开 debug 包，以及 8181 转发与 `--no-dds`。隧道或手机断开后恢复连接并重启 attach。脚本支持 `XUDIAN_ADB_PORT` 与 `XUDIAN_VM_SERVICE_PORT`，WSL 配置见 [WSL 原生 ADB](#wsl-原生-adb连接与安装-apk)。

## 临时 APK 分享

在项目根目录运行 `scripts/share-apk.sh`，调试包加 `--debug`。需要 `python3` 与 `cloudflared`；默认端口 8765，可通过 `APK_SHARE_PORT` 修改。终端打印 HTTPS 地址，按 `Ctrl+C` 关闭；重启隧道会更换域名，持有地址的人可下载当前 APK。SSH 长会话可用 `screen` 保持服务。

## 源码同步与检查

VPS、WSL 和 Windows 各自保有源码与 SDK。用 `git remote -v` 和 `git branch -vv` 确认远端及工作分支。切换前提交并推送，另一端用 `git pull --ff-only`。有本地改动先处理，分叉时先检查历史。并行开发使用独立分支。依赖变更后在各自的 `client/` 运行 `flutter pub get`，检查命令见 [开发指南](../DEVELOPMENT.md#常用检查与构建)。

Windows 的 Shell／普通文本按仓库 `.gitattributes` 使用 LF，`.bat` 和 `.cmd` 检出为 CRLF，二进制资产保持原字节。

## 切换开发端

1. 当前 Flutter 终端按 `q`，结束调试；隧道可保留，切换前确保应用在手机上运行。
2. 按[源码同步与检查](#源码同步与检查)切换工作区。
3. 确认另一端的连接配置与签名/插件/SDK 一致，再运行对应 attach 预览命令。VPS 需要更新 APK 时用 HTTPS 下载，在手机旁安装；WSL 本地更新使用 Linux `adb install -r`，保持应用数据。
4. 修改 Dart 文件并保存，在该端 Flutter 终端按 `r` 热重载，`R` 热重启。attach 不构建或安装 APK，首次连接可能传输 Dart 编译结果，连续编辑期间使用增量热重载。

并行调试需要不同设备/模拟器，或不同应用 ID 的开发 flavor；当前项目未配置独立 flavor。同一应用的热重载只使用当前会话编译的源码，无法将两个工作区的修改自动合并到手机。

日常模拟器构建、模块导入及热重载优先使用 [更新脚本](EMULATOR_UPDATE.md)。
