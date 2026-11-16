# V2 页面优化候选

2026-11-06 根据用户反馈，将实际截图作为直接编辑底稿重新制作四页。使用内置 `image_gen.imagegen`，保留截图中的真实入口、信息和控件，限定局部调整。全部为 `draft`，尚未选定，未修改应用运行界面。

## 当前候选：直接结合截图

可打开[原截图与局部优化对照](../../../dist/verification/20261106-v2-screenshot-edits/gallery.html)，逐页查看左侧原截图和右侧修改稿。

| 页面 | 原截图 | 修改稿 | 完整提示词 | 调整范围 |
| --- | --- | --- | --- | --- |
| 新建任务 | [S03](../../../dist/verification/20261105T162753.549131Z-v2-design/screenshots/S03-create.png) | [图片](../../../design/screens/ui-03/20261106-155000-318838-screenshot-task-create-v01.png) | [提示词](../../../design/screens/ui-03/20261106-155000-318838-screenshot-task-create-v01.prompt.txt) | 保留名称、添加内容或规则、草稿提示和创建按钮，压缩面板高度与空白 |
| 课表 | [S04](../../../dist/verification/20261105T162753.549131Z-v2-design/screenshots/S04-schedule.png) | [图片](../../../design/screens/ui-08/20261106-155000-347985-screenshot-multicourse-timetable-v01.png) | [提示词](../../../design/screens/ui-08/20261106-155000-347985-screenshot-multicourse-timetable-v01.prompt.txt) | 保留第 5 周、12 节时间网格及原高等数学，补充为 6 类、8 个课程块 |
| 更多 | [S05](../../../dist/verification/20261105T162753.549131Z-v2-design/screenshots/S05-more.png) | [图片](../../../design/screens/ui-20/20261106-155000-376270-screenshot-more-v02.png) | [初稿提示词](../../../design/screens/ui-20/20261106-155000-376270-screenshot-more-v01.prompt.txt)、[修正提示词](../../../design/screens/ui-20/20261106-155000-376270-screenshot-more-v02.prompt.txt) | 保留模块、设置两个实际入口，统一卡片与说明；修正稿去掉生成器额外添加的菜单 |
| 模块管理 | [S06](../../../dist/verification/20261105T162753.549131Z-v2-design/screenshots/S06-modules.png) | [图片](../../../design/screens/ui-17/20261106-155000-404779-screenshot-module-manager-v01.png) | [提示词](../../../design/screens/ui-17/20261106-155000-404779-screenshot-module-manager-v01.prompt.txt) | 保留导入、商店、外观、分类及 6 个实际模块与版本，精简描述并改善间距 |

当前候选保留旧截图导航，便于对照页面局部变化；这不改变 V2 已确定的四个主入口。课表新增课程是合成示例。模块版本来自原截图，不代表当前安装或更新结果。生成图经过视觉核对，不保证截图之外区域逐像素一致，也不代替运行验证。

## 与已有规范的关系

V2 采用今天／规划／课表／模块四个主入口。按[页面流程](PAGE_FLOWS.md)，模块管理与工具入口整合到模块主入口，不保留独立“更多”中转页。“更多”截图用于参考工具行样式；本轮改图中的旧导航也仅供视觉对照，实现时按 V2 规范处理。

新建任务候选体现渐进表单；名称之外均可选。关闭保留草稿、普通创建直接保存以及高风险动作另行确认，继续按[页面流程](PAGE_FLOWS.md)实现。图片中的课程、任务、版本、数量与启用状态为示例；候选不新增业务字段或确认规则。

候选图用于评估布局与视觉效果；字号、对比度、触控面积、键盘避让、长文本及大字体适配以[视觉规范](VISUAL_SPEC.md)与后续运行验收为准。图中颜色也不自动覆盖 `tokens.json`。

完整交接使用[设计总稿](README.md)与[总稿下载包](../../../dist/verification/20261106-v2-master/v2-design-master.zip)，已包含当前四页、19 张截图、规范和提示词。最早那轮自由重排稿已按用户要求删除，仅在本机保留文件名、摘要及删除原因。本机图片不提交，缺少本机产物的仓库检出可阅读上述优化意图。
