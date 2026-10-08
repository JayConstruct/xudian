# VPS 与 WSL 开发配置

源码已推送到 [JayConstruct/xudian](https://github.com/JayConstruct/xudian)，主分支为 `main`。Windows 11 本地使用 Android Studio 模拟器时，先按 [Windows 模拟器调试指南](WINDOWS_ANDROID_DEVELOPMENT.md) 创建并启动模拟器；本文介绍 WSL 原生 ADB 连接、APK 安装，以及 VPS/WSL 共用身边手机的远程调试方式。

当前使用 Windows 电脑通过 USB 连接 Android 手机。建议 VPS 与 WSL 各有一份源码和 Linux SDK，通过 Git 交换修改，Windows 提供同一个 ADB server。两端都能运行 Flutter，但同一手机上的同一应用一次由一个 `flutter attach` 会话控制。

2026-09-30 VPS 已通过 ADB 15037 与 VM Service 8181 转发连接手机 PHY120，attach 与无源码变更的热重载已验证；Windows/WSL 互切仍待验证。固定端口连接使用 `--no-dds`。APK 通过独立 HTTPS 下载并在手机旁安装，VPS 只使用 flutter attach，不经 SSH 传输 APK。单机远程调试基础见 [开发环境](../DEVELOPMENT.md#通过-ssh-远程预览-android)。

2026-10-04 已在当前 WSL 工作区验证：Linux ADB 37.0.1 经 `127.0.0.1:5037` 连接 Windows ADB server，`adb devices -l` 显示 `emulator-5554`（x86_64，状态 `device`），`adb shell pm path dev.taskapp.task_app` 能查询已安装的序点。此记录只验证原生 ADB 连接和包查询，不代表当前源码构建、WSL 原生安装或 Flutter 热重载已验证。

## 源码与工具

- VPS 已配置 SSH 远端 `origin` 为 `git@github.com:JayConstruct/xudian.git`，本地 `main` 跟踪 `origin/main`。新 WSL 工作区可执行 `git clone git@github.com:JayConstruct/xudian.git ~/projects/xudian`，需在 WSL 单独配置 SSH 认证；也可使用 HTTPS 地址克隆。切换机器前 commit/push，另一端 `git pull --ff-only`；同时开发时使用独立分支，通过 merge 或 cherry-pick 合并。
- VPS 可继续使用 `/opt/my_app`；WSL 推荐 `~/projects/xudian`，将源码放在 WSL 的 Linux 文件系统，避免在 `/mnt/c` 上构建。
- 两端各自安装 Linux Flutter 3.47.5 / Dart 3.13.4、Java 21 和 Android SDK，布局沿用 `.tools/flutter` 与 `.tools/android-sdk`。`scripts/dev-env.sh` 根据自身位置计算项目根目录，不要求 WSL 使用 `/opt/my_app`；默认 Java 路径需在 WSL 存在或按实际安装调整。
- 保持 SDK 与 `client/pubspec.lock` 一致。两端各自执行 `flutter pub get`；`.tools/`、`.cache/`、`client/build/`、`.dart_tool/` 和 `client/android/local.properties` 保持本机生成，不在机器之间复制或共享。
- Android 调试安装使用相同的应用 ID。VPS 与 WSL 应使用同一开发用 debug keystore，并在私有渠道复制到各自的标准位置（通常为 `~/.android/debug.keystore`，若自定义 Android 用户目录则按实际位置配置）。不同签名无法覆盖已安装应用，卸载会清除应用数据；不要为切换开发机自动卸载。开发签名文件不进入源码仓库，正式发布签名单独管理。

## 手机连接与端口分配

Windows 安装新版 Platform-Tools，与 Linux SDK 的 ADB 协议保持兼容，并保持 Android Studio 的模拟器及其 ADB server 运行。当前 WSL 的设备查询、安装、启动和日志操作统一使用 Linux 版 `adb`，不通过 PowerShell、`cmd.exe` 或 `adb.exe` 调用 Windows ADB 客户端；Windows 只负责运行模拟器和 ADB server。连接 USB 手机时需在手机上确认调试授权，设备状态应为 `device`。

| 开发端 | 访问的 ADB 地址 | Flutter VM 端口 | 连接方式 |
| --- | --- | --- | --- |
| VPS | VPS `127.0.0.1:15037` → Windows `127.0.0.1:5037` | VPS 8181 → Windows 8181 | Windows 发起 SSH 反向转发 |
| WSL localhost 直连（当前已验证） | Windows `127.0.0.1:5037` | Windows 8182 | Linux ADB 通过 localhost 访问 Windows ADB server |
| WSL 使用 SSH 桥接 | WSL `127.0.0.1:5038` → Windows `127.0.0.1:5037` | WSL 8182 → Windows 8182 | Windows 发起到 WSL sshd 的反向转发 |

VM Service 转发由 Windows 的 ADB server 创建，因此不同开发端使用不同 VM 端口；只转发 ADB 端口不足以提供热重载。两个 SSH 隧道可同时存在，手机上的同一应用仍应依次调试。

## VPS 调试

在 Windows PowerShell 建立隧道（替换 SSH 目标，非默认 SSH 端口加 `-p 端口`）：

```powershell
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 127.0.0.1:15037:127.0.0.1:5037 -R 127.0.0.1:8181:127.0.0.1:8181 用户名@VPS地址
```

先按开发环境说明构建 debug 包并通过 HTTPS 下载、在手机旁安装和打开。VPS 执行以下命令连接应用，替换 `DEVICE_SERIAL`：

```bash
cd /opt/my_app
bash scripts/preview-android.sh DEVICE_SERIAL
```

## WSL 原生 ADB：连接与安装 APK

在当前工作区的 WSL 终端执行：

```bash
cd /home/jerry/my_app
command -v adb
adb version
export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037
adb devices -l
```

当前 `adb` 为 `/home/jerry/.local/bin/adb`，指向 Linux SDK 的 `/home/jerry/Android/Sdk/platform-tools/adb`；不要改用 Windows 的 `adb.exe`。`export` 仅对当前终端及其子进程生效，新终端需重新执行；本次没有修改用户的 Shell 配置。临时指定服务地址也可使用 `adb -H 127.0.0.1 -P 5037 devices -l`。

准备好 APK 后，在 WSL 使用 Linux 路径安装、启动并查询应用：

```bash
adb -s emulator-5554 install -r client/build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell am start -W -n dev.taskapp.task_app/dev.taskapp.task_app.MainActivity
adb -s emulator-5554 shell pm path dev.taskapp.task_app
```

设备 ID 以 `adb devices -l` 为准。APK 若位于 Windows 磁盘，仍使用 WSL 路径，例如 `adb -s emulator-5554 install -r "/mnt/d/下载/序点.apk"`，不使用 `D:\...` 路径。当前模拟器为 x86_64，应选包含 x86_64 的调试包或对应 release 包，不要默认选择只含 arm64 的包。覆盖安装若报签名不一致，不要自动卸载应用，以免丢失数据。

截至 2026-10-04，当前 WSL 工作区没有项目构建出的 APK，也未找到 Flutter SDK。模拟器中已安装并启动的是 Windows 下载目录内 2026-09-29 的序点调试包，不是当前源码的新构建；该次安装使用 Windows ADB，后续安装统一改用上述 WSL 原生 ADB 命令。重新构建前需先配置本机 Linux Flutter、Android SDK 与 Java；`scripts/dev-env.sh` 中的项目内 SDK 路径不能视为当前 WSL 已安装的工具。

2026-10-06 更新：项目内 Flutter／Android SDK 已配置，`source scripts/dev-env.sh` 可使用。已由当前源码构建 x86_64 调试 APK，并通过 Linux ADB 覆盖安装、打开 `emulator-5554` 检查全局助手及紧凑布局编辑器；保留应用数据，未调用真实模型服务。上段记录仅描述10月4日当时状态，不再代表当前 SDK 或安装来源。

2026-10-08 UI 示例更新：使用 `flutter build apk --release --target-platform android-x64 --build-number=27 --no-pub` 构建客户端；与已安装 APK 核对签名一致后，通过 Linux ADB 覆盖安装至 `emulator-5554`（versionCode 26 → 27）。模块管理中已将 `app.ui.examples` 更新至 1.1.0 并启用，验证新版 17 个示例正常显示及日期确认／取消／清除。原有应用数据保留；后续覆盖安装的 build-number 应不低于设备已安装版本。

当前 localhost 连接已验证可用，无需为此修改网络配置或重启 WSL。若 Codex 沙箱阻止网络访问，应申请在沙箱外执行同一条 Linux ADB 命令，不回退为调用 Windows ADB 客户端。

## WSL 2 调试：镜像网络配置（连接失败时）

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

## WSL 调试：SSH 桥接备选

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

## 切换开发端

1. 当前 Flutter 终端按 `q`，结束调试；隧道可保留，切换前确保应用在手机上运行。
2. 在当前端提交/推送代码，在另一端拉取；有本地未提交修改时先处理再合并。依赖变化后运行 `flutter pub get`。
3. 确认另一端的连接配置与签名/插件/SDK 一致，再运行对应 attach 预览命令。VPS 需要更新 APK 时用 HTTPS 下载，在手机旁安装；WSL 本地更新使用 Linux `adb install -r`，保持应用数据。
4. 修改 Dart 文件并保存，在该端 Flutter 终端按 `r` 热重载，`R` 热重启。attach 不构建或安装 APK，首次连接可能传输 Dart 编译结果，连续编辑期间使用增量热重载。

并行调试需要不同设备/模拟器，或不同应用 ID 的开发 flavor；当前项目未配置独立 flavor。同一应用的热重载只使用当前会话编译的源码，无法将两个工作区的修改自动合并到手机。
