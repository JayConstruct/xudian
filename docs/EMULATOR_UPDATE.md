# 一键更新模拟器

在 WSL 先启动 Windows 模拟器并等待 Android 就绪：

```bash
scripts/start-emulator.sh
```

默认使用本机 `Medium_Phone_API_37.0`，设备为 `emulator-5554`；已运行时直接复用，保留应用和数据。脚本用 PowerShell 启动 Windows 模拟器进程，设备查询和启动完成检查均使用项目 Linux ADB。无需先打开 Android Studio。Windows SDK 与 AVD 需提前安装、创建；脚本不下载 SDK 或创建 AVD。

其他机器可覆盖 Windows 可执行文件路径、AVD、端口和启动等待时间：

```bash
scripts/start-emulator.sh --avd YOUR_AVD \
  --emulator 'C:\Users\YOUR_USER\AppData\Local\Android\Sdk\emulator\emulator.exe' \
  --port 5556 --timeout 240
scripts/start-emulator.sh --dry-run
scripts/start-emulator.sh --memory 4096
```

新启动默认通过 `-memory 2048` 将 Android 客体 RAM 上限设为 2048 MB；`--memory MB` 可调整为 1536～8192 MB 的整数，覆盖本次启动的 AVD 内存配置。参数范围见 [Android 模拟器命令行文档](https://developer.android.com/studio/run/emulator-commandline#common)。这不是 Windows 模拟器进程总内存的硬上限，图形、快照等仍有额外开销。复用已有模拟器时不会改变其内存配置；需要应用新值时，使用 `--cold-boot --memory MB`，确认关闭后重新启动。

强制冷启动或开启高刷（例如 120 / 165 Hz）：

AVD 名称通过 Android 的 `ro.boot.qemu.avd_name` 属性核对；为空或查询失败时尝试旧版 `ro.kernel.qemu.avd_name`，并清理空行、首尾空白与回车，不依赖可能成功但没有名称输出的 `adb emu avd name`。关闭前若两个属性均不可读取，再检查 Windows 中明确带有目标 `-port` 参数的模拟器进程；仅接受这些进程指向唯一且一致的 `-avd` 名称。确认后再次核对。所有查询均失败或名称不匹配时停止关闭操作；启动完成后仍需通过 Android 属性核对。

```bash
scripts/start-emulator.sh --cold-boot
scripts/start-emulator.sh --cold-boot --refresh-rate 120
scripts/start-emulator.sh --cold-boot --refresh-rate 165

# 可选：同时锁定 Android 最高/最低刷新率，避免系统策略仍限制为 60Hz
scripts/start-emulator.sh --cold-boot --refresh-rate 165 --lock-refresh-rate

# 预览操作，不连接设备、不关闭或启动进程、不改设置
scripts/start-emulator.sh --cold-boot --refresh-rate 120 --lock-refresh-rate --dry-run

# 未运行时启动；已运行时只核对刷新率，不自动重启
scripts/start-emulator.sh --refresh-rate 120
```

`--cold-boot` 不清除应用或用户数据：目标设备已运行时，核对 AVD 后询问“是否关闭并冷启动？[y/N]”。输入 `y` 或 `yes`（不区分大小写），脚本再次核对目标，通过 `adb emu kill` 关闭该设备，等待 ADB 和 Windows 目标进程退出，然后自动启动。输入 `n`、`no` 或直接回车则取消，保留原模拟器；输入结束（EOF）时也不会关闭。目标未运行时直接启动，无需确认。若目标 offline、无法核对名称、名称不符、ADB 查询失败、关闭失败或退出超时，停止操作；无法通过 ADB 核对和关闭的 Windows 进程需手动关闭。脚本只关闭经核对并确认的目标设备。不带刷新率时使用 `-no-snapshot-load`，只跳过快照加载，退出仍允许保存 Quick Boot 快照。`--timeout` 分别限制退出等待和 Android 启动等待。

`--refresh-rate` 接受 30～240 Hz 的整数，包括 120 和 165；指定时新进程附加 `-vsync-rate HZ -no-snapshot`，不修改 AVD 配置、不加载或保存 Quick Boot 快照。此参数只改变 Android 客体的刷新节拍，保持原有分辨率和清晰度；主机显示器当前刷新率会限制窗口实际呈现，测量 120 / 165fps 时应使用至少对应刷新率的主机屏幕。未加 `--cold-boot` 时，已运行设备仅核对 `ro.boot.qemu.vsync`，不匹配或无法读取时会报错，提示强制冷启动。未指定参数时保留原有启动和复用行为。

脚本核对启动属性后，还需用 `adb -s emulator-5554 shell dumpsys display` 检查当前显示模式的分辨率、刷新率与 `supportedModes`，并测量实际呈现间隔。客体报告 120Hz 不保证 Windows 窗口显示了每一个 Flutter 帧，60Hz 测量中的同步等待也不能直接视为未满足 120fps 的计算预算。恢复客体 60Hz 时运行 `scripts/start-emulator.sh --cold-boot --refresh-rate 60`；无需降低分辨率。

即使 `ro.boot.qemu.vsync=120`、`supportedModes` 为 120Hz，Android 的默认刷新率策略仍可能使 `mActiveRenderFrameRate` 和 `mDisplayModeSpecs` 的 render 上限保持 60Hz。`--lock-refresh-rate` 必须与 `--refresh-rate` 一起使用；脚本先读取 Android 当前用户和两项设置原值，再保存恢复脚本到 `.cache/emulator-start/refresh-端口-随机标识.sh`，随后设置并读回核对 `peak_refresh_rate` / `min_refresh_rate`。终端会打印 `bash 恢复脚本路径`；原值为 `null` 时恢复脚本删除该覆盖值，而非写入字符串 `null`。只读失败时不写设置；写入或核对失败时保留恢复脚本并报错，不宣告就绪。

锁定设置跨模拟器重启持续生效，不会在脚本结束时自动恢复，且不能保证应用实际帧率。实验结束后对同一设备执行打印的恢复命令；多次锁定生成多份记录，按操作的逆序恢复可回到最初的设置。未加 `--lock-refresh-rate` 时脚本不修改 Android 刷新率策略。也可以继续手动记录和调整：

```bash
peak_before="$(adb -s emulator-5554 shell settings --user current get system peak_refresh_rate | tr -d '\r')"
min_before="$(adb -s emulator-5554 shell settings --user current get system min_refresh_rate | tr -d '\r')"
mkdir -p dist/verification
refresh_record="dist/verification/refresh-settings-$(date +%Y%m%d-%H%M%S).txt"
printf 'peak_refresh_rate=%s\nmin_refresh_rate=%s\n' "$peak_before" "$min_before" > "$refresh_record"
adb -s emulator-5554 shell settings --user current put system peak_refresh_rate 120
adb -s emulator-5554 shell settings --user current put system min_refresh_rate 120
adb -s emulator-5554 shell dumpsys display
adb -s emulator-5554 shell dumpsys SurfaceFlinger --latency
```

保留原值记录及调整前后的显示模式输出，与本次性能结果一并保存。调整后核对应用实际 render rate 为约 120Hz，SurfaceFlinger 的周期约为 8,333,333ns，并测量动画实际帧数；其他策略仍可能限速，不能仅凭设置成功就认定达到 120fps。实验结束后恢复两项原值，原值为 `null` 表示未设置，应删除覆盖值，不能写入字符串 `null`：

```bash
if [[ "$peak_before" == null ]]; then
  adb -s emulator-5554 shell settings --user current delete system peak_refresh_rate
else
  adb -s emulator-5554 shell settings --user current put system peak_refresh_rate "$peak_before"
fi
if [[ "$min_before" == null ]]; then
  adb -s emulator-5554 shell settings --user current delete system min_refresh_rate
else
  adb -s emulator-5554 shell settings --user current put system min_refresh_rate "$min_before"
fi
```

恢复命令使用同一终端中的原值变量；若换了终端，先根据保存的记录恢复这两个变量。随后再核对显示策略；需要恢复客体 60Hz 时，退出模拟器后按前述命令冷启动。

ADB 默认连接 `127.0.0.1:5037`，支持 `XUDIAN_ADB_HOST`（本机 loopback）和 `XUDIAN_ADB_PORT`。不同端口启动后，更新脚本也需指定对应 `--serial` 和 `--adb-port`。启动超时或连接失败会报错，不继续更新；新启动的模拟器保留运行，可排查后重试。在 Codex 沙箱中启动 Windows 窗口需申请在沙箱外执行同一脚本。

在项目根目录按本次改动选择模式：

| 场景 | 命令 | 行为 |
| --- | --- | --- |
| 日常修改 Flutter 页面 | `scripts/update-emulator.sh --dev` | 更新调试 APK，连接热重载 |
| 只修改课表模块 | `scripts/update-emulator.sh --modules-only --module app.schedule` | 测试、打包并从模块管理导入，不构建 APK |
| 只修改拾光导入模块 | `scripts/update-emulator.sh --modules-only --module app.import.shiguang` | 测试、打包并从模块管理导入，不构建 APK |
| 验收正式效果 | `scripts/update-emulator.sh` | 检查并更新 Release APK，自动复用有效缓存 |

脚本自动加载项目开发环境，默认连接 `127.0.0.1:5037` 的 `emulator-5554`，仅支持 x86_64 Android 模拟器。修改 `pubspec.yaml` 或首次准备依赖后，先运行 `source scripts/dev-env.sh` 和 `cd client && flutter pub get`。

## 热重载

```bash
scripts/update-emulator.sh --dev
```

安装、核对与启动成功后，终端保持 `flutter attach` 连接。在另一个终端或编辑器修改 Dart 文件，再回到此终端按 `r` 热重载；按 `R` 热重启，按 `q` 退出调试并停止应用。普通页面和交互改动可重复热重载，不必每次构建、安装。热重载过程不自动执行测试或提交文件；验收或提交前再运行更新脚本。

依赖、Android 原生代码、资源或 debug/release 模式变化时，重新运行脚本。仅安装调试版、不保持连接时使用 `--dev --no-attach`。

## 独立模块更新

```bash
scripts/update-emulator.sh --modules-only --module app.schedule

# 同时更新多个模块
scripts/update-emulator.sh --modules-only \
  --module app.schedule --module app.import.shiguang

# 客户端和模块都改动时
scripts/update-emulator.sh --module app.schedule
```

模块来自 `packages/modules/<模块 ID>`。脚本打包 `.xmodule`，非预装模块推送到模拟器下载目录并通过模块管理导入；若模块在 `client/assets/modules/catalog.json` 中且当前源码包摘要与该 ID 的 pin 一致，则使用模块管理底部“恢复随客户端发布的模块”中该 ID 同行的“安装 / 恢复”按钮，保留随客户端发布的来源身份，不通过本地导入替代官方来源。审核仍核对目标版本、SHA-256 及新增权限，随后验证已启用状态；预装恢复还读取已安装包详情核对实际摘要。同版本已安装时确认摘要一致后复用。

源码包与预装 pin 不一致时，在接触设备前停止；需要更新预装资源并构建、覆盖安装相应 APK。已安装 APK 的内置包版本或摘要落后于当前 pin 时，审核校验会拒绝确认，不会安装旧包或改走本地导入。新增权限仍须明确授权，否则保留审核界面供处理。宿主来源保护保持生效，更新过程不卸载模块、不清除数据。

**修改模块内容时必须递增 `module.json` 的版本号**；同版本但内容不同会报错，不会误报更新成功。此流程需要先安装客户端，并依赖当前模块管理和 Android 文件选择器界面；改变这些界面后需要同步更新自动化定位。

## 自动复用与测试范围

每次实际更新先执行仓库与预装资源检查，包括复用已有 APK 的情况；它拒绝意外跟踪的本机产物、多余预装包、损坏包和无索引发布包。检查或打包脚本变化也会使回归检查缓存失效。

源码、资源、Android 构建配置、依赖锁文件及 Flutter 工具版本未变化时，复用已核验的 APK。文档、测试和独立模块脚本不触发客户端 APK 重建。测试源码或检查工具变化会使检查缓存失效；debug 和 release 使用独立缓存。

本地 `packages/xquickjs` 的 Dart、C 源码、vendor 头文件、构建 hook 和包依赖声明也纳入构建指纹；修改这些运行时输入会重新构建并扩大到完整 Flutter 回归，不能仅因客户端 Dart 文件未变就复用旧 APK。包说明文档及本机缓存仍不触发重建。

模拟器实际 APK 的 SHA-256 和 versionCode 均一致时跳过重复安装。构建产物损坏、设备版本更高或构建输入变化时重新构建，构建号自动递增。覆盖安装使用 `adb install -r`，保留现有应用数据；安装后核对设备版本和摘要，再启动客户端。

默认测试覆盖宿主界面与菜单；后续根据距该模式上次成功构建的改动扩大范围。课表或拾光模块更新会加入各自相关测试；顶栏、页面宿主和设置修改加入对应页面回归；数据库、模块核心和依赖改动执行全部测试。首次运行没有历史改动基线，执行默认测试。需要指定范围时：

```bash
scripts/update-emulator.sh \
  --test test/schedule_layout_test.dart \
  --test test/ui_pack_chrome_test.dart

scripts/update-emulator.sh --full-tests
scripts/update-emulator.sh --force
```

`--test` 可重复，用于替换自动选择；`--full-tests` 执行全部 Flutter 测试，不能与 `--test` 同用。显式测试参数保证本次重新执行测试。`--force` 忽略检查和构建缓存；仅更新模块时仍按所选测试范围运行。

## 更新并提交指定文件

```bash
scripts/update-emulator.sh \
  --commit "Adjust workspace menu" \
  --path client/lib/app/app_shell.dart \
  --path client/test/ui_pack_chrome_test.dart \
  --test test/ui_pack_chrome_test.dart
```

检查、更新、核对与启动全部成功后，才创建本地提交。`--path` 可重复，接受单个文件及已跟踪的删除文件，不接受目录、忽略文件或仓库外文件。提交所选文件的全部改动，其他已暂存文件不会进入本次提交。脚本不自动推送 GitHub；只更新时省略 `--commit` 与 `--path`。

## 设备、预览与结果

```bash
scripts/update-emulator.sh --dry-run
scripts/update-emulator.sh --dev --dry-run
scripts/update-emulator.sh --serial emulator-5556 --adb-port 5037
```

`--dry-run` 只打印流程，不连接设备或修改文件。ADB 地址还可通过 `--adb-host` 或环境变量 `XUDIAN_ADB_HOST`、`XUDIAN_ADB_PORT` 设置。`--build-number` 可指定构建号，必须高于设备现有版本，不能与 `--modules-only` 同用。

最近成功和尝试记录分别在 `.cache/emulator-update/latest-success.json`、`latest-attempt.json`，包含各阶段及总耗时、测试范围、缓存复用情况、APK 版本与摘要、模块结果及可选提交 SHA。debug/release 缓存和 APK 也在此目录，已由 Git 忽略。同一工作区同时只允许一个更新流程；进入热重载后会释放更新锁。

步骤失败即停止，记录失败阶段，不继续提交。失败发生在安装之后时，模拟器可能已经更新，脚本不自动回滚。模块更新触发界面检查前请避免同时操作模拟器。

模拟器检查辅助类在短时间内复用同一份 UI XML；点击、输入等操作会使缓存失效，等待页面时强制读取新快照。截图与 XML 记录共享一次读取，减少重复 `uiautomator dump`。

脚本回归检查不需要模拟器或 Flutter：

```bash
python3 -m unittest discover -s scripts/tests -v
```
