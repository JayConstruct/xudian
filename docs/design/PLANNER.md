# 任务规划（app.planner 1.0.0）

任务规划独立安装，需要宿主 API 1.21 与任务模块 1.4。日程模块 1.7.1 展示精确时间；课表 1.12 提供可选占用查询。没有课表时显示「未计入课程」，已接入但查询失败时禁止确认。未配置可用时间不视为全天空闲。

## 使用

1. 安装 `dist/modules/app.planner.xmodule`。首次从顶栏菜单配置每周可用时段、时区、默认耗时与缓冲。
2. 多行添加任务，选择单次、每日、每周多次或最大间隔规则；也可以选择已有待办，保留任务 ID。每日规划、每日复盘与打字模板可修改。
3. 选择待安排实例并统一安排，默认七天，最多二十八天、二百项。预览列出日期、具体起止时间、原允许窗口及每个未安排原因。没有选中项时只计算尚未确认的候选。
4. 在预览中单项或多选调整日期、时间、优先级与锁定状态。整批经一次宿主审核提交。已确认任务不会因刷新或重算自动改期。
5. 已安排页可选择任务重新生成建议，完成／补记／撤销完成、锁定、跳过或取消。完成仍可使用日程入口。编辑窗口使用手机底部／宽屏侧边面板。
6. 顶栏提供日期例外、当天很忙、手动忙碌时段与批次历史。撤销会先验证所有任务和实例，任一后续修改或完成都会阻止整批撤销。

规则修改从当天生效，保留旧版本，影响尚未确认的未来实例；暂停和结束不删除已确认安排。当前不提供预设未来生效日期。历史日期可通过规划范围浏览，区分已完成、漏做、主动跳过及取消。每日、每周及空闲实例的执行有效期不会滚入次日欠账。

最大间隔按实际完成自然日计算，例如十月十三日完成，间隔六天、提前两天，下一窗口为十七至十九日；十七日提前完成后为二十一至二十三日。未来窗口按前一建议日期推演并标记预计；稳定序号使重新校准、补记和撤销完成不产生重复实例。跳过仍保留原间隔义务和最晚日期。已超期不会被自动移到将来。完成日期变化导致已确认安排越出窗口时显示持续提示，须重新预览并确认。

## 数据和服务

无新增 Drift 表。`app.planner` 使用 `rules`、`occurrences`、`settings`、`batches` 四个模块集合。真实任务和精确时间只保存在 `app.tasks`；实例保存关联 ID、窗口、锁定和状态。

| 服务（均为 @1） | 输入概要 | 行为 |
| --- | --- | --- |
| `planner.rules.list` | `{}` | 返回规则及历史版本 |
| `planner.rules.save` | `{rules:[...]}` | 批量创建／修改；修改传 `expectedVersion` |
| `planner.availability.get/save` | `{}` / `{availability}` | 星期可用时段、日期例外、忙碌、时区、默认耗时、缓冲 |
| `planner.candidates.list` | `{startDate?,days?}` | 候选、已有待办、占用及校准冲突摘要 |
| `planner.plan.preview` | `{startDate?,days?,selectedIds?,overrides?}` | 只读生成含依据的方案；不静默越过窗口或硬截止 |
| `planner.batch.apply` | `{batchKey,preview}` | 重读全部依据并核验，嵌套准备任务变更和规划记录，一次事务提交 |
| `planner.batch.list/undo` | `{}` / `{id}` | 批次历史与整批条件撤销 |
| `planner.occurrence.update` | `{id,changes,candidate?}` 或 `{taskId,window}` | 修改窗口、锁定、跳过、取消，或接纳原任务 |

规则字段、输入限制及 AI tool 元数据见模块 `module.json`。预览带 `schemaVersion:1`、`basis`、`input`、`assigned`、`unassigned`、`conflicts`、`warnings`、`confirmable`。相同批次键重复提交只返回已应用；复用键提交不同内容会拒绝。宿主提交时还校验集合／记录及可选服务目录基线。

`plannedStartAt/plannedEndAt` 为 UTC，`plannedTimezone` 为 IANA 标识；`plannedDate` 从精确时段同步维护。单独更改日期会清除精确时段。`actualCompletedOn/completedTimezone` 与审计 `completedAt` 分开。`executionExpiresOn` 是包含该日的有效期，旧任务缺省无限期。AI 条件撤销也恢复日期编辑隐式清除的精确字段及补记完成信息。

排程使用五分钟起点、连续任务、不跨午夜。手动建议支持分钟精度和调整耗时。优先锁定、必做、截止日期、窗口宽度、优先级及稳定 ID；空闲任务最后安排。课程采用原有停课、调课和临时课展开。UTC 与民用时间转换明确拒绝夏令时缺失或歧义端点。

## 验证（2026-10-13）

- 组合 Flutter/真实 QuickJS 回归覆盖规划、任务、日程、课表、AI 撤销、时区、服务依赖、分页与页面预计算。
- 引擎 Node 回归覆盖自然日、间隔推演／提前完成／撤销、跳过超期、周次数、缓冲、忙碌、锁定、规则版本和硬截止。
- 真实 QuickJS 二百项、二十八天预览和批次准备分别断言少于宿主十秒执行限制；超量明确报错，不截断。
- 320 与 1100 逻辑像素、深浅主题、1.5 倍字体组件测试，无布局异常。稳定列表键及编辑面板沿用公共控件的焦点／草稿和减弱动画机制。
- 本次未进行手机／模拟器实测、系统键盘与运行时帧率测量，远程发布信息见本页末尾。

可复验命令：

```bash
python3 -m unittest scripts.tests.test_planner_engine -v
source scripts/dev-env.sh
cd client
flutter test --no-pub test/planner_test.dart test/planner_task_schedule_test.dart test/planner_ai_undo_test.dart test/clock_conversion_test.dart test/host_service_compatibility_test.dart test/daily_date_browsing_test.dart test/schedule_today_feed_test.dart test/task_scan_pagination_test.dart test/module_catalog_test.dart test/page_preparation_test.dart --concurrency=2
flutter analyze --no-pub
```

## 模块商店发布

发布 tag：`modules-20261013-planner`。新增任务规划 1.0.0，并发布任务 1.4.0、日程 1.7.1、课表 1.12.0、AI 1.3.0 与 UI 示例 1.4.2。版本索引保留旧包历史，客户端按宿主兼容范围选择版本。发布过程先上传校验不可变包，再更新作者索引与统一目录。规划模块需要包含 API 1.21 的客户端；main 的 Android Actions 会生成对应 APK 产物。
