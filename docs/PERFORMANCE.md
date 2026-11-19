# 启动与页面性能

本文记录冷启动测量口径、页面加载实现及复验方法。最新结果见 [验证索引](VERIFICATION.md)，宿主能力见 [SDK](MODULE_SDK.md)。

## 进程冷启动采样

### 当前测量口径

`scripts/benchmark_startup.py` 为已安装的 Android 应用建立可重复的**进程冷启动／Activity 启动与首次显示代理指标**。每次先 `am force-stop`，用 `ps -A -o PID,NAME` 确认主进程及 `package:worker` 子进程均已退出，再执行 `am start -W`；保存 Android 原始 `ThisTime`、`TotalTime`、`WaitTime` 和每次启动的完整 `am` 输出。可加 `--check-pid` 验证启动后主进程存在。

这些 `am` 指标**不等于首页内容就绪、可交互时间或 TTFD**。应用仍可能显示恢复状态、等待模块初始化或加载首页内容。Android 将首次显示（TTID）与完全显示（TTFD）区分；本脚本采用 `am start -W` 的输出作为前者的便捷代理。客户端已接入 `reportFullyDrawn`；平台 TTFD 需通过 Android 系统启动 trace 或 `Fully drawn` 日志另行读取，不从本脚本的 `am` 字段推算。[Android 官方启动指标说明](https://developer.android.com/topic/performance/issues/launch-time)

脚本保留应用数据与文件系统缓存，不卸载、不清理数据、不修改系统设置、不清空 logcat。重复 `force-stop` 只确保进程重新创建，不模拟首次安装、设备刚开机或存储缓存全冷。采样结束应用保持启动状态。

### 运行

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

### 结果解释与比较

报告中的 `summary` 分别统计三个指标，单位毫秒：p50 为样本中位数；p95 采用 nearest-rank（排序后第 `ceil(0.95 × n)` 个样本）；同时保留 count/min/max。`samples` 保存每轮原始值和启动前无进程的验证结果。

前后对比固定以下条件：

- 同一设备、Android 版本、APK 构建模式与 ABI，记录 APK 摘要和版本。
- 相同已启用模块版本、首页、工作区和数据量；保留数据的数据库迁移与缓存状态单独说明。
- 相同采样次数、轮次间隔、屏幕状态和后台负载；先后顺序可能受温度、系统负载与缓存影响，必要时交错复测。
- 将首次安装、升级后的第一次启动、日常保留数据冷启动分开，避免混在同一个 p50/p95 中。

模拟器数据用于本地回归比较。面向用户的性能结论应在同一 ARM64 真机上复测。Flutter 官方性能分析建议使用真机和 profile 模式；release 的平台启动指标可作为另一组单独对照。[Flutter 官方性能分析说明](https://docs.flutter.dev/perf/ui-performance)

### 首页就绪与平台接入

`main()` 从 Dart 入口开始记录 `app.firstFrame` 和 `app.workspaceReady`；前者在首个 Flutter 帧的 post-frame 回调结束，后者等待当前工作区页面、脚本与组合区域的首轮内容准备，并在页面可见、入口转场完成后的 Flutter 帧结束。隐藏缓存页、过时目的页不会报告当前页面就绪。正常空数据属于就绪内容；渲染器返回带恢复操作的终态错误树也可能解除页面门控，因此此指标表示可用内容树，不保证网络成功、业务数据正确或所有操作成功。

当工作区满足上述条件，Android `MainActivity` 只调用一次 `reportFullyDrawn()`，并输出 `XudianStartup` 本地标记。壳层恢复失败或没有可用工作区分别报告 `restoreError`／`noWorkspace`，不调用完全显示 API；这些轮次不计入成功首页样本。布局读取失败但默认工作区正常展示仍属于就绪，恢复入口保留。

新 APK 支持在采样命令中增加 `--wait-ready --ready-timeout 30`。脚本读取本次启动主进程 PID，等待 `XudianStartup` 标记中匹配本轮随机 token 的 outcome；无需清空 logcat，历史启动或 PID 复用的旧标记不能满足本轮条件。只保存固定 outcome 和整数耗时，不保存其他日志正文。旧 APK 没有标记，应使用默认模式；启用等待会超时并保留失败报告。

额外指标 `ActivityCreateToWorkspaceReadyMs` 从原生 `Activity.onCreate` 进入到上述业务就绪报告，使用 Android 单调 uptime 时钟。**它不包含此前的进程创建，也不是平台 TTFD**，不得与 `TotalTime` 相减作为页面加载或引擎启动耗时。schemaVersion 2 的报告包含该指标独立 count/p50/p95/min/max；未启用等待时 count 为 0、统计为 null。成功就绪后才开始计算轮次间隔，减少上一轮尚在加载时就结束进程的问题。

profile 的 Dart 阶段分析继续使用 `UiLoadTrace` 与 Flutter Timeline，见 [本地计时](#本地计时)。release 默认关闭 Timeline，但原生就绪标记和 `reportFullyDrawn` 仍可用于上述流程。阶段存在嵌套，不能相加并冒充完整启动时间。

### 脚本验证

```bash
python3 -m unittest discover -s scripts/tests -p test_benchmark_startup.py -v
```

测试模拟 subprocess 输出，覆盖原始字段保留、缺失可选字段、错误状态、冷启动进程验证、ADB 超时／错误、失败样本剔除、PID 检查、统计口径、就绪 token 匹配、失败 outcome、超时和命令行校验，不连接或修改设备。Flutter 回归 `startup_readiness_test.dart`、`app_shell_startup_test.dart`、`workspace_page_transition_test.dart` 分别验证一次性报告、恢复路径、实际内容与转场就绪，以及过时页面隔离。


### 运行时实现边界

线程、包复用、恢复查询与日期缓存的现行行为见 [UI 加载机制](#已实现)。数据库阶段包含路径准备、线程启动、打开与迁移，不能将总耗时全部归因于 SQLite；阶段嵌套也不能相加。

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

### 后续验收

下一轮在同一 ARM64 真机固定模块版本、数据规模、诊断开关和后台负载复测。Windows 原生通知生命周期、低端设备和大数据量启动仍待验收。全模块懒启动及启动维护后移需结合采样决定，并保留顶层初始化、校验与迁移语义。

## 页面加载

### 已实现

- SQLite 加载、版本探测与迁移前备份在同一数据库 isolate 执行，首次查询就绪后才返回数据库；schema 1 备份失败仍不允许升级，不覆盖已有备份。
- 脚本 worker 由原生输出队列从空到非空的通知唤醒 Dart，移除周期轮询；关闭时先停止并 join 原生线程，再释放监听器。计算与交互 worker 隔离、依赖激活顺序和安装事务保留；模块可通过 `workflowStartup` 显式选择交互运行时初始化时机，见 [运行时约束](MODULE_HOST.md)。
- 不可变验证包复用脚本 UTF-8 解码结果；每次调用仍返回独立脚本 Map。解压文件移除二次复制，持久化来源恢复复用已经冻结的声明与 UI 编译结果；输入快照、CRC、逐文件 SHA 与原有来源／签名校验规则保留。
- 恢复时一次连接查询读取所有启用安装及包来源，减少逐包查数据库；预装来源回填合并为一次 SQL，保留用户来源与空目录行为。
- 一次恢复内复用已完整验证的模块包，避免依赖后置造成重复解包与校验；每次重新启动仍重新验证持久化包。默认资产恢复采用相同策略。
- 布局读取与宿主恢复并行，选择首个工作区前等待保存布局；读取失败保留默认布局与恢复入口。
- 每模块工作流保持串行，前台请求优先于尚未开始的日期预取。已执行的脚本不强行中断，过期预取仍在开始前检查取消条件。
- 前台无事件结果可种日期缓存；直接或嵌套副作用、未完成桥接、草稿变化、表单清空/替换和上下文改变均阻止重放。保留完整输入和实例身份，不把返回状态重新映射为请求状态。
- 日期缓存按同步依赖修订失效，无关模块写入可保留缓存。进行中请求继续使用全局修订保护；批安装只在最外层事务成功后发布修订。UI 偏好相同值写入不再发失效通知。
- 缓存最多每贡献 5 份，期限从请求开始计算，最多 30 秒且不跨分钟；慢请求、时间回退、模块变化、恢复前台仍有失效保护。
- 日程批量转换任务时间，50 个精确计划的转换桥接由 100 次变为 1 次；课表复用已读取的课表记录并同时派发独立集合查询，减少脚本往返等待，不假定 SQLite 并行执行。

### 模块源码与商店

源码编辑改为专用分文件界面，模块定义独立显示为 `module.json`，源码按实际换行显示。后台准备和组装完整文件，输入框只布局当前片段，避免将全部文件转义后塞入单个超长 JSON 段落。支持当前文件全文查找、完整复制和新增／删除文件；片段拼接保留原始内容。保存仍经过模块 ID 检查、隔离预览和摘要绑定的原审核流程。

模块管理列表复用安装读取和默认资源的 Future，普通筛选与布局重建不重新查询；宿主实例或模块注册变化才更新安装列表。SQL 只提取名称、说明和类型，避免每行读取及反复解码完整模块定义。刷新查询失败时显示错误与重试入口，避免帧间错误成为未处理异步异常。

商店索引请求限制并发数，每帧合并界面更新并缓存兼容稳定版本；可见行懒布局保留大字号自适应高度。展示缓存不替代安装和依赖解析时的完整校验。

模块管理详情与商店共用安装快照读取：一次连接查询取得安装状态、包摘要／来源和发布仓库，匹配 ID、版本、摘要与来源后复用已验证包。停用模块首次读取仍完整校验，之后可在本页复用；保留数据卸载的模块也能查看详情。详情先绘制可关闭的加载窗口，再读取包及依赖；关闭、返回或宿主替换后不发布过时结果。每次重开重新读取持久化身份，实际安装仍默认完整校验。

数据审核在打开弹窗时冻结并解析一次计划，字段差异按记录缓存。全量原始详情及长字段值首次展开才准备；大内容在后台编码并分段，每次只布局一段，折叠重开复用已准备结果。模块修改等通用原始 JSON 审核共用该展示组件，全文复制取自同一份已准备内容。此优化没有将计划初次冻结和记录比较移出 UI isolate，大批记录的这部分成本仍需采样。

这些是减少重复校验、查询和布局的结构改进。自动化回归与设备结果见 [验证记录](VERIFICATION.md)，不能据此换算真机帧率或提速百分比。新反馈和规划页面待办见 [体验优化待办](PLATFORM_VERIFICATION.md#待实现与待测性能项)。

### 本地计时

`UiLoadTrace` 输出到 Dart Timeline，debug/profile 默认开启，release 默认关闭；可用 `--dart-define=XUDIAN_TRACE_UI=false` 关闭，或显式设为 `true`。不记录任务内容、表单、时间戳参数、凭据或异常正文；不联网发送、不持续积累内存样本。测试可以通过 `UiLoadTrace.observe` 获取隔离于其他测试的样本。

| 事件 | 测量范围 |
| --- | --- |
| `app.start` | Dart 入口标记，不包括原生进程/引擎启动 |
| `app.firstFrame` | Dart 入口至首个 Flutter 帧结束，不包括此前的原生进程创建与引擎准备 |
| `app.workspaceReady` | Dart 入口至当前可用工作区树可见、入口转场结束后的 Flutter 帧；失败含固定 outcome |
| `database.open` / `database.ready` | 数据库路径与连接准备／数据库 isolate 内实际打开、备份、迁移及首次查询；前者包含后者，不能相加 |
| `host.restore` / `host.initialize` | 模块、迁移、默认资源等准备 |
| `host.restore.packages` / `host.defaults.metadata` | 启用安装及来源的连接查询／预装来源批量回填 |
| `host.package.verify` / `host.bundle.verify` | 已安装包读取校验／预装包校验 |
| `host.worker.load` | 单个计算或工作流 worker 加载入口 |
| `shell.restore` | 宿主与布局就绪到壳层解除恢复状态 |
| `page.queue` | 单次页面调用等待工作流的时间 |
| `page.execute` | 脚本页面执行，包含等待桥接的时间 |
| `page.bridge` | 单次宿主能力调用，含能力名和模块 ID |
| `page.cache` | 日期缓存命中或未命中计数 |
| `page.firstFrame` | 页面门控建立至可用子树完成 Flutter 绘制；不等于屏幕呈现时间 |

Android 已按工作区就绪条件接入 `reportFullyDrawn`；可重复进程冷启动脚本和首页指标口径见 [冷启动采样](#进程冷启动采样)。壳层恢复失败或没有工作区不报告成功首页；门控解除表示可用内容树，不保证所有网络请求或后续业务操作成功。

release 分阶段采样的构建开关、启动 token 与报告口径见 [分阶段采样](#分阶段采样)，该模式与 Timeline 开关独立。

阶段存在嵌套，不能直接将所有持续时间相加。绘制门控结束也不等于切换动画结束或平台屏幕已经呈现。

### 验收

在同一 ARM64 真机上运行 `flutter run --profile`，用 DevTools Performance 录制并导出 Timeline。分别记录已安装应用的进程冷启动、首次安装、首次打开日程/课表、保留工作区回访、日期缓存命中/未命中、快速反向切日和写入后刷新。结合平台启动指标、页面门控和动画结束分别报告可见内容与可交互耗时，记录 p50/p95、UI/raster 超预算帧、桥接次数与缓存命中率。使用固定模块版本和相同数据集，低数据量与大数据量分别比较。

Node 的等价与调用次数测试：

```bash
node --experimental-vm-modules scripts/module_host/page_reads_performance_test.mjs
```

核心真实 QuickJS／缓存／恢复回归位于 `page_read_performance_test.dart`、`module_startup_test.dart`、`app_shell_startup_test.dart`、`page_preparation_test.dart`、`collection_revision_test.dart`、`date_page_cache_test.dart` 和 `ui_pack_script_page_test.dart`。

调用次数减少是可重复的结构证据，不能换算为真机提速百分比。全模块懒启动、日期统计聚合下推及动画/GPU 开销仍需结合真实采样决定；这些加载优化不改变业务日期统计语义。


### 查询与运行时职责

`ScriptWorkerPair` 集中管理运行时加载去重、失败后重建和停用，宿主保留权限、服务和实例注册职责。任务规划声明延迟交互启动；首次前台打开创建交互运行时，日期预取不会创建尚未启动的交互运行时。安装预览通过同一 ready 流程获取运行时。

`CollectionQueryEngine` 负责 SQL 等价校验、分页、回退过滤排序。事务写入仅在同模块、空间、集合匹配时进入叠加路径。回退每批最多读取 256 行，排序以最大堆保留 `offset + limit` 条候选；无排序只保留最终页，仍遍历全量以维持原有过滤语义。读取结束核对集合修订，变化时报错，避免拼接不同修订的数据。

`collection.query` 记录模式 `sql`／`overlay`／`fallback`、模块与集合标识、页参数、叠加写入数、解码记录数和返回条数及耗时；不记录业务值或过滤参数。解码数量不是 SQLite 扫描行数。分块与有界排序控制内存，不能将其解释为所有回退查询都变成了索引查询，也不等同于真机速度数据。

测量规划页等独立模块时，单独记录从打开该页到可用内容树就绪的时间。
