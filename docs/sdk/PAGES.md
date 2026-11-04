# 页面、表单与状态

[SDK 入口与兼容要求](../MODULE_SDK.md)。各能力的最低宿主 API 在对应小节说明；旧调用的回退与权限边界继续适用。

## 页面

宿主 API `^1.45.0` 增加通用内容布局配置，业务字段、分组、文案和事件继续由模块声明：

- `icon {icon,size?:20,tone?:'accent',surface?:false,surfaceSize?:40,label?}` 显示共享矢量图标，可添加柔和底色。`badge {text,tone?,icon?}` 显示可换行状态文字；`tone` 支持 `accent`、`success`、`warning`、`muted`，沿用浅色与深色主题。共享图标增加 `book`、`clipboard`、`fitness`、`layers`。
- `card {variant:'outlined',padding?:14,event?,disabled?,children}` 提供细边框、连续圆角与可点击内容卡片；普通卡片声明 `event` 也可点击。`padding` 为 0～48 的逻辑像素。外部间距由父布局控制。
- `row.layout:'flex'` 的子节点可声明 `flex:1` 填充分配空间或 `width:70` 固定宽度；省略时使用内容自然宽度。`row.spacing` 为 0～48（默认8），`crossAxisAlignment:'start'` 顶部对齐，默认居中。普通 `row` 仍为可换行布局。`column.crossAxisAlignment:'start'` 取消横向拉伸，`trailingSpacing:false` 省略最后一项下方留白。
- `text.style` 增加 `headline`（24px粗体）、`body`、`caption`；`weight:'bold'|'semibold'`、`color:'primary'|'muted'`、`align:'center'|'end'` 可独立配置，文字继续适配系统字号。`maxLines` 支持1～10的整数，`overflow:'ellipsis'` 可将长标题在设定行数内省略，无障碍标签仍保留完整原文；省略配置时继续自然换行。`divider.height` 可配置分隔行总高度。
- `input.presentation:'search'` 将 `text` 显示为搜索占位而非浮动字段标签，其余输入、清空、防抖与草稿能力不变。`button.icon` 可显示共享图标。
- `tabs {variant:'pills'|'underline',items:[{label,event}],selectedIndex,scrollable?}` 提供紧凑状态筛选与下划线页签；每项保留48px操作区域与选中语义，`scrollable:true` 横向滚动，大字号或窄屏也自动允许横向滚动。
- 根节点 `footerStyle:'flat'` 让既有固定 `footer` 采用整宽内容底色、16px水平边距与顶部细分隔；省略时保留浮动底栏。`footerMessage` 仍单独位于按钮上方。双按钮可用 `row.layout:'flex'` 与各子按钮 `flex:1` 等宽呈现。普通根布局继续采用20px水平、16px顶端边距。
- 全屏子路由的 `header.compact:true` 使用20px粗体标题、48px返回区及8px标题间距。`header.backIcon:'chevron'` 将返回图标替换为共享左箭头，继续优先处理 `backEvent`，无内部返回时退出当前路由；省略时保持原顶栏呈现，面板样式不变。

使用这些配置须更新 APK 并声明 `hostApi:'^1.45.0'`，独立模块不能向旧宿主发送不支持的布局节点。

宿主 API `^1.37.0` 提供 `segmented {items:[{label,event}],selectedIndex}`、
`formSection {title,action?:{text,event},children}`、`notice {text,tone}`、
`choiceCard {title,subtitle,selected,event}`。`card.tone` 支持 `soft`／`selected`，
`listTile` 支持 `selected` 与 `trailingAccent`；搜索输入可声明 `showSearchIcon:false`。

宿主 API `1.43.0` 增加根页面配置 `pageTransition:{direction:"forward"|"back",duration?:260}`，以 `scrollKey`（回退为根 `key`）作为页面身份，在滚动区域与固定底栏外协调前进、返回过渡；同页输入不重播，减少动画模式立即切换。`queueInputActions:true` 允许输入刷新期间接受一次操作、等待最新输入回传后执行，并在真实提交期间禁用动作；未声明时保持旧页面交互约定。`formCache:{preferenceKey,fields:[字段名]}` 将白名单字段即时写入模块自己的 UI 偏好，越过输入防抖与页面关闭；后续页面工作流等待已有缓存写入完成。模块负责读取、恢复和创建成功后的清理，宿主保留现有容量与权限限制，失败显示可重试提示。`footerMessage` 可声明通知节点，固定显示在底栏上方并通过无障碍实时播报，不改变 `planReview` 的原生确认结构。模块负责页面身份、方向、文案和业务规则；宿主负责有界视口、旧页退出、交互隔离、表单回写与尺寸动画。使用新配置需更新 APK 并声明 `hostApi:"^1.43.0"`。

宿主 API `^1.42.0` 新增 `listTile.trailingAction:{icon,label,event,disabled?,tonal?}`，用于行内独立的添加、修改或移除按钮；`label` 为必填的无障碍名称，按钮事件不触发行本身的 `event`，页面执行中与行禁用时一同禁用。与 `trailing` 状态文字可并用，窄屏和大字号下保留可操作区域。共享图标新增 `location`、`hourglass`（别名 `duration`）、`lock`、`description`（别名 `notes`）、`repeat`、`priority`（别名 `flag`）。使用这些新能力须更新 APK 并声明 `hostApi:'^1.42.0'`。
根节点 `scrollKey` 为子页面分别保留滚动位置，详情／面板顶栏支持标准 `header.actions`。
草稿跨子页面同步使用 `replaceForms`；`clearForms` 用于真正清空，而非重新填入草稿。
完整任务新建流程见 [任务新建与持续规划](../design/TASK_CREATION.md)。

API 1.6 增加 `ui.component(ref, options)` 纯构造函数，返回 `{type:'component',ref,...options}` 节点。options 支持稳定 key、props、slots 和 events；events 把公共事件端口映射到原业务事件，例如 `events:{press:{type:'save'}}`。`await ui.catalog()` 返回当前可用公共契约目录，包含 ref、propsSchema、requiredSlots 和 events。仅展示目录不授予跨模块权限。未知独有组件应声明提供者依赖；系统公共组件不依赖特定风格包。

页面也可使用 `ui.page.list@1`、form、settings、detail、timeGrid 模板，传入契约要求的内容槽位。宿主兼容旧节点，输入控制器、焦点、业务事件和滚动由宿主保持。Flutter 页面使用 `UiPackScope(moduleId: ...)` 与 `UiComponent`；预览传入显式 previewPacks／previewSelection，默认恢复与审核使用 defaultOnly。详见公共 UI 文档。

handler 接收 `{state,context,event,formValues}`，返回 `{state,tree,header?,queryResult?,clearForms?,replaceForms?}`。组件包括 column、row、card、text、richText、source、input、sourceEditor、button、checkbox、switch、select、slider、progress、spinner、list、tabs、divider、timeGrid。column 根节点可带 footer 固定输入栏。组件嵌套最多 32 层。

API `^1.31.0` 增加通用紧凑对话呈现：根节点 `compact:true` 采用16px水平、8px顶端内边距，页内卡片内边距8px，列表使用14px正文、12px辅助文字和紧凑行距；`header` 子节点固定在滚动区上方。`pageHeader` 使用 `title/subtitle/actions:[{label,icon,event}]`，采用主题标题和辅助字号；`chatMessage` 使用 `text/role/label`，`role:'user'` 为右侧淡色消息，其余为左侧回复，正文可选择复制。`messageComposer` 使用 `key/text/event/interrupt`，复用页面表单控制器和草稿修订保护；请求中按钮执行声明的中断处理器，输入保持可编辑。作为根 `footer` 时自行提供一层浮动表面。根 `followEnd` 是消息变化令牌：初次或距底部不足80px时跟随末尾，用户向上阅读时保留位置。上述布局均沿用宿主主题、系统字号缩放和公共原生 UI 契约，不绑定业务模块身份。

值可以使用 `{bind:["state","selected",0,"name"]}` 的类型化路径，根支持 state/context/queryResult/formValues/event。异步迟到结果不能覆盖新上下文；清空和替换表单只作用于提交后没有被用户继续编辑的值。页面切换、面板最小化保留短期草稿。

`timeGrid` 输入 columns、rows、blocks。每块 column 引用列的 id，行范围为 start/end，包含 start 不包含 end，可带 title、subtitle、color、event。同一时段重叠块分栏显示。日期、实例合并和课程内容由模块计算。

API 1.1 的 `toolbar` 使用 title/event 显示居中可点击标题，leading/trailing/actions 提供 `{icon,label,event,disabled?}` 操作，图标支持 swap、chevron_left、chevron_right、today、settings。`timeGrid` 的列和行可分别使用 title/subtitle/highlight；corner 指定左上角文字，options 支持 rowHeight、headerHeight、labelWidth、minColumnWidth、fillWidth。fillWidth 为 true 时按可用宽度排布列，日期头与内容横向同步滚动，左侧行标签固定。根 column 的 `fillHeight:true` 使最后一个组件填满视口；`edgeToEdge:true`、`spacing:0` 用于连续网格布局。普通页面仍使用原有外边距与滚动方式。

当前客户端增加 `timeGrid.options.fitColumns: true`：所有日期列均分扣除行标签栏后的可用宽度，忽略最小列宽，确保完整表格不超出屏幕。省略此选项继续使用原有按最小列宽横向滚动的行为。课表 1.6.3 使用此选项，在显示设置中控制五天或七天；需要包含该控件更新的客户端。

contributions 通过宿主公开槽位提供入口；kind 为 content 时内嵌声明式内容，其他贡献默认显示面板启动入口。页面可以声明 entry 或 entries，使多个稳定入口指向同一页面；context.pageId 由宿主注入。页面可公开 slots，由已有布局设置挂载其他模块入口。入口模块/页面 ID 和窄/宽布局配置持续保留。

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


## API 1.46 的规划缩放与详情

`plannerBoard.options.pinchZoom` 可声明 `{event, min: .75, max: 3}` 开启双指纵向缩放，默认关闭。宿主实时以双指中心保持时间锚点，结束发出声明事件及 `pixelsPerMinute`；模块保存偏好，并回传 `options.pixelsPerMinute`。单指继续滚动，缩放不修改任何任务。菜单缩放仍可使用。宿主 API 范围必须声明 `^1.46.0`。

`blocks` 可声明 `showLocation`、`showTeacher`（默认 true）控制卡片辅助文字；`selectionDetails: [{label, value}]` 为选中后的通用详情行，缺失/空值不显示。`showSelectionSource`、`showSelectionGaps` 默认 true，可隐藏选中详情的来源、空闲时段。字段选择、文案和持久化由模块负责，标题、时间及操作不受影响。

规划看板拖动和端点调整统一5分钟增量，长按停留与横移不改变精度。手工输入的非整5分钟起点保留偏移；手动编辑仍可指定任意分钟。


## API 1.47 的规划拖动意图范围

`plannerBoard.options.allowedIntents` 可声明允许的 `move`、`swap`、`insert`、`resize` 意图。省略时保留原协议；显式列表不含某意图时不会生成该操作，未开放的悬停意图回到允许的普通移动／占用校验，无法移动的课程、固定和已完成目标不会提出交换。规划模块声明 `['move','swap','resize']`，避免触发尚未开放的插入顺延。使用此配置需声明 `hostApi:'^1.47.0'` 并更新 APK。

当日列表的课程卡片复用 `showLocation` / `showTeacher` 配置，隐藏的字段不占空行。日列表拖放按5分钟定位并报告 `snapMinutes:5`，手动编辑仍支持任意分钟。双指操作在组件禁用或配置移除时取消，不提交偏好，迟到焦点回调不再影响新视口。
