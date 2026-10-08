# 模块宿主实施与验收记录

日期：2026-10-07。交付文件及 SHA-256 见 [acceptance.json](../dist/verification/acceptance.json)。本记录区分自动化检查、模拟器实际操作与尚未验证的平台，不以 Linux 测试替代其他平台。

2026-10-08 的公共 UI、无脚本线程界面包和 SQL 分页实现及新增验证见 [界面包验证记录](UI_PACK_VERIFICATION.md)；分布式模块目录协议、作者发布工具及本地验证命令见 [模块目录接入文档](MODULE_CATALOG.md)。下文保留 2026-10-07 的历史结果与实施差异。

## 交付

- [Android Release APK](../client/build/app/outputs/flutter-apk/app-release-build17.apk)：本记录的 build 17，包含 Android x86_64、arm64 原生引擎。后续布局交付见 [课表布局记录](SCHEDULE_LAYOUT.md)。
- [独立课表 1.0.0](../dist/verification/app.schedule-1.0.0.xmodule)：客户端资源中不包含此包；原验收版单独保留，当前分发包版本见课表布局记录。
- [课表验证更新 1.0.1](../dist/verification/app.schedule-1.0.1.xmodule)：在原课表脚本上新增课程统计服务及页面文字，验证业务更新不需要重新构建客户端。
- 其余业务包位于 [dist/modules](../dist/modules)，包含任务、AI、今天、收件箱、项目、UI 示例和 UI 贡献。默认安装标记与用户卸载状态分别保存。
- [宿主与恢复说明](MODULE_HOST.md)、[模块 SDK](MODULE_SDK.md)、[QuickJS 构建说明](../packages/xquickjs/README.md)。

## 自动化检查

`flutter analyze --no-pub` 无问题。`flutter test --no-pub --concurrency=1` 全部 **415 项通过**，包括原有行为基准及新生产链测试。测试原始输出保存在 [flutter-tests.txt](../dist/verification/flutter-tests.txt)，分析与构建输出也保存在同一目录。

新测试直接运行 QuickJS、本地 SQLite 与生产宿主组件，覆盖以下行为：

| 范围 | 已检查内容 |
| --- | --- |
| 原生运行时 | ESM、包内相对导入、中文、异步 Promise、异常、无限循环中断、内存限制、取消和禁止操作系统模块/越界导入 |
| 包和权限 | 完整文件清单、签名/摘要、路径与大小限制、不可变来源、宿主接口/依赖版本、真实调用身份、授权撤销/过期、旧实例拒绝 |
| 提交与扩展 | 记录/集合基线冲突、重复提交、跨模块模板回滚、提交后事件、字段类型/范围/清除、规则条件和循环轨迹 |
| 迁移与恢复 | 完整旧样本 ID/日期/关系/计数/日志/历史一致、重复迁移、旧源码与来源保留、失败更新恢复、兼容回退、不兼容快照恢复、候选文件清理 |
| AI | 无任务包时聊天、模拟模型协议、历史、工具去重、取消、条件撤销、高级生成到隔离预览及私有模块更新、禁止预览联网/正式写入 |
| 课表 | 明确/单双/不连续周次、跨年民用日期、课表时区、周日起始、跨周调课、重叠课程、备份新 ID、稳定来源、三方冲突、局部/空/重复导入、删除标记、失效调课选择、预览基线 |
| 生产界面 | 空宿主设置和恢复、任务实际提交、课表导入确认、时间网格无障碍/重叠、设置贡献与宿主控制共存、草稿保留、布局基线 |
| HTTP/凭据 | 实际本机 HTTP、宿主认证注入、凭据句柄的模块/地址绑定、拒绝重定向/超大响应、请求取消 |

旧业务界面测试通过专用夹具保留原行为基准，不能据此声称新页面与旧页面逐像素一致。AI 模型测试使用受控响应，没有连接真实外部模型或使用用户 API Key。

生产引用检查从 `main.dart` 遍历可达代码，未发现旧任务/AI 控制器或旧业务表调用进入生产业务链；课表未进入默认资源。旧表定义及迁移读取保留。包清单、JSON Schema、默认资源摘要和交付 APK 内容另行核对。

## Android x86_64 模拟器实际操作

用户当前只提供此模拟器。使用保留数据的 APK 更新，没有清空 App 数据或 Wipe Data。

1. 从旧数据库启动升级，备份后迁入新空间，原任务与项目继续可见。
2. 从系统文件选择器导入独立课表包，在宿主来源审核后新增课表入口；导入示例课程，周视图显示课程。通过 Android 系统保存对话框导出 JSON 并核对引用与周次。
3. 卸载任务后，课表仍显示课程，AI 仍可打开。[课表截图](../dist/verification/android-schedule-without-tasks.png)、[AI 截图](../dist/verification/android-ai-without-tasks.png)。
4. 卸载全部业务包并重启，显示空宿主，设置、安装与恢复入口仍可用，不自动重装。[卸载截图](../dist/verification/android-all-business-uninstalled.png)、[重启截图](../dist/verification/android-empty-host-recovery.png)。
5. 重新安装业务包，恢复保留的课表数据。[恢复截图](../dist/verification/android-restored-schedule.png)。
6. 在最终 build 17 上回退到课表 1.0.0，确认没有新增统计；导入 1.0.1 后出现“脚本更新新增统计：1 门课程”，强制停止并重启后仍保留。此过程 APK 文件及设备安装的 APK 摘要保持不变。[原版截图](../dist/verification/android-schedule-original-final.png)、[更新截图](../dist/verification/android-schedule-script-update.png)、[重启截图](../dist/verification/android-schedule-update-restart.png)。

第 6 项可用 `source scripts/dev-env.sh` 后运行 `python3 scripts/module_host/verify_emulator.py --record-update` 重现。需要设备已安装课表验证版、保留原版历史与一门课程，且下载目录有验证更新包；脚本会通过宿主确认界面回退/更新，不删除数据。前五项是本轮人工/界面脚本实际验收，截图保留了其执行时的版本；不声称已在每次后续宿主改动后重复全部场景。

## 平台与实施差异

| 平台 | 结果 |
| --- | --- |
| Android x86_64 模拟器 | Release 实际安装、独立包、更新、重启与卸载恢复已检查 |
| Android arm64 真机 | APK 已编译此 ABI；用户尚无可连接真机，未实际运行 |
| Windows x64 | 已提供 Windows 构建桥接；没有可用 Windows 构建/运行环境，未完成 Release 构建或运行验收 |
| Linux | 静态分析、真实引擎与数据库自动化测试通过；不替代其他平台验收 |

与初始方案的实施差异仍需保留在交付结论中：每模块有计算/工作流两个运行时，合计 64 MiB 堆；声明索引实施唯一性校验，查询优化尚未实现；高级审核目前展示结构化源码/定义/实际数据预览，尚无专门逐行差异编辑器；源码编辑器只支持 UTF-8 文本，二进制资源需用外部包工具更新。旧界面视觉一致性尚未逐项验收。恢复测试覆盖代表性失败与重启路径，没有完成每个更新阶段的真实断电矩阵。因此跨平台和上述验收项尚未全部闭环，不能标为原计划的完整验收通过。

正方登录/实际适配、自动刷新、提醒、拖动课程、跨设备同步与公开市场服务端按原计划留待后续。
