# 组件、顶栏与菜单

[SDK 入口与兼容要求](../MODULE_SDK.md)。各能力的最低宿主 API 在对应小节说明；旧调用的回退与权限边界继续适用。

## API 1.2 的顶栏与设置组件

工作区页面声明 `headerMode: "contributed"` 后，可返回：

```javascript
header: {
  title: '第 1 周',
  leading: {label: '大学课表', event: {type: 'chooseTimetable'}},
  titleEvent: {type: 'chooseWeek'},
  actions: [{label: '回到本周', event: {type: 'currentWeek'}}],
}
```

宿主只接收活动工作区对应页面和实际模块实例的贡献；旧页面、停用实例、更新前实例的迟到响应不能改写顶栏。声明委托顶栏的页面从第一帧起由模块提供标题与页面操作；首次返回前预留标题区域，不用导航入口名作临时标题。普通页面继续显示宿主标题，脚本错误通过内容区错误提示和重试处理。工作区右上角统一保留一个「页面菜单」按钮，依次包含当前页面操作、全部顶部模块入口和设置；普通页面也使用同一个菜单。界面风格与恢复从“设置 → 外观与交互 → 界面风格”进入。顶部入口按布局顺序完整显示，菜单可以滚动，不再按屏幕宽度将顶部入口移至底部「更多」。菜单由宿主独立保留，界面包的顶栏模板不能移除它；`ui.chrome.header@1` 的 `actions` 槽位继续提供，当前为空槽位。

### API 1.30 的图标按钮与分级菜单

使用下列新增顶栏能力的模块声明 `hostApi: '^1.30.0'`。普通动作继续使用 `{label,event}`；`presentation:'inline'` 请求顶栏快捷入口，`variant:'filled'|'tonal'|'text'` 控制外观。`iconOnly:true` 显示纯图标按钮，仍须提供 `label` 作为读屏名称与提示。`overflowOnly:true` 仅在该快捷入口实际显示时从菜单隐藏，窄屏放不下时自动恢复菜单入口，不会丢失动作。

```javascript
actions: [
  {label:'新建', icon:'add', presentation:'inline', variant:'filled',
   iconOnly:true, overflowOnly:true, event:{type:'add'}},
  {label:'视图与显示', presentation:'menu', separatorBefore:true, children:[
    {kind:'choiceGrid', label:'显示天数', children:[
      {label:'3天', event:{type:'periodShortcut',days:3}},
      {label:'5天', selected:true, event:{type:'periodShortcut',days:5}},
    ]},
    {label:'每日显示时段', subtitle:'自动 07:00–22:00', event:{type:'displayHours'}},
    {kind:'stepper', label:'时间轴缩放', valueLabel:'标准',
     decreaseEvent:{type:'zoom',delta:-1}, increaseEvent:{type:'zoom',delta:1},
     decreaseEnabled:true, increaseEnabled:true},
  ]},
]
```

有 `children` 的普通菜单项进入子菜单，不要求 `event`；`valueLabel` 显示当前选择，`subtitle` 显示说明，`separatorBefore:true` 增加组间分隔。叶子项的 `selected:true` 显示当前选项。`choiceGrid` 的子项是带事件的选项，`stepper` 必须同时提供两个事件，可分别禁用。网格选择与步进保持菜单打开，从当前活动页面的最新贡献更新选中状态和标签；其他叶子动作关闭菜单后分发事件。子菜单在同一锚定浮层中替换当前内容，按钮或系统返回键逐级返回。

动作总数最多64项，根列表最多12项，每组最多16个子项，根层计为0、最大深度4；标签及可选文字非空且不超过256字符。事件仍经当前页面租约分发，失活、替换或停用实例不能继续调用旧页面；宿主入口、设置及恢复能力不由模块菜单控制。活动工作区声明 `backEvent` 时，Android系统返回与顶栏返回发送相同事件；子菜单、弹窗和详情路由先处理自身返回，不向下层工作区发送事件。

`listTile` 使用 `title/subtitle/icon/trailing/event`，适合分组设置、内容概览及导航；无 event 时显示信息行。`timeInput` 使用 `key/text/value/event`，打开原生 24 小时时间选择器并返回 `{...event,value:"HH:mm"}`。普通 input 的 `onChangeEvent` 在输入变化后防抖 150ms；提交命令仍需读取最新 formValues，避免防抖期间的旧状态。输入控制器与定时器在页面上下文变化时清理；原生时间选择器还会拒绝更新或停用实例的迟到结果。

`ui.panel(pageId,context,{adaptive:true})` 在手机显示底部面板，在宽屏显示侧边详情面板。省略第三个参数保持原来的面板行为。`timeGrid.options.scrollToColumn` 指向列 ID，`scrollRequest` 为每次主动定位递增的令牌；普通刷新不重置用户横向滚动位置。声明 `hostApi: "^1.2.0"` 使用这些能力。


## API 1.3 的滚动工具栏

活动工作区的 `header` 可声明 `autoHideChrome: true`。顶栏按真实纵向拖动距离收缩，松手保留进度。时间表先消耗顶栏收缩距离，顶栏完全收起后才滚动表格；反向拖动先恢复顶栏。到顶下拉产生的空隙先被消除，惯性、回弹、横向滚动、脚本定位、位置恢复与视口尺寸变化不推动顶栏。手机导航在顶栏完全显示时展开，其他状态以独立300毫秒动画收起，同时以淡入、轻移和缩放显示宿主“展开工具栏”按钮；点击恢复顶栏和导航。动画支持中途反向与减少动画设置，隐藏区域关闭点击、焦点和无障碍节点。桌面侧栏保持可用。

切换工作区、页面实例更新、脚本错误或模块停用会恢复宿主控制入口。该能力由宿主实现，业务包只声明是否启用，不获得隐藏设置或恢复入口的控制权。需要声明 `hostApi: "^1.3.0"`。课表1.3.0在非空周视图启用此选项，课程与数据协议保持原样。


## API 1.4 的内容延伸与滚动余量

填满视口的根 column 使用 `underlapChrome: true` 时，宿主不再从页面视口中扣除悬浮栏高度。配合 `timeGrid.options.underlapChrome: true`，时间网格延伸至悬浮导航后方，宿主将当前工具栏遮挡高度作为网格纵向滚动末尾的余量。余量位于滚动内容内部，最后一行可完全移到导航或展开按钮上方；固定日期头保持原位。其他页面省略此选项保留原布局。需要 `hostApi: ^1.4.0`。

宿主 API 1.5.0 支持根 tree 的 `floatingPanel`：`{title,closeLabel,closeEvent,top,child}`。宿主在页面内容上方绘制可滚动的悬浮面板，最大宽度300、最大高度为可用视口的55%，避开底部导航。拖动标题栏可移动面板，位置始终限制在可用视口内；标题和关闭按钮始终可见。`child` 使用现有节点协议，关闭按钮发送 `closeEvent`，模块通过省略 `floatingPanel` 隐藏面板。面板外的页面保持可操作，显示/关闭面板不改变主内容的尺寸和滚动组件身份。`top` 默认为16并限制在视口高度的25%以内。使用此能力需声明 `hostApi: ^1.5.0`。

底部导航与展开按钮共用轻度半透明的模糊面板，图标及文字保持实色。高对比度模式采用不透明背景并关闭模糊，减少动画时直接切换。

## API 1.7 的选择控件与组件示例

`ui.dateInput@1`、`ui.timeInput@1`、`ui.dateTimeInput@1`、`ui.dateRangeInput@1` 由宿主提供真实选择器。props 支持 label、value、disabled、clearable、minDate、maxDate 和 errorText；日期与日期时间支持手动编辑，时间使用 24 小时选择器。日期范围不提供手动字符串编辑。`editable:false` 可将单值字段设为仅选择。

| 控件 | 确认后的 value | 清除后的 value |
| --- | --- | --- |
| 日期 | `"2026-10-08"` | null |
| 时间 | `"09:30"` | null |
| 日期时间 | `"2026-10-08T09:30"`，无时区的本地日期时间 | null |
| 日期范围 | `{start:"2026-10-08",end:"2026-10-10"}`，起止日均包含 | null |

确认／清除先更新 formValues，再转发 change；取消保留旧值，不发出 change。日期时间的两个选择步骤全部确认后才更新。手动编辑的非法文本保留在 formValues 并显示错误，提交时仍应校验，不得把不合法文本当成已确认日期。旧宿主对话框 date／datetime 的空值仍返回空字符串，既有 ISO 日期时间输入保持兼容。

```javascript
ui.component('ui.dateInput@1', {
  key: 'plannedDate',
  props: {label: '计划日', value: null, clearable: true},
  events: {change: {type: 'chooseDate'}},
})
```

新增 `ui.dateRangeInput@1`、`ui.slider@1` 保留 control 槽位。`ui.multiSelect@1` 使用 items/options 中的 `{value,label}`，change 回传完整数组，空选为 `[]`。`ui.numberInput@1` 支持 integer/min/max，编辑原文为字符串，验证后由调用方转换为数字。`ui.input@1` 可设置 `inputMode:'search'` 和 clearable，change 延续 150ms 防抖。宿主表单新增 time/dateRange 字段，并支持数字边界和整数校验。

旧节点支持 dateInput、dateTimeInput、dateRangeInput、multiSelect。tabs 可选 selectedIndex 显示当前项，scrollable 为 true 时横向滚动；未提供 selectedIndex 的旧 tabs 保持文本按钮。grid 采用宿主固定规则：内容宽度足够时两列，大字提高双列阈值；本身不滚动。inset 提供宿主标准内边距，disclosure 提供可展开说明。button 的 variant 可选 text/outlined/filled，默认仍是 tonal。

`ui.page.list@1` 的 filters 用作固定筛选区。items 的 list 节点可带 scrollKey 保留分类位置，scrollRequest 变化后滚动到顶部；仅保留本次页面实例。clearForms/replaceForms 同时检查字段内容和编辑修订号，保护在脚本执行期间继续输入的草稿。

UI 示例模块展示 17 个组件示例，支持搜索静态名称／用途／契约 ID、分类、演示状态、局部重置和展开说明。使用以上新增能力的模块应声明 `hostApi:"^1.7.0"`。

## API 1.9 的模块详情导航

详情页也支持声明 `headerMode: "contributed"`，并返回 `header: {title, backEvent?: {type: 'back'}}`。宿主在 App 顶栏显示当前 `title`；存在 `backEvent` 时，左上角箭头与 Android 系统返回向当前模块发送该事件，模块负责切回内部上一层。首页省略 `backEvent`，返回才退出详情路由。首次渲染前也不显示路由传入的临时标题，App 返回按钮继续可用。内容区域无需再次显示页标题或返回按钮。模块应保存内部导航路径，并在返回时保留输入、筛选及未保存草稿。

每条详情路由使用独立顶栏控制器，只接受自身顶层页面的贡献；内嵌页面、被替换或停用实例的迟到响应不能改写它，也不能影响下层工作区顶栏。需要声明 `hostApi: "^1.9.0"`，旧宿主拒绝安装，避免出现内容按钮已移除而宿主仍不支持内部返回的页面。

## API 1.10 的数字网格选择

`ui.dialog` 的 `select` 字段可以增加 `presentation: "grid"`，以圆角按钮网格显示选项并突出当前选择。按钮按可用宽度、字体大小和选项文字计算列数；对话框内容可滚动。单字段对话框同时声明 `submitOnSelect: true` 时，点击选项直接提交并关闭，取消仍返回 `null`。包含其他字段的表单继续使用“继续”统一确认。教学周使用纯数字标签和该模式，不再打开下拉长列表；需要声明 `hostApi: "^1.10.0"`。

宿主 API 1.11.0 为 v3 页面 `sections` 槽位增加 `inline: true`，例如 `{id:"daily",label:"今日内容",kind:"sections",public:true,inline:true}`。贡献按挂载顺序使用自然高度排列，共享槽位的一根纵向滚动；空槽位不显示占位内容，末尾余量避开悬浮导航。省略 `inline` 或设置 `false` 保持原有定高分区及各贡献独立的页面滚动。`inline` 必须为布尔值，且仅 `sections` 可设置为 `true`；定义此槽位的模块声明 `hostApi: "^1.11.0"`。

内联贡献的脚本返回普通自然高度 `column`，可使用文本、卡片和任务行等节点；不使用 `fillHeight`、`timeGrid`、`ui.page.*` 整页模板或独立纵向滚动节点。宿主将该贡献以嵌入模式渲染；同一贡献移到普通页面槽位后恢复完整页面渲染，用户挂载配置、排序、容量及上下文规则沿用原契约。旧 v1/v2 source 的槽位协议不增加 `inline`。

## API 1.12 的 UI 偏好、提示和过渡动画

声明 `hostApi: "^1.12.0"` 使用以下通用能力。`await ui.preferences.get(key)` 返回当前模块的 JSON 偏好值或 `null`；`await ui.preferences.set(key,value)` 持久保存并返回值，`null` 删除对应项。用于收藏的演示 ID、展示模式等界面偏好；不使用业务集合，不创建审核计划，不改变现有业务写入的审核规则。

偏好存入宿主独立 `host_ui_preferences` 表，以调用模块 ID 隔离，不接受 `moduleId` 等额外参数。仅具有 `ui` 权限的页面工作流可使用；查询、命令准备、迁移、安装验证及隔离预览拒绝访问。预览页面可捕获读取失败并显示默认界面。停用、普通卸载和升级保留偏好；“彻底删除数据和历史”清除该模块偏好。偏好不属于业务数据快照。

key 以英文字母开头，只允许字母、数字、下划线、点和短横线，长度 1–64。值仅接受有限 JSON：嵌套深度最多 8、总值节点最多 256、字符串最多 4096 字符、对象键最多 64 字符；单值编码最多 8 KiB，每模块最多 64 个键、总值编码最多 32 KiB。超限或非法值拒绝，原值保留。

```js
const pinned = await ui.preferences.get('gallery.pinned') || [];
await ui.preferences.set('gallery.pinned', [...new Set([...pinned, 'button'])]);
await ui.notify({message: '已固定到首页', kind: 'success', duration: 3000});
```

`ui.notify({message,kind?,duration?})` 显示顶部圆角悬浮 Toast，返回 `null`，带状态图标、自动消失和关闭按钮，页面仍可操作并遵循减少动画设置。message 为 1–200 字符的非空文本，kind 为 `info`（默认）、`success` 或 `error`，error 使用错误色；duration 为 1000–10000 毫秒的整数，默认 3000。不同提示替换当前提示；展示中的相同 message 与 kind 不重播、不延长计时，即使新调用传入不同 duration。关闭开始后再次调用可展示新条目。返回值不等待提示消失；调用无导航或业务数据副作用，权限和执行阶段限制与 UI 偏好相同。原生与脚本共用 `ui.notification@1`，UI、动画、场景边界及真实演示见 [全局 Toast 规范](../design/TOAST.md)。

`transition` 节点包装一个 `child`，effect 为 `fade`（默认）、`scale`、`slide` 或 `page`。`slide` 为向上滑入，`page`（API `^1.32.0`）使用与 App 普通页面一致的横向小幅滑入和淡入（水平位移为宽度的 4%，曲线为 easeOutCubic），适合模块内的页面切换。visible 默认 `true`，切换时播放进出动画；更新字符串／数字 `replayKey` 或更换节点 key 重播。duration 为 100–2000 毫秒整数，`page` 默认 300，其余效果默认 350。宿主保留原内容布局和控件状态，隐藏内容不响应输入且不进入无障碍树；系统或应用“减少动画”直接呈现最终状态。

API `^1.34.0` 增加 `timeRangeTable` 本地表单：节点提供稳定 `key`、`value`、`baseline`。值为 `{durationMinutes:"45",rows:[{id:"1",label:"第 1 节",start:"08:00",end:"08:45",manualEnd:false}]}`，基线使用相同结构。组件在本地处理时长和时间滚轮，修改开始时间时只为未标记手动的结束时间计算同日结果；手动结束时间始终保留。时长修改只作用于后续开始时间编辑，已有行不批量改写。表单回传完整草稿及 `dirty/resetDisabled/saveDisabled/error` 到 `formValues[key]`，编辑不触发页面 handler；固定保存按钮可绑定这些状态。保存时模块仍须重新验证值、数据基线与引用关系，不能信任表单提供的状态标记。

API `^1.33.0` 的 `page` 效果支持 `direction:"forward"|"back"`：切换 `replayKey` 时，前进让目标页横移淡入，返回让当前页按 App 路由的反向时间线横移淡出并露出目标页。同一页面的查询或表单更新不重播；旧页在切换期间不可操作或获得焦点，结束后释放。系统减少动画时立即切换。

```js
{type: 'transition', key: 'demo', effect: 'slide', visible: true,
 replayKey: state.replay || 0, duration: 350,
 child: {type: 'card', children: [{type: 'text', text: '动画内容'}]}}
```

`ui.button@1` 的 `props.variant` 支持 `tonal`（默认）、`filled`、`outlined` 和 `text`，内置实现及没有显式 variant 的界面包按钮原子节点均使用传入值。


### 已注册 UI 组件示例（API 1.12）

`ui.examples()` 无参数，返回所有已启用 UI 包公开注册的纯声明式示例，字段为 `providerId/ref/category/name/description/props/slots/events/contract`；props、slots、events 默认空对象／空对象／空数组。调用此接口的页面订阅 UI 注册表变化，提供者安装、更新、启停会刷新目录，普通业务页面继续只因业务读取变化刷新。

`{type:'componentExample',providerId,ref,key?,events?}` 展示目录注册的固定样例，并局部采用该提供者界面；events 仅映射样例已声明端口为本页事件，不能覆盖样例 props／slots。此节点不改变全局界面选择，也不扩展普通自定义组件的依赖权限。注册元数据、槽位限制与实际跨模块消费说明见 [UI 组件注册](../UI_COMPONENTS.md#注册组件示例与跨模块消费api-112)。

### 可复制的调用方式弹窗（API 1.13）

声明 `hostApi: "^1.13.0"`，页面可调用 `await ui.showCode({title, sections: [{title, code}]})`。宿主打开圆角弹窗，各段代码支持文字选择和“复制”，底部“复制全部”按顺序用空行连接原文；关闭后返回原页面。只允许具有 `ui` 权限的页面工作流，预览与服务拒绝调用；不会写入业务集合或审核记录。

弹窗标题和各段标题均为 1–120 字符的非空文本；sections 为 1–12 段，每段仅含 title/code，code 必须为非空文本，总代码长度不超过 100000 字符。

```js
await ui.showCode({
  title: '按钮 · 调用方式',
  sections: [{title: '组件调用', code: "ui.component('ui.button@1', {props: {label: '确定'}})"}]
});
```

API 1.13 的默认日期控件使用中文；时间以小时、分钟两列滚轮选择，取消保留原值。日期范围采用起止两个日期入口，沿用 `ui.dateRangeInput@1` 的完整 `{start,end}` / `null` 契约，没有独立的全屏范围选择器。单选用强调色和固定布局，按钮采用胶囊形状；滑块、进度条与折叠详情使用圆角表面。

## API 1.15 的原生公共 UI

原生普通页面与控件也通过公共 UI 契约解析所选界面包。新增 `ui.page.native@1`（body）、`ui.chrome.pageHeader@1`（control）、`ui.nativeSection@1`（content）、`ui.nativeTile@1`、`ui.nativeControl@1`、`ui.iconButton@1`、`ui.nativeDialog@1`、`ui.nativeFeedback@1`（control）及 `ui.notification@1`（content）。这些必需槽位由宿主持有并且只能呈现一次；provider 可实际调整包装与布局，输入焦点、控制器、回调、键盘避让及审核流程仍由宿主管理。

公共系统引用的默认 provider 为 `app.ui.default`，它标识内置原生实现。缺失 recipe 按引用回退；恢复与权限审核固定使用此默认实现。旧 @1 引用仍兼容。原生与脚本控件的 UI 包选择机制相同，完整覆盖和 viewport 约束见 [原生页面与默认实现](../UI_COMPONENTS.md#原生页面与默认实现api-115)，默认矢量与包替换规则见 [图标系统](../design/ICON_SYSTEM.md)。

## 紧凑日程配置（API 1.44）

API `1.44.0` 为现有 `dayOverview`、`sectionHeader`、`agendaItem`、`taskItem` 增加可选 `compact` 显示配置。`agendaItem` 可声明 `hideTime`、`eyebrow`、`icon`；`taskItem` 可声明 `startTime`、`endTime`、`color` 或 `colorKey`，时间列在窄屏或大字体下自动移到内容上方。任务与规划共用稳定内容配色；组件不查询、排序或修改业务数据。使用这些配置需更新 APK，并声明 `hostApi: "^1.44.0"`；省略配置时保持原组件呈现。
