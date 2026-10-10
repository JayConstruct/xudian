> 历史归档：保留当时的方案、状态与验证结果。当前文档见 [文档导航](../README.md)，历史构建和截图可能只存在于原验收工作区。

# 课表悬浮底栏与内容延伸

课表1.4.0让时间网格延伸到悬浮导航下方，取消固定的整块底部留白。底部导航和收起后的“展开工具栏”共用轻度半透明背景、局部模糊、细边框及柔和阴影，图标和文字保持实色。展开按钮保留至少48逻辑像素的点击高度，高对比度使用不透明背景并关闭模糊。

工具栏遮挡高度改为网格滚动内容末尾的余量，最后一节课可以完整滚动到导航上方并点击查看详情。滚到末尾后再展开工具栏，会随视口和滚动余量变化保持末尾位置，避免恢复的导航重新遮住课程。日期头保持固定，既有纵向收缩、向上恢复、横向保持控件和辅助功能行为保留。没有挂载内容的入口槽位不再产生额外的16像素留白；有挂载内容时仍保留入口及诊断。

宿主API为1.4.0。填满视口的根column声明 `underlapChrome:true`，时间网格options也声明 `underlapChrome:true`；具体协议见 [SDK](../MODULE_SDK.md)。其他页面省略选项保留原来的空间安排。首次使用先安装 [build24 Release客户端](../../client/build/app/outputs/flutter-apk/app-release.apk)，再导入 [课表1.4独立包](../../dist/modules/app.schedule.xmodule)。数据版本仍为1，更新不更改课表、课程或作息。build23和课表1.3已归档，见 [滚动工具栏历史](SCHEDULE_CHROME.md)。

验证结果见 [schedule-glass.json](../../dist/verification/schedule-glass.json)。截图包括 [展开悬浮栏](../../dist/verification/android-schedule-glass-expanded.png)、[收起胶囊](../../dist/verification/android-schedule-glass-collapsed.png)、[末节滚动余量](../../dist/verification/android-schedule-glass-last-period.png)和 [重启恢复](../../dist/verification/android-schedule-glass-restart.png)。只读复验命令为 `source scripts/dev-env.sh` 后运行 `python3 scripts/module_host/verify_schedule_glass.py`。

静态检查无问题，442项非HTTP回归测试全部通过，生产宿主架构检查通过（53个Dart文件）。新增4项生产界面测试覆盖网格延伸、末节课完整滚动至展开导航上方并点击、恢复胶囊、高对比度、大字体及减少动画。网络实现和测试未变，沿用 [网络诊断](../../dist/verification/schedule-layout-network-diagnosis.md)。Android x86_64模拟器完成实际运行；Release包含arm64原生库，Windows与arm64真机暂无环境。
