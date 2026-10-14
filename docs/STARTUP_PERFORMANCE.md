# 冷启动采样与验收

## 当前测量口径

`scripts/benchmark_startup.py` 为已安装的 Android 应用建立可重复的**进程冷启动／Activity 启动与首次显示代理指标**。每次先 `am force-stop`，用 `ps -A -o PID,NAME` 确认主进程及 `package:worker` 子进程均已退出，再执行 `am start -W`；保存 Android 原始 `ThisTime`、`TotalTime`、`WaitTime` 和每次启动的完整 `am` 输出。可加 `--check-pid` 验证启动后主进程存在。

这些 `am` 指标**不等于首页内容就绪、可交互时间或 TTFD**。应用仍可能显示恢复状态、等待模块初始化或加载首页内容。Android 将首次显示（TTID）与完全显示（TTFD）区分；本脚本采用 `am start -W` 的输出作为前者的便捷代理。客户端已接入 `reportFullyDrawn`；平台 TTFD 需通过 Android 系统启动 trace 或 `Fully drawn` 日志另行读取，不从本脚本的 `am` 字段推算。[Android 官方启动指标说明](https://developer.android.com/topic/performance/issues/launch-time)

脚本保留应用数据与文件系统缓存，不卸载、不清理数据、不修改系统设置、不清空 logcat。重复 `force-stop` 只确保进程重新创建，不模拟首次安装、设备刚开机或存储缓存全冷。采样结束应用保持启动状态。

## 运行

在仓库根目录执行；ADB 需要连接已解锁且可启动应用的设备：

```bash
python3 scripts/benchmark_startup.py \
  --serial emulator-5554 \
  --adb-host 127.0.0.1 --adb-port 5037 \
  --package dev.taskapp.task_app --activity .MainActivity \
  --runs 20 --interval 2 --check-pid \
  --output /tmp/startup-baseline.json
```

`--adb` 可指定 ADB 可执行文件路径；`--activity` 支持 `.MainActivity` 或完整类名。默认采样 10 次、间隔 1 秒。间隔是上一次 `am start -W` 返回后开始计算；若首页后续加载较长，应增加间隔并记录相同设置，使每轮起始数据状态尽量一致。小样本的 p95 接近最大值，不能当作稳定的尾延迟估计。

异常输出、非 `Status: ok`、非零 ADB 返回码、显式 `HOT/WARM`、启动前残留进程、无法解析进程列表、缺失／非法必需计时均中止采样。退出码为 1，JSON 保留已成功样本与失败轮次，`complete: false`；应处理错误后重新采样，不把不完整报告当作完整对照组。部分 Android 不输出 `ThisTime`，对应字段为 `null`，不会从 `TotalTime` 推算。

`errors` 保留固定诊断字段：`phase` 为 `forceStop`、`verifyProcessAbsence`、`launch`、`checkPid` 或 `waitForWorkspaceReady`；`operation` 标明实际的 `am force-stop`、`ps`、`am start`、`pidof` 或 `logcat`。同时记录 `exitCode`（未返回时为 null）、`stdoutPresent`／`stderrPresent`、`timedOut`、`timeoutSeconds`，异常另附 `exceptionType`，不保存失败命令任意输出或异常正文。解析校验错误保留所属阶段及最近命令的这些结构信息。就绪轮询中的每次 logcat 调用以剩余 deadline 为超时上限；deadline 已过不再启动读取。可据此区分设备命令故障、进程状态不符、就绪标记缺失和壳层恢复失败。

## 结果解释与比较

报告中的 `summary` 分别统计三个指标，单位毫秒：p50 为样本中位数；p95 采用 nearest-rank（排序后第 `ceil(0.95 × n)` 个样本）；同时保留 count/min/max。`samples` 保存每轮原始值和启动前无进程的验证结果。

前后对比固定以下条件：

- 同一设备、Android 版本、APK 构建模式与 ABI，记录 APK 摘要和版本。
- 相同已启用模块版本、首页、工作区和数据量；保留数据的数据库迁移与缓存状态单独说明。
- 相同采样次数、轮次间隔、屏幕状态和后台负载；先后顺序可能受温度、系统负载与缓存影响，必要时交错复测。
- 将首次安装、升级后的第一次启动、日常保留数据冷启动分开，避免混在同一个 p50/p95 中。

模拟器数据用于本地回归比较。面向用户的性能结论应在同一 ARM64 真机上复测。Flutter 官方性能分析建议使用真机和 profile 模式；release 的平台启动指标可作为另一组单独对照。[Flutter 官方性能分析说明](https://docs.flutter.dev/perf/ui-performance)

## 首页就绪与平台接入

`main()` 从 Dart 入口开始记录 `app.firstFrame` 和 `app.workspaceReady`；前者在首个 Flutter 帧的 post-frame 回调结束，后者等待当前工作区页面、脚本与组合区域的首轮内容准备，并在页面可见、入口转场完成后的 Flutter 帧结束。隐藏缓存页、过时目的页不会报告当前页面就绪。正常空数据属于就绪内容；渲染器返回带恢复操作的终态错误树也可能解除页面门控，因此此指标表示可用内容树，不保证网络成功、业务数据正确或所有操作成功。

当工作区满足上述条件，Android `MainActivity` 只调用一次 `reportFullyDrawn()`，并输出 `XudianStartup` 本地标记。壳层恢复失败或没有可用工作区分别报告 `restoreError`／`noWorkspace`，不调用完全显示 API；这些轮次不计入成功首页样本。布局读取失败但默认工作区正常展示仍属于就绪，恢复入口保留。

新 APK 支持在采样命令中增加 `--wait-ready --ready-timeout 30`。脚本读取本次启动主进程 PID，等待 `XudianStartup` 标记中匹配本轮随机 token 的 outcome；无需清空 logcat，历史启动或 PID 复用的旧标记不能满足本轮条件。只保存固定 outcome 和整数耗时，不保存其他日志正文。旧 APK 没有标记，应使用默认模式；启用等待会超时并保留失败报告。

额外指标 `ActivityCreateToWorkspaceReadyMs` 从原生 `Activity.onCreate` 进入到上述业务就绪报告，使用 Android 单调 uptime 时钟。**它不包含此前的进程创建，也不是平台 TTFD**，不得与 `TotalTime` 相减作为页面加载或引擎启动耗时。schemaVersion 2 的报告包含该指标独立 count/p50/p95/min/max；未启用等待时 count 为 0、统计为 null。成功就绪后才开始计算轮次间隔，减少上一轮尚在加载时就结束进程的问题。

profile 的 Dart 阶段分析继续使用 `UiLoadTrace` 与 Flutter Timeline，见 [UI 加载性能](UI_LOADING_PERFORMANCE.md)。release 默认关闭 Timeline，但原生就绪标记和 `reportFullyDrawn` 仍可用于上述流程。阶段存在嵌套，不能相加并冒充完整启动时间。

## 当前启动改进与证据

恢复模块时，用一次 `LEFT JOIN host_packages` 同时取得所有启用安装的包来源、摘要；依赖重试继续复用本轮已验证字节，每次进程启动仍重新完整校验。预装仓库来源回填合并为一次 SQL，空目录跳过写入、已有用户来源保留。新增 `host.restore.packages` 与 `host.defaults.metadata` 观察这两步。

`module_startup_test.dart` 在真实内存 SQLite 中计数查询与文件读取，并覆盖依赖顺序、缺失来源、包身份／版本不匹配、重新启动后损坏、空目录和来源不覆盖。调用次数减少是结构性证据，尚不能换算成真机提速百分比；全模块懒启动与维护工作后移保留为后续采样决策。

## 2026-10-14 模拟器采样

在同一 x86_64 模拟器、同一 AVD、客体 60Hz、release 模式下对照 build103 与 build104；覆盖安装保留现有数据，未更新模块或更改字号与密度。每组 20 轮、间隔 2 秒、启动后检查主进程。设备刚启动的第一次应用打开不纳入统计。模块版本清单与业务数据量未单独导出，本轮用于本机流程验证，不代表完整真机性能矩阵。

| 组别 | 完成轮次 | `TotalTime` p50／p95 | Activity 创建到工作区就绪 p50／p95 |
| --- | --- | --- | --- |
| build103，恢复模拟器后的基线 | 20／20 | 750／830ms | 旧 APK 没有标记 |
| build104，覆盖安装后首次完整采样 | 20／20 | 1002.5／1130ms | 未启用等待 |
| build104，模拟器再次启动后的复测 | 20／20 | 750／864ms | 未启用等待 |
| build104，单独启用 `--wait-ready` | 20／20 | 921／1237ms | 1322.5／1571ms |

**没有证实稳定提速。** 新版首次采样更慢，复测启动代理指标中位数与旧版持平、p95 略高。不同轮次及模拟器恢复前后的波动明显，不能将查询次数减少换算为启动提速；也不能依据这些顺序采样将差异归因到某一处代码。`--wait-ready` 组在就绪后才开始轮次间隔，采样条件与默认组不同，不混在同一组统计。

首次基线尝试因启动超时未产生有效样本；核对目标后重启模拟器、保留数据重新采样。新版第一次首页就绪采样在第 16 轮遇到 ADB 错误，随后确认设备断开且 Windows 模拟器进程已退出；15／20 的报告保留为不完整结果，不作为最终对照。恢复同一模拟器后最终两个 20 轮组完整通过。失败期间没有卸载或清数据，也没有清空 logcat。

build104 安装后已核对 versionCode 4104、APK SHA-256 与构建产物一致，采样结束保持应用前台运行。[精简验收摘要](verification/startup-ui-20261014.json) 记录版本、摘要和各组统计；原始报告、失败尝试与元数据保留在本地 `dist/verification/startup-20261014/`。

后续使用同一 ARM64 真机、记录模块版本和数据规模，导出 profile Timeline 定位包校验、worker 加载和首页查询耗时，再决定懒加载或维护任务后移。新版新增的首页指标无法直接与没有该指标的旧 APK 比较。

## 脚本验证

```bash
python3 -m unittest discover -s scripts/tests -p test_benchmark_startup.py -v
```

测试模拟 subprocess 输出，覆盖原始字段保留、缺失可选字段、错误状态、冷启动进程验证、ADB 超时／错误、失败样本剔除、PID 检查、统计口径、就绪 token 匹配、失败 outcome、超时和命令行校验，不连接或修改设备。Flutter 回归 `startup_readiness_test.dart`、`app_shell_startup_test.dart`、`workspace_page_transition_test.dart` 分别验证一次性报告、恢复路径、实际内容与转场就绪，以及过时页面隔离。

## 2026-10-14 第二轮深层优化

首轮查询批处理之后，继续针对实际启动路径修改运行时，三项实现分别对应不同成本：

| 修改 | 实际行为与保护 |
| --- | --- |
| SQLite 初始化线程 | 版本探测、SQLite binding 初始化与 schema 1 备份由同一数据库 isolate 执行；`AppDatabase.open()` 等待首次查询就绪后返回。原文件仍以 SQLite backup API 一致备份，备份失败不迁移，已有备份不覆盖 |
| worker 通知 | 原生输出队列从空到非空时用 `NativeCallable.listener` 通知 Dart，代替周期探测；结果、异步 host 回复与订阅沿用现有队列。关闭先停止并 join 原生线程，再释放监听器，保留 owner zone、双 worker 隔离与安装事务 |
| 包对象复用 | 已解压的独占缓冲区直接冻结，减少第二份文件复制；脚本 UTF-8 只解码一次，每次 getter 返回独立 Map；来源恢复复用已验证声明。每次启动仍读取文件并执行原有完整校验规则，不用文件属性或历史摘要代替验证 |

这是线程、调度与重复工作的优化，没有全模块懒启动，也没有改变脚本顶层副作用发生时机。数据库阶段涉及路径调用、线程启动、打开与迁移；仅凭 `database.open` 总时间不能将全部成本归因于 SQLite。

### 微基准

Linux 本机真实 QuickJS，30 轮；测量范围包含构造／load 与顶层 await，串行桥接为 12 次 host 往返：

| 指标 | 原实现 p50／p95 | 优化后 p50／p95 |
| --- | --- | --- |
| worker 构造与 load | 3840／4034µs | 754／1178µs |
| 12 次串行桥接 | 25989／26177µs | 1846／2688µs |
| 空闲一秒内 worker 定时器数 | 20 | 0 |

工具为 `client/tool/benchmark_script_worker.dart`，原始前后样本保存在本地 `dist/verification/startup-deep-20261014/worker-before.json` 与 `worker-after.json`。这是消息调度与本机耗时的证据，不是 Android 启动、CPU、耗电或电池寿命测量。

包层工具 `client/tool/benchmark_module_package.dart` 完整验证每轮输入。四份约 264KB Unicode 脚本的重复 getter p50／p95 从 4699／5191µs 降至 7／16µs；120 次累计从 571164µs 降至 1023µs。完整合成包校验 p50 从 13047µs 到 13054µs，三个默认包校验从 2314µs 到 2413µs，未显示完整校验提速。记录区分消除重复解码与每次完整验证，不以局部大幅下降声称整机等比例改善。

### 分阶段采样

默认正式构建不记录阶段聚合。要采样，使用相同源码和 ABI 构建带 `--dart-define=XUDIAN_CAPTURE_STARTUP=true` 的 release，再运行：

```bash
source scripts/dev-env.sh
python3 scripts/benchmark_startup.py \
  --serial emulator-5554 --runs 10 --interval 2 --check-pid \
  --wait-ready --capture-phases \
  --output /tmp/startup-phases.json
```

`--capture-phases` 必须与 `--wait-ready` 同用；脚本从当前 PID 的 `XudianStartupPhases` 读取同一启动 token 的白名单阶段，收到 `complete=true` 才接受该轮。就绪与阶段读取共用超时预算，坏字段、重复分组或缺少完整标记均拒绝当轮，不保存原始日志正文。release 的阶段采样与 Dart Timeline 开关独立。

`samples.startupPhases` 保存 `name/count/elapsedUs` 和可选模块／worker 身份；`summary.startupPhases` 分组统计样本数与耗时、计数的 p50／p95／min／max。最多 96 组，聚合在就绪后清空并停止；超出组数的后续组不记录。`database.open` 包含新增 `database.ready`；宿主恢复、初始化、包验证等也存在嵌套，不能相加。

当前装有的 8 个模块可从阶段组身份核对，但本轮未导出业务数据量或用户内容。诊断基线 build105 保留优化前运行时；候选 build106 使用同一诊断开关。最终 build107 关闭开关，避免常规启动持续采样。APK、元数据、每轮原始计时和并行负载标记留在本地 `dist/verification/startup-deep-20261014/`。

### 验收与限制

完整 **1,147 项 Flutter**、**190 项 Python**、完整静态分析、仓库及架构检查通过；组合定向回归 **51 项**通过。回归覆盖 schema 1 备份与失败不升级、真正签名篡改、同长度内容替换、双 worker 初始化与全局状态隔离、100 轮通知／关闭压力、晚到 host 回复、安装事务／迁移回滚和真实首页读取。构建指纹已包含 `packages/xquickjs` 的 Dart、C、vendor 头文件、构建 hook 和包声明，避免仅改运行时却复用旧 APK。

模拟器阶段和最终 release 数据见本节后续结果表及 [精简记录](verification/startup-deep-20261014.json)。诊断版、普通 release、并行构建／测试以及模拟器重新启动后的组分别报告；它们不是一个统一对照组。现有数据不支持将微基准收益换算成稳定的整机冷启动百分比。ARM64 真机与 Windows 原生通知生命周期、低端设备以及大数据量启动仍需分别验收。

### 设备结果与交付

| 组别与条件 | 完成轮次 | `TotalTime` p50／p95 | Activity 创建到工作区就绪 p50／p95 |
| --- | --- | --- | --- |
| build104 普通 release，原设备状态 | 10／10 | 950.5／1063ms | 1368.5／1516ms |
| build105 同开关诊断基线 | 10／10 | 1344／1833ms | 1839／1950ms |
| build106 诊断候选，Flutter 全量回归并行 | 10／10 | 1400／1704ms | 1913／2060ms |
| build106，全量 Flutter 结束后；期间短暂执行 Python 工具检查 | 10／10 | 1358／1471ms | 1769.5／2057ms |
| build106 扩大采样；最终 APK 编译与本组重叠 | 20／20 | 1466.5／1647ms | 1955／2347ms |
| build107 普通 release，模拟器退出导致未完成 | 10／20 | 不作为完整对照 | 不作为完整对照 |
| build107 普通 release，恢复同一模拟器后，无并行构建或测试 | 10／10 | 721.5／1036ms | 987／1311ms |

10 轮阶段诊断中，`host.initialize` p50 从 520.5ms 到 396.3ms，当前首页 `app.ui.examples` 的 `page.execute` 从 16.0ms 到 7.8ms；所有顺序 worker load 持续时间按每轮相加的中位数从 87.7ms 到 54.2ms。此加法只覆盖依次完成的 load 调用，不包含构造、不与宿主总阶段相加。期间负载不同、数据库 `open` 的就绪边界也已变化，因此这些值是观察结果，不能单独证明某项代码的精确收益。扩大组未稳定复现整体提速，完整数据全部保留。

最终普通 release 的完整 10 轮首页就绪中位数为 **987ms**，p95 为 **1311ms**。它是在模拟器重新启动、排除第一次应用打开后取得，先前普通基线与它没有在相同模拟器状态下交错测量；不能将差异全部归因于改动或宣称稳定提速百分比。脚本／微基准证明了调度等待和重复解码成本减少，整机结论继续受测量范围限制。

最终 20 轮尝试在第 11 轮 `am start` 返回 255，随即确认 ADB 无设备且 Windows 模拟器进程已退出，故报告标为 `complete: false`。同类断开在前一轮未改造 worker 的 build104 验收中已发生；本轮没有取得模拟器退出原因，不能据此证明应用崩溃或排除平台问题。恢复同一 AVD、原 60Hz 与现有数据后，完整 10 轮通过，应用保持前台运行。

交付 **build107 / versionCode 4107**，普通 release 未启用阶段聚合开关。设备 APK 与最终产物 SHA-256 相同；原数据与模块保留。构建缓存与最近成功记录同步到该版本，原始失败报告不覆盖。没有提交、推送或发布。
