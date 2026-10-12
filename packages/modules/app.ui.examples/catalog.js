export const categories = [
  ['actions','基础操作'],['inputs','输入与表单'],['selection','选择控件'],
  ['dates','日期与时间'],['feedback','状态反馈'],['overlays','浮层与动画'],['layout','布局与高级组合'],
];
export const examples = [
  {id:'button',category:'actions',title:'按钮',description:'填充、浅色、描边、文字与禁用状态。',ref:'ui.button@1',modes:['默认','禁用']},
  {id:'confirm',category:'actions',title:'确认对话框',description:'打开原生表单弹窗，确认或取消操作。',ref:'ui.dialog'},
  {id:'entry',category:'actions',title:'普通条目',description:'信息、导航及可点击条目。',ref:'ui.listTile@1'},
  {id:'content',category:'actions',title:'文字、图标与分割线',description:'公共文字、38 个矢量图标的名称与分割线。',ref:'ui.text@1'},
  {id:'title',category:'inputs',title:'文本输入',description:'单行输入与必填校验。',ref:'ui.input@1',initial:'准备一次周末出行',modes:['默认','禁用','错误']},
  {id:'notes',category:'inputs',title:'多行备注',description:'保留输入草稿，支持多行编辑。',ref:'ui.input@1',initial:'输入、选择和提交都只用于演示。',modes:['默认','禁用']},
  {id:'number',category:'inputs',title:'数字输入',description:'数字范围、整数约束及非法文本反馈。',ref:'ui.numberInput@1',initial:'40',modes:['默认','禁用','错误']},
  {id:'search',category:'inputs',title:'搜索输入',description:'搜索图标、清除与输入防抖。',ref:'ui.input@1',initial:'',modes:['默认','禁用']},
  {id:'validation',category:'inputs',title:'表单校验',description:'验证当前输入，修正错误后重新提交。',ref:'ui.input@1',initial:''},
  {id:'priority',category:'selection',title:'单项选择',description:'从选项列表中选择一项。',ref:'ui.select@1',initial:1,modes:['默认','禁用']},
  {id:'tags',category:'selection',title:'多项选择',description:'标签选择、取消及空选状态。',ref:'ui.multiSelect@1',initial:['学习'],modes:['默认','禁用']},
  {id:'toggle',category:'selection',title:'开关',description:'切换本地演示状态。',ref:'ui.toggle@1',initial:false,modes:['默认','禁用']},
  {id:'checkbox',category:'selection',title:'复选框',description:'确认选择与取消选择。',ref:'ui.checkbox@1',initial:false,modes:['默认','禁用']},
  {id:'slider',category:'selection',title:'滑块',description:'拖动调节并观察进度。',ref:'ui.slider@1',initial:.4,modes:['默认','禁用']},
  {id:'date',category:'dates',title:'日期选择器',description:'日历、手动输入、清除及日期边界。',ref:'ui.dateInput@1',initial:null,modes:['默认','已选','禁用','错误']},
  {id:'time',category:'dates',title:'时间选择器',description:'原生 24 小时时间选择器。',ref:'ui.timeInput@1',initial:null,selected:'09:30',modes:['默认','已选','禁用','错误']},
  {id:'datetime',category:'dates',title:'日期时间选择器',description:'日期与时间全部确认后再更新。',ref:'ui.dateTimeInput@1',initial:null,modes:['默认','已选','禁用','错误']},
  {id:'range',category:'dates',title:'起止日期',description:'分别选择开始日期与结束日期，组成完整区间。',ref:'ui.dateRangeInput@1',initial:null,modes:['默认','已选','禁用','错误']},
  {id:'status',category:'feedback',title:'空状态',description:'空内容提示及添加示例后的恢复。',ref:'ui.empty@1',initial:false},
  {id:'loading',category:'feedback',title:'加载动画',description:'启动与停止原生循环加载动画。',ref:'ui.loading@1',initial:false},
  {id:'progress',category:'feedback',title:'进度指示',description:'确定进度与不确定进度动画。',ref:'ui.progress@1',initial:.4},
  {id:'error',category:'feedback',title:'错误提示与重试',description:'真实错误组件及重试恢复操作。',ref:'ui.error@1',initial:true},
  {id:'notification',category:'feedback',title:'消息提示',description:'短暂消息、成功与错误反馈。',ref:'ui.notify'},
  {id:'panel',category:'overlays',title:'操作面板',description:'手机底部面板与宽屏侧边详情。',ref:'ui.panel'},
  {id:'floating',category:'overlays',title:'悬浮窗',description:'在当前页面上方显示可关闭面板。',ref:'floatingPanel'},
  {id:'animation',category:'overlays',title:'过渡动画',description:'淡入、缩放、滑动与重播。',ref:'transition',initial:'fade'},
  {id:'tasks',category:'layout',title:'任务列表',description:'完成、筛选与进度，仅操作模拟任务。',ref:'ui.taskItem@1'},
  {id:'card',category:'layout',title:'内容卡片',description:'标题、说明、控件及操作的组合。',ref:'ui.card@1'},
  {id:'list',category:'layout',title:'列表',description:'添加或移除本地示例条目。',ref:'ui.list@1',initial:3},
  {id:'tabs',category:'layout',title:'页签',description:'切换内容与保留选中状态。',ref:'tabs',initial:0},
  {id:'grid',category:'layout',title:'响应式网格',description:'按可用空间与文字大小排列卡片。',ref:'grid'},
  {id:'disclosure',category:'layout',title:'折叠内容',description:'展开详细内容，再收起说明。',ref:'disclosure'},
  {id:'timeGrid',category:'layout',title:'时间网格',description:'日期、节次、课程块及点击事件。',ref:'ui.timeGrid@1'},
  {id:'dailyOverview',category:'dates',title:'每日概览',description:'真实日期与被动日期条，标记当天。',ref:'ui.dayOverview@1'},
  {id:'dailyHeader',category:'layout',title:'分区标题',description:'标题、数量与轻量操作入口。',ref:'ui.sectionHeader@1'},
  {id:'dailyAgenda',category:'layout',title:'日程条目',description:'左侧时间与柔和内容块，点击触发本地反馈。',ref:'ui.agendaItem@1'},
  {id:'dailyTask',category:'layout',title:'待办条目',description:'勾选完成、点击正文及折叠详情。',ref:'ui.taskItem@1',initial:false},
  {id:'composition',category:'layout',title:'页面槽位与跨模块嵌套',description:'公开页签、纵向内容及局部位置。',ref:'ui.page.list@1'},
];
export const tasks=[['plan','规划周末出行','计划今天 · 高优先级'],['read','阅读一章新书','学习 · 普通优先级'],['done','整理桌面','日常整理 · 普通优先级']];
export const formKey=id=>'demo.'+id;
export const initialValue=item=>item.initial??null;
export const demoPage=id=>'app.ui.examples.demo.'+id;
export const pinnedKey='gallery.pinned';
