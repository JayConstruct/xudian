export const categories = [
  ['all', '全部'], ['actions', '基础操作'], ['inputs', '输入与表单'],
  ['selection', '选择控件'], ['dates', '日期与时间'], ['feedback', '状态反馈'], ['layout', '布局与组合'],
];
export const examples = [
  {id:'button', category:'actions', title:'按钮与确认', description:'体验常规、禁用按钮及确认对话框。', ref:'ui.button@1', modes:['默认','禁用']},
  {id:'panel', category:'actions', title:'操作面板', description:'手机底部面板与宽屏侧边面板。', ref:'ui.panel@1'},
  {id:'title', category:'inputs', title:'文本输入', description:'单行输入与必填校验。', ref:'ui.input@1', initial:'准备一次周末出行', modes:['默认','禁用','错误']},
  {id:'notes', category:'inputs', title:'多行备注', description:'保留输入草稿，支持多行编辑。', ref:'ui.input@1', initial:'输入、选择和提交都只用于演示。', modes:['默认','禁用']},
  {id:'number', category:'inputs', title:'数字输入', description:'输入 0 到 100 的数字，非法文本保留并提示。', ref:'ui.numberInput@1', initial:'40', modes:['默认','禁用','错误']},
  {id:'search', category:'inputs', title:'搜索输入', description:'搜索图标、清除按钮和输入防抖。', ref:'ui.input@1', initial:'', modes:['默认','禁用']},
  {id:'priority', category:'selection', title:'单项选择', description:'从优先级列表选择一项。', ref:'ui.select@1', initial:1, modes:['默认','禁用']},
  {id:'tags', category:'selection', title:'多项选择', description:'可同时选择多个标签，点击已选标签取消。', ref:'ui.multiSelect@1', initial:['学习'], modes:['默认','禁用']},
  {id:'toggle', category:'selection', title:'开关', description:'切换本地演示状态。', ref:'ui.toggle@1', initial:false, modes:['默认','禁用']},
  {id:'slider', category:'selection', title:'进度调节', description:'通过滑块选择进度并观察变化。', ref:'ui.slider@1', initial:.4, modes:['默认','禁用']},
  {id:'date', category:'dates', title:'日期选择器', description:'计划日支持日历、手动输入、清除和日期边界。', ref:'ui.dateInput@1', initial:null, selected:'2026-10-08', modes:['默认','已选','禁用','错误']},
  {id:'time', category:'dates', title:'时间选择器', description:'原生 24 小时时间选择，确认后更新。', ref:'ui.timeInput@1', initial:null, selected:'09:30', modes:['默认','已选','禁用','错误']},
  {id:'datetime', category:'dates', title:'日期时间选择器', description:'先选日期再选时间，任一步取消保留原值。', ref:'ui.dateTimeInput@1', initial:null, selected:'2026-10-08T09:30', modes:['默认','已选','禁用','错误']},
  {id:'range', category:'dates', title:'日期范围选择器', description:'选择包含起止日的区间，支持跨月及清除。', ref:'ui.dateRangeInput@1', initial:null, selected:{start:'2026-10-08',end:'2026-10-10'}, modes:['默认','已选','禁用','错误']},
  {id:'status', category:'feedback', title:'页面状态', description:'体验空状态、加载、错误和成功反馈。', ref:'ui.empty@1', initial:0},
  {id:'tasks', category:'layout', title:'任务卡片', description:'任务完成与未完成筛选，只操作模拟任务。', ref:'ui.card@1'},
  {id:'composition', category:'layout', title:'页面槽位与跨模块嵌套', description:'公开页签、纵向内容和局部位置演示。', ref:'ui.page.list@1'},
];
export const tasks = [
  ['plan','规划周末出行','计划今天 · 高优先级'],
  ['read','阅读一章新书','学习 · 普通优先级'],
  ['done','整理桌面','日常整理 · 普通优先级'],
];
export const formKey = id => 'demo.' + id;
export const initialValue = item => item.initial ?? null;
