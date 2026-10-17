# JavaScript 模块 SDK v1

当前宿主 API 为 `1.25.0`。公共 UI 契约、声明式 UI 包和全局／模块选择见 [公共 UI 与界面包](UI_COMPONENTS.md)。

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
| 工作区助手、日期容器初始门控、概览日期控件开关 | 1.18 |
| 系统 IANA 时区读取 | 1.22 |

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

`ui.navigate(pageId,context)`、`ui.panel(pageId,context)`、`ui.dialog({title,fields})` 使用宿主交互；表单支持 text/multiline、number、date/datetime、boolean、select/multiSelect 与安全输入；可声明 required/maxLength，非法输入留在对话框中。`ui.review(planId)` 展示真实写集和结果，宿主控制最终确认。当前合法计划先展示增改删摘要与记录前后对比，完整原始计划可展开；未知结构回退原始审核。取消不提交，过期快照仍由提交校验拒绝，规则见 [实际数据审核](design/DATA_CHANGE_REVIEW.md)。

宿主API `^1.27.0` 支持 `ui.review(planId, {title, message, confirmLabel, acknowledgement?})`，将日常操作显示为简洁确认框。标题、说明和按钮文字由模块从当前已校验预览生成，宿主绑定原冻结计划并负责最终确认；真实写集与完整前后值收进“查看变更详情”，存在真实删除时仍显示删除提醒。`acknowledgement` 是可选的风险确认文字，初始未勾选，勾选前确认按钮不可用，适合“安排超出截止”等需要明确接受的情况。不能用该参数绕过准备、权限、审核或提交前快照检查；未知计划结构继续回退原始审核。所有参数是非空纯文本，长度上限分别为120／6000／48／1000，未知参数拒绝；省略第二个参数保持原审核行为。

`ui.navigate` 指向可用工作区时，宿主关闭覆盖工作区的详情路由和模态面板，再激活目标并传递上下文；目标不可用时保留当前页面。目标模块随后打开的确认详情页直接显示，不需要用户手动返回工作区。`ui.panel` 继续打开面板，不切换工作区。

跨宿主调用被拒绝时，脚本捕获的 Error 的 `message` 和 `String(error)` 提供业务正文，去除重复异常前缀与调用堆栈；原始异常文本保存在 `error.diagnostic` 供诊断使用，不应展示给用户。未捕获的页面异常也以业务正文和重试操作显示，原始异常仍供宿主诊断。

`http.request({id,url,method,headers,body,credential})`、`http.cancel(id)` 受网络许可、地址和容量限制。`secrets.configure({endpoint,label})` 通过安全输入返回凭据句柄；`secrets.delete(handle)` 删除自身凭据。`grants.request({scopes})` / `revoke(id)` 经宿主审核，默认 30 分钟及 20 次写入。

`packages.prepare({definition,files})` 编译并在隔离临时数据空间执行预览，返回摘要绑定的提案；`packages.review(id)` 再次核验基线、来源和摘要，审核后安装。普通服务授权不包含安装权限。预览不能联网、交互或修改正式数据。

`files.readText()` / `saveText(name,text)` 为用户选择的 JSON 文本交换。`clock.today(ianaZone)`、`clock.now()` 和 `ids.new()` 由宿主提供。API 1.1 增加 `clock.local(ianaZone)`，返回 `{date,time,weekday}`，分别为民用日期、`HH:mm` 和星期 1–7，按指定时区计算。JavaScript 不读取设备文件路径、进程、系统命令或凭据明文。

API 1.22 增加 `await clock.systemTimezone()`，无参数，返回 `{zone,source}`。`zone` 是宿主时区库认可的 IANA 名称；`source` 为 `system` 或 `fallback`。每次调用重新读取系统设置，读取失败、无支持、无效名称或超时使用明确的 `Asia/Shanghai` 回退。`GMT`、`Etc/GMT` 和 `Etc/UTC` 等明确零时区别名规范为库支持的 `UTC`；不从数字偏移或 `CST` 等歧义缩写猜测地区。

该调用需要 `clock.today`、`clock` 或精确 `clock.systemTimezone` 权限，可用于有权限的查询、命令准备和只读页面准备；隔离预览、迁移与安装验证不能访问真实系统能力。异步读取完成后重新核对调用者是否仍启用。结果用于新记录默认值，已有记录应保留存储的时区，不能因系统设置变化自动改写；`source: 'fallback'` 应向用户说明。Android 及 Windows 实现与实测限制见 [时区与显示诊断](design/TIMEZONE_DISPLAY.md)。

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

活动工作区的 `header` 可声明 `autoHideChrome: true`。当前实现按真实纵向拖动距离连续收缩顶栏和手机导航，反向拖动连续恢复，松手保留进度。到顶下拉可拉开空隙，上滑先消除空隙再收缩顶栏；惯性、回弹、横向滚动、脚本定位、位置恢复与视口尺寸变化不推动收缩。桌面滚轮通过实际指针信号控制进度。完全收起后保留宿主“展开工具栏”按钮；宽屏按钮位于常驻侧栏，手机按钮位于底部。完全隐藏的导航关闭点击和无障碍节点，辅助导航开启时仍保留可访问的展开按钮。

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

`ui.notify({message,kind?,duration?})` 显示顶部圆角悬浮 Toast，返回 `null`，带状态图标、自动消失和关闭按钮，页面仍可操作并遵循减少动画设置。message 为 1–200 字符的非空文本，kind 为 `info`（默认）、`success` 或 `error`，error 使用错误色；duration 为 1000–10000 毫秒的整数，默认 3000。不同提示替换当前提示；展示中的相同 message 与 kind 不重播、不延长计时，即使新调用传入不同 duration。关闭开始后再次调用可展示新条目。返回值不等待提示消失；调用无导航或业务数据副作用，权限和执行阶段限制与 UI 偏好相同。原生与脚本共用 `ui.notification@1`，UI、动画、场景边界及真实演示见 [全局 Toast 规范](design/TOAST.md)。

`transition` 节点包装一个 `child`，effect 为 `fade`（默认）、`scale` 或 `slide`。visible 默认 `true`，切换时播放进出动画；更新字符串／数字 `replayKey` 或更换节点 key 重播。duration 为 100–2000 毫秒整数，默认 350。宿主保留原内容布局和控件状态，隐藏内容不响应输入且不进入无障碍树；系统或应用“减少动画”直接呈现最终状态。

```js
{type: 'transition', key: 'demo', effect: 'slide', visible: true,
 replayKey: state.replay || 0, duration: 350,
 child: {type: 'card', children: [{type: 'text', text: '动画内容'}]}}
```

`ui.button@1` 的 `props.variant` 支持 `tonal`（默认）、`filled`、`outlined` 和 `text`，内置实现及没有显式 variant 的界面包按钮原子节点均使用传入值。


### 已注册 UI 组件示例（API 1.12）

`ui.examples()` 无参数，返回所有已启用 UI 包公开注册的纯声明式示例，字段为 `providerId/ref/category/name/description/props/slots/events/contract`；props、slots、events 默认空对象／空对象／空数组。调用此接口的页面订阅 UI 注册表变化，提供者安装、更新、启停会刷新目录，普通业务页面继续只因业务读取变化刷新。

`{type:'componentExample',providerId,ref,key?,events?}` 展示目录注册的固定样例，并局部采用该提供者界面；events 仅映射样例已声明端口为本页事件，不能覆盖样例 props／slots。此节点不改变全局界面选择，也不扩展普通自定义组件的依赖权限。注册元数据、槽位限制与实际跨模块消费说明见 [UI 组件注册](UI_COMPONENTS.md#注册组件示例与跨模块消费api-112)。

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

## API 1.14 的日程与待办呈现

默认界面采用柔和极简风格，设计规范与参考图见 [设计说明](design/SOFT_MINIMAL_UI.md)。界面包选择与公共组件协议保持有效，模块可替换这些新组件的呈现。

| 公共组件 | 原生节点简写 | 数据与动作 |
| --- | --- | --- |
| `ui.dayOverview@1` | `dayOverview` | `date` 为民用日期；`summary` 文本，`days:[{date,label}]` 与 `selectedDate` 展示日期条。API 1.16 可绑定可选 `change` 端口切换日期；无事件时保持信息展示。 |
| `ui.sectionHeader@1` | `sectionHeader` | `title/subtitle/count`，`actionLabel/actionIcon`；组件 `press` 端口执行操作。简写使用 `action:{label,icon,event}`。 |
| `ui.agendaItem@1` | `agendaItem` | `title/subtitle/startTime/endTime/color/badge`；`press` 打开真实课程或事件详情。简写使用 `event`。 |
| `ui.taskItem@1` | `taskItem` | `title/subtitle/completed`；`change` 提交布尔值，`open` 打开详情；可选 `details` 槽。简写使用 `event/openEvent/children`。 |

组件均支持声明式界面包覆盖。待办勾选与正文点击分开：勾选转发完成状态，正文转发编辑动作；模块继续通过已有 prepare/review/commit 更新数据。课程色只用于浅色块和窄色条，标题与说明使用宿主主题文字色；窄屏大字时可调整时间列排布。

```js
ui.component('ui.agendaItem@1', {
  key: 'course:' + item.occurrenceId,
  props: {title: item.title, subtitle: item.location,
          startTime: item.startTime, endTime: item.endTime, color: item.color},
  events: {press: {type: 'openCourse', reference: item}}
});
ui.component('ui.taskItem@1', {
  key: task.id,
  props: {title: task.title, completed: task.completed},
  events: {change: {type: 'complete', task}, open: {type: 'edit', task}}
});
```

“日程”（原“今天／每日”）沿用公共 inline daily 槽：概览、课程与任务分别贡献独立内容，共用滚动区域。概览仅读取任务模块，课程计数由课表模块自己的分区显示，课表未安装或停用不会阻断日程。快速添加通过分区标题的加号展开，扩展字段放入圆角折叠区。


## API 1.15 的原生公共 UI

原生普通页面与控件也通过公共 UI 契约解析所选界面包。新增 `ui.page.native@1`（body）、`ui.chrome.pageHeader@1`（control）、`ui.nativeSection@1`（content）、`ui.nativeTile@1`、`ui.nativeControl@1`、`ui.iconButton@1`、`ui.nativeDialog@1`、`ui.nativeFeedback@1`（control）及 `ui.notification@1`（content）。这些必需槽位由宿主持有并且只能呈现一次；provider 可实际调整包装与布局，输入焦点、控制器、回调、键盘避让及审核流程仍由宿主管理。

公共系统引用的默认 provider 为 `app.ui.default`，它标识内置原生实现。缺失 recipe 按引用回退；恢复与权限审核固定使用此默认实现。旧 @1 引用仍兼容。原生与脚本控件的 UI 包选择机制相同，完整覆盖和 viewport 约束见 [原生页面与默认实现](UI_COMPONENTS.md#原生页面与默认实现api-115)，默认矢量与包替换规则见 [图标系统](design/ICON_SYSTEM.md)。

## API 1.16 的每日日期上下文

“日程”（曾名“每日”）保留 `app.views.today.home` 与公共 `daily` 槽的标识。贡献模块通过 `context.selectedDate` 读取选中日；未选择时用 `clock.today()`。所选日期采用 `YYYY-MM-DD` 民用日期，课程模块在各课表时区内查询该日期的课程。

概览使用 `ui.dayOverview@1` 的可选 `change` 端口；事件值为日期字符串。`date/selectedDate` 指定所选日，`selectedDate` 优先；可选 `todayDate` 指定业务时区的今天，用于回今天入口。默认实现提供日期条、前后日按钮、中文日期选择器及回今天入口，支持 0001 至 9999 年有效日期。无 `change` 事件时仍是被动展示，已有界面包不必新增事件即可继续使用。

```js
export async function render({state = {}, event, context = {}}) {
  const today = await clock.today();
  const selectedDate = event?.type === 'selectDate'
    ? event.value : context.selectedDate || today;
  return {
    state,
    ...(event?.type === 'selectDate' ? {
      runtimeContextPatch: ui.runtimeContextPatch({selectedDate})
    } : {}),
    tree: ui.component('ui.dayOverview@1', {
      props: {date: selectedDate, selectedDate, todayDate: today},
      events: {change: {type: 'selectDate'}}
    })
  };
}
```

`ui.runtimeContextPatch` 是纯辅助函数，返回补丁本身。宿主只接受真实有效的 `selectedDate`，拒绝其它键；它不能改写任务、项目、实体或页面身份。补丁作用于当前页面合成树的运行时上下文，并通知所有内联贡献和嵌套容器重新查询；不写业务记录、界面偏好或导航编排。根页面建立作用域，详情与其它工作区隔离。更新保留脚本状态、输入控制器与草稿，过期异步渲染不能覆盖较新的选中日。

任务模块新增 `task.list` 的 `view: 'daily', date`：今日保持未完成计划任务和到期／逾期任务；其它日期只匹配当日计划或截止日期。历史日可显示关联的已完成任务，完成状态为当前状态；未来日只显示未完成任务。快速添加将所选日期写为 `plannedDate`，仍执行原有审核流程。旧 `today/all/inbox/raw` 查询保持兼容。

## API 1.17 的日期顶栏

工作区或详情根页面可声明 `headerMode: 'date'`，容器无需运行额外标题处理器。宿主从当前页面合成树的 `context.selectedDate` 生成具体日期与星期，当前年份显示“10月10日 周六”，跨年带年份。日期尚未建立时保留标题区域，首次渲染不显示入口名作为临时标题。

底栏名称独立于顶栏日期；当前入口为“日程”。日期标题继续走公共顶栏与受保护页面菜单，日期模式不自动启用滚动收缩。只有活动根页面且模块／页面匹配的租约可以发布标题；内联贡献和旧实例不能覆盖其它页面，脚本 `header` 仅在 `contributed` 模式生效。

`ui.dayOverview@1` 可传 `dateHeading: false` 隐藏重复的完整日期，仍保留中文“选择日期”、前后日、回今天和日期条。默认 `true`，已有调用与界面包保持兼容。此模式与运行时日期共享机制需要 `hostApi: '^1.17.0'`。

## API 1.18 的工作区助手与日程加载

使用以下新增能力的脚本模块声明 `hostApi: '^1.18.0'`。公共组件仍使用原来的 `@1` 契约主版本。

### 工作区助手入口

助手模块可在 `contributions` 注册 `workspaceAssistant` 槽位，`handler` 是打开助手时运行的页面工作流；该贡献不作为普通内容挂载到日程分区。

```json
{"id":"example.assistant.launcher","slot":"workspaceAssistant","handler":"render","label":"AI 助手"}
```

宿主按活动工作区根页面所属模块、通过槽位、权限、上下文与容量校验的内联 sections 内容模块，以及这些模块的递归依赖，确定相关模块集合。该集合中至少一个启用服务带有 `tool` 元数据时，支持该工作区的助手入口才显示；多个助手贡献时使用注册顺序中的首个支持者。未打开的 tabs、入口按钮及失效挂载不计入内容分支。“更多”工作区不显示助手入口。此判断依据页面组合和服务目录，不依赖固定的日程或待办模块 ID。

打开时助手工作流收到当前页面上下文；日期工作区还传入当前共享的 `selectedDate`。相关模块集合用于判断入口是否适用，不授予服务调用权，也不将助手的全部可用工具限制为该集合；读取目录、查询、命令准备及提交仍遵循原有权限与审核规则。

### 日期容器的初始上下文

页面可声明 `initializesRuntimeContext: true`，默认 `false`。当前初始门控只作用于拥有运行时上下文的根容器：`kind: 'container'`、`headerMode: 'date'`，且上下文尚无 `selectedDate`。宿主先运行容器自己的 handler，待它发布有效日期后再挂载内容槽位，避免各分区先查询默认日期、随后又查询选中日期。

```json
{
  "id":"example.daily.home", "handler":"render", "kind":"container",
  "headerMode":"date", "initializesRuntimeContext":true,
  "slots":[{"id":"daily","label":"日程内容","kind":"sections","public":true,"inline":true}]
}
```

```js
import {clock, ui} from '@xudian/sdk';

export async function render({state = {}, context = {}}) {
  const selectedDate = context.selectedDate ?? await clock.today();
  return {
    state,
    runtimeContextPatch: ui.runtimeContextPatch({selectedDate}),
    tree: {type: 'column', children: []}
  };
}
```

初始化 handler 应保持轻量，并声明所用 `clock.today` 权限；它须发布有效日期，否则槽位会继续等待。错误使用页面原有错误与重试界面。默认关闭该选项，已有原生容器及由内容贡献建立日期的页面继续按原方式工作。

同一内联分区组首次加载时，宿主等待各异步页面完成后统一显示；错误也算完成，失败分区显示错误而不会让其余分区永久等待。等待较长时使用一处进度提示。后续日期或数据刷新保留已显示子树、输入草稿和滚动位置，并显示更新进度；等待期间禁用业务内容交互，日期上下文控制仍可继续切换。旧请求不能恢复已过期的日期或清除较新请求的等待状态。

### 五日概览与待办统计

`ui.dayOverview@1` 新增 `dateControls`，默认 `true`。设为 `false` 时隐藏“选择日期”及前后日按钮，保留五日日期条、选中反馈、`change` 事件与回今天入口。`dateHeading` 独立控制完整日期标题；在已有可操作日期顶栏的页面可同时设置二者为 `false`，已有仅设置 `dateHeading: false` 的调用仍保留日期操作。

`days` 的条目可带 `pending`、`completed`、`truncated`、`isToday`：默认实现显示待办数量、非零已完成数量、当天标识与选中状态；`truncated: true` 在数量后标记 `+`。`todayDate` 也可确定当天标识。组件只展示调用方提供的数据，不自行查询服务，也不要求每个条目都提供统计。

待办模块 `app.tasks` 从 `1.3.0` 提供只读服务 `task.dayCounts@1`，它是模块服务，不是新增宿主全局方法。调用方声明依赖 `app.tasks: ^1.3.0` 和权限 `services.query:app.tasks/task.dayCounts@1`，单次传入 1–7 个不同的有效民用日期：

```js
const counts = await services.query(
  {moduleId: 'app.tasks', serviceId: 'task.dayCounts', majorVersion: 1},
  {dates: ['2026-10-10', '2026-10-11', '2026-10-12', '2026-10-13', '2026-10-14']}
);
// {today: '2026-10-12', days: [{date, pending, completed, overdue,
//   loadedPending, loadedCompleted, hasMore, truncated}, ...]}
ui.component('ui.dayOverview@1', {
  props: {selectedDate: '2026-10-12', todayDate: counts.today,
    dateHeading: false, dateControls: false,
    days: counts.days.map(day => ({...day, label: day.date.slice(5)}))},
  events: {change: {type: 'selectDate'}}
});
```

统计遵循 `task.list` 的 daily 口径：排除已删除、归档任务及子任务；今天包括未完成的当日计划任务和到期／逾期任务，其它日期只匹配当日计划或截止日期。历史日期包含关联任务当前的完成状态，未来日期只含未完成任务。同一任务在同一日期只计一次；不同日期可分别关联同一任务。`overdue` 仅在今天统计截止日期早于今天的未完成任务，历史统计不重建过去的完成状态。

从 `app.tasks 1.3.1` 起，服务按每页 1000 条读取过滤并排序后的任务，流式累计所有匹配记录，不逐日调用列表、不读取任务扩展或项目。`pending/completed` 返回完整统计，成功返回时兼容字段 `truncated` 为 `false`；旧版 `1.3.0` 最多读取 10000 条，达到上限时 `truncated` 为 `true`。`loadedPending/loadedCompleted` 对应该日期按优先级降序、创建时间升序排列的前 50 项，`hasMore` 表示匹配项超过 50，用于与任务分区首批列表一致的摘要。分批读取使用同一次服务调用的快照；读取期间集合版本变化会拒绝结果，避免混用不同版本。

`task.list` 的非空 `query` 也按每页 1000 条扫描，沿用 QuickJS 的 Unicode `toLowerCase().includes()` 语义，匹配后再应用 `offset/limit`，凑齐所请求的结果页即停止；任务扩展只查询该结果页。搜索可以找到第 10000 条之后的记录。搜索与统计的分批处理限制了每次桥接传输及脚本临时数组规模，但未将 Unicode 搜索或统计聚合下推至 SQLite；尾部或无匹配搜索、完整统计仍需扫描所有候选页。

日程概览以选中日为中心构造前后各两天，在一次渲染中批量查询五日统计；日期或实际数据变化后更新，不在每帧或每个日期条目中发起服务调用。课程仍由课表自己的内容分区提供，不增加概览对课表模块的强制依赖。


## API 1.19 的可折叠过渡

`transition` 新增可选布尔字段 `collapse`，默认 `false` 保持原来隐藏后仍占位的行为。声明 `hostApi: '^1.19.0'` 并设置 `collapse: true`，宿主在 `visible` 改变时渐变内容和高度；收起完成后内容离屏且不占高度，控件仍保留原 Element、输入草稿和选择。隐藏开始即撤出焦点、点击和无障碍遍历，重新展开不自动请求键盘。普通数据刷新不会重播；减少动画直接切到最终可见状态，快速反转从当前高度继续。通用默认时长保持 350ms，快速添加显式使用 220ms。

```js
{type: 'transition', key: 'quick-add', collapse: true,
 visible: !!state.quickExpanded, duration: 220,
 child: {type: 'column', children: [
   {type: 'input', key: 'quickTitle', text: '添加任务…', event: {type: 'add'}}
 ]}}
```

宿主自然高度 `column` 将唯一子节点 key 提升到最外层间距包装，插入、删除同级行时保留控件状态；重复 key 不提升，保持旧节点兼容。该保证不扩展到未声明重排索引的惰性列表。日程的内联贡献使用此自然高度路径，快速添加与业务审核、提交及输入清空逻辑独立。任务完成提示仅在审核通过且提交成功后显示，提示展示失败不改变业务提交结果。

## API 1.20 的稳定列表与提交反馈

声明 `hostApi: '^1.20.0'` 后可使用 `keyedList`。`children` 的每个节点必须提供不同的非空字符串 `key`；必填字符串 `scope` 标识日期、筛选或项目。相同 scope 内插入、删除、重排按 key 匹配各行，已有行保留 Element 与控件状态；首次挂载、普通刷新、加载更多和更换 scope 不播放整表入场。更换 scope 立即清除旧列表与进行中的反馈，避免把日期或筛选变化解释成任务完成。

根节点在独立页面始终使用惰性 `ListView.builder`，并按稳定 key 查找新索引，包括短暂保留的退出行；控件状态不会因跨过 50 行阈值改换布局。内联贡献或嵌套节点使用自然高度 `Column`，沿用其原有装载范围；不提供嵌套滚动视口。

```js
{type: 'keyedList', key: 'tasks', scope: `${selectedDate}:${projectId || ''}`,
 children: tasks.map(task => ({type: 'taskItem', key: task.id,
   title: task.title, completed: task.completed, event: {type: 'complete', task}})),
 feedbackKey: state.feedback?.key,
 removeKeys: state.feedback?.removeKeys || [],
 highlightKeys: state.feedback?.highlightKeys || [], duration: 220}
```

`feedbackKey` 是可选的有限数字或字符串。同一 scope 中，调用方只在业务提交成功后发布新的 token，并在随后刷新时复用；清空 token 不重新启用刚消费的 token，页面首次挂载会消费已有 token 而不重放。每次操作应使用不同 token，不将审核等待、取消、提交失败或普通查询结果作为成功反馈。

新的 token 仅对本次差量生效：`removeKeys` 中已从当前 children 消失的旧行渐隐并收拢，仍存在的行只更新数据；`highlightKeys` 中真正新增的行短暂显示 900ms 背景高亮，不改变已有行透明度。两者都是字符串数组，默认空。普通删除、翻页、外部写入不带新 token 时立即更新；历史日期的已完成任务如果仍在查询结果中，不执行退出。退出开始即禁用点击、焦点和无障碍遍历；连续提交与同 token 刷新保留每条退出的原截止时间，离屏行也按时释放。系统或应用“减少动画”立即更新最终列表并跳过高亮，开启该设置也会结束在途退出。

`duration` 控制退出时长，为 100–2000ms 的整数，默认 220ms；`spacing` 为 0–48 的有限数字，默认 12。UI 包仍可替换每个行组件，列表只负责稳定身份与通用呈现，不调用业务服务。这是视觉差量更新，服务查询、脚本执行和跨桥传输仍按既有刷新流程完成；不是 SQLite 或跨桥的局部更新协议。日程 `app.views.today 1.6.2` 使用此节点，在任务创建、完成的审核提交成功后提供反馈；快速添加仍使用独立的可折叠 `transition`。

## API 1.21 的纯时区转换与可选查询

API 1.23 新增 `await clock.toLocalMany([{utc, zone}, ...])`，返回与输入顺序相同的本地时间数组。最多 256 项，空数组返回空数组；每项复用 `clock.toLocal` 的日期、时区与夏令时规则，任一项无效则整批失败。页面、只读准备、query、command prepare 均可调用且无需额外权限。使用它的模块需声明 `hostApi: '^1.23.0'`。日程 `app.views.today 1.8.0` 使用批量转换，50 个精确计划的时间转换桥接从 100 次减少至 1 次，超过 128 个计划分批处理。

声明 `hostApi: '^1.21.0'` 后可使用两项无副作用转换，在页面、只读页面准备、query 和 command prepare 中均可调用，不需要额外权限，也不读取宿主当前时间：

```js
await clock.toLocal({utc: '2026-11-01T05:30:00.000Z', zone: 'America/New_York'});
// {date:'2026-11-01', time:'01:30', weekday:7}
await clock.toUtc({date: '2026-11-01', time: '01:30', zone: 'America/New_York'});
// {status:'ambiguous', instants:['2026-11-01T05:30:00.000Z','2026-11-01T06:30:00.000Z']}
```

`zone` 必填，为有效 IANA 时区名；`utc` 必须是以 `Z` 结尾、包含秒的 ISO UTC 时间戳，可含 1–6 位小数。输出日期为 `YYYY-MM-DD`、时间为 `HH:mm`，星期一为 1、星期日为 7。反向输入仅接受有效的 `YYYY-MM-DD` 日期与 `HH:mm` 时间；非法日期、时刻和时区报错。`clock.toUtc` 的 `status` 为 `unique`（一个候选）、`ambiguous`（多个候选，UTC 升序）或 `nonexistent`（空数组）。夏令时跳跃、重复与整日跳过均返回明确状态，不替调用者选候选或移动时间。

`manifest.optionalServices` 可声明只读可选服务，且必须保留相同引用的精确查询权限：

```json
{
  "permissions": ["services.query:app.schedule/schedule.query.timetables@1"],
  "optionalServices": [{"moduleId":"app.schedule","serviceId":"schedule.query.timetables","majorVersion":1,"kind":"query"}]
}
```

该声明仅排除由精确查询权限推导的必需依赖；显式 `dependencies`、`serviceDependencies` 与 command 权限仍是必需依赖。提供者缺失、停用或服务不兼容不阻止可选调用方安装、启用；停用提供者不会级联停用可选调用方。可先通过 `services.directory()` 判断服务是否存在；实际查询仍校验精确权限、服务种类、主版本与 Schema，缺少服务时抛错。可选声明本身不授予权限，也不允许 command。

`services.directory()` 记录当前服务目录与实例代数作为 prepare 的读取基线，包含可选提供者尚未安装或启用的状态；目录变化后提交拒绝并要求重新准备。只读页面准备也记录声明的可选提供者 ID，即使提供者当前缺失，安装或启停后页面可重新查询。


### API 1.24 规划交互原型

`ui.panel(pageId, context, {adaptive:true, wide:'center'})` 在手机仍用底部面板，在宽屏使用居中弹窗；未传 `wide` 时保留侧边面板。面板保存后可通过 `ui.navigate` 返回工作区并关闭面板。

新增原生树类型 `plannerBoard`。宿主只负责显示和发出拖动意图，合法性、来源权限、时区解析、变更审核与持久化由模块服务负责。声明 `hostApi: '^1.24.0'`。

- `days: [{date, label}]`；`candidates` 与 `blocks` 为任务块数组。每项可含 `id,title,start,end,durationMinutes,deadlineSummary,overdue,fixed,readOnly,sourceLabel,event,moveEvent,selected,selectEvent`。
- `start/end` 使用同一显示时区的无偏移本地 ISO 文本。脚本负责 `clock.toLocal` / `clock.toUtc` 转换并拒绝夏令时歧义，不能把它们直接当 UTC 写回。
- `blocks` 可附带真实来源提供的 `location` 与 `teacher` 文本；空间足够时地点优先、教师其次，未提供时省略，不从任意任务描述推断地点。`schedule.query.busy@1` 可选返回这两个字段，来自本次课程实例的地点和教师（包含调课覆盖），不改变只读来源及时间语义。
- 候选选择事件保留 `selectEvent.id` 并附加布尔 `value`。移动事件包含 `id,start,end,intent,targetId?,snapMinutes`，`intent` 可为 `move/swap/insert`，并不代表业务校验已通过。
- `options` 支持 `minColumnWidth,startMinute,endMinute,pixelsPerMinute,initialMinute,candidateLabel`；每日显示区间仅影响渲染。`previewBlocks/previewLabel` 可展示脚本计算的变更预览。

当前 app.planner 1.1.0 使用此原型：快速添加、任务详情、移动与交换及整体撤销；插入顺延和高级生成器仍待后续实施，参见 [第一阶段记录](verification/PLANNER_UX_STAGE1.md)。


### API 1.25 规划拖动预览与时长调整

`plannerBoard.previewQuery` 声明 `{ref: ServiceRef, input: {...}}`。宿主以当前页面模块身份调用只读 query，并把当前拖动事件作为 `proposal` 合并到 input；不能指定 command 绕过审核。权限、输入输出 Schema 和模块生命周期仍由宿主校验。声明此能力的模块要求 `hostApi: '^1.25.0'`。

宿主API `^1.28.0` 的 dashboard 看板会向当前工作区报告拖动状态，宿主仅将手机底栏淡出并停止其命中与语义，页面尺寸和底部避让值保持稳定；切页、取消与销毁自动清理，旧页面不能影响当前底栏。首页根节点可设置 `underlapChrome: true`，时间表绘制延伸到底栏下，宿主传入的底部避让仍用于选中面板、缩放操作和滚动末尾。dashboard 拖动默认5分钟步长，短横移进入1分钟精调并锁定日期，大幅横移进入新列换日，保留当前时刻并恢复5分钟步长；停留不换档。模式和日期转换重新锚定候选时刻，纵向精调降低灵敏度，手指附近显示模式、任务、日期起止和手势提示，并限制在屏幕安全区域。通用非dashboard看板保留15分钟普通吸附与停留1分钟细调。正常块与选中块不改变真实几何，调整时长手柄仅在选中后出现。

宿主API `^1.29.0` 的 `plannerBoard` 可声明顶层 `quickAdjustment: {taskModuleId, applyServiceId, undoServiceId}`；两个服务必须属于当前页面模块、major为1，任务来源仍须具备已有服务权限。此声明仅显示原生“快速调整”按钮，脚本不能设置开启状态或声明免审核。用户点亮按钮后，真实 `move`／`resize` 手势可对同一落点、单一任务的时间字段及配套历史写集授权一次；来源为通用 `tasks` 集合，配套 `batches`／`receipts`／`occurrences` 使用当前规划事务契约。冻结写集、服务参数、任务快照与时区瞬间均须一致，交换、插入、超截止及不匹配计划回到原确认。成功后提供8秒“撤销”，只恢复该次快照；后续编辑或完成仍阻止撤销。现有 `ui.review(planId, confirmation)` 和 `services.commit(planId)` 不增加脚本免审核参数。

原生页面自行维护快速调整的保存中显示，模块不需要传临时假任务：松手后目标位置显示一份任务，原候选／原安排临时隐藏，失败时恢复。保存不改变表格尺寸，用户可继续滚动。成功提示从宿主实际提交回执和冻结任务快照生成，最多两行展示具体任务与新时间，连续成功替换提示、撤销绑定最新操作；较早操作仍可在模块历史中处理。此原生显示优化不改变上述脚本契约与模块版本要求。

- 候选位置改变后停留180毫秒发起查询；只采用当前拖动中最新请求的结果。查询结果可包含 `previewBlocks, previewLabel, conflicts, valid, overdue`。旧结果、取消后和页面切换后的结果不继续显示。
- `previewIdentity` 是调用方提供的稳定视图版本，改变时取消当前拖动。当前页面忙碌、上下文失效或离开页面时停止拖动、滚动和预览。宿主还校验查询返回前的数据版本与页面实例。
- `intent` 增加 `resize`：保留原开始，移动末端，仍只发一次完整起止事件。固定／只读块没有末端手柄。边缘横纵自动滚动与手指速度分离；退出、取消或销毁时停止。
- 交换在本地先显示保留各自时长的双位置几何预览，随后可由服务校验结果替换。预览只是提示，最终提交仍须重新校验，不能根据 `valid` 客户端标志直接写入。

app.planner 1.2.0 用 `planner.operation.inspect` 提供轻量只读结果；使用 task 1.5.1 的单调编辑时间戳与轻量版本令牌阻止旧草稿覆盖。图形拖动仍走既有审核流程。详情见 [第二阶段记录](verification/PLANNER_UX_STAGE2.md)。


### 规划模块1.3：候选分页与移动时长

`planner.board.get` 增加 `candidateOffset`（默认0）、`candidateLimit`（默认100，范围1–200）、`onlyDeadline`（默认false）。输出 `candidateTotal/candidateOffset/candidateLimit/hasMoreCandidates`；只对待安排候选先过滤、稳定排序、再分页，`scheduled/busy` 不受影响。候选的选择标识跨页保留，最终排程服务会再次验证所有选中标识。只传回当前页候选与显示范围内已安排任务的轻量版本依据；服务内部候选构建仍会扫描任务和规则。

`planner.operation.preview` 的 `move` 可传 `preserveDuration:true`：已安排任务按原UTC起止的实际间隔计算新结束，未安排任务使用预计时长。图形拖动与 `operation.inspect` 的移动默认启用；详情明确编辑起止时传false。这样跨夏令时切换仍保留实际耗时；新开始时刻存在歧义时依然拒绝，不自动选择时区分支。`resize` 保持其独立语义，只改结束。

看板原生组件现在缓存按日局部碰撞组的几何索引，按横纵可见窗口及缓冲区构建任务块；已开始手势的源控件保留到释放，避免滚动时销毁。密集组只聚合本组，选择清单使用按需构建；业务校验仍读取完整占用，不能因任务未渲染而忽略冲突。

撤销在原有快照校验之外，先验证恢复的起止位置是否与新任务、课程或手动占用冲突；失败时整体不写入。仅撤销描述、删除新建任务等不会新增占用的变更不要求排程检查。详见 [第三阶段记录](verification/PLANNER_UX_STAGE3.md)。
