> 历史归档：保留当时的方案、状态与验证结果。当前文档见 [文档导航](../README.md)，历史构建和截图可能只存在于原验收工作区。

# 课表 1.2：单顶栏与分组设置（历史记录）

课表主界面只显示一条宿主顶栏：左侧切换课表，中间选择教学周，右侧只保留页面菜单按钮。菜单提供回到本周、今日课程、课表设置、显示设置及有课时的周末入口，并合并 AI 等顶部模块入口、宿主设置和界面风格与恢复。周视图继续使用参考图的连续网格、固定节次栏和同步滚动的日期头。

课表设置使用概览、课表配置、课程与调课、数据管理四组信息行，显示课表名称、学期、时区、节次数、课程和调课数量。学期、作息、课程管理、导入备份等继续保留稳定子页面 ID。

作息按上午、下午和晚间逐节编辑，原生时间选择器使用24小时制。只允许从末尾增减，引用中的节次不能删除，重叠和跨午夜阻止保存。修改后才显示保存栏；离开页面保留当前运行会话中的草稿并说明尚未保存。保存与模板操作均由宿主审核实际写集，配置发生外部修改时拒绝覆盖并要求重新载入。

新建课表默认12节，每节45分钟：08:00–08:45、08:50–09:35、09:50–10:35、10:40–11:25、11:30–12:15、14:00–14:45、14:50–15:35、15:45–16:30、16:35–17:20、18:30–19:15、19:20–20:05、20:10–20:55。安装更新不会改写已有课表。用户可审核“使用12节作息模板”替换时间，也可选择“补足至12节”保留所有现有时段，只追加末尾；追加时间无法容纳到当天时拒绝保存。

点击课程先显示只读详情，包括实际日期、节次、教师、地点、周期安排和调课状态，再选择单次调课或编辑周期安排。手机使用底部面板，宽屏使用右侧面板。详情重新读取当前数据，跨周移动和撤销后不沿用旧课块内容。

JSON导入先展示新增、修改、删除、冲突和警告，原始JSON折叠展示；预览不写入正式数据。处理冲突后重新准备计划，最终审核并一次提交。数据基线变化使旧预览失效，需要重新预览。教务适配器仍通过公开导入服务和槽位接入。

客户端宿主 API 升至1.2.0；课表1.2.0声明 `hostApi: ^1.2.0`，`dataVersion`仍为1。新增通用顶栏贡献、listTile、timeInput、输入变化事件、自适应面板及列定位协议，详见 [MODULE_SDK.md](../MODULE_SDK.md)。旧宿主明确拒绝缺少这些能力的新包。先安装 [Release客户端](../../dist/verification/app-release-build20.apk)，再导入 [独立课表包](../../dist/verification/app.schedule-1.2.0.xmodule)。

验证摘要及真实模拟器截图见 [schedule-ux.json](../../dist/verification/schedule-ux.json)。build19和课表1.1记录保存在 [SCHEDULE_LAYOUT.md](SCHEDULE_LAYOUT.md)。Windows x64和arm64真机暂无环境，仅Android x86_64模拟器完成实际运行；arm64包含在Release构建中。


本次交付 build20，静态分析无问题、430项非HTTP回归全部通过，生产架构检查51个Dart文件通过。手机420px、1.6倍字体、1200px宽屏、原生时间选择、草稿恢复、导入事务和权限隔离纳入回归。HTTP测试本轮未改动；此前组合测试2项通过、1项本地socket偶发超时，取消测试单独通过，保留 [网络诊断](../../dist/verification/schedule-layout-network-diagnosis.md)，不将它算入430项。

演示课表通过宿主真实审核从2节补足至12节。导出JSON逐项比较证实原有两节08:00–08:45、08:55–09:40，课表/数据集/课程/安排ID及全部课程和单次变更保持一致；只增加十节作息。补足会保留模板的课间间隔，因此此旧课表后续时间比新建默认模板推迟5分钟，末节20:15–21:00。安装本身不改写作息，原始build19备份另存 [schedule-demo-build19.json](../../dist/verification/schedule-demo-build19.json)。

[单顶栏主页](../../dist/verification/android-schedule-ux-home.png) · [分组设置](../../dist/verification/android-schedule-ux-settings.png) · [逐节作息](../../dist/verification/android-schedule-ux-periods.png) · [只读课程详情](../../dist/verification/android-schedule-ux-detail.png) · [导入摘要](../../dist/verification/android-schedule-ux-import-preview.png)。独立包更新前后及重启后的安装APK摘要相同；只读复验命令为 `source scripts/dev-env.sh; python3 scripts/module_host/verify_schedule_ux.py`。

最新滚动收缩工具栏见 [SCHEDULE_CHROME.md](SCHEDULE_CHROME.md)。

## 课表 1.7：菜单切换课表与数字周选择

客户端 build38（宿主 API 1.10.0）配合课表1.7.0：主界面不再显示左侧切换课表按钮，从右上角页面菜单选择“切换课表”。点击顶栏教学周打开纯数字圆角按钮网格，当前选中周高亮，点击直接切换；取消保留原周数。列数按屏幕宽度、字号和数字长度适配，较多教学周可以滚动。课表数据版本不变，更新不改课程、学期或作息。

静态分析、76个Dart文件的生产架构检查及609项Flutter测试通过，覆盖320px、1.6倍字体、100周滚动选择与菜单切换另一张课表。三种Android ABI的Release构建完成，x86_64模拟器已安装build38与课表1.7.0，验证点选立即切换、取消保留原周、菜单入口及原课程保留。结果见 [构建与测试记录](../../dist/verification/schedule-week-grid-checks.json) 和 [模拟器验收](../../dist/verification/schedule-week-grid-emulator.json)。

[菜单](../../dist/verification/android-schedule-week-grid-menu.png) · [数字周选择](../../dist/verification/android-schedule-week-grid-picker.png) · [独立模块包](../../dist/verification/app.schedule-1.7.0.xmodule) · [模拟器客户端](../../dist/verification/app-release-build38.apk)。可在已安装的模拟器上运行 `source scripts/dev-env.sh; python3 scripts/module_host/verify_schedule_week_picker.py` 复验；脚本结束恢复原教学周，不保存课表切换。

客户端build39调整宿主脚本页面进度反馈：页面被模态弹窗覆盖时隐藏背景进度条，仍保留执行状态和真正页面加载时的反馈。教学周和课表选择弹窗的背景无进度条回归、其余相关测试共19项通过；静态分析和生产架构检查通过。模拟器已覆盖安装并验证弹窗截图、取消与课程保留，见 [检查记录](../../dist/verification/schedule-modal-progress-checks.json)、[模拟器验收](../../dist/verification/schedule-modal-progress-emulator.json) 和 [弹窗截图](../../dist/verification/android-schedule-week-picker-no-progress.png)。

客户端build40将脚本页面的初次加载与刷新反馈统一延迟500ms显示，快速完成的今天、课表、收件箱等页面不显示加载动画。弹窗覆盖页面时暂停并清除计时，关闭后重新计时，避免把等待用户选择的时间计入加载。已有页面刷新保留原内容；慢加载超过阈值仍有反馈。21项相关测试及教学周弹窗第一帧复验通过，覆盖快速完成、慢加载、完成后清除、弹窗等待与关闭。静态分析与生产架构检查通过，三种Android ABI完成Release构建。记录见 [检查摘要](../../dist/verification/fast-page-feedback-checks.json) 和 [模拟器验收](../../dist/verification/fast-page-feedback-emulator.json)。

客户端build41优化委托顶栏首次显示：`headerMode: contributed` 的工作区和详情页在模块首次返回前不显示入口或路由的临时标题，工作区预留模块标题控制高度，避免切入课表先显示左侧“课表”再改成教学周。标准页面仍显示宿主标题，右上角菜单、设置与返回入口照常可用。22项相关回归通过，另复验2项详情页首次标题与内部返回；静态分析与生产架构检查通过，三种Android ABI的Release构建完成。结果见 [检查摘要](../../dist/verification/module-owned-header-checks.json) 和 [模拟器验收](../../dist/verification/module-owned-header-emulator.json)。

客户端build42统一工作区顶栏高度：普通标题、模块标题与教学周按钮均使用相同标题控制高度，垂直留白统一为上下各4，默认总高度56逻辑像素。控制高度根据主题文本样式与实际字号计算，大字体时今天、课表、收件箱同步增高，首次渲染前也保留相同高度。25项相关测试通过，覆盖1.0、1.6及2.0倍字号、反复切换、无临时标题、教学周选择和界面风格菜单；静态分析、生产架构检查及三种Android ABI的Release构建通过。结果见 [检查记录](../../dist/verification/workspace-header-height-checks.json) 和 [模拟器验收](../../dist/verification/workspace-header-height-emulator.json)。

客户端build43精简工作区页面菜单：移除“界面风格与恢复”，从“设置 → 外观与交互 → 界面风格”进入风格选择与恢复默认。右上角菜单仍包含当前页面操作、顶部模块入口与设置。10项相关测试通过，覆盖手机和桌面自定义界面下从设置恢复默认风格，以及模块入口和工作区设置；静态分析与生产架构检查通过。验证记录见 [检查摘要](../../dist/verification/page-menu-simplify-checks.json) 和 [模拟器验收](../../dist/verification/page-menu-simplify-emulator.json)。
