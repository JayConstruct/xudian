import {services,ui,files,browser} from '@xudian/sdk';
import {convert,suggestedMonday} from './convert.js';
import {captureScript} from './bridge.js';
import zhengfang from './zhengfang.js';
export {convert};
export {compileBridge} from './bridge.js';
const ref=serviceId=>({moduleId:'app.schedule',serviceId,majorVersion:1});
const text=value=>({type:'text',text:value});
const button=(label,type)=>({type:'button',text:label,event:{type}});
const field=(key,label,value,type='text',extra={})=>({key,label,value,type,...extra});
async function configure(payload,previous={}) {
  const {timetables}=await services.query(ref('schedule.query.timetables'),{});
  const target=await ui.dialog({title:'选择导入目标',fields:[field('target','课表','new','select',{required:true,options:[{value:'new',label:'新建课表'},...timetables.map(t=>({value:t.id,label:t.name}))]})]});
  if (!target) return null;
  const base=timetables.find(t=>t.id===target.target),config=payload.config||{};
  const settings=await ui.dialog({title:'确认来源与学期配置',fields:[
    field('name','课表名称',base?.name||previous.name||'教务导入课表','text',{required:true,maxLength:120}),
    field('scope','来源标识（学校/账号别名/学年学期）',previous.scope||'','text',{required:true,maxLength:500}),
    field('firstMonday','第一教学周周一',config.semesterStartDate?suggestedMonday(config):(base?.firstMonday||previous.firstMonday||''),'date',{required:true}),
    field('totalWeeks','学期周数',config.semesterTotalWeeks??base?.totalWeeks??20,'number',{integer:true,min:1,max:100}),
    field('timezone','课表时区',base?.timezone||'Asia/Shanghai','text',{required:true}),
    field('displayWeekStart','每周起始日',String(config.firstDayOfWeek??base?.displayWeekStart??1),'select',{required:true,options:[{value:'1',label:'周一'},{value:'7',label:'周日'}]}),
    ...(base?[field('mode','导入方式','merge','select',{required:true,options:[{value:'merge',label:'合并课程，保留其他安排'},{value:'replaceSource',label:'替换该来源的课程'}]})]:[]),
    field('complete','确认来源包含本学期全部课程',false,'boolean'),
  ]});
  if (!settings) return null;
  const options={...settings,totalWeeks:Number(settings.totalWeeks),displayWeekStart:Number(settings.displayWeekStart),...(base?{timeSlots:base.periods}:{})};
  return {options,input:{draft:convert({payload,options}),mode:base?settings.mode:'new',...(base?{targetTimetableId:base.id}:{}),choices:{}}};
}
async function prepare(state) {
  const plan=await services.prepare(ref('schedule.import.prepare'),state.input);
  state.plan={planId:plan.planId,result:plan.result};
  delete state.error;
  if (!plan.result.blocked) {
    await ui.navigate('app.schedule.home',{importPlanId:plan.planId});
    state.notice='已打开课表导入预览，请在课表中确认保存';
  }
}
export async function render({state={},event,formValues={},context={}}) {
  try {
    // Navigation context is untrusted input, not a permission or saved draft.
    // School adapters hand off JSON only; configuration and conversion remain
    // in this module and provider review is still required for every write.
    if (context.shiguangImport && !state.handoffConsumed) {
      state.handoffConsumed=true;
      const incoming=context.shiguangImport;
      if (incoming.version!==1 || !incoming.payload || typeof incoming.payload!=='object') throw new Error('学校模块的导入数据接口无效');
      const configured=await configure(Array.isArray(incoming.payload)?{courses:incoming.payload}:incoming.payload);
      if (configured) {state.options=configured.options;state.input=configured.input;}
      else state.notice='已取消学校模块的导入';
    }
    if (event?.type==='customScript') {
      const result=await ui.dialog({title:'使用拾光学校适配脚本',fields:[field('script','粘贴学校适配器完整 JavaScript',state.script||'','multiline',{required:true,maxLength:240000})]});
      if (result) {state.script=result.script;state.notice='已选用学校脚本，仅在本次运行会话中保留';}
    }
    if (event?.type==='defaultScript') {delete state.script;state.notice='已切换为正方 HTML 通用脚本';}
    if (event?.type==='json' || event?.type==='browser') {
      let payload;
      if (event.type==='json') {
        const raw=await files.readText();
        if (raw==null) return {state,tree:tree(state)};
        payload=JSON.parse(raw);
      } else {
        const url=String(formValues.url||state.url||'').trim();
        state.url=url;
        payload=await browser.capture({url,script:captureScript(state.script||zhengfang)});
        if (payload==null) return {state,tree:tree(state)};
      }
      const configured=await configure(Array.isArray(payload)?{courses:payload}:payload,state.options);
      if (configured) {state.options=configured.options;state.input=configured.input;delete state.plan;delete state.error;delete state.notice;}
    }
    if (event?.type==='preview' && state.input) await prepare(state);
    if (event?.type==='conflicts' && state.plan?.result.conflicts?.length) {
      const choices=await ui.dialog({title:'处理来源与本地修改冲突',fields:state.plan.result.conflicts.map(c=>field(c.key,`${c.field}：本地 ${JSON.stringify(c.local)} / 来源 ${JSON.stringify(c.source)}`,state.input.choices[c.key]||c.options?.[0]||'local','select',{required:true,options:c.options?c.options.map(value=>({value,label:value==='extra'?'保留为临时课':'撤销失效调课'})):[{value:'local',label:'保留本地'},{value:'source',label:'采用来源'}]}))});
      if (choices) {state.input.choices={...state.input.choices,...choices};await prepare(state);}
    }
    if (event?.type==='clear') {delete state.input;delete state.plan;delete state.error;delete state.notice;}
  } catch(error) {state.error=error.message;delete state.plan;}
  return {state,tree:tree(state)};
}
function tree(state) {
  const draft=state.input?.draft;
  return {type:'column',children:[
    text('拾光教务导入'),
    text('在教务浏览器登录并打开个人课表，执行脚本后预览课程，再确认保存。'),
    {type:'input',key:'url',text:'教务登录网址',inputMode:'url',value:state.url||''},
    button('打开教务浏览器','browser'),
    text(state.script?'当前使用学校适配脚本':'当前使用正方 HTML 通用脚本，需页面支持 jQuery'),
    button('使用学校适配脚本','customScript'),
    ...(state.script?[button('恢复正方通用脚本','defaultScript')]:[]),
    button('导入拾光 JSON 文件','json'),
    text('桌面端可导入拾光导出的 JSON；内置教务浏览器当前支持 Android。'),
    ...(state.notice?[text(state.notice)]:[]),
    ...(state.error?[text('无法继续：'+state.error)]:[]),
    ...(draft?[
      {type:'card',children:[text(`${draft.timetable.name} · ${draft.courses.length} 门课程 · ${draft.meetings.length} 个安排`),text(`第一周 ${draft.timetable.firstMonday} · ${draft.timetable.totalWeeks} 周 · ${draft.timetable.periods.length} 节`),...draft.warnings.map(text),button('预览实际变更','preview'),...(state.plan?.result.blocked?[text(`${state.plan.result.conflicts.length} 项冲突`),button('处理导入冲突','conflicts')]:[]),button('取消本次导入','clear')]}
    ]:[]),
  ]};
}
