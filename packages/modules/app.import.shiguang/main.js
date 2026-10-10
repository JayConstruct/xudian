import {services,ui,files,browser} from '@xudian/sdk';
import {convert,suggestedMonday} from './convert.js';
import {captureScript} from './bridge.js';
import zhengfang from './zhengfang.js';
import {loadAdapter,snapshot} from './warehouse/catalog.js';
import {selectedAdapter,schoolPicker,generalPicker,schoolAdapters,compatibilityNote} from './schools.js';
import {aboutPage,repository} from './about.js';
export {convert};
export {compileBridge} from './bridge.js';
export {listAdapters} from './schools.js';
const ref=serviceId=>({moduleId:'app.schedule',serviceId,majorVersion:1});
const text=value=>({type:'text',text:value});
const button=(label,type)=>({type:'button',text:label,event:{type}});
const field=(key,label,value,type='text',extra={})=>({key,label,value,type,...extra});
function clearSourceDraft(state) {
  delete state.input;delete state.plan;delete state.options;delete state.error;
}
const views=new Set(['home','schools','general','about','detail']);
function currentView(state) {
  return views.has(state.view)?state.view:state.choosingSchool?'schools':state.input||state.adapterId||state.script?'detail':'home';
}
function initializeNavigation(state) {
  state.view=currentView(state);
  if (!Array.isArray(state.history)) {
    state.history=state.view==='home'?[]:[{view:'home',schoolSearch:state.schoolSearch||'',schoolPage:state.schoolPage||0}];
    if (state.view==='detail' && selectedAdapter(state)) state.history.push({view:selectedAdapter(state).category==='GENERAL_TOOL'?'general':'schools',schoolSearch:state.schoolSearch||'',schoolPage:state.schoolPage||0});
  }
}
function enterView(state,view) {
  if (currentView(state)===view) return;
  state.history.push({view:currentView(state),schoolSearch:state.schoolSearch||'',schoolPage:state.schoolPage||0});
  state.view=view;state.choosingSchool=view==='schools';
}
function back(state) {
  const previous=state.history.pop();
  state.view=previous&&views.has(previous.view)?previous.view:'home';
  if (previous) {state.schoolSearch=previous.schoolSearch||'';state.schoolPage=previous.schoolPage||0;}
  state.choosingSchool=state.view==='schools';
}
function detailTitle(state) {
  const chosen=selectedAdapter(state);
  return state.sourceKind==='json'||state.sourceKind==='handoff'?'确认导入结果':chosen?.category==='GENERAL_TOOL'?chosen.name.replace('html通用获取','').replace('通用获取',''):chosen?.school||'学校脚本导入';
}
function response(state,replaceForms={}) {
  const view=currentView(state);
  const title=view==='schools'?'选择学校':view==='general'?'通用系统导入':view==='about'?'关于与致谢':view==='detail'?detailTitle(state):'拾光教务导入';
  return {state,replaceForms,header:{title,...(view==='home'?{}:{backEvent:{type:'back'}})},tree:tree(state)};
}
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
  let replaceForms={};
  initializeNavigation(state);
  if (currentView(state)==='schools' && formValues.schoolSearch!==undefined) state.schoolSearch=String(formValues.schoolSearch).trim();
  if (currentView(state)==='detail' && formValues.url!==undefined) state.url=String(formValues.url).trim();
  try {
    if (event?.type==='back' || event?.type==='closeSchools' || event?.type==='backToPicker') {
      back(state);replaceForms.schoolSearch=state.schoolSearch||'';replaceForms.url=state.url||'';
    }
    if (event?.type==='chooseSchool') {
      const changing=currentView(state)!=='schools';
      enterView(state,'schools');
      if (changing) {state.schoolSearch='';state.schoolPage=0;}
      if (formValues.url!==undefined) state.url=String(formValues.url).trim();
      replaceForms.schoolSearch=state.schoolSearch||'';
    }
    if (event?.type==='goHome') {state.view='home';state.choosingSchool=false;state.history=[];}
    if (event?.type==='chooseGeneral') enterView(state,'general');
    if (event?.type==='openAbout') enterView(state,'about');
    if (event?.type==='continueImport') enterView(state,'detail');
    if (event?.type==='searchSchool' || event?.type==='schoolPage') {
      state.schoolSearch=String(formValues.schoolSearch??state.schoolSearch??'').trim();
      state.schoolPage=event.type==='searchSchool'?0:event.page;
    }
    if (event?.type==='selectSchool') {
      const chosen=selectedAdapter({adapterId:event.id});
      if (!chosen) throw new Error('学校脚本不存在，请重新选择');
      enterView(state,'detail');
      clearSourceDraft(state);
      state.adapterId=chosen.id;state.url=chosen.url;state.choosingSchool=false;
      state.view='detail';state.sourceKind='browser';
      delete state.script;delete state.error;delete state.notice;
      replaceForms.url=chosen.url;
    }
    // Navigation context is untrusted input, not a permission or saved draft.
    // School adapters hand off JSON only; configuration and conversion remain
    // in this module and provider review is still required for every write.
    if (context.shiguangImport && !state.handoffConsumed) {
      state.handoffConsumed=true;
      const incoming=context.shiguangImport;
      if (incoming.version!==1 || !incoming.payload || typeof incoming.payload!=='object') throw new Error('学校模块的导入数据接口无效');
      const configured=await configure(Array.isArray(incoming.payload)?{courses:incoming.payload}:incoming.payload);
      if (configured) {enterView(state,'detail');state.options=configured.options;state.input=configured.input;state.sourceKind='handoff';}
      else state.notice='已取消学校模块的导入';
    }
    if (event?.type==='customScript') {
      const result=await ui.dialog({title:'使用拾光学校适配脚本',fields:[field('script','粘贴学校适配器完整 JavaScript',state.script||'','multiline',{required:true,maxLength:240000})]});
      if (result) {enterView(state,'detail');clearSourceDraft(state);state.script=result.script;delete state.adapterId;state.sourceKind='browser';state.notice='已选用学校脚本，仅在本次运行会话中保留；原导入预览已清除';}
    }
    if (event?.type==='defaultScript') {enterView(state,'detail');clearSourceDraft(state);delete state.script;delete state.adapterId;state.sourceKind='browser';state.notice='已切换为正方 HTML 通用脚本，原导入预览已清除';}
    if (event?.type==='json' || event?.type==='browser') {
      let payload;
      if (event.type==='json') {
        const raw=await files.readText();
        if (raw==null) {state.notice=state.input?'已取消文件选择，仍保留上一次导入草稿':'已取消文件选择';return response(state,replaceForms);}
        payload=JSON.parse(raw);
      } else {
        const url=String(formValues.url||state.url||'').trim();
        state.url=url;
        const chosen=state.adapterId?await loadAdapter(state.adapterId):null;
        payload=await browser.capture({url,script:captureScript(state.script||chosen?.script||zhengfang)});
        if (payload==null) {state.notice=state.input?'已取消采集，仍保留上一次导入草稿':'已取消采集';return response(state,replaceForms);}
      }
      const configured=await configure(Array.isArray(payload)?{courses:payload}:payload,state.options);
      if (configured) {enterView(state,'detail');state.options=configured.options;state.input=configured.input;state.sourceKind=event.type==='json'?'json':'browser';delete state.plan;delete state.error;delete state.notice;}
      else state.notice=state.input?'已取消导入配置，仍保留上一次导入草稿':'已取消导入配置';
    }
    if (event?.type==='preview' && state.input) await prepare(state);
    if (event?.type==='conflicts' && state.plan?.result.conflicts?.length) {
      const choices=await ui.dialog({title:'处理来源与本地修改冲突',fields:state.plan.result.conflicts.map(c=>field(c.key,`${c.field}：本地 ${JSON.stringify(c.local)} / 来源 ${JSON.stringify(c.source)}`,state.input.choices[c.key]||c.options?.[0]||'local','select',{required:true,options:c.options?c.options.map(value=>({value,label:value==='extra'?'保留为临时课':'撤销失效调课'})):[{value:'local',label:'保留本地'},{value:'source',label:'采用来源'}]}))});
      if (choices) {state.input.choices={...state.input.choices,...choices};await prepare(state);}
    }
    if (event?.type==='clear') {delete state.input;delete state.plan;delete state.error;delete state.notice;}
  } catch(error) {state.error=error.message;delete state.plan;}
  return response(state,replaceForms);
}
function tree(state) {
  const view=currentView(state);
  if (view==='schools') return schoolPicker(state);
  if (view==='general') return generalPicker();
  if (view==='about') return aboutPage();
  if (view==='home') return home(state);
  return detail(state);
}
function messages(state) {
  return [...(state.notice?[text(state.notice)]:[]),...(state.error?[text('无法继续：'+state.error)]:[])];
}
function home(state) {
  const chosen=selectedAdapter(state);
  const entry=(title,subtitle,icon,type)=>({type:'listTile',title,subtitle,icon,event:{type}});
  return {type:'column',children:[
    text('选择学校或教务系统，登录后采集课程，再预览确认。'),
    ...(state.input?[{type:'card',children:[entry('继续本次导入',`${state.input.draft.courses.length} 门课程 · 查看转换结果与导入预览`,'calendar','continueImport')]}]:chosen||state.script?[{type:'card',children:[entry('继续上次选择',chosen?.school||'已粘贴的学校脚本','calendar','continueImport')]}]:[]),
    {type:'card',children:[
      entry('按学校导入','搜索学校名称或缩写','school','chooseSchool'),
      {type:'divider'},
      entry('通用系统导入','正方、青果、URP、超星','importExport','chooseGeneral'),
    ]},
    {...text('其他导入方式'),style:'heading'},
    {type:'card',children:[
      entry('粘贴学校脚本','使用学校提供的完整适配脚本','list','customScript'),
      {type:'divider'},
      entry('导入拾光 JSON 文件','适用于桌面端和已有导出文件','importExport','json'),
    ]},
    entry('关于与致谢','源码地址、脚本贡献者与开源许可','info','openAbout'),
    ...messages(state),
  ]};
}
function detail(state) {
  const draft=state.input?.draft;
  const chosen=selectedAdapter(state);
  const isFile=state.sourceKind==='json'||state.sourceKind==='handoff';
  const variants=chosen?.category!=='GENERAL_TOOL'&&chosen?schoolAdapters(chosen):[];
  return {type:'column',children:[
    ...messages(state),
    ...(!isFile&&variants.length>1?[{type:'card',children:[
      {...text('选择导入入口'),style:'heading'},
      ...variants.map(a=>({type:'listTile',title:a.name,subtitle:a.id===chosen.id?'当前入口':undefined,icon:'school',disabled:a.id===chosen.id,event:{type:'selectSchool',id:a.id}})),
    ]}]:[]),
    ...(!isFile?[
    {type:'card',children:[
      {...text('使用说明'),style:'heading'},
      text(chosen?.description||'在教务网页登录，进入个人课表查询页面，选择学年学期后执行采集。'),
      ...(chosen&&compatibilityNote(chosen)?[text(compatibilityNote(chosen))]:[]),
      ...(chosen?.category==='GENERAL_TOOL'?[text('请填写本校教务网址。通用脚本不保证适用于该系统的所有版本。')]:[]),
    ]},
    {type:'input',key:'url',text:'教务登录网址',inputMode:'url',value:state.url||''},
    button('打开教务浏览器','browser'),
    text(state.script?'当前使用粘贴的学校脚本':chosen?'当前使用所选学校脚本':'当前使用正方 HTML 通用脚本，需页面支持 jQuery'),
    {...text('教务浏览器当前支持 Android。'),style:'muted'},
    ]:[]),
    ...(draft?[
      {type:'card',children:[text(`${draft.timetable.name} · ${draft.courses.length} 门课程 · ${draft.meetings.length} 个安排`),text(`第一周 ${draft.timetable.firstMonday} · ${draft.timetable.totalWeeks} 周 · ${draft.timetable.periods.length} 节`),...draft.warnings.map(text),button('预览实际变更','preview'),...(state.plan?.result.blocked?[text(`${state.plan.result.conflicts.length} 项冲突`),button('处理导入冲突','conflicts')]:[]),button('取消本次导入','clear')]}
    ]:[]),
    ...(!isFile?[{type:'card',children:[
      {...text('脚本来源'),style:'heading'},
      text('维护者：'+(chosen?.maintainer||(state.script?'由你提供':'星河欲转'))),
      ...(!state.script?[{type:'richText',text:chosen?`${repository}/blob/${snapshot.revision}/${chosen.path}`:`${repository}/blob/ff72d1f08782df965cae110034a9d87cd91e0c07/resources/zhengfang_jiaowu/zhengfang_01.js`}]:[]),
      {...text('长按源码地址可以复制。'),style:'muted'},
    ]}]:[]),
    button('关于与致谢','openAbout'),
  ]};
}
