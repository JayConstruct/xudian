# 一键更新模拟器

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

模块来自 `packages/modules/<模块 ID>`。脚本打包 `.xmodule`、推送到模拟器下载目录、打开模块管理并导入，核对审核页的名称、版本和 SHA-256，安装后验证已启用状态。遇到新增权限会停止，保留审核界面供手动处理。同版本已安装时会核对已安装包摘要，确认一致后复用。

**修改模块内容时必须递增 `module.json` 的版本号**；同版本但内容不同会报错，不会误报更新成功。此流程需要先安装客户端，并依赖当前模块管理和 Android 文件选择器界面；改变这些界面后需要同步更新自动化定位。

## 自动复用与测试范围

每次实际更新先执行仓库与预装资源检查，包括复用已有 APK 的情况；它拒绝意外跟踪的本机产物、多余预装包、损坏包和无索引发布包。检查或打包脚本变化也会使回归检查缓存失效。

源码、资源、Android 构建配置、依赖锁文件及 Flutter 工具版本未变化时，复用已核验的 APK。文档、测试和独立模块脚本不触发客户端 APK 重建。测试源码或检查工具变化会使检查缓存失效；debug 和 release 使用独立缓存。

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
