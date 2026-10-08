# 课表 1.2：单顶栏与分组设置（历史记录）

课表主界面只显示一条宿主顶栏：左侧切换课表，中间选择教学周，右侧保留宿主设置和页面菜单。菜单提供回到本周、今日课程、课表设置及有课时的周末定位，并保留 AI 等模块贡献入口。周视图继续使用参考图的连续网格、固定节次栏和同步滚动的日期头。

课表设置使用概览、课表配置、课程与调课、数据管理四组信息行，显示课表名称、学期、时区、节次数、课程和调课数量。学期、作息、课程管理、导入备份等继续保留稳定子页面 ID。

作息按上午、下午和晚间逐节编辑，原生时间选择器使用24小时制。只允许从末尾增减，引用中的节次不能删除，重叠和跨午夜阻止保存。修改后才显示保存栏；离开页面保留当前运行会话中的草稿并说明尚未保存。保存与模板操作均由宿主审核实际写集，配置发生外部修改时拒绝覆盖并要求重新载入。

新建课表默认12节，每节45分钟：08:00–08:45、08:50–09:35、09:50–10:35、10:40–11:25、11:30–12:15、14:00–14:45、14:50–15:35、15:45–16:30、16:35–17:20、18:30–19:15、19:20–20:05、20:10–20:55。安装更新不会改写已有课表。用户可审核“使用12节作息模板”替换时间，也可选择“补足至12节”保留所有现有时段，只追加末尾；追加时间无法容纳到当天时拒绝保存。

点击课程先显示只读详情，包括实际日期、节次、教师、地点、周期安排和调课状态，再选择单次调课或编辑周期安排。手机使用底部面板，宽屏使用右侧面板。详情重新读取当前数据，跨周移动和撤销后不沿用旧课块内容。

JSON导入先展示新增、修改、删除、冲突和警告，原始JSON折叠展示；预览不写入正式数据。处理冲突后重新准备计划，最终审核并一次提交。数据基线变化使旧预览失效，需要重新预览。教务适配器仍通过公开导入服务和槽位接入。

客户端宿主 API 升至1.2.0；课表1.2.0声明 `hostApi: ^1.2.0`，`dataVersion`仍为1。新增通用顶栏贡献、listTile、timeInput、输入变化事件、自适应面板及列定位协议，详见 [MODULE_SDK.md](MODULE_SDK.md)。旧宿主明确拒绝缺少这些能力的新包。先安装 [Release客户端](../dist/verification/app-release-build20.apk)，再导入 [独立课表包](../dist/verification/app.schedule-1.2.0.xmodule)。

验证摘要及真实模拟器截图见 [schedule-ux.json](../dist/verification/schedule-ux.json)。build19和课表1.1记录保存在 [SCHEDULE_LAYOUT.md](SCHEDULE_LAYOUT.md)。Windows x64和arm64真机暂无环境，仅Android x86_64模拟器完成实际运行；arm64包含在Release构建中。


本次交付 build20，静态分析无问题、430项非HTTP回归全部通过，生产架构检查51个Dart文件通过。手机420px、1.6倍字体、1200px宽屏、原生时间选择、草稿恢复、导入事务和权限隔离纳入回归。HTTP测试本轮未改动；此前组合测试2项通过、1项本地socket偶发超时，取消测试单独通过，保留 [网络诊断](../dist/verification/schedule-layout-network-diagnosis.md)，不将它算入430项。

演示课表通过宿主真实审核从2节补足至12节。导出JSON逐项比较证实原有两节08:00–08:45、08:55–09:40，课表/数据集/课程/安排ID及全部课程和单次变更保持一致；只增加十节作息。补足会保留模板的课间间隔，因此此旧课表后续时间比新建默认模板推迟5分钟，末节20:15–21:00。安装本身不改写作息，原始build19备份另存 [schedule-demo-build19.json](../dist/verification/schedule-demo-build19.json)。

[单顶栏主页](../dist/verification/android-schedule-ux-home.png) · [分组设置](../dist/verification/android-schedule-ux-settings.png) · [逐节作息](../dist/verification/android-schedule-ux-periods.png) · [只读课程详情](../dist/verification/android-schedule-ux-detail.png) · [导入摘要](../dist/verification/android-schedule-ux-import-preview.png)。独立包更新前后及重启后的安装APK摘要相同；只读复验命令为 `source scripts/dev-env.sh; python3 scripts/module_host/verify_schedule_ux.py`。

最新滚动收缩工具栏见 [SCHEDULE_CHROME.md](SCHEDULE_CHROME.md)。
