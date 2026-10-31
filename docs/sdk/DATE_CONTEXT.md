# 日程与日期上下文

[SDK 入口与兼容要求](../MODULE_SDK.md)。各能力的最低宿主 API 在对应小节说明；旧调用的回退与权限边界继续适用。

## API 1.14 的日程与待办呈现

默认界面采用柔和极简风格，设计规范与参考图见 [设计说明](../design/SOFT_MINIMAL_UI.md)。界面包选择与公共组件协议保持有效，模块可替换这些新组件的呈现。

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

从 `app.tasks 1.6.1` 起，`task.list` 的 daily 查询和 `task.dayCounts` 均可传入 `includeCompleted: true`：在所有日期保留计划日期、截止日期或实际完成日期为当天的已完成任务；未完成任务仍沿用日期与执行有效期规则。日程 `app.views.today 1.10.3` 使用此选项，完成前后共用优先级、创建时间排序及同一分页，不单独追加完成列表；精确计划继续参与课程时间混排，其他任务保持原分组。勾选、淡色、删除线及“已完成”说明表示完成状态，点击勾选可在原位重新打开。省略选项的旧调用保持原查询口径，复盘页继续按完成时间查看记录。

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
