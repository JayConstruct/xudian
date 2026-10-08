# UI 示例页调研与改造建议

调研日期：2026-10-08。范围是 Flutter 组件示例的组织方式、交互演示和对当前项目的适用性。本次查看了 GitHub README、目录以及能够读取的源码，没有运行第三方项目或测量性能。以下优缺点属于结合本项目需求的设计判断。

## GitHub 参考

| 项目 | 已核对的做法 | 优点 | 对本项目的代价或限制 |
| --- | --- | --- | --- |
| [Flutter Material 3 Demo](https://github.com/flutter/samples/tree/main/material_3_demo) | 按操作、反馈、容器、导航、选择、文本输入分组；统一示例容器；宽屏切换双列；按钮展示多种样式及禁用状态 | 适合横向比较组件；使用 Flutter 原生控件，与当前 Material 3 主题相容 | 全量展示会使手机页面很长；源码的双列各自滚动，需要用户管理两个位置；固定示例尺寸不能直接作为本项目大字适配方案 |
| [Widgetbook](https://github.com/widgetbook/widgetbook) | 按文件夹、组件、用例组织；完整示例有设备视口、检查器、网格、对齐和缩放工具 | 能稳定复现不同状态；适合开发、设计评审和组件回归 | 对应用内展示而言，完整工具面板增加学习成本和维护工作；每种状态仍需要维护用例 |
| [shadcn_flutter](https://github.com/sunarya-thito/shadcn_flutter) | 单独的 Flutter Web 文档／组件画廊；文档源码区分组件、排版、颜色、主题；库包含日期、时间和多选等组件 | 组件目录容易扩展；可参考其组件覆盖范围和文档组织 | 属于另一套设计体系；虽然支持渐进混用，整套引入仍需适配本项目主题及公共 UI 契约，不能仅靠换库解决示例布局 |
| [Flutter Gallery](https://github.com/flutter-team-archive/gallery) | 定位是 Flutter 能力展示；README 已标记弃用，并推荐 Material 3 Demo 等替代资源；仓库于 2026-06-08 归档 | 可作为历史展示架构的参考 | 不适合作为需要持续维护的新实现基线 |

源码核对入口：

- [Material 3 分组、示例容器、日期／时间交互](https://github.com/flutter/samples/blob/main/material_3_demo/lib/src/component_screen.dart)
- [Material 3 响应式页面与双列切换](https://github.com/flutter/samples/blob/main/material_3_demo/lib/src/home.dart)
- [Widgetbook 完整示例及预览工具](https://github.com/widgetbook/widgetbook/blob/main/examples/full_example/lib/widgetbook.dart)
- [shadcn_flutter 文档目录](https://github.com/sunarya-thito/shadcn_flutter/tree/master/packages/docs/lib/pages/docs)
- [shadcn_flutter 库说明与渐进集成](https://github.com/sunarya-thito/shadcn_flutter/blob/master/packages/shadcn_flutter/README.md)

shadcn_flutter 部分文件正文未能通过浏览工具读取，因此这里不把具体预览界面、移动端体验或源码质量作为已验证结论。

## 当前项目的具体问题

生产入口使用 `packages/modules/app.ui.examples/main.js`，由 `client/lib/core/module_host/script_page.dart` 渲染。另有原生 `client/lib/features/ui_examples/ui_examples_page.dart`，主要用于旧架构示例与测试；只修改该文件不能改善生产示例页。

1. 标题、重置、说明、组合示例入口逐项占据主列，正文的视觉层级和空间利用不足。
2. 输入示例把文本、优先级、多选、日期、开关和滑块放进同一张卡片，定位某个组件不方便。
3. 脚本 `tabs` 渲染为普通文本按钮，没有读取当前选中项；切换后缺少明确的分类位置提示。
4. 脚本日期操作打开 `ui.dialog`；宿主对 `date`／`datetime` 仍渲染文本框，要求手输日期。已有 `timeInput` 原生时间选择器可以作为统一交互的起点。
5. 公共契约已经有 `ui.dateInput@1`、`ui.dateTimeInput@1` 和 `ui.multiSelect@1`，但脚本渲染映射分别还是普通输入和单选。目录中存在契约不等于已有完整交互能力。
6. 示例状态主要靠分散点击观察，缺少同一组件默认、已选、禁用、错误等状态的统一展示方式。

## 建议方案

采用 Material 3 的分类与示例容器，借鉴 Widgetbook 的状态用例组织，沿用本项目的颜色、连续圆角、公共组件契约和界面包机制。

布局分两层：分类浏览页帮助定位组件；组件卡片提供真实交互与结果。宽屏按可用内容宽度并排展示卡片，窄屏和大字模式回到单列。整个内容区共用一个纵向滚动区域，避免卡片内部再出现垂直滚动。不要为示例页复制应用已有的主导航。

每张示例卡片统一提供名称、简短用途、交互区域、当前值，以及局部重置。技术信息放入可展开的说明，展示公共契约 ID、值格式和事件格式。状态切换限于演示控件；示例页自身仍保持可操作。

建议分类为：基础操作、文本输入、选择控件、日期与时间、状态反馈、布局与导航。组件较多后增加名称搜索；当前阶段先做好分类和选中态。

## 组件补充顺序

第一批：日期、时间、日期时间、日期范围选择器，以及真实多选、数字输入、搜索输入。它们直接服务任务计划、截止日期、筛选和表单。

第二批：分段选择、菜单、提示气泡、折叠区、徽标和表单校验；完善加载、空、错误、成功状态的操作与结果反馈。

第三批：复杂表格、树、拖拽和颜色选择等，在出现明确业务用途后加入。

日期系列优先使用 Flutter Material 原生选择器并封装统一外壳。示例应覆盖空值、默认值、清除、取消、禁用、允许日期范围、非法输入和日期范围起止关系。日期时间须明确表示本地日期时间还是带时区的时间点；具体格式纳入公共契约。桌面锚点弹出日历可以后续按需求实现。

新增控件应贯通公共契约、宿主原生渲染、脚本事件、表单值和 UI 包的 `control` 槽位，再放入示例。避免只增加一个可点击的演示按钮，而其他模块仍无法使用。

## 验收重点

覆盖手机窄屏、桌面宽屏、大字、浅／深色；切换分类保留本次演示输入，局部重置只影响对应示例。选择确认正确回传值，取消保留旧值，清除回传空值；页面退出或模块更新后的迟到结果不得更新新会话。示例不产生业务写入。切换 UI 包后保留输入状态、焦点和滚动位置。

本次仅形成调研方案，未修改运行中的示例模块或公共组件。
