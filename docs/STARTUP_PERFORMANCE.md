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

## 脚本验证

```bash
python3 -m unittest discover -s scripts/tests -p test_benchmark_startup.py -v
```

测试模拟 subprocess 输出，覆盖原始字段保留、缺失可选字段、错误状态、冷启动进程验证、ADB 超时／错误、失败样本剔除、PID 检查、统计口径、就绪 token 匹配、失败 outcome、超时和命令行校验，不连接或修改设备。Flutter 回归 `startup_readiness_test.dart`、`app_shell_startup_test.dart`、`workspace_page_transition_test.dart` 分别验证一次性报告、恢复路径、实际内容与转场就绪，以及过时页面隔离。


## 运行时实现边界

启动路径还包含以下实现，解释阶段采样时应区分其成本：

| 修改 | 实际行为与保护 |
| --- | --- |
| SQLite 初始化线程 | 版本探测、SQLite binding 初始化与 schema 1 备份由同一数据库 isolate 执行；`AppDatabase.open()` 等待首次查询就绪后返回。原文件仍以 SQLite backup API 一致备份，备份失败不迁移，已有备份不覆盖 |
| worker 通知 | 原生输出队列从空到非空时用 `NativeCallable.listener` 通知 Dart，代替周期探测；结果、异步 host 回复与订阅沿用现有队列。关闭先停止并 join 原生线程，再释放监听器，保留 owner zone、双 worker 隔离与安装事务 |
| 包对象复用 | 已解压的独占缓冲区直接冻结，减少第二份文件复制；脚本 UTF-8 只解码一次，每次 getter 返回独立 Map；来源恢复复用已验证声明。每次启动仍读取文件并执行原有完整校验规则，不用文件属性或历史摘要代替验证 |

这是线程、调度与重复工作的优化，没有全模块懒启动，也没有改变脚本顶层副作用发生时机。数据库阶段涉及路径调用、线程启动、打开与迁移；仅凭 `database.open` 总时间不能将全部成本归因于 SQLite。

## 分阶段采样

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

## 历史基线与待验收范围

| 记录 | 结论与边界 |
| --- | --- |
| [首轮采样](verification/startup-ui-20261014.json) | 模拟器 build103／104 顺序采样没有证实稳定提速；首页就绪与默认采样条件不同，失败组不计为完整对照 |
| [深层优化](verification/startup-deep-20261014.json) | 本机微基准证明调度和重复解码成本减少；模拟器最终完整组首页就绪 p50／p95 为 987／1311ms，未在相同设备状态下交错测量，不能归因或换算整机提速比例 |

原始样本、失败尝试、APK 元数据和微基准保存在本机 `dist/verification/performance/startup-20261014/` 与 `startup-deep-20261014/`。微基准工具为 `client/tool/benchmark_script_worker.dart` 和 `benchmark_module_package.dart`。

下一轮在同一 ARM64 真机固定模块版本、数据规模、诊断开关和后台负载复测。Windows 原生通知生命周期、低端设备和大数据量启动仍待验收；全模块懒启动、启动维护后移须按采样决定，不能破坏顶层初始化、校验与迁移语义。
