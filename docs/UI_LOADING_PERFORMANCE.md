# UI 加载性能

本轮优化覆盖冷启动准备、日程页面读取与日期回访。源码宿主 API 为 1.23.0；日程 1.8.0 已同步到预装资源，课表 1.14.0 为独立候选包。更新 APK 不会自动替换已有安装的模块。线上目录、公开发布和设备安装版本需单独核对。

## 已实现

- 一次恢复内复用已完整验证的模块包，避免依赖后置造成重复解包与校验；每次重新启动仍重新验证持久化包。默认资产恢复采用相同策略。
- 布局读取与宿主恢复并行，选择首个工作区前等待保存布局；读取失败保留默认布局与恢复入口。
- 每模块工作流保持串行，前台请求优先于尚未开始的日期预取。已执行的脚本不强行中断，过期预取仍在开始前检查取消条件。
- 前台无事件结果可种日期缓存；直接或嵌套副作用、未完成桥接、草稿变化、表单清空/替换和上下文改变均阻止重放。保留完整输入和实例身份，不把返回状态重新映射为请求状态。
- 日期缓存按同步依赖修订失效，无关模块写入可保留缓存。进行中请求继续使用全局修订保护；批安装只在最外层事务成功后发布修订。UI 偏好相同值写入不再发失效通知。
- 缓存最多每贡献 5 份，期限从请求开始计算，最多 30 秒且不跨分钟；慢请求、时间回退、模块变化、恢复前台仍有失效保护。
- 日程批量转换任务时间，50 个精确计划的转换桥接由 100 次变为 1 次；课表复用已读取的课表记录并同时派发独立集合查询，减少脚本往返等待，不假定 SQLite 并行执行。

## 本地计时

`UiLoadTrace` 输出到 Dart Timeline，debug/profile 默认开启，release 默认关闭；可用 `--dart-define=XUDIAN_TRACE_UI=false` 关闭，或显式设为 `true`。不记录任务内容、表单、时间戳参数、凭据或异常正文；不联网发送、不持续积累内存样本。测试可以通过 `UiLoadTrace.observe` 获取隔离于其他测试的样本。

| 事件 | 测量范围 |
| --- | --- |
| `app.start` | Dart 入口标记，不包括原生进程/引擎启动 |
| `database.open` | 数据库对象准备；Drift 延迟打开的实际查询还包括在后续阶段 |
| `host.restore` / `host.initialize` | 模块、迁移、默认资源等准备 |
| `host.package.verify` / `host.bundle.verify` | 已安装包读取校验／预装包校验 |
| `host.worker.load` | 单个计算或工作流 worker 加载入口 |
| `shell.restore` | 宿主与布局就绪到壳层解除恢复状态 |
| `page.queue` | 单次页面调用等待工作流的时间 |
| `page.execute` | 脚本页面执行，包含等待桥接的时间 |
| `page.bridge` | 单次宿主能力调用，含能力名和模块 ID |
| `page.cache` | 日期缓存命中或未命中计数 |
| `page.firstFrame` | 页面门控建立至可用子树完成 Flutter 绘制；不等于屏幕呈现时间 |

阶段存在嵌套，不能直接将所有持续时间相加。绘制门控结束也不等于切换动画结束或平台屏幕已经呈现。

## 验收

在同一 ARM64 真机上运行 `flutter run --profile`，用 DevTools Performance 录制并导出 Timeline。分别记录已安装应用的进程冷启动、首次安装、首次打开日程/课表、保留工作区回访、日期缓存命中/未命中、快速反向切日和写入后刷新。结合平台启动指标、页面门控和动画结束分别报告可见内容与可交互耗时，记录 p50/p95、UI/raster 超预算帧、桥接次数与缓存命中率。使用固定模块版本和相同数据集，低数据量与大数据量分别比较。

Node 的等价与调用次数测试：

```bash
node --experimental-vm-modules scripts/module_host/page_reads_performance_test.mjs
```

核心真实 QuickJS／缓存／恢复回归位于 `page_read_performance_test.dart`、`module_startup_test.dart`、`app_shell_startup_test.dart`、`page_preparation_test.dart`、`collection_revision_test.dart`、`date_page_cache_test.dart` 和 `ui_pack_script_page_test.dart`。

调用次数减少是可重复的结构证据，不能换算为真机提速百分比。全模块懒启动、日期统计聚合下推及动画/GPU 开销仍需结合真实采样决定；本轮没有改变既有日期统计语义或视觉效果。
