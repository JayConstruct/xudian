# 课表 1.1 布局与设置子页（历史记录）

当前课表 1.6.3 默认隐藏周末，手动显示七天后仍完整适配屏幕，见 [课表显示设置](SCHEDULE_DISPLAY.md)。下文的周末横向滚动描述保留为 1.1 版本历史记录。

参考项目 `tmp/IMG_20261007_153208.jpg`。课表 1.1.0 的主页保留居中教学周选择、右侧课表切换和连续时间网格。左上角显示年份与教学周，日期头显示星期与月日，左侧显示节次及上下排列的起止时间。日期头和课程同步横向滚动，左侧节次固定；日期头在纵向浏览时保留。浅色网格线及当前日期/节次高亮随课表时区计算。

手机按宽度显示主要日期列，横向滚动仍可查看周末课程。宽屏可同时显示七天。点击周次选择教学周，点击课块仍可进行单次调课。实际日期和周数来自课表配置，不使用图片中的固定示例日期。

宿主设置中的“课表设置”打开管理子页，包含学期设置、作息设置、课程管理、调课记录、导入与备份、课表管理及今日课程。学期和作息可在页面内编辑、保存，实际修改仍需宿主审核；课表选择在各子页与主页之间保持一致。返回主页保留浏览状态；旧版本页面状态中的课程管理页签会被清除，避免更新后主页恢复旧布局。

已有课程、安排、导入来源及调课数据结构保持，`dataVersion` 仍为 1。旧导入适配器继续使用主页入口，宿主导航到新的导入子页，原公开服务及主页面 ID 保留。原教务导入槽位继续兼容，新导入页面也提供 `importers` 槽位。

本次宿主增加通用 toolbar、时间网格的视口布局/标题/高亮和 `clock.local`，接口升至 1.1。新课表包声明 `hostApi: ^1.1.0`，旧客户端会明确拒绝不支持的包。需要先更新 [Release 客户端](../dist/verification/app-release-build19.apk)，再导入 [课表 1.1.0](../dist/verification/app.schedule-1.1.0.xmodule)；后续在此接口能力内调整课表页面仍只需要更新脚本包。

布局回归使用真实 QuickJS 和生产界面，覆盖设置入口和保存、子页返回、当地日期/时段、共享课表选择、旧页签恢复，以及窄屏固定节次栏和同步横滚。模拟器截图和最新交付摘要保存在 `dist/verification/schedule-layout*` 与 `android-schedule-*`；原 build 17 的独立更新证据单独保留。

最终交付为 build 19，摘要见 [schedule-layout.json](../dist/verification/schedule-layout.json)。[主页截图](../dist/verification/android-schedule-reference-layout.png)、[设置子页](../dist/verification/android-schedule-settings.png)、[周次选择](../dist/verification/android-schedule-week-selector.png)和[重启恢复](../dist/verification/android-schedule-layout-restart.png)来自实际 Android x86_64 模拟器。周次按钮和网格使用独立无障碍边界，自动点击与辅助功能不会把整片网格当成周次按钮。

静态分析无问题；416 项非 HTTP 回归通过，最后的无障碍边界调整另经 9 项生产界面测试通过。网络测试文件未修改：组合运行中两项通过、取消测试在本机 socket 阶段偶发超时，同一取消测试单独运行通过。保留[失败日志](../dist/verification/schedule-layout-network.txt)与[诊断说明](../dist/verification/schedule-layout-network-diagnosis.md)，不将这些结果描述为全套一次通过。Windows 与 arm64 真机的环境限制仍沿用原宿主验收记录。

新版单顶栏与分组设置交付见 [SCHEDULE_UX.md](SCHEDULE_UX.md)。
