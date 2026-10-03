# VPS 与 WSL 开发配置

源码已推送到 [JayConstruct/xudian](https://github.com/JayConstruct/xudian)，主分支为 `main`。Windows 11 本地使用 Android Studio 模拟器时，先按 [Windows 模拟器调试指南](WINDOWS_ANDROID_DEVELOPMENT.md) 操作；本文介绍 VPS/WSL 共用身边手机的远程调试方式。

当前使用 Windows 电脑通过 USB 连接 Android 手机。建议 VPS 与 WSL 各有一份源码和 Linux SDK，通过 Git 交换修改，Windows 提供同一个 ADB server。两端都能运行 Flutter，但同一手机上的同一应用一次由一个 `flutter attach` 会话控制。

2026-09-30 VPS 已通过 ADB 15037 与 VM Service 8181 转发连接手机 PHY120，attach 与无源码变更的热重载已验证；Windows/WSL 互切仍待验证。固定端口连接使用 `--no-dds`。APK 通过独立 HTTPS 下载并在手机旁安装，VPS 只使用 flutter attach，不经 SSH 传输 APK。单机远程调试基础见 [开发环境](../DEVELOPMENT.md#通过-ssh-远程预览-android)。

## 源码与工具

- VPS 已配置 SSH 远端 `origin` 为 `git@github.com:JayConstruct/xudian.git`，本地 `main` 跟踪 `origin/main`。新 WSL 工作区可执行 `git clone git@github.com:JayConstruct/xudian.git ~/projects/xudian`，需在 WSL 单独配置 SSH 认证；也可使用 HTTPS 地址克隆。切换机器前 commit/push，另一端 `git pull --ff-only`；同时开发时使用独立分支，通过 merge 或 cherry-pick 合并。
- VPS 可继续使用 `/opt/my_app`；WSL 推荐 `~/projects/xudian`，将源码放在 WSL 的 Linux 文件系统，避免在 `/mnt/c` 上构建。
- 两端各自安装 Linux Flutter 3.47.5 / Dart 3.13.4、Java 21 和 Android SDK，布局沿用 `.tools/flutter` 与 `.tools/android-sdk`。`scripts/dev-env.sh` 根据自身位置计算项目根目录，不要求 WSL 使用 `/opt/my_app`；默认 Java 路径需在 WSL 存在或按实际安装调整。
- 保持 SDK 与 `client/pubspec.lock` 一致。两端各自执行 `flutter pub get`；`.tools/`、`.cache/`、`client/build/`、`.dart_tool/` 和 `client/android/local.properties` 保持本机生成，不在机器之间复制或共享。
- Android 调试安装使用相同的应用 ID。VPS 与 WSL 应使用同一开发用 debug keystore，并在私有渠道复制到各自的标准位置（通常为 `~/.android/debug.keystore`，若自定义 Android 用户目录则按实际位置配置）。不同签名无法覆盖已安装应用，卸载会清除应用数据；不要为切换开发机自动卸载。开发签名文件不进入源码仓库，正式发布签名单独管理。

## 手机连接与端口分配

Windows 安装新版 Platform-Tools，与 Linux SDK 的 ADB 协议保持兼容。电脑执行 `adb start-server` 和 `adb devices -l`，手机授权后状态应为 `device`。

| 开发端 | 访问的 ADB 地址 | Flutter VM 端口 | 连接方式 |
| --- | --- | --- | --- |
| VPS | VPS `127.0.0.1:15037` → Windows `127.0.0.1:5037` | VPS 8181 → Windows 8181 | Windows 发起 SSH 反向转发 |
| WSL 2 镜像网络 | Windows `127.0.0.1:5037` | Windows 8182 | WSL 通过 localhost 访问 Windows |
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

## WSL 2 调试：镜像网络

Windows 11 22H2 或更新版本及支持镜像网络的新版 WSL 可采用此方式。先在 PowerShell 执行 `wsl --update`，编辑 Windows 用户目录下的 `.wslconfig`（保留已有设置，在对应节中添加）：

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
3. 确认另一端的连接配置与签名/插件/SDK 一致，再运行对应 attach 预览命令。需要更新 APK 时用 HTTPS 下载，在手机旁安装，保持应用数据。
4. 修改 Dart 文件并保存，在该端 Flutter 终端按 `r` 热重载，`R` 热重启。attach 不构建或安装 APK，首次连接可能传输 Dart 编译结果，连续编辑期间使用增量热重载。

并行调试需要不同设备/模拟器，或不同应用 ID 的开发 flavor；当前项目未配置独立 flavor。同一应用的热重载只使用当前会话编译的源码，无法将两个工作区的修改自动合并到手机。
