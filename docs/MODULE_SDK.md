# JavaScript 模块 SDK v1

当前宿主 API 为 `1.10.0`。公共 UI 契约、声明式 UI 包和全局／模块选择见 [公共 UI 与界面包](UI_COMPONENTS.md)。

新增模块使用 `formatVersion: 3`、`packageFormat: 2`，按所用能力声明最低 `hostApi`。组件/服务的 `@1` 主版本与宿主 API 版本分别管理，下方完整契约保留兼容规则。

| 能力 | 最低宿主 API |
| --- | --- |
| 工作区顶栏、设置行、时间输入 | 1.2 |
| 滚动收起工具栏 | 1.3 |
| 内容延伸 / 悬浮面板 | 1.4 / 1.5 |
| 公共组件与无脚本 UI 包 | 1.6 |
| 日期、多选及组件示例 | 1.7 |
| Android 网页采集 | 1.8 |
| 详情标题与内部返回 | 1.9 |
| 数字网格选择 | 1.10 |

模块包目录示例：

```text
module.json
main.js
calendar.js
assets/...
```

模块清单中的 id 采用命名空间，版本为语义版本（支持预发布/构建标识），`hostApi` 使用兼容版本范围（如 `"^1.0.0"`），`dataVersion` 为正整数。collections 声明本模块集合及 JSON Schema，services 声明版本化 query/command，pages 声明页面及入口。依赖可声明模块 ID，或 `{moduleId,version}` 版本约束；宿主更新会检查依赖范围与服务主版本。完整示例见 `packages/modules/app.schedule/module.json`。

```javascript
import {data, services, ui, ids, clock} from '@xudian/sdk';

export async function create({title}) {
  const id = await ids.new();
  return {
    writes: [{collection: 'items', id, value: {id, title}}],
    events: [{type: 'item.created', entity: {moduleId: 'private.example', collection: 'items', id}}],
    result: {id},
  };
}

export async function render({state = {}, event, formValues}) {
  if (event?.type === 'create') {
    const plan = await services.prepare(
      {moduleId: 'private.example', serviceId: 'items.create', majorVersion: 1},
      {title: formValues.title},
    );
    if (await ui.review(plan.planId)) await services.commit(plan.planId);
  }
  return {
    state,
    tree: {type: 'column', children: [
      {type: 'input', key: 'title', text: '标题'},
      {type: 'button', text: '创建', event: {type: 'create'}},
      ...(await data.query('items')).map(x => ({type: 'text', text: x.title})),
    ]},
  };
}
```

## 数据和服务

- `data.get(collection,id)`：只读本模块已声明集合；不存在返回 null。
- `data.query(collection,{filter,sort,offset,limit})`：filter 支持 all/any 与 `{field,op,value}`；op 为 eq/ne/lt/lte/gt/gte/in/isNull。sort 为 `{field,direction}` 数组；分页上限 10000。
- `data.watch(collection,options,listener)`、`services.watch(ref,input,listener)`：返回可关闭订阅句柄；停用时自动释放。
- `services.directory()`：当前启用服务及 tool 元数据目录；目录不授予调用权限。
- `services.query(ref,input)`：只读，校验输入/输出 Schema。
- `services.prepare(ref,input)`：界面工作流返回 `{planId,result,writes}`；在命令准备中调用则组合受权子计划并返回子结果。
- `services.commit(planId)`：须先经 `ui.review`；重新检查权限和数据基线。
- `services.adopt(planId)`：提供者接收自己确认的外部导入计划；仅限写入自身集合且单一提供者确认的计划。保留原来源身份与读取基线，不能改变写集。
- `extensions.query(entity)` / `queryMany(entities)`：实体拥有者读取已启用扩展的定义和值；扩展服务声明 `extensionFor`，值归扩展自身。`extensionFor.commands` 可发布 set/clear/setMany 服务；实体视图声明 `extensions.command:<owner>/<collection>` 后可调用这些明确的扩展命令，不能借此调用任意服务或其他实体范围。
- `events.subscribe({moduleId,types},listener)`：需精确 `events.subscribe:<module>/<type>` 权限，提交后通知。

query/command 的 JSON Schema 使用明确子集：type、properties、required、additionalProperties、items、enum、min/maxLength、min/maxItems、minimum/maximum。不要使用未支持关键字；更复杂的业务约束在 JavaScript 中验证。唯一索引用 `{id,fields,unique:true}` 声明。

## 交互和外部操作

`ui.navigate(pageId,context)`、`ui.panel(pageId,context)`、`ui.dialog({title,fields})` 使用宿主交互；表单支持 text/multiline、number、date/datetime、boolean、select/multiSelect 与安全输入；可声明 required/maxLength，非法输入留在对话框中。`ui.review(planId)` 展示真实写集和结果，宿主控制最终确认。

`http.request({id,url,method,headers,body,credential})`、`http.cancel(id)` 受网络许可、地址和容量限制。`secrets.configure({endpoint,label})` 通过安全输入返回凭据句柄；`secrets.delete(handle)` 删除自身凭据。`grants.request({scopes})` / `revoke(id)` 经宿主审核，默认 30 分钟及 20 次写入。

`packages.prepare({definition,files})` 编译并在隔离临时数据空间执行预览，返回摘要绑定的提案；`packages.review(id)` 再次核验基线、来源和摘要，审核后安装。普通服务授权不包含安装权限。预览不能联网、交互或修改正式数据。

`files.readText()` / `saveText(name,text)` 为用户选择的 JSON 文本交换。`clock.today(ianaZone)`、`clock.now()` 和 `ids.new()` 由宿主提供。API 1.1 增加 `clock.local(ianaZone)`，返回 `{date,time,weekday}`，分别为民用日期、`HH:mm` 和星期 1–7，按指定时区计算。JavaScript 不读取设备文件路径、进程、系统命令或凭据明文。

## 页面

API 1.6 增加 `ui.component(ref, options)` 纯构造函数，返回 `{type:'component',ref,...options}` 节点。options 支持稳定 key、props、slots 和 events；events 把公共事件端口映射到原业务事件，例如 `events:{press:{type:'save'}}`。`await ui.catalog()` 返回当前可用公共契约目录，包含 ref、propsSchema、requiredSlots 和 events。仅展示目录不授予跨模块权限。未知独有组件应声明提供者依赖；系统公共组件不依赖特定风格包。

页面也可使用 `ui.page.list@1`、form、settings、detail、timeGrid 模板，传入契约要求的内容槽位。宿主兼容旧节点，输入控制器、焦点、业务事件和滚动由宿主保持。Flutter 页面使用 `UiPackScope(moduleId: ...)` 与 `UiComponent`；预览传入显式 previewPacks／previewSelection，默认恢复与审核使用 defaultOnly。详见公共 UI 文档。

handler 接收 `{state,context,event,formValues}`，返回 `{state,tree,header?,queryResult?,clearForms?,replaceForms?}`。组件包括 column、row、card、text、richText、source、input、sourceEditor、button、checkbox、switch、select、slider、progress、spinner、list、tabs、divider、timeGrid。column 根节点可带 footer 固定输入栏。组件嵌套最多 32 层。

值可以使用 `{bind:["state","selected",0,"name"]}` 的类型化路径，根支持 state/context/queryResult/formValues/event。异步迟到结果不能覆盖新上下文；清空和替换表单只作用于提交后没有被用户继续编辑的值。页面切换、面板最小化保留短期草稿。

`timeGrid` 输入 columns、rows、blocks。每块 column 引用列的 id，行范围为 start/end，包含 start 不包含 end，可带 title、subtitle、color、event。同一时段重叠块分栏显示。日期、实例合并和课程内容由模块计算。

API 1.1 的 `toolbar` 使用 title/event 显示居中可点击标题，leading/trailing/actions 提供 `{icon,label,event,disabled?}` 操作，图标支持 swap、chevron_left、chevron_right、today、settings。`timeGrid` 的列和行可分别使用 title/subtitle/highlight；corner 指定左上角文字，options 支持 rowHeight、headerHeight、labelWidth、minColumnWidth、fillWidth。fillWidth 为 true 时按可用宽度排布列，日期头与内容横向同步滚动，左侧行标签固定。根 column 的 `fillHeight:true` 使最后一个组件填满视口；`edgeToEdge:true`、`spacing:0` 用于连续网格布局。普通页面仍使用原有外边距与滚动方式。

当前客户端增加 `timeGrid.options.fitColumns: true`：所有日期列均分扣除行标签栏后的可用宽度，忽略最小列宽，确保完整表格不超出屏幕。省略此选项继续使用原有按最小列宽横向滚动的行为。课表 1.6.3 使用此选项，在显示设置中控制五天或七天；需要包含该控件更新的客户端。

contributions 通过宿主公开槽位提供入口；kind 为 content 时内嵌声明式内容，其他贡献默认显示面板启动入口。页面可以声明 entry 或 entries，使多个稳定入口指向同一页面；context.pageId 由宿主注入。页面可公开 slots，由已有布局设置挂载其他模块入口。入口模块/页面 ID 和窄/宽布局配置持续保留。

## 升级

提高数据版本时，在 `migrations` 中为旧数据版本声明 handler；处理程序读候选副本并返回正常写集，不使用外部能力。迁移成功才切换正式指针。不兼容回退必须经过快照恢复。停用不删除数据，卸载后重启不会自动安装。

模块包工具和原生源码来源见 [MODULE_HOST.md](MODULE_HOST.md)。

## 受保护宿主服务

服务目录公开 `app.host/settings.get@1`、`settings.patch@1`、`layout.get@1`、`layout.patch@1`、`navigation.list@1` 和 `navigation.open@1`。它们与业务服务使用相同授权、实际变更审核、基线校验和条件撤销机制。布局编辑器存在未保存草稿时拒绝写入，页面参数不能扩大调用范围。


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

`listTile` 使用 `title/subtitle/icon/trailing/event`，适合分组设置、内容概览及导航；无 event 时显示信息行。`timeInput` 使用 `key/text/value/event`，打开原生 24 小时时间选择器并返回 `{...event,value:"HH:mm"}`。普通 input 的 `onChangeEvent` 在输入变化后防抖 150ms；提交命令仍需读取最新 formValues，避免防抖期间的旧状态。输入控制器与定时器在页面上下文变化时清理；原生时间选择器还会拒绝更新或停用实例的迟到结果。

`ui.panel(pageId,context,{adaptive:true})` 在手机显示底部面板，在宽屏显示侧边详情面板。省略第三个参数保持原来的面板行为。`timeGrid.options.scrollToColumn` 指向列 ID，`scrollRequest` 为每次主动定位递增的令牌；普通刷新不重置用户横向滚动位置。声明 `hostApi: "^1.2.0"` 使用这些能力。


## API 1.3 的滚动工具栏

活动工作区的 `header` 可声明 `autoHideChrome: true`。宿主响应实际用户的纵向滚动：向下累计48逻辑像素收起顶栏和手机导航，向上累计16像素或上拉至顶部恢复。横向滚动、脚本定位、位置恢复与视口尺寸变化不会触发收起。收起后保留宿主“展开工具栏”按钮；宽屏按钮位于常驻侧栏，手机按钮位于底部。隐藏导航同时关闭其点击和无障碍节点，减少动画设置使用即时切换，辅助导航开启时仍保留可访问的展开按钮。

切换工作区、页面实例更新、脚本错误或模块停用会恢复宿主控制入口。该能力由宿主实现，业务包只声明是否启用，不获得隐藏设置或恢复入口的控制权。需要声明 `hostApi: "^1.3.0"`。课表1.3.0在非空周视图启用此选项，课程与数据协议保持原样。


## API 1.4 的内容延伸与滚动余量

填满视口的根 column 使用 `underlapChrome: true` 时，宿主不再从页面视口中扣除悬浮栏高度。配合 `timeGrid.options.underlapChrome: true`，时间网格延伸至悬浮导航后方，宿主将当前工具栏遮挡高度作为网格纵向滚动末尾的余量。余量位于滚动内容内部，最后一行可完全移到导航或展开按钮上方；固定日期头保持原位。其他页面省略此选项保留原布局。需要 `hostApi: ^1.4.0`。

宿主 API 1.5.0 支持根 tree 的 `floatingPanel`：`{title,closeLabel,closeEvent,top,child}`。宿主在页面内容上方绘制可滚动的悬浮面板，最大宽度420、最大高度为视口的65%，避开底部导航，标题和关闭按钮始终可见。`child` 使用现有节点协议，关闭按钮发送 `closeEvent`，模块通过省略 `floatingPanel` 隐藏面板。面板外的页面保持可操作，显示/关闭面板不改变主内容的尺寸和滚动组件身份。`top` 默认为16并限制在视口高度的25%以内。使用此能力需声明 `hostApi: ^1.5.0`。

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

## API 1.8 的通用网页采集

`browser.capture({url,script})` 需要明确的 `browser.capture` 权限，Android 打开用户可操作的 WebView。用户登录、导航后点击「执行采集」才运行模块传入的脚本。只接受 HTTP/HTTPS URL（不含内嵌凭据）及最多256 KiB的脚本。关闭返回 null；其他平台明确报不支持，可使用文件导入。允许 HTTP 以兼容旧教务入口；现有宿主 HTTP 服务仍独立校验其许可和地址。

WebView 使用设备提供的内核和网络解析。主页面加载失败会保留 DNS、连接、HTTP 或证书错误提示，并禁用执行；页面重新加载成功后恢复。证书验证失败时取消加载。

网页脚本调用 `window.xudianCapture.send(type,value)`。type 为 status 显示状态，为 error 标记该执行失败，为 complete 返回 JSON 对象；结果上限2 MiB。每次执行独立标识，导航、关闭和新执行使旧结果失效。此接口没有数据库、服务提交或文件能力。宿主返回后重新核验调用实例，停用模块关闭采集窗口。业务兼容桥接由独立模块注入，宿主不识别拾光或正方数据结构。

课表1.6.1的 `app.schedule/schedule.query.timetables@1` 返回 `{timetables:[...]}`，供导入适配器选择目标和读取课表作息；需要精确 query 权限，不返回导入凭据。正方导入兼容包用法见 [SHIGUANG_IMPORT.md](SHIGUANG_IMPORT.md)。

兼容模块1.1.0的 `app.import.shiguang/shiguang.bridge.compile@1` 接受 `{script,bridgeVersion:1}`，返回含公共桥接的浏览器脚本文本。独立学校模块采集后通过导航上下文 `shiguangImport:{version:1,payload}` 交给兼容页的配置和预览流程；协议见 [SHIGUANG_ADAPTER_API.md](SHIGUANG_ADAPTER_API.md)。
## API 1.9 的模块详情导航

详情页也支持声明 `headerMode: "contributed"`，并返回 `header: {title, backEvent?: {type: 'back'}}`。宿主在 App 顶栏显示当前 `title`；存在 `backEvent` 时，左上角箭头与 Android 系统返回向当前模块发送该事件，模块负责切回内部上一层。首页省略 `backEvent`，返回才退出详情路由。首次渲染前也不显示路由传入的临时标题，App 返回按钮继续可用。内容区域无需再次显示页标题或返回按钮。模块应保存内部导航路径，并在返回时保留输入、筛选及未保存草稿。

每条详情路由使用独立顶栏控制器，只接受自身顶层页面的贡献；内嵌页面、被替换或停用实例的迟到响应不能改写它，也不能影响下层工作区顶栏。需要声明 `hostApi: "^1.9.0"`，旧宿主拒绝安装，避免出现内容按钮已移除而宿主仍不支持内部返回的页面。

## API 1.10 的数字网格选择

`ui.dialog` 的 `select` 字段可以增加 `presentation: "grid"`，以圆角按钮网格显示选项并突出当前选择。按钮按可用宽度、字体大小和选项文字计算列数；对话框内容可滚动。单字段对话框同时声明 `submitOnSelect: true` 时，点击选项直接提交并关闭，取消仍返回 `null`。包含其他字段的表单继续使用“继续”统一确认。教学周使用纯数字标签和该模式，不再打开下拉长列表；需要声明 `hostApi: "^1.10.0"`。
