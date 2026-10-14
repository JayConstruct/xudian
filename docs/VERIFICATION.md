# 验证记录

本页索引实际执行证据，测试数量只代表对应日期和范围。生产代码的 `host_*`、`script_*`、`schedule_*` 等回归与旧行为夹具分别核对；Linux 测试不能替代各平台运行及性能验收。

## 2026-10-15 累计改动提交前复验

用户确认将当前全部已验证的累计改动提交到 GitHub，范围包括启动／数据库／QuickJS 通知优化、更新通道、拾光导入流程、源码与商店加载、界面风格统一、相关测试和待办说明。构建产物与本机缓存按仓库规则保留在本地。

完整 Flutter 首轮 **1190 项中 1189 项通过**，唯一失败为拾光首次导入的旧弹窗数量断言：没有课表时当前流程只显示学期配置，不再显示目标选择。修正断言并补已有课表仍显示目标选择的检查，时区整文件 **9 项**通过。第二轮完整复验 **1190 项中 1188 项通过**，两项失败为既有 `host_network_test.dart` 的本机回环 HTTP 超时；没有修改网络实现或增加超时。待其他测试结束后，该文件独立 **3 项全部通过**。不能将分组复验改写为单次全量1190通过；本机网络波动曾在历史记录出现，远端 Ubuntu 结果以 Actions 为准。

Python 工具 **204 项**、模块目录／发布 **36 项**、拾光 Node 兼容 **20 项**、脚本等价与桥接调用次数检查通过；9个目录条目及固定发布包校验、模块候选打包、完整 Flutter 静态分析、134文件架构、暂存仓库边界与差异检查通过。最终提交前仓库检查覆盖新增源码、测试、工具及相对路径验证记录。已有 Android x64 调试打包成功，详见下节；此次提交不创建新 Release 或更新设备。

## 2026-10-15 风格一致性统一修复

三个子 agent 分别完成原生浏览器、商店／管理与源码／弹窗，根 agent 整合主题分发与设置错误恢复。STYLE-01 至 STYLE-07 的实现已统一：学校采集从 Flutter 当前实际主题传递可信颜色和半径，覆盖手动浅深及跟随系统；原生提示框和系统栏同步主题，网页配色保留；按钮至少48dp、按文字扩展并提供可滚动工具区。Android 原生角形按连续角语义绘制，不宣称与 Flutter 逐像素一致。

商店输入、筛选、离线提示、调用方式与脚本折叠区采用公共主题／连续形状；源码、表单与关于页采用公共线性图标。源码／服务／管理弹窗复用公共留白，设置页去掉分区标题重复的水平边距，详情字段区分标签与正文。复制成功使用 Toast，失败可重试；模块管理、外观和界面风格读取失败使用共享错误状态与正确 provider 的重试。恢复及审核仍默认保护，完整内容和操作保留。

同时修复 UX-10 导入／UI包预览异步退出后读取已销毁 ref，以及 UX-11 连续查找逆序与同名文件重建旧结果；对应可控延迟回归通过。剩余性能待办和规划页面未在本轮实施。

定向验证：商店／管理 **33 项**、源码／调用方式／关于／表单／脚本 **43 项**、浏览器与平台桥接 **19 项**、设置／层级／风格选择／更新 **22 项**、真实宿主／界面包／表单／启动 **29 项**通过。最终设置错误／管理样式／源码／调用方式／浏览器／桥接六文件联合 **43 项**通过；首次命令误写调用方式测试文件名导致该文件未加载，改为实际 `code_and_floating_panel_test.dart` 后重新执行完整组通过。组间有重叠，不相加为唯一总数。浏览器主题包含三种 ThemeMode 与两种系统 brightness 的六种组合，以及可信主题不能被脚本参数覆盖。新增布局回归覆盖320宽、浅深主题、两倍字号、键盘和横屏。交叉审查未发现新增阻断问题。

完整 `flutter analyze --no-pub`、134 文件架构、仓库边界及差异检查通过；Android x64 Kotlin 编译和离线 `:app:assembleDebug -Ptarget-platform=android-x64` 成功，产物为 `client/build/app/outputs/apk/debug/app-debug.apk`。Gradle保留既有插件弃用提示，构建成功。Flutter／Gradle本机测试端口经自动审核许可在沙箱外运行。没有提交、发布或安装设备，没有完成原生真机视觉／系统栏返回／实际学校登录／帧率验收。

实现规则见 [界面设计系统](UI_DESIGN_SYSTEM.md) 与 [拾光交互](SHIGUANG_IMPORT_UX.md)，状态见 [风格一致性待办](design/UX_PLATFORM_BACKLOG.md#风格与交互一致性检查)。

## 2026-10-14 模块源码、学校系统栏与商店

按用户要求使用三个子 agent 并行修复前三项，整合时另做只读交叉审查。源码编辑改为后台准备／组装、按文件与片段呈现，保留全文搜索、完整复制、文件增删和原隔离预览审核；大粘贴自动分片，不截断。模块管理列表仅在模块注册或宿主变化时重读，查询失败可重试。学校采集原生窗口显式设置白色背景与深色系统栏图标，覆盖透明栏及脚本提示框。

商店合并安装与来源查询，仅展示路径复用身份／版本／摘要／来源一致的已验证包；实际安装继续完整读取校验。卡片按可见行构建，索引预取最多四路并合并每帧更新，详情先显示加载窗口。交叉审查补修刷新同 ID 更换索引来源的竞态、目录保存后页面退出检查，以及 320 逻辑宽／两倍字号／128 片段页码换行。

实际执行：源码与管理加载两文件 **9 项**通过；商店性能、筛选、布局、目录缓存安全、默认商店安装、安装审核与批安装 **67 项**通过；源码审核、UI 包生命周期、浏览器、拾光及导入表单 **36 项**通过；宿主、仓库入口、默认安装、审核与页面转场组合 **24 项**通过。最终源码／管理／商店／宿主／入口七文件联合复验 **38 项**通过。这些组有重叠，不相加为唯一测试总数。

Android x64 离线 `:app:compileDebugKotlin`、拾光 Node 兼容 **20 项**、完整 `flutter analyze --no-pub`、134 文件架构、仓库边界及 `git diff --check` 通过。Flutter 与 Gradle 首次被沙箱禁止本地 socket，自动审核许可后在沙箱外运行通过。没有提交、发布或安装新 APK，没有执行真实学校登录、真机系统栏视觉或 FPS 测量；以上结构证据不换算真机提速比例。

实现说明见 [UI 加载性能](UI_LOADING_PERFORMANCE.md#模块源码与商店) 与 [拾光导入交互](SHIGUANG_IMPORT_UX.md)，待办见 [新反馈](design/UX_PLATFORM_BACKLOG.md#2026-10-14-新反馈)。规划页面等待用户补充具体要求。

## 最近记录

2026-10-14 新反馈的源码、学校系统栏和商店修复见 [模块页面修复记录](#2026-10-14-模块源码学校系统栏与商店)。任务规划页面等待用户补充具体要求，状态保存在 [体验优化待办](design/UX_PLATFORM_BACKLOG.md#2026-10-14-新反馈)。

| 日期与范围 | 结果与证据 |
| --- | --- |
| 2026-10-14 App 更新测试通道 | `github_app_updates_test.dart`、`app_update_page_test.dart`、`app_update_channel_test.dart` 共 21 项测试通过，覆盖通道切换与持久化、预发布数字排序、测试版到正式版升级、防降级、下载页链接、保存失败及小屏大字体滚动。`flutter analyze --no-pub`、仓库、架构与差异检查通过。Flutter 测试因沙箱禁止回环端口首次无法启动，获准在沙箱外运行；新增设置项后的滚动定位断言已修正复验。[更新规则](APP_UPDATES.md)。本轮未构建安装包、部署设备或发布。 |
| 2026-10-14 UI 加载链优化 | 三个 `gpt-6.1-sol high` 子 agent 分工实施启动、日期缓存和页面读取，整合前台队列及本地 Timeline。最终 230 项相关 Flutter（36 文件）、153 项 Python、Node 真实源码等价/调用次数检查通过；静态分析、129 文件架构与最终工作树仓库检查通过。50 个精确任务时间转换桥接 100→1；三层反向依赖夹具每轮包读取/验证 6→3，重启仍完整验证。API 1.23.0，日程 1.8.0 预装资源已同步，课表 1.14.0 独立候选；ARM64 目标 release 构建成功并核验 APK 内日程摘要。初轮计时参数可变性、测试异步 zone、原生服务夹具及旧审核文案断言问题均修复复验，详见[精简记录](verification/ui-loading-20261014.json)。[实现与采样说明](UI_LOADING_PERFORMANCE.md)。未部署设备、提交或发布，未测真机启动耗时/帧率，不将调用次数减少换算为提速百分比。 |
| 2026-10-13～14 ARM 真机显示与体验验收 | Android 15 ARM64 真机与 Android 17 x86_64 模拟器同签名覆盖至 build117／versionCode2117、4117，逐项审核升级本地课表 1.13.0／拾光 1.6.0 候选包，未清业务数据。系统与新诊断页实测 480／420 DPI、360×800／411.43×914.29 逻辑视口、默认字号 1.0，无显示覆盖；默认密度解释同尺寸约 14.29% 的物理像素差异。真机商店首卡 531.67→267.67dp，前移 264dp；安装／数据审核长文本交给外层滚动，保留完整选择复制。两设备创建／导入默认时区分别为 Asia/Shanghai／UTC，取消后课表列表文字与当前选择逐项一致。模拟器 1.5 字号筛选／键盘／审核取消通过，恢复 1.0；真机 ROM 拒绝 ADB 改字号且原值保持，大字号待真机补验。最终 74 项相关 Flutter、57 项脚本回归、静态分析、127 文件架构、627 文件仓库及差异检查通过，三 ABI release 构建成功。[精简记录](verification/arm-ux-20261013.json) / [本轮详情](#2026-10-13-arm-真机显示与体验验收)。弱网、未知下载长度、实际读屏、Windows 和性能未验收；候选变更未提交发布，线上目录未更新。 |
| 2026-10-13 跨模块导入导航与错误正文 | 宿主工作区导航先校验目标，再关闭覆盖的详情路由／模态面板；Dart／JS 桥接向界面提供业务正文，原始异常文本保留供诊断。51 项相关 Flutter／真实 QuickJS 回归通过，最终正文过滤边界另复验 9 项；静态分析、121 文件架构、627 文件仓库及差异检查通过。Android 15 ARM64 真机与 Android 17 x86_64 模拟器同签名覆盖到 build113／versionCode2113、4113；模拟器原版复现导入停留和 AI 堆栈，两台设备从设置与课表内入口直接进入确认页并保存课程。真机完成后条件撤销仍被阻止，完成记录保留，规划与 AI 提示不含异常前缀或堆栈。真机原商店模块保持；模拟器规划／任务／课表通过商店安装或更新，原数据保留，两设备恢复原工作区与课表选择。真机锁屏曾中断采集，用户解锁后完成；未清数据或卸载。[修复记录](verification/host-navigation-errors-20261013.json) / [完整报告](../dist/verification/android-host-fixes-20261013/report.md)。未调用真实模型、登录教务或测量帧率；修复尚未提交发布。 |
| 2026-10-13 全局 Toast 规范与示例 | 最终 Toast／设置／快捷输入／原生示例／界面包／脚本参数 29 项、图库／组件示例／工作区 17 项、仓库链接／更新／标注／任务流／模块管理 26 项相关回归通过，静态分析、120 文件架构检查及 `git diff --check` 通过。宿主反馈迁至共享 UI，保留 App 兼容导出；同正文与状态去重且不延长计时，根 Overlay 分别管理，长文在安全区与键盘上方局部滚动，保留状态语义和关闭操作。普通原生消息统一接入，安装后的“打开模块”和字段保存失败的“重试”保留可执行提示。`app.ui.examples 1.4.2` 的真实交互包含三状态、长文、1／10 秒、连续／重复和面板内调用；预装资源及摘要已同步，默认启用标记保留。首次测试因沙盒禁止本地端口未加载，获自动审核许可后运行；迁移后旧测试受顶部 Toast 遮挡，补真实关闭步骤再执行页面操作后通过，并修正语义句柄清理。直接仓库检查曾因旧包删除尚未暂存失败，使用临时 Git 索引与对象目录映射最终工作树后，标准仓库检查通过，真实索引未修改。规范见 [Toast](design/TOAST.md)，核心回归见 [app_toast_test.dart](../client/test/app_toast_test.dart)，示例见 [ui_gallery_test.dart](../client/test/ui_gallery_test.dart)。本轮未构建 APK、未进行 Android／Windows 设备视觉、实际读屏或帧率验收。 |
| 2026-10-13 App 与默认商店上线 | 源码 `4703f0c` 提交并发布 [v0.2.0-beta.2](https://github.com/JayConstruct/xudian/releases/tag/v0.2.0-beta.2)，模块 [modules-20261013-runtime-ui](https://github.com/JayConstruct/xudian/releases/tag/modules-20261013-runtime-ui) 的 8 个新包匿名下载与本地字节一致；作者索引与默认目录已同步，两个失效退役条目移除。主分支及 App 标签线上完整检查、Flutter 回归和三 ABI APK 构建成功；本机 958 项完整 Flutter、84 项脚本与 36 项发布工具验证、静态分析和 119 文件架构检查通过。批安装长期 worker 不再保留已结束事务，初始化／迁移仍参加原事务，失败回滚与成功后立即查询均验证。下载公开三 ABI APK 核验签名、SHA256SUMS、SOURCE_COMMIT、ABI／原生库与六个内置模块固定摘要；全新独立 x86_64 Android 17 模拟器直接安装公开 APK，不配置仓库，从默认商店安装拾光 1.5.0 并自动补齐课表 1.11.0，首轮安装提示遮挡底栏中心点击，保留失败记录并校正自动化入口，在同 APK、同用户且不重新安装／不提前重启的首次会话中打开课表／拾光／日程，之后重启再次通过，APK 摘要保持不变；原模拟器与数据保持。[App 发布记录](verification/app-release-20261013.json) / [默认商店匿名复验](verification/module-store-release-20261013.json) / [公开 APK 首装](verification/fresh-install-20261013.json)。本机额外网络复验曾因 WSL socket 绑定与 VM 采样信号迟滞超时，独立 Dart 探针可复现，未修改生产网络代码或提高测试超时，线上 Ubuntu 完整回归通过；不声称该本机环境问题已根治。测试版使用 CI 开发签名；ARM 真机运行、具体学校教务登录及真机帧率未验证。 |
| 2026-10-13 波浪水滴透镜 | 36 项局部透镜／波浪像素／真实日程／日期上下文回归、静态分析、119 文件架构及 554 文件仓库检查通过。窄环带约 1.04 倍局部径向放大、纹理偏移不足 1dp，波前及带边保持原采样位置，旧／新纹理分侧绘制；明暗细肩随原光带淡出。目标首帧就绪时捕获一次完整纹理，不增加动画等待，实际子树仅绘制一次，一组旧／新图上限合计 8MP，替换图像帧后释放。点击保持 480ms，横滑、顶栏即时反馈、五天栏统一揭示及减少动画／高对比行为保持。像素验证纹理折射、不同分辨率、导航静止及目标未揭示角落完整捕获；实际模拟器录屏核对快速反向和手动滑动。build101／versionCode4101 覆盖安装并核对摘要、保留数据。[报告](verification/water-lens-20261013.json) / [录屏](../dist/verification/water-lens-20261013/water-lens.mp4) / [连续帧](../dist/verification/water-lens-20261013/water-lens-frames.png)。仅复验本次受影响范围；图像上限不等于实测峰值内存，未测真机帧率。 |
| 2026-10-13 五天日期栏随波浪刷新 | 53 项相关 Flutter 回归、静态分析、118 文件架构及 554 文件仓库检查通过。五天栏和摘要／课程／任务保留上一画面，所有贡献齐备后随波浪统一揭示，不叠加独立平移及选中背景动画；等待和揭示期间撤下五天栏命中与语义，结束恢复真实控件和手动滑动。顶栏继续即时局部翻页，箭头及菜单支持连续目标修改。延迟查询像素回归核对整栏旧画面保留，真实回归覆盖快速反向、缓存、草稿、写后失效和模块移除。模拟器 build100／versionCode4100 覆盖安装、摘要一致且保留数据，录屏确认五天栏在波浪前沿经过后更新。[报告](verification/five-day-wave-20261013.json) / [录屏](../dist/verification/five-day-wave-20261013/five-day-wave.mp4) / [连续帧](../dist/verification/five-day-wave-20261013/wave-frames.png)。本轮仅复验受影响范围；等待期间可通过顶栏继续选日，未测真机帧率。 |
| 2026-10-12 回到今天移入菜单 | 30 项真实日程／日期上下文／独立日期控件／顶栏租约／菜单回归、静态分析、118 文件架构及 554 文件仓库检查通过。日程正文移除返回行，查看其它日期时菜单首项显示“回到今天”，今天页隐藏；目标沿用概览声明的今天，波浪起点位于右上角菜单按钮。独立概览无宿主菜单时保留原返回控件。模拟器 build99／versionCode4099 覆盖安装并核对摘要，截图及实际菜单点击确认返回今天，保留数据。[报告](verification/today-menu-20261012.json) / [其它日期菜单](../dist/verification/today-menu-20261012/menu-away.png) / [今天菜单](../dist/verification/today-menu-20261012/menu-today.png)。本轮仅复验受影响范围。 |
| 2026-10-12 加宽日期波浪 | 33 项受影响动画／真实日程／日期上下文／组合就绪回归、静态分析、118 文件架构及 554 文件仓库检查通过。原 8dp 淡线改为 32–56dp 主题色渐变光带及 2dp 轮廓，最大透明度分别 14%／18%，结束前淡出；点击改为 480ms easeOutQuad，横滑保持 380ms。绘制避开实时导航，不增加 blur 或 saveLayer。模拟器 build98／versionCode4098 与安装摘要一致，录屏核对 20→21 日期揭示和快速反向，保留数据并回到原选 20 日。[精简报告](verification/large-date-wave-20261012.json) / [录屏](../dist/verification/large-date-wave-20261012/large-date-wave.mp4) / [连续帧](../dist/verification/large-date-wave-20261012/large-wave-frames.png)。仅复验本次受影响范围，前轮 948 项全量属于 build97，未测真机帧率。 |
| 2026-10-12 日期整页波浪揭示与相邻预取 | 最终 948 项非网络 Flutter 回归、76 项脚本与 36 项目录 Python 测试、47 项设备更新定点回归、静态分析、118 文件架构和 554 文件仓库检查通过。日期点击保留上一完整画面，所有贡献准备并完成首帧后从按钮位置作 380ms 圆形揭示，拖动采用横向揭示；导航绘制与命中持续同步，业务操作与语义等待完整揭示，连续选择保留当前合成画面。空闲逐项只读准备前后一天，每贡献最多 5 份完整输入／实例快照，30 秒且不过分钟；写修订号同步失效，嵌套只读能力限制阻止预取副作用。新增真实回归覆盖最慢区块门控、缓存绕过工作流等待、草稿、写后失效及准备中停用模块；像素回归覆盖导航移动、透明留白清除和中途再次准备。模拟器 build97／versionCode4097 与 APK 摘要核对，保留数据；录屏验证快捷切日、反向、拖动及三课程到零课程的跨年冷日期揭示，已恢复今天。[精简报告](verification/date-wave-20261012.json) / [日期录屏](../dist/verification/date-wave-20261012/date-wave.mp4) / [课程清除录屏](../dist/verification/date-wave-20261012/date-wave-empty.mp4) / [连续帧](../dist/verification/date-wave-20261012/empty-wave-frames.png)。既有网络用例继续隔离；已开始的预取仍共享工作流队列，未缓存日期仍需读取，未测真机帧率或零延迟。 |
| 2026-10-12 日程日期局部翻页与五天栏 | 最终 914 项非网络 Flutter 回归、38 项设备更新定点回归、静态分析、115 文件架构检查及 554 文件仓库检查通过。顶栏变化字段作 280ms 翻页，五天栏 320ms 平移居中，支持横向拖动和快速反向；大字体放不下时保留横向浏览。查询期间日期导航持续显示和响应，旧日摘要／任务／课程隐藏保态；过期结果及排队事件不能覆盖最后一次日期选择。build95 录屏发现整树隐藏会打断日期栏，延迟查询测试另发现旧拖动反写新顶栏日期，两项均修复并纳入回归。最终 build96 覆盖安装模拟器，versionCode4096 与安装 APK 摘要一致，数据保留；录屏核对真实字体、局部翻页和手动滑动。[精简报告](verification/date-motion-20261012.json) / [最终录屏](../dist/verification/date-motion-20261012/date-motion.mp4) / [切换连续帧](../dist/verification/date-motion-20261012/date-motion-frames.png)。既有网络用例隔离范围同上轮；未测量真机帧率或零延迟。 |
| 2026-10-12 工作区首帧、底栏与统一标题 | 896 项非网络 Flutter 回归及后补 1 项真实底栏回访集成、76 项 Python 测试、静态分析、113 文件架构检查及仓库检查通过。最近 4 个工作区保留真实内容、草稿与控件；首次进入按真实首帧门控切入，快速加载不显示占位动画，后台页暂停刷新，旧日期内容隐藏但保留 Element。活跃脚本桥接等待从 8ms 降到 1ms，空轮询继续退避至 64ms；这是等待策略优化，不是 CPU 或耗电测量。AI 按钮与胶囊宽度采用同一 500ms 可反向时间线，日程日期与课表周标题共用 24px／w700 字体参数。build94 覆盖安装 x86_64 模拟器，versionCode4094 与 APK 摘要核对一致，数据保留；截图核对日程／课表标题与回访内容衔接。[精简报告](verification/instant-workspace-20261012.json) / [日程](../dist/verification/instant-workspace-20261012/agenda.png) / [课表](../dist/verification/instant-workspace-20261012/schedule.png) / [切换中间帧](../dist/verification/instant-workspace-20261012/return-agenda-00.png)。本机网络用例因独立监听／请求迟滞隔离，未认定根因；首次准备、截图 ADB 延迟与真机帧率仍须分别测量。 |
| 2026-10-12 v0.2.0-beta.1 发布准备 | 测试版标签校验支持 alpha／beta／rc 编号并要求与客户端完整版本一致；GitHub 工作流在全部检查、测试和三 ABI 构建通过后发布 Pre-release，禁用 Latest，正式版固定签名要求保持。发布准备阶段 70 项脚本测试与 36 项模块目录／发布测试全部通过，actionlint、100 文件架构检查、8 项目录条目校验及暂存差异检查通过。提交当前预装包替换记录后，554 文件仓库边界检查通过，原 6 个旧包索引阻断解除。此前唯一超时的 `host_network_test.dart` 本次独立复验 3 项全部通过；这不回写此前全量 828／829 的实际结果。远端最终回归、构建及发布状态以该版本 [Actions](https://github.com/JayConstruct/xudian/actions/workflows/android.yml) 与 [Release](https://github.com/JayConstruct/xudian/releases/tag/v0.2.0-beta.1) 为准。测试版使用 CI 开发签名，覆盖安装兼容性及真机性能未验证。 |
| 2026-10-12 任务列表身份与提交反馈 | API 升至 `1.20.0`，日程模块 `app.views.today 1.6.2` 使用通用 `keyedList`：稳定 key 保留行状态，成功提交后才执行 220ms 收拢退出或 900ms 新增高亮；普通刷新、分页、日期切换与审核取消不重播完成效果。独立根列表保留惰性构建及重排索引，内联列表仍为自然高度。最终 Flutter 全量实际结束于 4 分 46 秒：829 项中 828 项通过，唯一失败为既有 `host_network_test.dart` 的请求取消／模块撤销用例 30 秒超时；本轮未修改网络实现。任务动画文件 9 项另行完整通过，静态分析零问题、100 文件架构检查、11 项打包边界回归与差异检查通过；6 个当前包摘要及默认安装标记核验通过，仅日程包更新，旧 1.6.1 已归档。覆盖首次反馈、连续提交、减少动画、退出交互／语义撤下、离屏退出释放、历史任务保留、冲突提交无成功反馈，以及内联／独立列表输入 Element、焦点、选择保留。两尺寸组件组合预览经审阅：[390 浅色新增高亮](../dist/verification/task-motion-20261012/390-added.png) / [320 深色双倍字体](../dist/verification/task-motion-20261012/320-added.png) / [收拢中间帧](../dist/verification/task-motion-20261012/320-removing.png)。首轮发现的反馈延迟初始化缺陷已修复；新增测试夹具的异步安装等待及脚本括号错误修正后，相关整文件已正常退出，完整测试重新执行并保留上述唯一网络失败。[最终完整日志](../dist/verification/task-motion-20261012/flutter-full.log)。这是视觉身份与状态保留优化，未改变服务查询或跨桥传输范围；上方插入可让输入离开视口，但保留焦点和草稿，未新增自动滚动策略。未部署设备或验证真机帧率；仓库检查仍受本轮前 6 个旧包 Git 索引记录阻断。 |
| 2026-10-12 日程公共动效与大字体可读性 | 宿主日期节奏统一为 180ms，快速添加高度／透明度过渡为 220ms；整页切换仍为 360ms，底栏弹簧保持原参数。API 升至 1.19，`app.views.today 1.6.1` 使用可保态折叠及审核提交后的成功提示。全量 Flutter 816 项中 815 项通过，唯一失败为旧测试要求隐藏输入从脚本树移除；按新的 collapse／visible 契约修正，最终受影响 8 个文件共 37 项全部通过（24 秒）。静态分析零问题、99 文件架构检查、11 项打包边界回归及差异检查通过；预装资源只更新日程版本／摘要，默认标记和其它模块包保持。新增测试验证自然高度内联列表在 51→52→51 项变化时输入 Element、焦点、选择及 composing 保留，折叠撤焦点、重开不抢键盘，快速日期反转与减少动画，日期条横滚保持及选中日可见；大字体课程改为时间上置、正文全宽。两尺寸真实组合离屏截图经审阅：[390 浅色](../dist/verification/ui-motion-20261012/xudian-ui-motion-390-overview.png) / [320 深色双倍字体](../dist/verification/ui-motion-20261012/xudian-ui-motion-320-overview.png)。首轮新增测试异步 zone 与语义资源释放问题已修复；最终全量后局部响应式和等效 lint 修正采用受影响定点复验，没有第二次最终全量。任务行离场动画、惰性列表重排协议及真机 FPS／键盘动画性能未实现或验证；仓库检查仍因本轮前 6 个旧预装包已删除但索引跟踪而阻断。 |
| 2026-10-12 任务分批扫描与脚本工作线程轮询 | 静态分析、98 文件架构检查与 11 项模块打包回归通过。807 项 Flutter 全量运行中 806 项通过，1 项既有课表高对比度测试的滤镜数量断言过时；修正为非空且全部禁用模糊后，该文件 5 项完整复验通过。首轮发现的跨 Zone 定时器归属问题和过期模块更新夹具已修复，相关 18 项回归通过。`app.tasks 1.3.1` 以每页 1000 条流式搜索与统计，10005 条夹具的早期搜索仅跨桥读取 1000 条，尾部搜索和完整统计各读取 11 页／10005 条；中文、Unicode 大小写、匹配后分页、前 50 项状态、暂存写集与快照冲突均有回归。虚拟时钟一秒空闲轮询 17 次、待返回请求 32 次，对照旧固定 8ms 的 125 次；这是调度计数，不是 CPU、内存峰值或耗电真机基准。预装包仅任务版本／摘要更新，其他身份及默认标记保留；仓库检查仍被本轮前已删除但 Git 索引跟踪的 6 个旧预装包阻断。性能仍需 Android／Windows 设备测量。[任务扫描](../client/test/task_scan_pagination_test.dart) / 调度与 Zone（当时的轮询测试已于 2026-10-14 通知式改造后移除；当前回归见下方原生异步测试） / [原生异步回归](../client/test/script_worker_test.dart)。 |
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

## 2026-10-13 商店安装体验首批完善

对应 [UX-01、UX-02、UX-04](design/UX_PLATFORM_BACKLOG.md)：下载窗口把真实阶段、当前包进度和批次字节进度前置；安装审核分组说明所选模块、必需依赖、版本变化及权限用途，技术详情保留完整计划；事务成功后合并为一条 Toast，商店保留打开入口。当前规范见 [模块目录](MODULE_CATALOG.md#安装流程反馈)。

最终 64 项相关 Flutter 回归通过，覆盖下载阶段／缓存／校验失败／网络重试清零、320 宽与两倍字体可见进度、取消后晚到传输、保留已完成包数、权限与签名区别、审核取消、事务回滚、真实拾光包安装，以及 Toast 消失后的商店打开入口、界面包和 Toast 生命周期。执行：

```bash
source scripts/dev-env.sh
cd client
flutter test --no-pub test/module_management_ui_test.dart test/host_batch_install_test.dart test/module_catalog_test.dart test/module_download_feedback_test.dart test/module_install_review_dialog_test.dart test/native_ui_pack_test.dart test/app_toast_test.dart --concurrency=2
flutter analyze --no-pub
```

14 项设备验收脚本单测通过（`python3 -m unittest scripts.tests.test_fresh_install_verification`）；脚本支持先核对概要再展开完整技术详情、按商店模块定位持久打开入口，并保留旧审核与 SnackBar 兼容。静态分析无问题；122 个生产 Dart 文件架构检查、627 个已跟踪文件仓库检查及 `git diff --check` 通过。

首轮 Flutter 启动受沙盒本地端口限制，自动审核允许在沙盒外执行后正常加载。集成回归发现下载初始化短暂出现重试按钮，已改为初始运行态并阻止并行尝试；另修正测试等待尚未出现元素时使用 `.first` 的错误，最终整组重跑通过。本轮未构建 APK、未部署 Android ARM／模拟器／Windows；真机视觉、读屏、弱网及实际设备操作仍待验收，以上自动化结果不代表原真机体验反馈已闭环。

真实学校账号/网站、Android ARM64 真机、Windows 构建与安装的验证须分别记录。已有学校快照审计、模拟 DOM 采集和 x86_64 截图不代表这些场景已经通过。

新增验收时记录日期、版本、具体检查范围、结果、数据保留及证据路径，保留失败和未验证范围。完整验收产物位于被 Git 忽略的 `dist/verification/`；供公开复验的精简报告可脱敏后保存在 `docs/verification/`。归档中的本机构建/截图可能不在其他检出工作区。索引引用的不可变模块包位于 [发布目录](../releases/README.md)，历史记录中的旧目录路径保留当时含义。

## 2026-10-13 商店布局弹窗与数据审核第二批完善

对应 UX-03、UX-05、UX-06，[待办中的已完善记录](design/UX_PLATFORM_BACKLOG.md#已完善记录) 已登记两批实现与剩余设备验收。商店使用紧凑卡片与按可用宽度／字号排列的一至三列；全局默认弹窗减少外侧留白，核心表单与审核共用内边距；实际数据审核基于冻结写集展示增改删及记录前后字段对比，未知结构完整回退。规范见 [商店](MODULE_CATALOG.md#安装流程反馈)、[弹窗](UI_DESIGN_SYSTEM.md#弹窗尺寸与留白)、[数据审核](design/DATA_CHANGE_REVIEW.md)。

最终 113 项组合 Flutter 回归通过，涵盖前批下载、安装事务、审核、Toast 与持久打开入口，以及新增商店布局 7 项、弹窗尺寸 7 项、数据审核 11 项，还包括原生界面包、类型表单、日期时间选择器、主题、代码与浮层。另单独复验既有记录／集合冲突及幂等提交 1 项通过。执行：

```bash
source scripts/dev-env.sh
cd client
flutter test --no-pub --concurrency=2 \
  test/module_management_ui_test.dart test/host_batch_install_test.dart \
  test/module_catalog_test.dart test/module_download_feedback_test.dart \
  test/module_install_review_dialog_test.dart test/native_ui_pack_test.dart \
  test/app_toast_test.dart test/module_catalog_layout_test.dart \
  test/module_catalog_store_metadata_test.dart test/dialog_layout_test.dart \
  test/data_change_review_test.dart test/app_design_theme_test.dart \
  test/code_and_floating_panel_test.dart test/temporal_input_test.dart \
  test/host_extension_test.dart
flutter test --no-pub test/module_host_test.dart \
  --plain-name 'record and collection conflicts reject commits, repeated commit emits once'
flutter analyze --no-pub
```

20 项首装验收脚本测试通过（`python3 -m unittest scripts.tests.test_fresh_install_verification`），支持新旧商店状态文案、持久打开按钮、新卡片语义与版本解析；安装验收区分实际当前版本与更新目标，拒绝停用及多卡片歧义。静态分析无问题，124 个生产 Dart 文件架构检查、627 个已跟踪文件仓库检查及差异检查通过。

窄屏标准字号测试测得 320 逻辑宽时正文宽 248；两倍字体按 Flutter 的自动内边距缩减保持正文及操作可达。横屏长内容可滚动、桌面复杂弹窗不超过 760、短确认维持内容宽；键盘进出保留宿主表单输入草稿。数据审核真实取消测试使用已封存数据库计划，确认取消后记录不变；回退不误称无变化，删除、字段不存在与 `null`、长嵌套数据、超出摘要上限的记录均能核对完整详情。

首轮尺寸断言未考虑 Flutter 大字体自动缩减内边距，按实际行为调整后最终组合重跑通过；商店语义测试句柄释放时机也已修正。只读审阅发现首装脚本依赖旧状态格式，已修复并补回归；未改提交、快照、权限或模块版本。本轮未构建或部署 APK，未进行 ARM／模拟器／Windows 设备视觉、读屏或性能验收，DISPLAY-01 缩放原因仍未定位。

## 2026-10-13 系统时区与显示诊断第三批完善

对应 UX-07 与 DISPLAY-01 的诊断准备，规范见 [时区与显示诊断](design/TIMEZONE_DISPLAY.md)。API 1.22 增加权限控制的系统 IANA 读取，Android 和 Windows 原生通道独立于业务；完整时区库保留历史别名、明确 GMT／UTC 规范化、3 秒超时与可见回退。课表 1.13.0、拾光 1.6.0 将普通创建／导入中的时区输入移除，新建默认设备时区，旧课表、明确来源和 JSON 备份保留原时区；手动编辑在高级设置，继续审核与冲突检查。

设置工具新增实时 Flutter 显示诊断，使用当前视图、根 MediaQuery 和实际 TextScaler 样本，用户主动复制白名单指标。新增 Android 只读测量脚本，系统估算与 Flutter 实测分别记录，不调整显示大小、字体或业务数据。[精简报告](verification/timezone-display-20261013.json) 保留候选模块／APK 摘要、设备基线和未验证范围。

168 项相关 Flutter 组合回归通过，包括系统时区新增 11 项、真实模块时区新增 9 项、显示诊断新增 6 项，以及课表布局／时区查询／导入、拾光、规划与实际 UTC 占用、QuickJS、设置、安装事务与审核。最后拾光来源时区校验补充后重新生成候选包，核对两包与最终源码字节一致，课表时区／拾光导入／商店安装另复验 28 项通过。执行：

```bash
source scripts/dev-env.sh
python3 scripts/module_host/build_packages.py
cd client
flutter test --no-pub --concurrency=2 \
  test/system_timezone_test.dart test/schedule_timezone_test.dart \
  test/display_diagnostics_test.dart test/clock_conversion_test.dart \
  test/schedule_ux_test.dart test/schedule_import_test.dart \
  test/schedule_today_feed_test.dart test/schedule_layout_test.dart \
  test/schedule_chrome_test.dart test/schedule_underlap_test.dart \
  test/shiguang_import_test.dart test/shiguang_school_picker_test.dart \
  test/planner_task_schedule_test.dart test/planner_test.dart \
  test/script_worker_test.dart test/settings_test.dart \
  test/module_management_ui_test.dart test/module_install_review_dialog_test.dart \
  test/host_batch_install_test.dart
flutter analyze --no-pub
flutter build apk --debug --no-pub --target-platform android-x64 --build-number 4114
```

36 项 Python 定点测试通过，包含显示测量 5 项、首装验收 20 项及模块打包 11 项；Node 拾光兼容测试文件通过。静态分析无问题，127 个生产 Dart 文件架构、627 个已跟踪文件仓库及差异检查通过。Android 最终 x86_64 调试 APK 已构建；第一次 Gradle 受沙盒网络接口限制未启动，自动审核允许后正常编译；未安装设备。

只读测量当前模拟器：Android 17、1080×2400、420 DPI、系统字号 1.0，无显示尺寸／密度覆盖，估算像素比 2.625、逻辑显示 411.43×914.29；当前应用 Android 配置 411×914 dp。该基线属于设备原安装客户端，不代表新页面 Flutter 实测。ARM 真机未连接，DISPLAY-01 原因尚未确定；Windows 通道只有代码与官方 SDK 声明核验，原生构建／运行未验证。两候选模块没有加入默认资源、没有发布目录更新或设备升级；APK 更新本身不会自动更新这些商店模块。未登录教务、调用真实 AI 或测量性能，原业务数据和系统设置保持。

## 2026-10-13 任务规划模块

新增独立 app.planner，宿主时间转换及可选查询服务、任务精确时段和完成日期、课表占用、原子批次与条件撤销。实现与复验命令见 [任务规划验证记录](design/PLANNER.md)。保留现有 UI 工作区改动；模块包输出到 dist/modules，更新已预装任务／日程／AI 包，规划模块不自动加入预装清单。

发布前补充：全量 Flutter 首轮 995 项通过、11 项失败，失败项为旧 AI 版本断言及旧日期径向揭示预期；修正后 AI 4 项、日期动画 17 项、日程集成 9 项定向复验通过。保留背景波纹和内容淡入实现，未就绪业务区要求空白且不可交互。Python 工具 119 项、模块发布工具 36 项通过；静态分析无问题。

## 2026-10-13 ARM 真机显示与体验验收

验收开始于 10 月 13 日，结束于 14 日，证据目录沿用 `arm-ux-20261013`。对应 [DISPLAY-01 及已实现体验项](design/UX_PLATFORM_BACKLOG.md)，本轮实现真机发现的两项修正，并完成相关设备闭环：

- 真机与模拟器同为 1080×2400、字号 1.0、无显示覆盖；系统密度分别为 480／420 DPI，新诊断页实际像素比 3／2.625，逻辑视口 360×800／411.43×914.29。密度差使同一逻辑尺寸在真机占用的物理像素多约 14.29%；根应用没有额外缩放，未更改显示密度或关闭字号缩放。
- 商店移除重复说明，将状态／分类标签改为两个保留完整选项的下拉控件；长标签或大字号按实际文字宽度上下排列。真机首卡 y=1595→803px，即 531.67→267.67dp，前移 264dp；标准字号下两张完整卡片和第三张主要操作可见。搜索、组合筛选、清除、打开、更新和宽屏键盘行为继续回归。对照：[调整前](../dist/verification/arm-ux-20261013/phone/02-store-before-refinement.png) / [最终 build117](../dist/verification/arm-ux-20261013/phone/10-store-build117-standard.png)。
- 长 `SelectableText` 内部继承弹性／始终可滚动物理规则，会在没有可滚范围时抢占竖拖；三个审核组件局部关闭文本内部滚动，由外层负责。实际生产 `AppScrollBehavior` 下的正文拖动及逐字全文复制回归通过；设备升级完整技术计划时可滚到各模块身份、权限和摘要，并精确核对后才确认。
- 两设备实际创建表单与拾光来源配置均无时区输入。课表新建冻结计划新增 1 条，拾光样例导入的业务预览新增 3 项，实际冻结写集新增 5 条（包含来源元数据），时区分别为 `Asia/Shanghai`／`UTC`。两条路径均在最终数据审核取消；原课表列表及当前选择的全部可见文字与前置快照逐项相同，真机 2 张、模拟器 3 张，测试课程／课表未写入。证据：[真机创建](../dist/verification/arm-ux-20261013/phone/07-create-review-timezone.png) / [真机导入正文拖动](../dist/verification/arm-ux-20261013/phone/09-import-data-review-scroll.png) / [模拟器 UTC](../dist/verification/arm-ux-20261013/emulator/09-import-data-review.png)。
- 模拟器临时系统字号 1.5：实际非线性样本为 12→18、14→22、24→28；商店筛选上下排列、状态菜单可操作，新建表单、键盘草稿、最终审核及取消通过，`finally` 恢复原 1.0。首次脚本未滚到大字号页面下方的课表管理入口，停止后已恢复字号；改用滚动定位完成剩余表单复验。真机 ROM 拒绝 ADB 字号写入（退出 255），只读复查原值仍为 1.0；真机大字号保留待验收，没有扩大系统权限。证据：[大字号商店](../dist/verification/arm-ux-20261013/emulator/10-store-large-font.png) / [实际样本](../dist/verification/arm-ux-20261013/emulator/10-diagnostics-large-bottom.png) / [键盘](../dist/verification/arm-ux-20261013/emulator/10-create-large-keyboard.png)。

最终 `build117` 的 ARMv7、ARM64、x86_64 release APK 均构建成功；新旧签名证书 SHA-256 一致，ARM64 真机／x86_64 模拟器 `adb install -r` 成功，versionCode 为 2117／4117，未卸载或清数据。逐项审核本地课表 1.13.0 与拾光 1.6.0 候选包；只允许拾光本次明确新增的 `clock.today` 权限。在线目录和预装资源未更新，候选源码未提交发布。

验收脚本同时修正 DocumentsUI 根目录抽屉误判、完整计划重叠字段归属及模块管理保留底部滚动位置的问题：抽屉未明确关闭时不触碰背后文件；模块版本、SHA-256 或新增权限不明确时不确认。之前安全停止和异常采集证据保留在本地目录，最终两台设备升级均通过，原业务数据保留。设备运行过程中曾有并发采集冲突，后续同一设备只串行采集。

最终 74 项相关 Flutter 回归、57 项 Python 脚本回归通过；静态分析无问题，生产架构 127 个 Dart 文件、仓库 627 个已跟踪文件及 `git diff --check` 通过。回归包含真实商店筛选、布局、模块管理、下载反馈、两种审核、弹窗、系统时区、真实课表／拾光业务及显示诊断；没有用历史全套数量替代本轮结果。主要复验命令：

```bash
source scripts/dev-env.sh
python3 -m unittest scripts.tests.test_emulator_modules scripts.tests.test_fresh_install_verification scripts.tests.test_android_display_measurement
python3 scripts/module_host/check_architecture.py
python3 scripts/check_repository.py
cd client
flutter test --no-pub test/module_catalog_filter_test.dart test/module_catalog_layout_test.dart test/module_management_ui_test.dart test/module_download_feedback_test.dart test/module_install_review_dialog_test.dart test/dialog_layout_test.dart test/data_change_review_test.dart test/system_timezone_test.dart test/schedule_timezone_test.dart test/display_diagnostics_test.dart
flutter analyze --no-pub
flutter build apk --release --split-per-abi --no-pub --build-number 117
```

[精简设备与构建记录](verification/arm-ux-20261013.json) 不含业务名称、记录 ID 或设备序列号；截图／XML／签名与审核扫描证据留在本地 `dist/verification/arm-ux-20261013`。本轮未完成弱网／未知下载长度／缓存和失败重试设备矩阵、Toast 批量时序视觉、横屏、实际读屏、Windows 原生、学校登录、真实 AI 或帧率／耗电验收，不将部分设备闭环记为七项反馈全部完成。

## 2026-10-14 v0.2.0-beta.3 发布前校验

本轮提交包含 UI 加载优化及此前已验证的商店、审核、导航、时区和显示诊断改动。客户端版本为 `0.2.0-beta.3+1`，沿用测试版渠道；准备 `modules-20261014-ui-performance` 的日程 1.8.0、课表 1.14.0、拾光 1.6.0 三个不可变包，历史版本保持原样。

150 个 Flutter 测试文件全量首轮 1,113 项通过、7 项失败。五项商店失败来自旧 ChoiceChip 查找及旧安装成功文案，已按当前下拉筛选和数量文案更新；一项筛选布局测试需等待所有索引本地 I/O 完成再等待动画静止。两个修正文件共 13 项定向复测通过。一项本地 HTTP 重定向测试超时，原文件不变单独复测 3 项通过。最终全套是否通过以发布标签的 CI 重跑为准，不将定向复验记为全量一次通过。

153 项 Python 工具测试、36 项模块目录测试、Node 显示结果等价及桥接调用数量校验全部通过；Flutter 静态分析和两修正文件分析无问题。129 个生产 Dart 文件架构、仓库边界、模块目录及三包摘要、版本标签、Actions 配置和差异检查通过。原始日志保存在本地 `dist/verification/releases-20261014/local/`。发布工作流新增 Node 性能等价检查，并从版本说明文件读取发布说明。

### 远端发布结果

源码提交 `5294409b729fb3011421c573372ab8a0f5e15f7e` 已推送。不可变标签 [`v0.2.0-beta.3`](https://github.com/JayConstruct/xudian/releases/tag/v0.2.0-beta.3) 与 [`modules-20261014-ui-performance`](https://github.com/JayConstruct/xudian/releases/tag/modules-20261014-ui-performance) 发布成功。[App CI](https://github.com/JayConstruct/xudian/actions/runs/38490018149) 最终全量 **1,120 项 Flutter 测试全部通过**，153 项 Python、36 项模块目录测试、静态分析、Node 等价及桥接计数检查全部通过，三个 ABI 的 release APK 构建和上传成功。

从公开 Release 重新下载三个 APK、SHA256SUMS、SOURCE_COMMIT 和三个模块包。下载摘要与发布摘要、本地不可变模块包逐一相同，SOURCE_COMMIT 与标签源码一致；APK 的应用 ID、0.2.0-beta.3 版本名、ABI、签名验证及六个内置模块字节全部核对通过。三个 APK 使用同一 CI 开发证书；versionCode 为 ARMv7 1114、ARM64 2114、x86_64 4114，不代表可覆盖任意本地测试构建。模块下载资产确认存在后才更新 `module-catalog` 分支；三个公开索引与源码相同，独立目录仓库内容已匹配，无需修改。

[发布摘要与文件 SHA-256](verification/release-20261014.json) 已归档，APK、签名输出和校验日志保存在本地 `dist/verification/releases-20261014/`。本轮没有安装设备或测量实际启动耗时；测试版不进入正式版更新提示，已有模块仍需独立确认升级。此前验证记录中的“未发布”描述保留其当时状态，以本节为最新发布结果。

## 2026-10-14 冷启动观测与 UI 规则统一

按用户要求由子 agent 分别修改启动与 UI，主 agent 整合审阅并验收；范围见 [首轮优化路线](design/STARTUP_UI_ROADMAP.md)。

- 模块恢复合并安装与包来源读取；预装来源回填批量执行，保持已有来源、依赖顺序和每次重新验证包的行为。真实 SQLite 与文件读取回归覆盖缺失来源、错误身份／版本、损坏包与空目录。
- 补齐 Dart 首帧及可见工作区就绪，Android 接入一次性 `reportFullyDrawn`；通知等待当前页面内容与入口转场完成，过时／隐藏页不报告，恢复失败／无工作区独立记录。可用错误内容树可能解除现有渲染门控，不将指标解释为所有业务成功。
- 新增冷启动采样脚本，检查进程退出，保存原始代理指标与 p50／p95；可按 PID 与本轮 token 等待固定就绪标记。失败保留不完整报告和阶段、操作、退出码等结构化诊断，不保存任意错误正文；日志等待受剩余超时约束。
- UI 文档按公共实现统一圆角、Chip、日期动效及截图规则，补齐间距、文字层级、页面状态、界面包边界与验收矩阵。日期业务区域在既有点击／语义门控处加入同条件焦点排除，显式导航可继续使用键盘；等待／淡入不可触发业务，结束或取消后可重新聚焦，controller 与草稿保留，不自动抢回焦点。规则依据与既有页面覆盖限制见 [UI 规则核对](design/UI_RULES_AUDIT.md)。

启动定向 **28 项**、日期交互 **35 项**、整合回归 **70 项** Flutter 测试通过；最终 Python 工具全套 **172 项**通过。全客户端静态分析无问题，生产架构 131 个 Dart 文件、仓库边界 670 个已跟踪文件、修改文档链接及 `git diff --check` 通过。本轮未运行全量 Flutter，不用历史全套结果替代本次范围。

x86_64 release **build104** 构建并覆盖安装成功，versionCode **4104**、设备与产物摘要一致，保留原数据；最终客户端构建输入指纹仍与安装记录一致。原生 Kotlin 通道完成实际构建与设备采样验证。未执行 Git 提交、推送或发布。

同一模拟器 release 默认采样每组 20 轮：build103 的启动代理指标 `TotalTime` p50／p95 为 **750／830ms**；build104 首轮为 **1002.5／1130ms**，模拟器重新启动后复测为 **750／864ms**。新版独立首页就绪组完整 20 轮，Activity 创建到就绪的 p50／p95 为 **1322.5／1571ms**，该组 `TotalTime` 为 **921／1237ms**。没有证实稳定提速；初轮变慢与复测持平全部记录，不将结构优化描述为真机加速。原生就绪指标不是平台 TTFD，旧 APK 没有该标记，不能做首页就绪前后比较。

首次基线超时和新版首页采样 15／20 后设备断开的报告均保留为失败／不完整记录；恢复同一 AVD 与 60Hz 后重新完整采样，未卸载、清数据或清空 logcat。采样结束 build104 在模拟器前台运行。详细方法、波动与后续真机范围见 [启动验收](STARTUP_PERFORMANCE.md)，[精简摘要](verification/startup-ui-20261014.json) 可复查。当前尚未完成 ARM64 真机阶段采样、全局页面状态覆盖或本轮截图视觉矩阵。

## 2026-10-14 深层启动优化与原生通知

第二轮实现 SQLite 版本探测与迁移前备份转移至数据库 isolate，worker 周期轮询改为原生输出通知，验证包复用解码及冻结声明、减少解压文件复制。保持每次重新读取与完整校验、双 worker 隔离、顶层初始化顺序、owner zone 和安装事务；没有实施全模块懒启动。release 阶段采样需显式开启 `XUDIAN_CAPTURE_STARTUP`，就绪后停止并清空最多 96 组聚合，正式版关闭。

完整 **1,147 项 Flutter** 回归一次运行通过，最终 **190 项 Python**、整合定向 **51 项**、完整静态分析、132 文件架构、仓库边界与差异检查通过。真实回归覆盖数据库一致备份／失败不迁移／不覆盖旧备份，ZIP 位损坏／同长度篡改／真实 Ed25519 签名失败，100 轮 queued notification 关闭压力、晚到 host 回复、双 worker 全局隔离、迁移回滚后前台查询、日期缓存与宿主 UI。旧轮询实现与只验证其算法的测试移除，当前异步调度回归归于 `script_worker_test.dart`。本地原生包源码和 hook 已纳入更新脚本输入指纹。

Linux 30 轮真实 QuickJS 微基准：load p50 **3840→754µs**；12 次串行 host 桥接 **25989→1846µs**，空闲一秒 worker 定时器 **20→0**。合成大脚本重复 getter p50 **4699→7µs**；完整校验本身未显示可测提升。微基准不换算为 Android 冷启动百分比。

build105 诊断基线与 build106 同开关候选进行了分阶段采样；并行负载和数据库计时边界变化明确记录。候选 10 轮宿主初始化 p50 **520.5→396.3ms**、当前首页脚本执行 **16.0→7.8ms**，但扩大组没有稳定复现整机提速。保留所有组，而非只选较快一组。

最终普通 release **build107 / versionCode 4107** 已同签名覆盖模拟器，设备和产物 SHA-256 相同，关闭阶段采样开关，保留原数据与模块。20 轮最终组因模拟器在第 11 轮退出而标为不完整；确认无 ADB 设备、无 Windows 模拟器进程后恢复同一 AVD／60Hz，排除设备启动首轮并完成 10 轮。启动代理 p50／p95 **721.5／1036ms**，Activity 创建到就绪 **987／1311ms**，采样结束应用前台运行。此前普通基线为 **1368.5／1516ms** 的首页指标；模拟器恢复与负载条件不同，未取得受控交错对比，不宣称稳定提速比例。

新旧运行时包及 worker 微基准、元数据、所有设备组、失败尝试、完整测试日志留在 `dist/verification/startup-deep-20261014/`；[精简验证摘要](verification/startup-deep-20261014.json) 与 [启动专题](STARTUP_PERFORMANCE.md) 记录准确口径。缓存及最近成功安装记录已同步 build107，没有 Git 提交或发布。ARM64 真机、Windows 原生运行、低端设备与大数据集阶段矩阵尚未完成。
