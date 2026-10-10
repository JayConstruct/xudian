# 远程 Android 预览

环境准备和临时 APK 分享见 [开发指南](../DEVELOPMENT.md)。本流程用于 VPS 与身边电脑/手机之间的调试连接；本机模拟器优先使用 [一键更新](EMULATOR_UPDATE.md)。

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

如果能列出设备但一直等待调试服务，检查是否安装并打开 debug 包，以及 8181 转发与 `--no-dds`。隧道或手机断开后恢复连接并重启 attach。脚本支持 `XUDIAN_ADB_PORT` 与 `XUDIAN_VM_SERVICE_PORT`，WSL 配置见 [VPS 与 WSL 开发配置](MULTI_MACHINE_DEVELOPMENT.md)。

历史连接测量见 [开发记录](archive/DEVELOPMENT_20261009.md)。
