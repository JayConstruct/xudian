# 设备复验脚本

## 课表周选择器

在已启用「大学课表」的 Android 模拟器上运行。底部导航应能打开「课表」，当前课表至少有两个教学周，本机的 `client/build/app/outputs/flutter-apk/app-x86_64-release.apk` 应与设备上的 APK 对应。

```bash
source scripts/dev-env.sh
python3 -m scripts.verification.verify_schedule_week_picker
```

从仓库根目录执行，可用 `--serial` 指定设备，默认是 `emulator-5554`。脚本从模块管理详情读取已启用的 `app.schedule` 版本和包摘要，验证取消、选周、恢复原周和「切换课表」入口，并核对 APK 摘要。结果写入 `dist/verification/emulator/schedule-week-grid-emulator.json`。

## 历史场景复验

以下脚本依赖对应时期的界面、模块包或测试数据。复现某次交付时，从仓库根目录运行 `python3 -m scripts.verification.<脚本名>`。日常安装与更新使用[模拟器更新流程](../../docs/EMULATOR_UPDATE.md)。

| 脚本名 | 适用场景与前提 |
| --- | --- |
| `verify_schedule_script_update` | 课表 1.0.0 → 1.0.1 验证包。默认仅核对 APK，加 `--record-update` 会实际回退、导入并重启。 |
| `verify_schedule_layout` | 课表 1.1.0，使用第 1 周含「高等数学」的样例。默认导入指定旧包，已安装该版本时加 `--installed`。 |
| `verify_schedule_ux` | 课表 1.2.0，复验当时的设置、选择器与重启。 |
| `verify_schedule_chrome` | 课表 1.3.0、宿主构建 23，复验滚动时工具栏和底栏的显隐。 |
| `verify_schedule_glass` | 课表 1.4.0、宿主构建 24，另检查末节课与底栏的位置。 |
| `verify_shiguang_browser` | 拾光旧版正方导入流程。用本地 HTML 验证浏览器、错误恢复和取消采集。`--install` 会覆盖安装 APK 并按需导入课表与拾光模块。 |
| `verify_shiguang_catalog` | 拾光学校目录与银杏适配器，使用本地教务网页样例。`--install` 会导入拾光包。报告中的版本和模块包摘要来自本机清单与候选包。 |
| `verify_shiguang_hierarchy` | 核对学校分组、多个导入入口、通用系统与致谢。记录本机包版本和摘要。 |
| `verify_shiguang_navigation` | 核对当前宿主及拾光模块的标题、返回与重新打开，报告使用设备上的构建号。 |

两项复验的结果分别写入 `dist/verification/emulator/shiguang-hierarchy-emulator.json` 和 `dist/verification/emulator/shiguang-navigation-emulator.json`。
