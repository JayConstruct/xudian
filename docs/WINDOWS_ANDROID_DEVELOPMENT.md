# Windows 11：Android Studio 与模拟器调试

Windows 负责本地 Flutter 编译和模拟器运行，源码通过 [JayConstruct/xudian](https://github.com/JayConstruct/xudian) 与 VPS 同步。客户端位于 `client/`，启动入口为 `lib/main.dart`。本流程直接在 Windows PowerShell 和 Android Studio 中操作。

使用 **WSL 开发 + Windows Android Studio 模拟器** 时，Windows 负责模拟器和 ADB server，设备查询、APK 安装、启动和日志在 WSL 使用 Linux 版 `adb`，连接命令见 [WSL 原生 ADB](MULTI_MACHINE_DEVELOPMENT.md#wsl-原生-adb连接与安装-apk)。以下 Windows Flutter 安装和编译步骤用于纯 Windows 开发；WSL 使用自己的 Linux SDK。

## 1. 安装开发工具

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

## 2. 克隆并打开客户端

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

## 3. 创建并启动模拟器

Android Studio 打开 **Device Manager → Create Device**：

1. 选择一个 Pixel 手机配置。
2. 选择 Android API 36 系统镜像；Intel/AMD Windows 电脑通常选择 x86_64 镜像，其他架构按 Device Manager 推荐选择。
3. 完成创建并点击启动，等待模拟器进入 Android 桌面。

在 `client/` 目录的 PowerShell 或 Android Studio Terminal 中确认设备：

```powershell
flutter devices
```

应看到 Android 模拟器，例如 `emulator-5554`。如果无法启动模拟器，按 Device Manager 的诊断提示检查 BIOS/UEFI 中的 CPU 虚拟化和 Windows Hypervisor Platform 配置；系统设置变化后可能需要重启电脑。

## 4. 运行、断点与热重载

Android Studio 顶部选择模拟器和 `lib/main.dart` 启动配置，点击 **Debug**。首次构建需要下载 Gradle、Android 依赖和可能缺少的 NDK，耗时通常比后续构建长。启动后可设置断点、查看变量和调试日志。

修改 Dart 文件并保存后，点击 **Hot Reload**（闪电图标）；需要重新执行应用初始化时点击 **Hot Restart**。原生代码或插件依赖变化后，应停止并重新运行应用；依赖变化时先执行 `flutter pub get`。

也可使用命令行启动，将设备 ID 替换为 `flutter devices` 输出的实际值：

```powershell
flutter run -d emulator-5554
```

命令行运行时按 `r` 热重载、`R` 热重启、`q` 退出。只有通过 IDE 的 Debug 或 `flutter run` 启动的 debug 版本支持这一调试流程。模拟器中的任务、设置和 AI 凭据存储在该设备本地，Git 同步源码，不同步应用数据。

## 5. 与 VPS 同步源码

先确认当前分支与上游，作者索引源码分支见 [模块目录](MODULE_CATALOG.md)。开发端修改并推送后，在 Windows 的仓库根目录更新同一工作分支：

```powershell
cd C:\dev\xudian
git status
git pull --ff-only
cd .\client
flutter pub get
```

更新完成后在 IDE 热重载或重新启动。拉取前如有本地改动，先提交，或使用 `git stash push -u` 暂存，拉取后 `git stash pop` 并处理可能的冲突。`--ff-only` 若因两端已有不同提交而失败，应先检查历史，再合并或变基。

如果也在 Windows 修改源码，先在仓库根目录配置本仓库的提交身份，替换为自己的信息；邮箱可使用 GitHub **Settings → Emails** 提供的隐私邮箱：

```powershell
git config user.name "你的GitHub用户名"
git config user.email "你的GitHub提交邮箱"
git status
git add .
git commit -m "Describe the change"
git push
```

切换机器前提交并推送，另一台机器开始工作前拉取。同一功能尽量在一台机器完成一轮修改；并行修改使用不同分支。

`.gitattributes` 统一普通文本和 Shell 脚本为 LF，Windows `.bat` / `.cmd` 脚本检出为 CRLF，二进制资产不转换换行。SDK、缓存、构建产物、`client/android/local.properties` 和签名密钥保持本机生成，已由 `.gitignore` 排除。

## 6. 本地验证

在 `client/` 目录执行：

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

这些检查验证静态分析与现有测试；模拟器界面、输入、键盘和交互仍需实际运行确认。若 SDK 或依赖版本发生变化，先执行 `flutter pub get` 再检查。
