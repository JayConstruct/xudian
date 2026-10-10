> 历史归档：保留当时的方案、状态与验证结果。当前文档见 [文档导航](../README.md)，历史构建和截图可能只存在于原验收工作区。

# 课表1.3滚动工具栏（历史记录）

课表1.3.0向下浏览时自动收起宿主顶栏和手机底部导航，向上浏览或上拉至顶部恢复。横向切换日期不触发收缩，节次与日期表头继续保留。收起后在手机底部保留“展开工具栏”按钮；宽屏侧栏保持可用，展开按钮位于侧栏，避免遮挡课程内容。

行为通过通用 `header.autoHideChrome: true` 开启，没有新增课表专用宿主分支。脚本只请求此布局行为，收缩、动画、恢复及设置访问由宿主管理。用户纵向向下累计48逻辑像素后收起，向上累计16像素后恢复，避免轻微抖动反复展开。隐藏导航不响应点击，并从无障碍树移除。脚本定位、滚动恢复和视口尺寸变化不触发收缩。减少动画时即时切换；辅助导航启用时仍保留可访问的展开按钮。切换工作区、更新实例、模块停用或脚本错误时恢复宿主控制入口。

首次使用需要先安装 [build23 Release客户端](../../dist/verification/app-release-build23.apk)，再通过模块管理导入 [课表1.3.0独立包](../../dist/verification/app.schedule-1.3.0.xmodule)。宿主API为1.3.0，包声明 `hostApi: ^1.3.0`，数据版本仍为1，更新不修改课程或作息。此前build20与课表1.2包已归档，见 [单顶栏记录](SCHEDULE_UX.md)。

验证记录见 [schedule-chrome.json](../../dist/verification/schedule-chrome.json)；真实模拟器截图包含 [展开](../../dist/verification/android-schedule-chrome-expanded.png)、[收起](../../dist/verification/android-schedule-chrome-collapsed.png)、[上滑恢复](../../dist/verification/android-schedule-chrome-scroll-restored.png)和 [按钮恢复](../../dist/verification/android-schedule-chrome-button-restored.png)。只读手势复验：`source scripts/dev-env.sh` 后运行 `python3 scripts/module_host/verify_schedule_chrome.py`。

手机大字体、横向与程序定位、宿主恢复、真实JS渲染错误及宽屏侧栏均有生产界面测试；滚动阈值、轻微抖动、嵌套滚动、鼠标滚轮与页面切换有通用组件测试。HTTP实现和测试未修改，沿用 [此前网络诊断](../../dist/verification/schedule-layout-network-diagnosis.md)。Windows和arm64真机暂无连接环境，Android x86_64模拟器完成实际运行；Release包含x86_64及arm64原生引擎。

最终静态分析无问题，438项非HTTP回归通过，6项工具栏测试包含辅助功能与减少动画场景通过，生产架构检查52个Dart文件通过。

最新悬浮底栏与滚动余量见 [SCHEDULE_GLASS.md](SCHEDULE_GLASS.md)。
