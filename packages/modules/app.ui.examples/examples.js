import {ui} from '@xudian/sdk';
import {formKey,initialValue,tasks} from './catalog.js';
export const text=(value,style)=>({type:'text',text:value,...(style?{style}:{})});
export const button=(label,event,disabled=false,variant='tonal')=>ui.component('ui.button@1',{key:'demo.button:'+label+':'+JSON.stringify(event),props:{label,disabled,variant},events:{press:event}});
export const column=children=>({type:'column',children});
export const tile=(title,subtitle,event,icon)=>({type:'listTile',title,subtitle,...(icon?{icon}:{}),...(event?{event}:{trailing:''})});
export const group=(title,children)=>({type:'column',children:[{type:'sectionHeader',title},...children]});
const change=id=>({type:'changeDemo',id});
const iconGroups=[
  ['页面与内容',[['today','今天'],['calendar','课表与日期'],['tasks','任务'],['modules','模块'],['projects','项目'],['inbox','收件箱'],['school','学校'],['schedule','时间']]],
  ['操作与导航',[['add','添加'],['edit','编辑'],['delete','删除'],['search','搜索'],['settings','设置'],['tune','调整'],['copy','复制'],['pin','固定'],['unpin','取消固定'],['refresh','刷新'],['close','关闭'],['more','更多'],['chevronRight','向右'],['chevronLeft','向左'],['expandMore','展开'],['expandLess','收起']]],
  ['状态与工具',[['check','完成'],['info','信息'],['warning','警告'],['error','错误'],['ai','AI'],['importExport','导入导出'],['history','历史'],['link','链接'],['code','代码'],['play','播放'],['pause','暂停'],['eye','查看'],['download','下载'],['upload','上传']]],
];
export function demoValue(item,state,forms) {
  const key=formKey(item.id);
  return Object.prototype.hasOwnProperty.call(forms,key)?forms[key]:Object.prototype.hasOwnProperty.call(state.examples,item.id)?state.examples[item.id]:initialValue(item);
}
export function componentSpec(item,state,forms) {
  const value=demoValue(item,state,forms),mode=state.modes[item.id]||'默认';
  let props={label:item.title,value,disabled:mode==='禁用',clearable:true,...(mode==='错误'?{errorText:'演示错误：请检查输入值'}:{}),...(item.id==='validation'&&state.results.validation==='请输入示例标题'?{errorText:'请输入示例标题'}:{})};
  if(item.id==='notes')props={...props,multiline:true,minLines:3,maxLines:5};
  if(item.id==='number')props={...props,min:0,max:100,integer:true};
  if(item.id==='search')props={...props,inputMode:'search',helperText:'输入防抖 150ms，仅搜索本地演示'};
  if(item.id==='priority')props={...props,items:[{value:0,label:'低优先级'},{value:1,label:'普通优先级'},{value:2,label:'高优先级'}]};
  if(item.id==='tags')props={...props,items:['学习','工作','生活'].map(tag=>({value:tag,label:tag}))};
  if(item.id==='slider')props={...props,min:0,max:1,divisions:10};
  if(['date','datetime','range'].includes(item.id))props={...props,minDate:'2020-01-01',maxDate:'2035-12-31'};
  return {key:formKey(item.id),props,events:{change:change(item.id)}};
}
export function control(item,state,forms) {
  const id=item.id,value=demoValue(item,state,forms),mode=state.modes[id]||'默认',disabled=mode==='禁用';
  const component=()=>ui.component(item.ref,componentSpec(item,state,forms));
  if(['notes','number','search','priority','tags','toggle','checkbox','slider','date','time','datetime','range'].includes(id))return component();
  if(id==='title'||id==='validation')return column([component(),button('验证示例表单',{type:'validate',id},disabled,'outlined')]);
  if(id==='button')return column(['filled','tonal','outlined','text'].map(variant=>button({filled:'填充按钮',tonal:'浅色按钮',outlined:'描边按钮',text:'文字按钮'}[variant],{type:'action',id,action:variant},disabled,variant)));
  if(id==='confirm')return button('打开确认对话框',{type:'confirm',id},false,'outlined');
  if(id==='entry')return column([tile('普通信息条目','说明与内容'),tile('可点击条目','点击后在本页显示操作结果',{type:'action',id}),tile('打开日期选择演示','导航到真实独立子页面',{type:'openDemo',id:'date'})]);
  if(id==='content')return column([
    ui.component('ui.text@1',{props:{text:'公共文字组件'}}),text('标题文字','title'),text('补充说明','muted'),
    ...iconGroups.map(([title,items])=>group(title,[{type:'grid',children:items.map(([name,label])=>column([
      ui.component('ui.icon@1',{key:'demo.icon:'+name,props:{name,size:28,semanticLabel:label}}),text(label),text(name,'muted'),
    ]))}])),
    ui.component('ui.divider@1'),text('分割线下方的内容'),
  ]);
  if(id==='status')return column([value?text('已添加一条示例内容'):ui.component('ui.empty@1',{props:{title:'暂无示例内容'}}),button(value?'清空示例':'添加示例内容',{...change(id),value:!value})]);
  if(id==='loading')return column([...(value?[ui.component('ui.loading@1'),text('正在加载示例…','muted')]:[text('尚未开始加载','muted')]),button(value?'停止加载':'开始加载',{...change(id),value:!value})]);
  if(id==='progress')return column([ui.component('ui.progress@1',{props:{value:state.indeterminate?null:Number(value)}}),{type:'slider',key:formKey(id),min:0,max:1,divisions:10,value:Number(value),event:change(id)},{type:'switch',text:'不确定进度',value:!!state.indeterminate,event:{type:'value',key:'indeterminate'}}]);
  if(id==='error')return column([value?ui.component('ui.error@1',{props:{message:'示例加载失败，请重试'},events:{retry:{...change(id),value:false}}}):text('重试成功，已恢复示例内容'),button('再次显示错误',{...change(id),value:true},false,'outlined')]);
  if(id==='notification')return {type:'row',children:['info','success','error'].map(kind=>button({info:'显示消息',success:'成功提示',error:'错误提示'}[kind],{type:'notify',kind}))};
  if(id==='panel')return button('打开操作面板',{type:'panel'},false,'outlined');
  if(id==='floating')return column([text('悬浮窗在页面上方显示，不挤压下方内容。','muted'),button('显示悬浮窗',{type:'floating',visible:true}),tile('页面下方仍可操作','悬浮窗打开时也可点击此项',{type:'action',id})]);
  if(id==='animation')return column([
    {type:'transition',key:'demo-transition',effect:value||'fade',visible:state.animationVisible!==false,replayKey:state.animationReplay||0,duration:350,child:group('动画预览',[text('淡入、缩放或滑动的内容')])},
    {type:'tabs',selectedIndex:['fade','scale','slide'].indexOf(value||'fade'),items:[['fade','淡入'],['scale','缩放'],['slide','滑动']].map(([effect,label])=>({label,event:{type:'animationEffect',effect}}))},
    {type:'row',children:[button(state.animationVisible===false?'显示':'隐藏',{type:'value',key:'animationVisible',value:state.animationVisible===false}),button('重播动画',{type:'replay'},false,'outlined')]},
  ]);
  if(id==='dailyOverview') {
    const date=state.demoDate,day=new Date(date+'T00:00:00Z');
    const days=Array.from({length:5},(_,i)=>{const value=new Date(day.getTime()+(i-2)*86400000);return {date:value.toISOString().slice(0,10),label:['周日','周一','周二','周三','周四','周五','周六'][value.getUTCDay()]};});
    return ui.component(item.ref,{props:{date,selectedDate:date,summary:'每日概览演示',days}});
  }
  if(id==='dailyHeader')return ui.component(item.ref,{props:{title:'待办事项',subtitle:'本地演示，不添加业务数据',count:2,actionLabel:'添加示例',actionIcon:'add'},events:{press:{type:'action',id,action:'分区操作'}}});
  if(id==='dailyAgenda')return ui.component(item.ref,{props:{title:'课程条目演示',subtitle:'教学楼 A101 · 示例教师',startTime:'09:00',endTime:'10:30',color:'#7F9ABD',badge:'示例'},events:{press:{type:'action',id,action:'日程详情'}}});
  if(id==='dailyTask')return ui.component(item.ref,{props:{title:'整理今天的计划',subtitle:'本地演示任务',completed:!!value},events:{change:change(id),open:{type:'confirm',id}},slots:{details:{type:'disclosure',key:'daily-task-details',text:'查看补充说明',children:[text('勾选修改本地状态；点击任务正文打开演示对话框。')]}}});
  if(id==='tasks')return column([text(`共 ${tasks.length} 项，已完成 ${state.completed.length} 项`),ui.component('ui.progress@1',{props:{value:state.completed.length/tasks.length}}),{type:'checkbox',text:'只看未完成',value:state.onlyPending,event:{type:'value',key:'onlyPending'}},...tasks.filter(([key])=>!state.onlyPending||!state.completed.includes(key)).map(([key,title,subtitle])=>ui.component('ui.taskItem@1',{key:'demo-task:'+key,props:{title,subtitle,completed:state.completed.includes(key)},events:{change:{type:'done',id:key},open:{type:'action',id,action:title}}}))]);
  if(id==='card')return ui.component('ui.card@1',{slots:{content:column([text('卡片标题','heading'),text('可组合文字、控件与操作'),button('卡片操作',{type:'action',id})])}});
  if(id==='list')return column([ui.component('ui.list@1',{slots:{items:column(Array.from({length:Number(value)},(_,i)=>tile('示例条目 '+(i+1),'点击查看本地反馈',{type:'action',id,action:'第 '+(i+1)+' 项'})))}}),{type:'row',children:[button('添加条目',{...change(id),value:Math.min(10,Number(value)+1)},Number(value)>=10),button('移除条目',{...change(id),value:Math.max(0,Number(value)-1)},Number(value)<=0,'outlined')]}]);
  if(id==='tabs')return column([{type:'tabs',selectedIndex:Number(value),scrollable:true,items:['概览','详情','活动'].map((label,index)=>({label,event:{...change(id),value:index}}))},group(['概览','详情','活动'][Number(value)]+'内容',[text('切换页签后，内容与选中态同步更新。')])]);
  if(id==='grid')return {type:'grid',children:Array.from({length:4},(_,i)=>ui.component('ui.card@1',{key:'demo-grid:'+i,slots:{content:column([text('卡片 '+(i+1),'heading'),text('空间足够时排列为两列'),button('操作 '+(i+1),{type:'action',id,action:'卡片 '+(i+1)})])}}))};
  if(id==='disclosure')return {type:'disclosure',key:'demo-disclosure',text:'展开详细内容',children:[text('这里是真实可折叠的内容。'),button('折叠区内操作',{type:'action',id})]};
  if(id==='timeGrid')return {type:'timeGrid',columns:[{id:'mon',label:'周一'},{id:'tue',label:'周二'},{id:'wed',label:'周三'}],rows:['08:00','09:00','10:00','11:00'].map((time,index)=>({id:String(index),label:time})),blocks:[{id:'demo-block',column:'mon',start:0,end:2,title:'示例课程',subtitle:'点击查看反馈',color:'#486DA4',event:{type:'action',id,action:'示例课程'}}],options:{rowHeight:56,headerHeight:40,labelWidth:48,fitColumns:true,fillWidth:true}};
  if(id==='composition')return button('打开页面槽位示例',{type:'composition'},false,'outlined');
  return text('暂无示例');
}
export function callCode(item,state,forms) {
  if(['title','notes','number','search','validation','priority','tags','toggle','checkbox','slider','date','time','datetime','range'].includes(item.id))return {
    call:`ui.component('${item.ref}', ${JSON.stringify(componentSpec(item,state,forms),null,2)})`,
    handler:`if (event?.type === 'changeDemo') {\n  state.examples = {...state.examples, [event.id]: event.value};\n}\n// 提交时读取最新值，避免输入防抖期间使用旧状态\nconst value = formValues['${formKey(item.id)}'] ?? state.examples?.['${item.id}'];`,
  };
  if(item.id==='panel')return {call:"await ui.panel('app.ui.examples.local', {}, {adaptive: true});",handler:'// 用户关闭面板后返回当前演示页。'};
  if(item.id==='confirm')return {call:"const result = await ui.dialog({\n  title: '确认演示操作',\n  fields: [{key: 'name', label: '演示名称', value: '本地示例', required: true}]\n});",handler:"if (result) state.result = '已确认 ' + result.name;"};
  if(item.id==='notification')return {call:"await ui.notify({message: '演示操作已完成', kind: 'success', duration: 3000});",handler:'// kind 支持 info、success、error；仅展示消息。'};
  if(item.id==='content')return {
    call:`ui.component('ui.icon@1', {\n  key: 'demo.icon:today',\n  props: {name: 'today', size: 28, semanticLabel: '今天'}\n})\n\n// 完整内容组件树\n${JSON.stringify(control(item,state,forms),null,2)}`,
    handler:'// name 使用图标下方的实际名称，size 指定尺寸，semanticLabel 提供无障碍说明。\n// ui.icon@1 默认使用 AppSymbolIcon 矢量图标；选定的 UI 包可覆盖同一公共组件。\n// 将组件放入 render 返回的 tree.children。',
  };
  if(item.id==='floating')return {call:`tree.floatingPanel = ${JSON.stringify({title:'悬浮窗示例',closeLabel:'关闭悬浮窗',closeEvent:{type:'floating',visible:false},top:16,child:column([text('此内容位于当前页面上方'),button('完成演示',{type:'floating',visible:false})])},null,2)};`,handler:"if (event?.type === 'floating') state.floating = event.visible;\n// state.floating 为 false 时省略 tree.floatingPanel。"};
  if(item.id==='composition')return {call:"await ui.navigate('app.ui.examples.composition');",handler:'// 页面声明 public slots，贡献入口声明 targetPageId / slotId / content。'};
  const handlers={
    animation:"if (event?.type === 'replay') { state.animationReplay = (state.animationReplay || 0) + 1; state.animationVisible = true; }\nif (event?.type === 'value') state[event.key] = event.value;\nif (event?.type === 'animationEffect' && ['fade', 'scale', 'slide'].includes(event.effect)) state.examples.animation = event.effect;\n// visible 播放进出动画，replayKey 改变时重播；减少动画设置即时完成。",
    error:"if (event?.type === 'changeDemo') state.examples.error = event.value;\n// retry 事件将 value 改为 false，再返回正常内容。",
    tasks:"if (event?.type === 'done') {\n  state.completed = event.value ? [...new Set([...state.completed, event.id])] : state.completed.filter(id => id !== event.id);\n}\nif (event?.type === 'value') state[event.key] = event.value;\nif (event?.type === 'action') state.results.tasks = '已执行：' + event.action;",
    dailyTask:"if (event?.type === 'changeDemo') state.examples.dailyTask = event.value;\nif (event?.type === 'confirm') { const result = await ui.dialog({title: '确认演示操作', fields: [{key: 'name', label: '演示名称', value: '本地示例', required: true}]}); state.results.dailyTask = result ? '已确认 ' + result.name : '已取消演示'; }",
    content:'// 将这些公共组件放入 render 返回的 tree.children。',
    entry:"if (event?.type === 'action') state.results.entry = '已执行本地示例操作';\nif (event?.type === 'openDemo') await ui.navigate('app.ui.examples.demo.' + event.id);",
  };
  return {call:JSON.stringify(control(item,state,forms),null,2),handler:handlers[item.id]||`if (event?.type === 'changeDemo') state.examples[event.id] = event.value;\nif (event?.type === 'value') state[event.key] = event.value;\nif (event?.type === 'action') state.results[event.id] = '已执行：' + (event.action || '本地示例操作');\n// 将 state 返回，并根据它重新生成上述 ${item.ref} 示例。`};
}
