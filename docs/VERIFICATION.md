# 验证记录

本页索引实际执行证据，测试数量只代表对应日期和范围。生产代码的 `host_*`、`script_*`、`schedule_*` 等回归与旧行为夹具分别核对；Linux 测试不能替代各平台运行及性能验收。

## 最近记录

| 日期与范围 | 结果与证据 |
| --- | --- |
| 2026-10-12 v0.2.0-beta.1 发布准备 | 测试版标签校验支持 alpha／beta／rc 编号并要求与客户端完整版本一致；GitHub 工作流在全部检查、测试和三 ABI 构建通过后发布 Pre-release，禁用 Latest，正式版固定签名要求保持。发布准备阶段 70 项脚本测试与 36 项模块目录／发布测试全部通过，actionlint、100 文件架构检查、8 项目录条目校验及暂存差异检查通过。提交当前预装包替换记录后，554 文件仓库边界检查通过，原 6 个旧包索引阻断解除。此前唯一超时的 `host_network_test.dart` 本次独立复验 3 项全部通过；这不回写此前全量 828／829 的实际结果。远端最终回归、构建及发布状态以该版本 [Actions](https://github.com/JayConstruct/xudian/actions/workflows/android.yml) 与 [Release](https://github.com/JayConstruct/xudian/releases/tag/v0.2.0-beta.1) 为准。测试版使用 CI 开发签名，覆盖安装兼容性及真机性能未验证。 |
| 2026-10-12 任务列表身份与提交反馈 | API 升至 `1.20.0`，日程模块 `app.views.today 1.6.2` 使用通用 `keyedList`：稳定 key 保留行状态，成功提交后才执行 220ms 收拢退出或 900ms 新增高亮；普通刷新、分页、日期切换与审核取消不重播完成效果。独立根列表保留惰性构建及重排索引，内联列表仍为自然高度。最终 Flutter 全量实际结束于 4 分 46 秒：829 项中 828 项通过，唯一失败为既有 `host_network_test.dart` 的请求取消／模块撤销用例 30 秒超时；本轮未修改网络实现。任务动画文件 9 项另行完整通过，静态分析零问题、100 文件架构检查、11 项打包边界回归与差异检查通过；6 个当前包摘要及默认安装标记核验通过，仅日程包更新，旧 1.6.1 已归档。覆盖首次反馈、连续提交、减少动画、退出交互／语义撤下、离屏退出释放、历史任务保留、冲突提交无成功反馈，以及内联／独立列表输入 Element、焦点、选择保留。两尺寸组件组合预览经审阅：[390 浅色新增高亮](../dist/verification/task-motion-20261012/390-added.png) / [320 深色双倍字体](../dist/verification/task-motion-20261012/320-added.png) / [收拢中间帧](../dist/verification/task-motion-20261012/320-removing.png)。首轮发现的反馈延迟初始化缺陷已修复；新增测试夹具的异步安装等待及脚本括号错误修正后，相关整文件已正常退出，完整测试重新执行并保留上述唯一网络失败。[最终完整日志](../dist/verification/task-motion-20261012/flutter-full.log)。这是视觉身份与状态保留优化，未改变服务查询或跨桥传输范围；上方插入可让输入离开视口，但保留焦点和草稿，未新增自动滚动策略。未部署设备或验证真机帧率；仓库检查仍受本轮前 6 个旧包 Git 索引记录阻断。 |
| 2026-10-12 日程公共动效与大字体可读性 | 宿主日期节奏统一为 180ms，快速添加高度／透明度过渡为 220ms；整页切换仍为 360ms，底栏弹簧保持原参数。API 升至 1.19，`app.views.today 1.6.1` 使用可保态折叠及审核提交后的成功提示。全量 Flutter 816 项中 815 项通过，唯一失败为旧测试要求隐藏输入从脚本树移除；按新的 collapse／visible 契约修正，最终受影响 8 个文件共 37 项全部通过（24 秒）。静态分析零问题、99 文件架构检查、11 项打包边界回归及差异检查通过；预装资源只更新日程版本／摘要，默认标记和其它模块包保持。新增测试验证自然高度内联列表在 51→52→51 项变化时输入 Element、焦点、选择及 composing 保留，折叠撤焦点、重开不抢键盘，快速日期反转与减少动画，日期条横滚保持及选中日可见；大字体课程改为时间上置、正文全宽。两尺寸真实组合离屏截图经审阅：[390 浅色](../dist/verification/ui-motion-20261012/xudian-ui-motion-390-overview.png) / [320 深色双倍字体](../dist/verification/ui-motion-20261012/xudian-ui-motion-320-overview.png)。首轮新增测试异步 zone 与语义资源释放问题已修复；最终全量后局部响应式和等效 lint 修正采用受影响定点复验，没有第二次最终全量。任务行离场动画、惰性列表重排协议及真机 FPS／键盘动画性能未实现或验证；仓库检查仍因本轮前 6 个旧预装包已删除但索引跟踪而阻断。 |
| 2026-10-12 任务分批扫描与脚本工作线程轮询 | 静态分析、98 文件架构检查与 11 项模块打包回归通过。807 项 Flutter 全量运行中 806 项通过，1 项既有课表高对比度测试的滤镜数量断言过时；修正为非空且全部禁用模糊后，该文件 5 项完整复验通过。首轮发现的跨 Zone 定时器归属问题和过期模块更新夹具已修复，相关 18 项回归通过。`app.tasks 1.3.1` 以每页 1000 条流式搜索与统计，10005 条夹具的早期搜索仅跨桥读取 1000 条，尾部搜索和完整统计各读取 11 页／10005 条；中文、Unicode 大小写、匹配后分页、前 50 项状态、暂存写集与快照冲突均有回归。虚拟时钟一秒空闲轮询 17 次、待返回请求 32 次，对照旧固定 8ms 的 125 次；这是调度计数，不是 CPU、内存峰值或耗电真机基准。预装包仅任务版本／摘要更新，其他身份及默认标记保留；仓库检查仍被本轮前已删除但 Git 索引跟踪的 6 个旧预装包阻断。性能仍需 Android／Windows 设备测量。[任务扫描](../client/test/task_scan_pagination_test.dart) / [调度与 Zone](../client/test/worker_poll_scheduler_test.dart) / [原生异步回归](../client/test/script_worker_test.dart)。 |
| 2026-10-10 目录与发布流程整理 | 从暂存快照生成独立干净检出，通过仓库边界检查、78 文件架构检查、53 项开发脚本测试和 36 项模块目录/发布测试。20 个索引引用包迁至 `releases/modules/`，所有字节和摘要不变；6 个无版本客户端包、4 个已下架包取消跟踪并保留本机副本。`--defaults` 重跑未改变清单或包，升级时旧资源归档与冲突拒写有回归覆盖。当前快照与历史 `00f6` 快照均用当前工具成功准备同一 tag 的 2 个资产；旧 tag、Release 地址与原包保持不变。完整日志在本机 `.cache/repository-clean-checkout.log`，检查命令见 [开发指南](../DEVELOPMENT.md#github-提交范围)。 |
| 2026-10-10 Android 从零安装与商店 | 独立 x86_64 模拟器用户 11 原先未安装 App；本机 build53 首装进入空白今天页，从默认在线商店安装拾光 1.4.0，并自动补齐课表 1.7.0。版本、权限、未签名提示和两包 SHA-256 审核通过；重启后两者启用、课表和拾光设置可打开，APK 摘要不变。[验收报告](verification/fresh-install-20261010.json)。采集进程曾发生 UIAutomation 连接超时，保留首轮失败记录，增强采集重试后基于原首装证据恢复并完成验收；未清除或卸载原用户数据，验收后已切回原用户。 |
| 2026-10-10 GitHub Actions 干净构建 | 最终源码提交 [0b80430](https://github.com/JayConstruct/xudian/commit/0b8043033b70872f900f3a048da777af12653d20) 的 [Android 工作流](https://github.com/JayConstruct/xudian/actions/runs/38021150220) 成功：静态分析、78 文件架构检查、60 项 Python 测试（脚本 36 项、模块发布 24 项）及 631 项 Flutter 回归通过，ARMv7 / ARM64 / x86_64 Release APK 全部编译成功。[下载产物](https://github.com/JayConstruct/xudian/actions/runs/38021150220/artifacts/11657938170) 含源码提交号及 SHA-256，保存至 2026-10-24 03:43 UTC。已修复初次 SDK `tools` 包安装失败、Release 草稿可见性问题及原生异步响应触发导航时测试未等待动画结束的偶发失败；最终全量 CI 通过。三 ABI 编译不代表 ARM 真机运行验收。 |
| 2026-10-09 完整 Android APK | 0.1.0 / build50 的 ARMv7、ARM64、x86_64 与通用 Release APK 构建完成，版本、签名、ABI/原生库及已移除模块资源核验通过；签名与模拟器 build50 一致，沿用项目测试密钥。源码未变，复用已有分析和 46 项相关回归；ARM 真机运行未验证。[构建记录](../dist/apk-build50/verification.json) / [完整下载包](../dist/xudian-0.1.0-build50-apks.zip) |
| 2026-10-09 布局设置子页面 | 46 项布局、设置与底栏相关测试通过；静态分析及架构检查通过。build50 将导航、右上角菜单和常用/隐藏入口分到子页，共用未保存草稿；补充延迟保存期间返回的回归，防止完成保存后多退一层。模拟器验证分类摘要、子页隔离及系统返回，未保存设备布局。[验收结果](../dist/verification/layout-subpages.json) |
| 2026-10-09 布局可视编辑 | 45 项布局、设置、底栏及新交互测试通过；静态分析与 78 文件架构检查通过。build48 展示底栏/侧栏及展开菜单，点选只编辑草稿；模拟器已验证入口检查器及高级模式往返，设备验收未保存布局配置。[验收结果](../dist/verification/layout-visual-editor.json) |
| 2026-10-09 移除收件箱与项目视图 | 45 项相关 Flutter 回归通过；静态/架构与 8 项模块目录检查通过。build47 覆盖安装后，两模块显示已卸载、数据保留；重启后导航及更多菜单入口消失，原有课表课程仍在。[验收结果](../dist/verification/remove-view-modules.json) |
| 2026-10-09 更新流程优化 | 36 项 Python 脚本测试、25 项页面回归通过；静态/架构检查通过，debug 热重载与模块摘要校验实测通过。[流程结果](../dist/verification/emulator-workflow/result.json) |
| 同轮模拟器 Release 更新 | build46 覆盖安装后课程保留；首次流程约 49 秒，无改动复用约 0.23 秒。[首次](../dist/verification/emulator-workflow/release-first.json) / [复用](../dist/verification/emulator-workflow/release-cached.json) / [模块摘要](../dist/verification/emulator-workflow/module-digest.json) |
| 设置与拾光发布 | 当时版本、全套回归及发布验收见 [发布记录](archive/MODULE_RELEASE_20261009.md) |
| 脚本宿主与迁移 | 初次交付和平台实施差异见 [宿主验收](archive/MODULE_HOST_VERIFICATION.md) |
| 公共 UI 与模块目录 | [界面包验收](archive/UI_PACK_VERIFICATION.md) / [目录验收](archive/MODULE_CATALOG_VERIFICATION.md) |

2026-10-12 网络超时的独立复验停在 Flutter 测试的 `setUp → HttpServer.bind(loopbackIPv4, 0)`，未进入取消或撤销操作；带明确超时的原生 Dart 监听探针正常退出。两种现象不能认定为同一原因，原全套的 30 秒取消超时仍未定位。诊断运行已停止，网络实现、用例和 timeout 均未修改。

表中 build46 是该轮设备记录，不能用来替代后续设备查询；缓存耗时仅为当时模拟器与工作区条件。

## 复验入口

常用检查与更新命令统一见 [开发指南](../DEVELOPMENT.md) 和 [模拟器更新](EMULATOR_UPDATE.md)。课表及拾光的相关测试、只读复验脚本和历史运行范围保留在 [归档索引](archive/README.md)。需要 profile 模式与真实设备测量帧耗时、内存和启动/切换性能；功能测试不证明 FPS。

真实学校账号/网站、Android ARM64 真机、Windows 构建与安装的验证须分别记录。已有学校快照审计、模拟 DOM 采集和 x86_64 截图不代表这些场景已经通过。

新增验收时记录日期、版本、具体检查范围、结果、数据保留及证据路径，保留失败和未验证范围。完整验收产物位于被 Git 忽略的 `dist/verification/`；供公开复验的精简报告可脱敏后保存在 `docs/verification/`。归档中的本机构建/截图可能不在其他检出工作区。索引引用的不可变模块包位于 [发布目录](../releases/README.md)，历史记录中的旧目录路径保留当时含义。
