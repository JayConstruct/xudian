# 动画与手势

| 想实现的效果 | 配置 | 最低宿主 API |
| --- | --- | --- |
| 局部出现或隐藏 | [`transition.visible`](#显示隐藏与折叠) | 1.12 |
| 收起表单并释放布局空间 | [`transition.collapse`](#api-119-的可折叠过渡) | 1.19 |
| 提交后高亮新增行、收拢删除行 | [`keyedList.feedbackKey`](../sdk/PAGES.md#api-120-的稳定列表与提交反馈) | 1.20 |
| 局部页面切换或返回 | [`transition` 的 `page` 效果](#页面切换) | 1.32，指定方向需 1.33 |
| 整页连同固定底栏一起切换 | [根页面 `pageTransition`](#页面切换) | 1.43 |
| 状态变化时平移、缩放或淡入淡出 | [`motion`](#属性动画) | 1.50 |
| 按住按钮时缩小 | [`button.feedback`](#按压反馈) | 1.50 |
| 横滑列表项以显示操作 | [`swipeActions`](#滑动操作) | 1.50 |

模块声明目标、时长和事件，Flutter 宿主处理每一帧与指针移动。看板的跨日拖动、端点调整和双指缩放带有时间与占用规则，见[规划看板 SDK](../sdk/PLANNER.md)。

## 显示、隐藏与折叠

`transition` 节点包装一个 `child`，effect 为 `fade`（默认）、`scale`、`slide` 或 `page`。`slide` 为向上滑入，`page`（API `^1.32.0`）使用与 App 普通页面一致的横向小幅滑入和淡入（水平位移为宽度的 4%，曲线为 easeOutCubic），适合模块内的页面切换。visible 默认 `true`，切换时播放进出动画；更新字符串／数字 `replayKey` 或更换节点 key 重播。duration 为 100–2000 毫秒整数，`page` 默认 300，其余效果默认 350。宿主保留原内容布局和控件状态，隐藏内容不响应输入且不进入无障碍树；系统“减少动画”直接呈现最终状态。

```js
{type: 'transition', key: 'demo', effect: 'slide', visible: true,
 replayKey: state.replay || 0, duration: 350,
 child: {type: 'card', children: [{type: 'text', text: '动画内容'}]}}
```

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

## 页面切换

API `^1.33.0` 的 `page` 效果支持 `direction:"forward"|"back"`：切换 `replayKey` 时，前进让目标页横移淡入，返回让当前页按 App 路由的反向时间线横移淡出并露出目标页。同一页面的查询或表单更新不重播；旧页在切换期间不可操作或获得焦点，结束后释放。系统减少动画时立即切换。

宿主路由（包括设置覆盖层和模块详情）使用 300 毫秒淡入与 4% 横向轻移；减少动画时以零时长完成，不会先停留一帧再切换。

根页面从 API 1.43 起可声明 `pageTransition: {direction:"forward", duration:260}`。前进使用 `forward`，返回使用 `back`。时长范围为 100–2000ms，默认 260ms。宿主通过 `scrollKey`（回退到根 `key`）识别页面，同时协调滚动内容和固定底栏的过渡。同页输入保持当前画面，减少动画时立即切换。

API 1.52 的根页面过渡还支持同级标签方向 `next` 和 `previous`。模块通过稳定的 `scrollKey` 保留各标签的滚动位置，分段栏放在根 `header` 中。内容交叉淡化并沿阅读顺序轻移 10 个逻辑像素。项目页沿用 `variant: "sliding"`。宿主设置中的分段栏、脚本 `segmented` 和声明了 `selectedIndex` 的 `tabs` 共用同一滑块。选中底色用 220 毫秒移动，文字颜色与字重跟随滑块位置变化。换行时逐项标示当前项。

脚本列布局中，切换时从选择栏下方到下一个同级选择栏之间的内容沿相应方向轻移并交叉淡化。输入框和滚动列表在过渡中维持当前实例，原画面仅用于绘制。减少动画时直接显示新内容。

## API 1.50 的属性动画与滑动操作

声明 `hostApi:'^1.50.0'`。新能力需要包含该实现的 APK；兼容宿主上修改下述参数或事件仅需递增模块版本并更新模块。在“UI 示例”中可体验“属性动画与按压反馈”和“滑动操作”。[节点 Schema](../../packages/schemas/ui-motion-v1.schema.json) · [示例源码](../../packages/modules/app.ui.examples/examples.js)

### 属性动画

`motion` 必须有稳定 `key`、单个 `child` 和非空 `target`。目标支持 `opacity`（0～1，默认1）、`translateX/Y`（±4096dp，默认0）、`scale`（0.1～4，默认1）。各目标数值支持现有路径绑定；首次挂载直接显示目标，同身份目标变化从当前位置继续。`timing:{duration:180,curve:'easeOut'}` 使用0～2000整数毫秒和 `linear/easeIn/easeOut/easeInOut`；省略参数使用默认值，显式 null、未知字段或越界值拒绝。目标不变只改 timing 时不重播；布局占位保持原尺寸。透明度不替代可见性，隐藏交互继续使用 `transition.visible`。入场、退出及折叠沿用现有节点。

```javascript
{type:'motion',key:'selection',
 target:{scale:state.selected ? .94 : 1,translateX:state.selected ? 16 : 0},
 timing:{duration:220,curve:'easeInOut'},
 child:{type:'text',text:'预览'}}
```

### 按压反馈

`button.feedback:{pressedScale:.98,duration:100}` 为可选的按钮内部缩放，范围分别为0.9～1、0～300整数毫秒。直接按钮与 `ui.button@1` 的 `props.feedback` 均支持，保持原命中区域、点击、command、interrupt 和输入排队规则。省略时保持旧反馈；自定义 UI 包可继续使用自身样式，不强制消费反馈字段。

### 滑动操作

`swipeActions` 必须有稳定 `key`、单个 `child`、`extent`（48～240dp）和1～3个 `actions`。动作 `{label,event,icon?,disabled?}` 的 label 非空，event 为原页面事件，icon 使用已知图标；extent 至少为动作数×48。`side:'start'|'end'` 默认 end 并跟随文字方向；`openThreshold` 为0.2～0.8、默认0.4；`settle` 与 timing 相同。`enabled` 默认 true，false 禁用此节点的滑动及动作，不改变 child 自身的操作；enabled、动作 disabled、可选 revision 支持绑定。revision 为模块提供的不透明字符串／整数，变化取消旧交互。

```javascript
{type:'swipeActions',key:'item:42',extent:96,
 settle:{duration:180,curve:'easeOut'},
 actions:[{label:'编辑',icon:'edit',event:{type:'edit',id:'42'}}],
 child:{type:'card',variant:'outlined',children:[{type:'text',text:'向左滑动'}]}}
```

API 1.53 支持 `menuTrigger: "longPress"`。整行长按、键盘菜单键或 Shift+F10 可打开条目菜单。浮层复用工作区右上角菜单的遮罩、圆角，以及 180 毫秒展开和 120 毫秒收起的淡入淡出与缩放。空间不足时浮层向上展开，减少动画时直接显示或关闭。默认 `"button"` 使用行末的更多操作按钮。

只有明确无连续交互的原生内容组合启用横滑；输入、可选文字、嵌套滚动和自定义配方等未知组合保留内容并使用 `menuTrigger` 声明的菜单入口。宽度或字号导致动作放不下时同样回退。横滑不触发 JS；稳定打开后点击动作才派发一次页面事件，菜单与滑出动作共用执行锁。打开后点击内容只收起；菜单支持键盘、读屏和取消。新动作第一版不接受 command，仍走模块的普通审核流程。

所属滚动区开始滚动、第二指加入、禁用、busy、配置变化、切页、模块升级和后台失活均取消局部交互；旧菜单不能执行变更前的动作。motion 在减少动态效果或页面失活时直接到目标值。新增动效使用局部控制器及页面预算，不逐帧调用脚本；超预算时装饰直接呈现目标，业务操作仍保留。该结构不等于真机帧率保证，性能需单独采样。

## 宿主动效时长

下表是宿主与内置模块采用的时长。日期切换、内容就绪及操作反馈各有独立时序。

| 场景 | 默认时长 | 维护位置 |
| --- | --- | --- |
| 独立概览日期选中色 | 180ms | `AppMotion.dateChange` |
| 日期标题变化字段翻页 | 280ms | `AppMotion.dateTitle` |
| 独立五天栏位置续行 | 320ms | `AppMotion.dateStrip` |
| 点击日期背景波浪 | 480ms | `AppMotion.dateReveal` |
| 日期旧内容离场／最新就绪内容入场 | 120ms／180ms | `AppMotion.dateContentLeave`／`dateContentFade` |
| 脚本局部过渡／快速添加展开收起 | 350ms／220ms | 默认 `AppMotion.scriptTransition`；快速添加由 `app.views.today/main.js` 显式声明 220ms |
| 工作区切换 | 360ms | `AppMotion.workspaceTransition` |
| 底栏助手出入与胶囊尺寸联动 | 500ms | `dock_motion.dart` |
| Toast 入场／退场 | [Toast 动画与生命周期](TOAST.md#动画与生命周期) | `AppToast.enterDuration`／`exitDuration` |

新动效先判断是状态变化、内容就绪还是操作反馈，再选择现有组件与时长。快速反向或连续操作从当前进度续行，动画不承担业务提交、数据有效性或首次就绪的判断。减少动画使用 `AppMotion.duration` 或组件现有即时路径；内容仍须通过就绪门控，跳过动画不跳过数据等待。日期标题、日期条和内容过渡在高对比时使用即时路径；玻璃表面使用实色并停用模糊，不因此停用所有动画。`AppMotion.disclosure` 目前是未被调用的 220ms 常量，不能据此推断 Flutter `ExpansionTile` 的实际时长。

## 检查动效

- 连续改变目标、快速反向和切出页面时，检查是否从当前进度衔接，以及旧内容是否及时释放点击、焦点和读屏语义。[过渡回归](../../client/test/script_transition_test.dart)
- 开启减少动画后，确认控件到达最终状态，保存、取消及返回仍可操作。检查侧滑在滚动、文本输入、读屏和窄宽度下的更多操作入口。[模块动效回归](../../client/test/script_page_motion_test.dart)
- 检查日期内容交替时，等待期间的点击与数据就绪顺序，以及减少动画和高对比下的显示。[日期过渡回归](../../client/test/date_reveal_test.dart)

原生 `listTile` 可以作为 `swipeActions.child`。单击条目打开详情，横滑展开动作，点击展开动作后才执行事件。替换了列表行的自定义界面包仍可使用声明的菜单入口。

API 1.58 的长按菜单最多支持五项。普通侧滑操作仍最多三项。
