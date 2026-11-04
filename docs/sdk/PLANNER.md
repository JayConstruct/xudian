# 规划看板与时间轴

[SDK 入口与兼容要求](../MODULE_SDK.md)。各能力的最低宿主 API 在对应小节说明；旧调用的回退与权限边界继续适用。

## 规划模块 1.12：优先时间点

批量创建及系列编辑的 `rules` 接受可选 `preferredTime: 'HH:mm'`；传 `null` 可清除，归一化存储时省略空字段。它必须位于 `timeWindow` 内，且开始后能完整容纳 `estimatedMinutes`。每个候选日期先尝试该精确分钟，再按离该点最近的顺序尝试原5分钟候选，同距取较早时间；未设置保持原算法。日期排序、重复间隔、实际可用时段、冲突及缓冲继续生效；手动指定和锁定位置优先，不移动已有实例。无需新增宿主组件，仍要求 API `^1.45.0`。

## 规划模块 1.11：批量任务管理

`app.planner.batches` 为完整子路由，列表、详情、规则预览及嵌入新建表单均由模块声明。使用宿主 API `^1.45.0` 的通用卡片、图标、徽标、搜索、筛选页签及固定底栏；改变这些宿主组件须更新 APK。

| 服务（major 1） | 输入与行为 |
| --- | --- |
| `planner.series.list` | 可选 `search`、`status:all/active/paused/ended`；返回真实系列、状态计数及下次任务，不按标题归组 |
| `planner.series.get` | `id`；返回系列摘要、`revision`、规则、生成实例、真实完成／待执行／取消数量及补齐原因 |
| `planner.series.status` | `id,status,expectedRevision,operationKey`；暂停／恢复／结束，保留所有已生成任务；已结束不可恢复 |
| `planner.series.update.preview` | `id,changes,expectedRevision`；校验规则并返回变更字段，`affectedExisting:0` |
| `planner.series.update.apply` | `operationKey,preview`；复验预览后保存，仅对后续生成任务生效 |
| `planner.series.retry.preview` | `id`；预览单个活动系列的补齐结果及失败原因 |
| `planner.series.retry.apply` | `operationKey,preview`；重新校验依据后补齐，保留既有实例 |
| `planner.series.tasks.cancel` | `id,taskIds,expectedTasks,operationKey`；只取消属于本系列的未完成任务，`expectedTasks` 映射任务 ID 到 `updatedAt` |

状态、规则、补齐及取消命令沿用 `services.prepare` → `ui.review` → `services.commit`。`revision` 是查询返回的完整不透明版本依据，调用方不得自行构造；操作键写持久回执，防止重复提交。批量取消记录可撤销历史，恢复任务前检查新增的任务、课程和手动占用，避免重新激活冲突时段。

### API 1.24 规划交互原型

`ui.panel(pageId, context, {adaptive:true, wide:'center'})` 在手机仍用底部面板，在宽屏使用居中弹窗；未传 `wide` 时保留侧边面板。面板保存后可通过 `ui.navigate` 返回工作区并关闭面板。

新增原生树类型 `plannerBoard`。宿主只负责显示和发出拖动意图，合法性、来源权限、时区解析、变更审核与持久化由模块服务负责。声明 `hostApi: '^1.24.0'`。

- `days: [{date, label}]`；`candidates` 与 `blocks` 为任务块数组。每项可含 `id,title,start,end,durationMinutes,deadlineSummary,overdue,fixed,readOnly,sourceLabel,event,moveEvent,selected,selectEvent`。
- `start/end` 使用同一显示时区的无偏移本地 ISO 文本。脚本负责 `clock.toLocal` / `clock.toUtc` 转换并拒绝夏令时歧义，不能把它们直接当 UTC 写回。
- `blocks` 可附带真实来源提供的 `location` 与 `teacher` 文本；空间足够时地点优先、教师其次，未提供时省略，不从任意任务描述推断地点。`schedule.query.busy@1` 可选返回这两个字段，来自本次课程实例的地点和教师（包含调课覆盖），不改变只读来源及时间语义。
- 候选选择事件保留 `selectEvent.id` 并附加布尔 `value`。移动事件包含 `id,start,end,intent,targetId?,snapMinutes`，`intent` 可为 `move/swap/insert`，并不代表业务校验已通过。
- `options` 支持 `minColumnWidth,startMinute,endMinute,pixelsPerMinute,initialMinute,candidateLabel`；每日显示区间仅影响渲染。`previewBlocks/previewLabel` 可展示脚本计算的变更预览。

早期 app.planner 1.1.0 使用此原型：快速添加、任务详情、移动与交换及整体撤销；插入顺延和高级生成器仍待后续实施，参见 [第一阶段记录](../verification/PLANNER_UX_STAGE1.md)。


### API 1.25 规划拖动预览与时长调整

`plannerBoard.previewQuery` 声明 `{ref: ServiceRef, input: {...}}`。宿主以当前页面模块身份调用只读 query，并把当前拖动事件作为 `proposal` 合并到 input；不能指定 command 绕过审核。权限、输入输出 Schema 和模块生命周期仍由宿主校验。声明此能力的模块要求 `hostApi: '^1.25.0'`。

宿主API `^1.28.0` 的 dashboard 看板会向当前工作区报告拖动状态，宿主仅将手机底栏淡出并停止其命中与语义，页面尺寸和底部避让值保持稳定；切页、取消与销毁自动清理，旧页面不能影响当前底栏。首页根节点可设置 `underlapChrome: true`，时间表绘制延伸到底栏下，宿主传入的底部避让仍用于选中面板、缩放操作和滚动末尾。自 API 1.46 起，看板拖动统一5分钟增量，横向只换日，停留与小幅横移不再进入1分钟精调；手动编辑仍可填写任意分钟。手指附近显示任务、日期起止和5分钟提示，并限制在屏幕安全区域。正常块与选中块不改变真实几何，调整时长手柄仅在选中后出现。

宿主API `^1.29.0` 的 `plannerBoard` 可声明顶层 `quickAdjustment: {taskModuleId, applyServiceId, undoServiceId}`；两个服务必须属于当前页面模块、major为1，任务来源仍须具备已有服务权限。此声明仅显示原生“快速调整”按钮，脚本不能设置开启状态或声明免审核。用户点亮按钮后，真实 `move`／`resize` 手势可对同一落点、单一任务的时间字段及配套历史写集授权一次；来源为通用 `tasks` 集合，配套 `batches`／`receipts`／`occurrences` 使用当前规划事务契约。冻结写集、服务参数、任务快照与时区瞬间均须一致，交换、插入、超截止及不匹配计划回到原确认。成功后提供8秒“撤销”，只恢复该次快照；后续编辑或完成仍阻止撤销。现有 `ui.review(planId, confirmation)` 和 `services.commit(planId)` 不增加脚本免审核参数。

原生页面自行维护快速调整的保存中显示，模块不需要传临时假任务：松手后目标位置显示一份任务，原候选／原安排临时隐藏，失败时恢复。保存不改变表格尺寸，用户可继续滚动。成功提示从宿主实际提交回执和冻结任务快照生成，最多两行展示具体任务与新时间，连续成功替换提示、撤销绑定最新操作；较早操作仍可在模块历史中处理。此原生显示优化不改变上述脚本契约与模块版本要求。

- 候选位置改变后停留180毫秒发起查询；只采用当前拖动中最新请求的结果。查询结果可包含 `previewBlocks, previewLabel, conflicts, valid, overdue`。旧结果、取消后和页面切换后的结果不继续显示。
- `previewIdentity` 是调用方提供的稳定视图版本，改变时取消当前拖动。当前页面忙碌、上下文失效或离开页面时停止拖动、滚动和预览。宿主还校验查询返回前的数据版本与页面实例。
- `intent` 增加 `resize`：保留原开始，移动末端，仍只发一次完整起止事件。固定／只读块没有末端手柄。边缘横纵自动滚动与手指速度分离；退出、取消或销毁时停止。
- 交换在本地先显示保留各自时长的双位置几何预览，随后可由服务校验结果替换。预览只是提示，最终提交仍须重新校验，不能根据 `valid` 客户端标志直接写入。

app.planner 1.2.0 用 `planner.operation.inspect` 提供轻量只读结果；使用 task 1.5.1 的单调编辑时间戳与轻量版本令牌阻止旧草稿覆盖。图形拖动仍走既有审核流程。详情见 [第二阶段记录](../verification/PLANNER_UX_STAGE2.md)。


### 规划模块1.3：候选分页与移动时长

`planner.board.get` 增加 `candidateOffset`（默认0）、`candidateLimit`（默认100，范围1–200）、`onlyDeadline`（默认false）。输出 `candidateTotal/candidateOffset/candidateLimit/hasMoreCandidates`；只对待安排候选先过滤、稳定排序、再分页，`scheduled/busy` 不受影响。候选的选择标识跨页保留，最终排程服务会再次验证所有选中标识。只传回当前页候选与显示范围内已安排任务的轻量版本依据；服务内部候选构建仍会扫描任务和规则。

`planner.operation.preview` 的 `move` 可传 `preserveDuration:true`：已安排任务按原UTC起止的实际间隔计算新结束，未安排任务使用预计时长。图形拖动与 `operation.inspect` 的移动默认启用；详情明确编辑起止时传false。这样跨夏令时切换仍保留实际耗时；新开始时刻存在歧义时依然拒绝，不自动选择时区分支。`resize` 保持其独立语义，只改结束。

看板原生组件现在缓存按日局部碰撞组的几何索引，按横纵可见窗口及缓冲区构建任务块；已开始手势的源控件保留到释放，避免滚动时销毁。密集组只聚合本组，选择清单使用按需构建；业务校验仍读取完整占用，不能因任务未渲染而忽略冲突。

撤销在原有快照校验之外，先验证恢复的起止位置是否与新任务、课程或手动占用冲突；失败时整体不写入。仅撤销描述、删除新建任务等不会新增占用的变更不要求排程检查。详见 [第三阶段记录](../verification/PLANNER_UX_STAGE3.md)。

### API 1.35 连续日期与紧凑规划界面

使用以下能力的模块声明 `hostApi: '^1.35.0'`。`plannerBoard.options.continuousDates: true` 启用连续日期布局：`days` 是附近日期的数据窗口，`visibleDays` 是同时显示的列数（1／3／5／7），两者不是业务排程范围。`initialDate` 指定视口最左日期，主动跳转时递增 `scrollRequest`；普通数据刷新保留当前绝对日期、列内偏移及纵向浏览时刻。

`viewportEvent` 提供页面事件模板。横向滚动结束后，宿主追加 `{startDate:'YYYY-MM-DD',visibleDays:3}`；模块可读取新的附近窗口，并保存界面偏好。窗口改变不能被当作用户主动跳转。日期与几何仍使用同一规划时区；`today` 是该时区的自然日，`now` 是由 `clock.toLocal` 转换的无偏移本地 ISO 时刻，用于今天列的当前时刻线。

该模式将日期选择、待安排任务条及单行星期日期头组合为紧凑界面；日期栏的 `rangeEvent` 打开日期选择，今天不在视口时显示 `todayEvent` 的返回入口。待安排默认横向一行，展开为覆盖表格的浮层，不改变网格原点，拖动时隐藏并于手势结束后收起。现有 `moveEvent`、预览、确认、快速调整及撤销协议不变。

页面顶栏可声明 `{compact:true,layout:'plannerTimeline'}` 请求20字号的紧凑标题和44逻辑像素操作区域。存在合法 `quickAdjustment` 节点时，宿主贡献“调整”开关；开关状态只属于当前页面宿主，不经脚本命令设置，也不扩大快速调整的授权写集。没有活动顶栏的独立页面保留原生操作入口；菜单及失活租约保护不变。其他顶栏布局不受影响。

### API 1.36 动态日期窗口

`plannerBoard.options.timeline` 可声明 `{rangeContextKey:'timelineRange',preferenceKey:'board.viewport',stateKeys:{startDate:'startDate',visibleDays:'days'}}`。模块需声明 `hostApi:'^1.36.0'`。启用后，视口移动由宿主直接更新模块页面状态中的指定字段，并延迟合并保存 `{startDate,days,selectedDate}` 界面偏好；不会派发旧的 `viewportEvent`、重新生成整页或修改业务记录。离开页面及业务操作前保存最新位置。

原生表格循环复用63天的物理日期范围，仅构建附近的日期表头及任务块，最多缓存84天数据。普通浏览命中缓存不调用模块页面；接近缓存边缘时，以同一模块身份只读调用当前页面处理器，输入 `event:null`，在 `context[rangeContextKey]` 中提供 `{startDate:'YYYY-MM-DD',days:21}`。模块应返回该范围的正常 `plannerBoard` 节点（相同 `key`），不得移动视口、递增 `scrollRequest`、写偏好或执行业务命令。加载日期范围与当前可见日期、自动安排范围相互独立。

后台回复只合并日期与任务块，不替换页面状态、顶栏或滚动控制器；模块实例、页面上下文或业务数据变化后丢弃过期回复。没有缓存的日期列显示局部加载或重试入口，不禁用其他日期的浏览。循环窗口在滚动停止后按绝对日期和列内偏移重定位，纵向阅读位置不变。缓存不作为拖放授权，实际提交仍使用原有权限、版本校验、审核与撤销协议。

未声明 `timeline` 的旧模块保留 API 1.35 的事件式加载路径。

## 区块动作、完成与外观

宿主 API `^1.38.0` 的 `plannerBoard` 区块和候选项支持 `actions:[{label,icon,event,command?}]`，最多三个动作，在选中任务后由原生面板显示；模块负责动作含义和命令输入。区块可声明 `completed:true`，宿主显示已完成样式并禁用拖动，仍可选中查看及执行重新打开等动作。

宿主 API `^1.40.0` 支持规划区块的可选配置 `statusIndicator:'edgeToCorner'`，与已有 `completed` 布尔值配合：未完成时显示贴右边缘的 3dp 彩色竖线，完成时显示 16dp 深色白勾角标；窄列竖线随既有边距缩至 2dp，紧凑区块的角标按可用留白缩小并避让时间，空间不足时保持贴边。宿主以同一形状约 280ms 收拢变形，重新打开时反向过渡，减少动态效果时立即切换；装饰不增加文字 padding、信息行或标题图标列。模块选择是否声明，省略时保留原显示；该字段只影响展示，不修改状态或命令授权。使用模块须声明 `hostApi:'^1.40.0'`，新增原生绘制能力需更新 APK。

宿主 API `^1.41.0` 支持规划区块的 `appearance: {borderStyle:'dashed', titleDecoration:'lineThrough', cornerIcon:'slash', badgeText:'已取消'}`。各属性独立可选，`cornerIcon` 也接受 `'check'`；这些字段不推断任务状态，不更改原时段、标题内容或交互授权。虚线轮廓、角标及标签不改变文字布局；角标避让时间，状态标签空间不足时收起，状态仍进入无障碍说明。`selectionNote` 为选中面板增加模块提供的说明；`selectionLayout:'inlineActions'` 在仅有一个 `actions` 操作时，将该操作与“查看详情”并排显示，多操作保留原布局。`occupiesTime:false` 保留区块显示，同时在本地空闲提示与日列表重叠预览中释放时段，最终安排仍由服务验证。需要更新 APK 并声明 `hostApi:'^1.41.0'`。
