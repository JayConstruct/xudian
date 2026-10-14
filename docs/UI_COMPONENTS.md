# 公共 UI 与界面包

公共组件通过稳定契约与实现分离。业务页面负责数据、校验和操作；UI 包负责样式与声明式布局。最终控件由 Flutter 宿主渲染，UI 包不启动脚本线程。

## 选择与恢复

设置 → 外观与交互 → 界面风格支持全局选择和模块专属选择，分别展示“全局风格”“模块专属界面”和“保存与恢复”；完整分类见 [设置层级](SETTINGS_HIERARCHY.md)。模块管理可以筛选 UI 包并预览；安装不会自动切换风格。预览包含五类模板、标题与导航，全部使用模拟数据，支持窄／宽屏和浅／深色，退出不保存。

界面风格和预览页的选择框共用 `AppSelectField`：弹出列表使用 20px 连续圆角、选项使用 14px 连续圆角，当前选项显示浅色背景与勾选；长名称最多显示三行，菜单按可用宽度和屏幕高度限制大小。选择框仅用于选择，不弹出输入键盘；选择风格仍先修改草稿，点击保存后应用。布局选择弹窗的选项沿用相同的连续圆角。

配置保存在现有 `AppSettings` 的 `ui.selection`，无需数据库结构迁移：

```json
{"formatVersion":1,"globalPackId":"app.ui.default","modulePackIds":{"app.views.today":"example.ui.compact"}}
```

组件按模块选择、全局选择、内置默认的顺序解析；模块显式选择“内置默认”时使用默认组件与样式，不继承全局包。导航使用全局选择。停用、卸载或加载失败的包不删除选择，界面回退并标明不可用，重新启用后恢复。保存成功后才发布选择；草稿保存检查持久化基线，拒绝覆盖其他操作的新配置。

选择与恢复页固定使用默认 UI。恢复默认只清除界面选择，不卸载包或删除业务数据；审核与权限等宿主控制由内置界面呈现。

宿主默认弹窗通过 `AppDesign.dialogInsets`、`dialogConstraints` 共用外侧留白与宽度上限；核心表单、审核和模块详情同时复用标题、内容和操作区内边距。长内容滚动，操作和草稿由宿主管理；界面包使用原有槽位，不改变最终确认和事务边界。尺寸与特殊浮层覆盖规则见 [弹窗尺寸与留白](UI_DESIGN_SYSTEM.md#弹窗尺寸与留白)。

## 契约与接口

组件 ID 的 `@1` 表示契约主版本，与包版本独立。`ui.catalog()` 提供当前契约目录。

| 类别 | 契约 | 必须保留 |
| --- | --- | --- |
| 操作 | `ui.button@1` | `press` 事件 |
| 内容 | `ui.card@1`、`ui.list@1` | `content`、`items` 槽位 |
| 输入 | 文本、开关、选择、日期／时间等输入契约 | `control` 槽位，宿主持有输入状态 |
| 列表模板 | `ui.page.list@1` | `items` |
| 表单模板 | `ui.page.form@1` | `fields`、`actions` |
| 设置模板 | `ui.page.settings@1` | `sections` |
| 详情模板 | `ui.page.detail@1` | `content`、`actions` |
| 时间网格模板 | `ui.page.timeGrid@1` | `grid` |
| 底栏 | `ui.chrome.bottomNav@1` | `navigation`、`input`（无快捷输入时提供空槽位） |
| 侧栏 | `ui.chrome.sidebar@1` | `navigation` |
| 标题 | `ui.chrome.header@1` | `title`、`actions` |
| 短暂反馈 | `ui.notification@1` | `content`，宿主持有正文、关闭与可访问语义 |

Flutter 页面通过 `UiComponent(ref, fallback, props, slots, events)` 使用组件，`UiPackScope` 传递模块与选择上下文。fallback 提供稳定默认内容；slots 是宿主持有的 Widget，输入、焦点与业务状态不交给包。

工作区顶栏右侧的统一「页面菜单」由宿主在标题模板外绘制，包含页面操作、顶部模块入口和设置；界面风格与恢复从设置中的外观分类进入。标题模板保留 `actions` 空槽位以兼容已有界面包，菜单不会被自定义顶栏隐藏或重复渲染。

统一菜单的历史验收见 [界面组件记录](archive/UI_COMPONENTS_20261009.md)，当前验证范围见 [验证记录](VERIFICATION.md)。

脚本页面使用纯构造函数：

```js
ui.component('ui.button@1', {
  key: 'save',
  props: {label: '保存', disabled: false},
  events: {press: {type: 'save'}}
})
```

事件端口只转发调用方提供的操作，UI 包不能添加权限或修改原业务事件。旧节点通过兼容层继续进入公共组件，原字段与事件语义保持。

## 包格式与示例

仍使用 `.xmodule` ZIP、`packageFormat: 2`、`formatVersion: 3` 和现有摘要／来源审核。manifest 声明 `kind: "uiPack"`、`hostApi: "^1.6.0"`；`dataVersion` 为 1，permissions、collections、services、pages 为空，省略 entryPoint。旧包未声明 kind 时仍作为脚本模块。

`uiPack.contractVersion: 1` 定义 tokens、components、templates 和 chrome。light／dark tokens 支持 primary、surface、canvas、radius 和 spacing，缺失配置继承默认；颜色使用 `#RRGGBB` 或 `#AARRGGBB`。每个组件实现包含 tree，最小按钮替换：

```json
{
  "ui.button@1": {
    "tree": {
      "type":"primitive", "name":"button",
      "props": {
        "label":{"bind":["props","label"]},
        "disabled":{"bind":["props","disabled"]},
        "variant":"outlined"
      },
      "event":"press"
    }
  }
}
```

节点支持 base（完整内置实现）、slot、primitive、component、if、repeat 和 responsive。绑定只能读取 props、当前 item／index 和 environment。条件与响应分支必须保留必要槽位／事件；base 满足当前契约的全部要求。循环引用、不兼容契约、重复放置原生控件和超过 32 层的展开被拒绝。原生滚动槽位不能放入会使视口失去高度约束的滚动包装；纵向布局中的列表、网格和导航槽位由宿主分配剩余高度。

原子节点支持 column、row、wrap、card、text、button、icon、divider、spacer、padding、expanded、scroll、list。以当前目录与验证器为准，不能把任意 Flutter 控件名作为原子节点。

示例源码为 `packages/modules/example.ui.compact/module.json`，产物为 `dist/modules/example.ui.compact.xmodule`。它使用绿色浅／深色配置、紧凑间距、描边按钮，以及保留默认内容的模板与导航包装。导入后在“界面风格”预览并保存。

## 性能与验证

校验时编译声明树，宿主发布不可变注册表；组件渲染不重复读取 ZIP 或解析 JSON。高频输入、焦点、滚动、按压由宿主执行；包只转发业务事件。列表按需构建，模板保留宿主的滚动与尺寸处理。任务视图首批读取 50 项，通过“加载更多任务”扩大页面；数据服务对兼容的标量筛选、排序和分页使用绑定参数的 SQLite 查询，仅解析请求页记录。比较涉及混合类型、非 ASCII 排序、复杂值或暂存写集时保留原 Dart 语义；类型检查按集合修订号缓存。

页面记录实际读取的模块，忽略无关模块的数据变化；纯 UI 包安装和风格切换只重建呈现，不重新执行业务页面脚本；读取 `ui.examples()` 的目录页面会因 UI 包注册表变化刷新示例列表。默认控件子树使用稳定身份保留文本、焦点、选择范围和滚动状态。

性能验收在相同设备、数据和操作下比较默认与示例包的帧耗时、掉帧、内存与切换耗时；使用 profile 构建分别检查 UI／绘制阶段。60Hz 帧预算约 16.7ms，120Hz 约 8.3ms。功能测试覆盖保存失败、并发修改、重启、缺失包回退、停用／更新、预览不写业务数据与输入／滚动状态保留。平台性能须分别测量，Linux 测试不能代替 Windows 或 Android 真机。

本轮实现、自动化结果和 Android 调试包见 [界面包验证记录](archive/UI_PACK_VERIFICATION.md)。

## 公共输入控件与 UI 示例

宿主 API 1.7.0 补齐日期、时间、日期时间、日期范围、多选与数字输入，搜索模式复用 ui.input@1；新增 ui.dateRangeInput@1 和 ui.slider@1，均保留 control 槽位。已有 @1 契约的必需槽位与事件要求保持兼容；未提供新控件样式的 UI 包使用内置回退。

生产 UI 示例位于 `packages/modules/app.ui.examples`。首页按操作、输入、选择、日期、反馈、浮层和布局七类列出示例，分类与普通条目不使用重复占位图标；每个示例打开独立页面，实际控件支持交互，底部按钮打开调用方式弹窗，支持单段复制与复制全部（API 1.13）。内置 38 项覆盖公共控件、反馈、浮层和淡入／缩放／滑动动画。点击固定会将入口保存到本模块的 UI 偏好，首页可直接打开。所有示例使用模拟数据。

API 1.12 支持 UI 包向这些分类注册自己的公开组件。`ui.examples()` 发现所有已启用 UI 包明确注册的示例；安装、更新和停用提供者时目录立即刷新。示例页通过 `componentExample` 在局部使用提供者的真实实现，浏览示例不改变全局界面风格。

值格式、事件和新节点见 [SDK API 1.7](MODULE_SDK.md#api-17-的选择控件与组件示例)。原始设计与验收历史见 [修改方案归档](archive/UI_EXAMPLES_PLAN.md)。


## 注册组件示例与跨模块消费（API 1.12）

UI 包的 recipe 可添加 `example`，与 `tree`、自定义契约字段并列。自定义引用仍须使用提供者包的命名空间。下面条目可放入 `uiPack.components`，manifest 的 `hostApi` 使用 `^1.12.0`：

```json
{
  "example.ui.compact.outlineButton@1": {
    "propsSchema": {"type":"object","properties":{"label":{"type":"string"}},"required":["label"],"additionalProperties":false},
    "events": ["press"],
    "tree": {"type":"primitive","name":"button","props":{"label":{"bind":["props","label"]},"variant":"outlined"},"event":"press"},
    "example": {"category":"actions","name":"描边操作按钮","description":"紧凑界面包公开的描边按钮","props":{"label":"执行示例"},"events":["press"]}
  }
}
```

分类仅支持 `actions`、`inputs`、`selection`、`dates`、`feedback`、`overlays`、`layout`。示例名称最多 80 字符、描述最多 500 字符、整个声明最多 8 KiB；props 按组件契约校验，不能绑定脚本状态或携带处理器。slots 仅接受有限的原生文字、布局、进度及输入节点，最多 128 节点／8 层，禁止组件递归、事件、脚本绑定与无限高度包装。自定义必需槽位须有样例；系统输入的 `control` 由宿主合成并持有输入状态。events 只列契约端口名，省略 props、slots、events 时分别为空对象、空对象、空数组。系统契约允许添加 example，仍不允许重定义契约。

目录每项返回 `providerId`、`ref`、上述元数据及 `contract`。专用示例节点只接受已注册样例，不能覆盖样例 props／slots，调用方可将已声明端口映射为本页事件：

```js
const samples = await ui.examples();
const sample = samples[0];
const tree = {type:'componentExample', providerId:sample.providerId,
  ref:sample.ref, events:{press:{type:'demoPressed'}}};
```

业务模块消费自定义引用时在 manifest 的 `dependencies` 声明 `example.ui.compact`，随后使用标准接口；依赖检查保持有效，示例浏览的局部权限不会授予其他引用：

```js
ui.component('example.ui.compact.outlineButton@1', {
  props:{label:'保存'}, events:{press:{type:'save'}}
})
```

对于 `ui.button@1` 等系统引用，普通 `ui.component` 遵循当前界面选择。目录的 `componentExample` 专门展示所标明提供者的实现；声明依赖不会改变系统引用的全局选择。公共按钮的 `props.variant` 支持 `tonal`、`filled`、`outlined`、`text`，包 recipe 显式设置 variant 时使用该实现的样式。

API 1.14 新增每日概览、分区标题、日程条目和待办条目四个公共组件及独立演示。通过公共引用调用可跟随当前界面包；日期条以真实日期标记当天，日程与待办传入模块数据与事件。详细属性见 [日程与待办呈现](MODULE_SDK.md#api-114-的日程与待办呈现)。

API 1.16 为 `ui.dayOverview@1` 增加可选 `change` 日期事件。默认实现支持日期条、前后日、中文日期选择器和回今天，事件值为 `YYYY-MM-DD` 字符串；无事件的旧调用与界面包保持兼容。日期与模块内容的联动使用容器局部运行时上下文，见 [每日日期上下文](MODULE_SDK.md#api-116-的每日日期上下文)。

API 1.17 可通过 `dateHeading: false` 隐藏概览的重复完整日期，保留日期选择操作；默认值为 `true`。根页面 `headerMode: 'date'` 在工作区或详情顶栏显示共享选中日，继续使用公共顶栏与受保护菜单，见 [日期顶栏](MODULE_SDK.md#api-117-的日期顶栏)。

## 日期概览与工作区组合（API 1.18）

使用以下新增行为的模块声明 `hostApi: '^1.18.0'`；`ui.dayOverview@1` 的引用、可选 `change` 端口及旧调用保持兼容。默认实现新增：

| 属性 | 默认值／用途 |
| --- | --- |
| `dateHeading` | `true`；控制完整日期标题，API 1.17 已提供 |
| `dateControls` | `true`；设为 `false` 隐藏日期选择及前后日一行，保留日期条和可交互的回今天入口 |
| `days[].pending` | 可选待办数量，显示在日期卡片中 |
| `days[].completed` | 可选已完成数量，非零时显示 |
| `days[].truncated` | 默认 `false`；为 `true` 时在数量后显示 `+`，表示统计可能未覆盖全部记录 |
| `days[].isToday` | 可选当天标识；`todayDate` 与条目日期相等时也标识当天 |

选中日保持明显的选中反馈，当天与选中日可分别标记。设置 `dateHeading: false` 不会隐式关闭日期控件；在顶栏已提供日期操作的页面，调用方可另设 `dateControls: false`。日期卡片仍通过原来的 `change` 端口发送有效民用日期；没有该端口时保持信息展示。

```js
ui.component('ui.dayOverview@1', {
  props: {selectedDate, todayDate, dateHeading: false, dateControls: false,
    days: [{date: selectedDate, label: '周一', pending: 3, completed: 0}]},
  events: {change: {type: 'selectDate'}}
});
```

`days` 的数量来自业务调用方，组件不会查询数据。日程以选中日为中心显示五日条，通过 `app.tasks/task.dayCounts@1` 一次取得各日统计；历史完成状态、今日逾期口径及读取上限见 [SDK 五日概览与待办统计](MODULE_SDK.md#五日概览与待办统计)。界面包可利用这些可选属性调整呈现，旧 recipe 仍可使用已有字段或 `base` 默认实现。

日期根容器可显式选择 `initializesRuntimeContext: true`，先建立 `selectedDate` 再挂载分区；默认关闭，已有容器保持兼容。内联内容首次统一显示，刷新保留原子树、草稿和滚动位置，并提供一处更新进度提示。门控条件与错误处理见 [SDK 日期容器的初始上下文](MODULE_SDK.md#日期容器的初始上下文)。这些等待、输入状态和业务交互规则由宿主管理，界面包无需实现异步协调。

`workspaceAssistant` 是模块贡献槽位，不是界面包组件引用。助手是否支持当前页，由活动根模块、有效内联 sections 内容模块及递归依赖中的工具服务决定；宿主选择首个适用助手并传入页面上下文。“更多”工作区不显示该入口。工具目录可见性不授予调用权限，详细注册方式见 [SDK 工作区助手入口](MODULE_SDK.md#工作区助手入口)。

## 原生页面与默认实现（API 1.15）

`app.ui.default` 是宿主内置原生实现的公共 provider 身份。没有选择界面包、所选包不提供某个引用或包不可用时，该引用回到此 provider；默认实现保留 Flutter 控件，不需要伪造 JavaScript 模块。图标使用同一 `ui.icon@1` 契约，默认绘制与兼容规则见 [图标系统](design/ICON_SYSTEM.md)。

普通设置、模块商店、布局编辑、详情页及宿主反馈通过 `NativeUi` 接入公共引用。纯文字按钮使用 `ui.button@1`，包可替换按钮实现并继续通过 `press` 调用原操作；复合图标按钮及有原生交互状态的控件保留完整控制槽，避免丢失私有 Flutter 子树、文字、焦点或回调。日期／时间、选择、复选、切换、文本、滑杆仍复用既有公共输入契约。

| 引用 | 必需槽位 | 用途 |
| --- | --- | --- |
| `ui.page.native@1` | `body` | 原生 Scaffold 的页面内容，保留 AppBar、键盘避让、抽屉、FAB 与导航 |
| `ui.chrome.pageHeader@1` | `control` | 详情页 AppBar，保留返回与标题语义 |
| `ui.nativeSection@1` | `content` | 设置分组与原生条目集合 |
| `ui.nativeTile@1` | `control` | 带导航、选择或原生行为的条目 |
| `ui.nativeControl@1` | `control` | 复合按钮及其他原生交互控件 |
| `ui.iconButton@1` | `control` | 原生图标按钮及触摸范围 |
| `ui.nativeDialog@1` | `control` | 普通原生对话框，包含原始内容与操作 |
| `ui.nativeFeedback@1` | `control` | 原生错误及重试状态 |
| `ui.notification@1` | `content` | 保留关闭、时长及可访问语义的宿主浮动提示 |

原生 `AppToast.show` 与脚本 `ui.notify` 共用这一通知契约，解析调用处的有效界面选择。UI 包可以包装 `content` 调整外观，位置、宽度约束、动画、计时、单条替换和重复提示去重由宿主持有。默认 UI、场景边界和真实交互示例见 [全局 Toast 规范](design/TOAST.md)。

这些 recipe 可用 padding、背景、card、column 等实际包装或布局原生控件。mandatory 槽位只能出现一次，不能通过隐藏、重复或丢弃控件移除操作。`ui.page.native@1` 的 `body` 需要有限高度；vertical column 自动为它分配剩余空间。card 应只有一个明确的 bounded column 子节点，不允许直接将标题与滚动 body 放进多子节点 card，也不能在 body 外再套 scroll／list／wrap／row。

界面包更换同时更新原生与脚本页面的公共组件和 Theme tokens；原生输入保留同一 controller、focus、选区和未提交内容。模块安装审核、权限确认、卸载影响及 UI 包恢复入口固定使用默认 provider；普通页面仍跟随用户界面包。这些保护界面继续使用同一默认视觉风格。系统键盘、系统文件选择与 Material/Cupertino picker 内部由平台控件管理。

真实安装两个 UI 包并进行全局切换的回归见 `client/test/native_ui_pack_test.dart`：覆盖原生页面布局、文字与复合按钮、ScriptPage 控件与事件、未提交输入状态，以及业务记录／操作日志不变。
