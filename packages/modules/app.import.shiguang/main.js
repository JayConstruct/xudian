import {services,ui,files,browser,clock} from '@xudian/sdk';
import {convert,suggestedMonday} from './convert.js';
import {captureScript} from './bridge.js';
import zhengfang from './zhengfang.js';
import {loadAdapter,snapshot} from './warehouse/catalog.js';
import {selectedAdapter,schoolPicker,generalPicker,schoolAdapters,schoolTitle,systemTitle,entranceTitle,compatibilityNote} from './schools.js';
import {aboutPage,projectSources,repository} from './about.js';
import {locationModes,locationSettings,suggestedCampusNames} from './locations.js';
import {card,column,footer,group,heading,input,text,tile} from './ui.js';
import {conflictOptions,conflictsPage,locationsPage,modeOptions,pastePage,previewPage,semesterFormKeys,semesterPage} from './workflow_ui.js';
export {convert};
export {compileBridge} from './bridge.js';
export {listAdapters} from './schools.js';

const ref=serviceId=>({moduleId:'app.schedule',serviceId,majorVersion:1});
const field=(key,label,value,type='text',extra={})=>({key,label,value,type,...extra});
const defaultSource=`${repository}/blob/ff72d1f08782df965cae110034a9d87cd91e0c07/resources/zhengfang_jiaowu/zhengfang_01.js`;
const schoolSource=chosen=>chosen?`${repository}/blob/${snapshot.revision}/${chosen.path}`:defaultSource;

export function normalizeUrl(value) {
  let url=String(value??'').trim();
  if (!url) throw new Error('请填写教务登录网址');
  if (url.length>4096) throw new Error('教务网址过长');
  if (url.startsWith('//')) url='https:'+url;
  else if (!/^https?:\/\//i.test(url)) {
    if (/^[a-z][a-z0-9+.-]*:/i.test(url) && !/^[^/:]+:\d+(?:[/?#]|$)/.test(url)) throw new Error('教务网址只支持 http 或 https');
    url='https://'+url;
  }
  url=url.replace(/^https?/i,scheme=>scheme.toLowerCase());
  if (!/^https?:\/\/[^/?#\s@]+(?:[/?#][^\s]*)?$/.test(url)) throw new Error('请输入有效的教务网址，不要包含账号或密码');
  return url;
}
const hostOf=url=>String(url||'').replace(/^https?:\/\//i,'').split(/[/?#]/)[0].toLowerCase();
function sourceIdentity(state) {
  if (state.sourceKind==='json'||state.sourceKind==='handoff') return state.sourceKind;
  const chosen=selectedAdapter(state);
  if (chosen && chosen.category!=='GENERAL_TOOL') return 'school:'+chosen.school;
  return 'web:'+hostOf(state.url);
}
function preferenceKey(prefix,identity) {
  // Short keys keep arbitrarily long school names out of host preference keys.
  let hash=2166136261;
  for (const char of identity) hash=Math.imul(hash^char.charCodeAt(0),16777619)>>>0;
  return prefix+'.'+hash.toString(16);
}
function loginIdentity(chosen) {
  return chosen?.school||chosen?.id||'custom';
}
async function rememberedUrl(chosen) {
  const identity=loginIdentity(chosen);
  const variants=schoolAdapters(chosen);
  if (variants.length<2) return await ui.preferences.get(preferenceKey('loginUrl',identity))||chosen.url;
  const stored=await ui.preferences.get(preferenceKey('loginUrl',chosen.id));
  if (stored) return stored;
  const legacy=await ui.preferences.get(preferenceKey('loginUrl',identity));
  return legacy&&(hostOf(legacy)===hostOf(chosen.url)||variants[0].id===chosen.id&&
    !variants.some(variant=>hostOf(variant.url)===hostOf(legacy)))?legacy:chosen.url;
}
async function rememberUrl(state) {
  const chosen=selectedAdapter(state);
  const identity=chosen&&schoolAdapters(chosen).length>1?chosen.id:loginIdentity(chosen);
  await ui.preferences.set(preferenceKey('loginUrl',identity),state.url);
  await ui.preferences.set('lastLoginUrl',state.url);
}
function clearSourceDraft(state) {
  delete state.input;
  delete state.payload;
  delete state.plan;
  delete state.options;
  delete state.error;
  delete state.timezoneNotice;
}
const viewTitles={
  home:'拾光教务导入',schools:'选择学校',general:'通用系统导入',about:'关于与致谢',preview:'导入预览',
  paste:'使用学校适配脚本',semester:'确认学期配置',locations:'处理导入地点',conflicts:'处理导入冲突',
};
const closingViews=new Set(['paste','semester','locations','conflicts']);
const views=new Set([...Object.keys(viewTitles),'detail','source']);
function currentView(state) {
  if (views.has(state.view)) return !state.workflowNavigation&&state.view==='detail'&&state.input?'preview':state.view;
  return state.choosingSchool?'schools':state.input?'preview':state.adapterId||state.script?'detail':'home';
}
function pageFrame(state,view=currentView(state)) {
  return {view,schoolSearch:state.schoolSearch||'',schoolPage:state.schoolPage||0};
}
function initializeNavigation(state) {
  state.view=currentView(state);
  state.workflowNavigation=true;
  if (!Array.isArray(state.history)) {
    state.history=state.view==='home'?[]:[pageFrame(state,'home')];
    const chosen=selectedAdapter(state);
    if (state.view==='detail'&&chosen) state.history.push(pageFrame(state,chosen.category==='GENERAL_TOOL'?'general':'schools'));
  }
}
function enterView(state,view) {
  if (state.view===view) return;
  state.history.push(pageFrame(state,state.view));
  state.view=view;
  state.choosingSchool=view==='schools';
  state.navigationDirection='forward';
}
function back(state) {
  const previous=state.history.pop();
  state.view=previous&&views.has(previous.view)?previous.view:'home';
  if (previous) {state.schoolSearch=previous.schoolSearch||'';state.schoolPage=previous.schoolPage||0;}
  state.choosingSchool=state.view==='schools';
  state.navigationDirection='back';
}
function replaceView(state,view) {
  state.view=view;
  state.choosingSchool=view==='schools';
  state.navigationDirection='forward';
}
function response(state,replaceForms) {
  const view=state.view;
  const chosen=selectedAdapter(state);
  const title=view==='detail'?(chosen?.category==='GENERAL_TOOL'?systemTitle(chosen):chosen?schoolTitle(chosen.school):'学校脚本导入'):
    view==='source'?state.source.title:viewTitles[view];
  const page=pageBody(state,chosen);
  const mainMessages=closingViews.has(view)?[]:messages(state);
  const child=mainMessages.length?column([...mainMessages,...page.body.children]):page.body;
  return {state,replaceForms,header:{title,minHeight:65,...(view==='home'?{}:{backEvent:{type:'back'}}),...(closingViews.has(view)?{backIcon:'close'}:{})},
    tree:{type:'transition',key:'importNavigation',compact:true,queueInputActions:true,scrollKey:`import:${view}`,
      effect:'page',direction:state.navigationDirection||'forward',replayKey:view,child,
      ...(page.footer?{footer:page.footer,footerStyle:'edge'}:{}),
      ...(closingViews.has(view)&&state.error&&page.footer?{footerMessage:{type:'notice',tone:'warning',text:state.error}}:{}),
    }};
}
async function configure(payload,sourceKind,state,replaceForms,previous) {
  const identity=sourceIdentity({...state,sourceKind});
  const remembered=await ui.preferences.get(preferenceKey('semester',identity))||{};
  const {timetables}=await services.query(ref('schedule.query.timetables'),{});
  const editing=previous!=null;
  const priorTarget=previous?timetables.find(table=>table.id===state.input?.targetTimetableId):null;
  previous??={};
  const target=timetables.length?await ui.dialog({
    title:'选择导入目标',presentation:'sheet',fullWidthActions:true,
    fields:[field('target','',priorTarget?.id||'new','select',{required:true,presentation:'list',options:[
      {value:'new',label:'新建课表',icon:'add',subtitle:'将采集结果导入新课表'},
      ...timetables.map(t=>({value:t.id,label:t.name,icon:'calendar',subtitle:'更新已有课表'})),
    ]})],
  }):{target:'new'};
  if (!target) return false;
  const base=timetables.find(t=>t.id===target.target),config=payload?.config||{};
  if (target.target!=='new'&&!base) throw new Error('所选课表已不可用，请重新选择');
  const explicit=base?.timezone??config.timezone??payload?.timezone;
  const zone=explicit===undefined?await clock.systemTimezone():{zone:explicit,source:'explicit'};
  await clock.today(zone.zone);
  const chosen=selectedAdapter(state);
  const current=editing&&target.target===(state.input?.targetTimetableId??'new')?previous:{};
  const settings={
    name:current.name||base?.name||previous.name||remembered.name||(chosen?.school?chosen.school+'课表':'教务导入课表'),
    firstMonday:current.firstMonday||(config.semesterStartDate?suggestedMonday(config):(base?.firstMonday||previous.firstMonday||remembered.firstMonday||'')),
    totalWeeks:current.totalWeeks??config.semesterTotalWeeks??base?.totalWeeks??previous.totalWeeks??remembered.totalWeeks??20,
    displayWeekStart:String(current.displayWeekStart??config.firstDayOfWeek??base?.displayWeekStart??previous.displayWeekStart??remembered.displayWeekStart??1),
    mode:base&&priorTarget?.id===base.id?current.mode??state.input.mode:'merge',
    complete:!!base&&current.complete===true,
    scope:previous.scopeAlias??remembered.scopeAlias??'',
    locationMode:previous.locationMode??remembered.locationMode??'keep',
    campusNames:previous.campusNames??remembered.campusNames??suggestedCampusNames(payload),
  };
  state.configuration={payload,sourceKind,base,settings,zone,identity};
  for (const key of semesterFormKeys) replaceForms[key]=settings[key];
  enterView(state,'semester');
  return true;
}
async function saveConfiguration(state) {
  const {settings,payload,sourceKind,base,zone,identity}=state.configuration;
  if (!settings.firstMonday) throw new Error('请选择第一教学周');
  if (base&&!modeOptions.some(option=>option.value===settings.mode)) throw new Error('请选择导入方式');
  const firstMonday=suggestedMonday({semesterStartDate:settings.firstMonday,firstDayOfWeek:1});
  const scopeAlias=String(settings.scope||'').trim();
  const options={...settings,firstMonday,scopeAlias,scope:scopeAlias||identity+'/'+firstMonday,timezone:zone.zone,
    ...(base?{timeSlots:base.periods,targetName:base.name}:{}),
  };
  const draft=convert({payload,options});
  options.totalWeeks=draft.timetable.totalWeeks;
  options.displayWeekStart=draft.timetable.displayWeekStart;
  await ui.preferences.set(preferenceKey('semester',identity),{name:draft.timetable.name,scopeAlias,totalWeeks:options.totalWeeks,
    displayWeekStart:options.displayWeekStart,firstMonday,locationMode:options.locationMode,campusNames:options.campusNames,
  });
  state.timezoneNotice=zone.source==='fallback'?`设备时区未能获取，当前使用 ${zone.zone}。保存后可在课表高级设置中修改。`:null;
  if (state.timezoneNotice) draft.warnings.push(`设备时区未能获取，当前使用 ${zone.zone}`);
  state.options=options;
  state.input={draft,mode:base?settings.mode:'new',...(base?{targetTimetableId:base.id}:{}),choices:{}};
  state.sourceKind=sourceKind;
  state.payload=payload;
  delete state.configuration;
  delete state.plan;
  delete state.notice;
  if (state.history.at(-1)?.view==='preview') state.history.pop();
  replaceView(state,'preview');
}
async function prepare(state) {
  const plan=await services.prepare(ref('schedule.import.prepare'),state.input);
  state.plan={planId:plan.planId,result:plan.result};
  if (!plan.result.blocked) {
    await ui.navigate('app.schedule.imports',{importPlanId:plan.planId});
    state.notice='已打开实际变更，取消后可继续调整本次导入';
  }
}
function messages(state) {
  return [
    ...(state.timezoneNotice&&!state.input?[text(state.timezoneNotice,'muted')]:[]),
    ...(state.notice?[text(state.notice,'muted')]:[]),
    ...(state.error?[{type:'notice',tone:'warning',text:'无法继续：'+state.error}]:[]),
  ];
}

export async function render({state={},event,formValues={},context={}}) {
  const replaceForms={};
  initializeNavigation(state);
  if (!state.urlLoaded) {state.urlLoaded=true;state.url=state.url||await ui.preferences.get('lastLoginUrl')||'';}
  if (state.view==='schools'&&formValues.schoolSearch!==undefined) state.schoolSearch=String(formValues.schoolSearch).trim();
  if (state.view==='detail'&&formValues.url!==undefined) state.url=String(formValues.url).trim();
  if (state.view==='semester') {
    for (const key of semesterFormKeys) if (formValues[key]!==undefined) state.configuration.settings[key]=formValues[key];
  }
  if (state.view==='locations'&&formValues.campusNames!==undefined) state.locationDraft.campusNames=String(formValues.campusNames);
  if (event?.type) delete state.error;
  try {
    if (context.shiguangImport&&!state.handoffConsumed) {
      // Other modules hand off JSON only. The schedule provider still reviews every write.
      state.handoffConsumed=true;
      const incoming=context.shiguangImport;
      if (incoming.version!==1||!incoming.payload||typeof incoming.payload!=='object') throw new Error('学校模块的导入数据接口无效');
      const payload=Array.isArray(incoming.payload)?{courses:incoming.payload}:incoming.payload;
      if (!await configure(payload,'handoff',state,replaceForms)) state.notice='已取消学校模块的导入';
    }
    switch (event?.type) {
      case 'back': case 'closeSchools': case 'backToPicker':
        if (state.view==='paste') replaceForms.scriptText='';
        if (state.view==='locations') delete state.locationDraft;
        if (state.view==='source') delete state.source;
        if (state.view==='conflicts') delete state.conflictChoices;
        if (state.view==='semester') {
          delete state.configuration;
          state.notice=state.input?'已取消导入配置，仍保留上一次导入草稿':'已取消导入配置';
        }
        back(state);
        replaceForms.schoolSearch=state.schoolSearch||'';
        replaceForms.url=state.url||'';
        break;
      case 'chooseSchool':
        if (state.view!=='schools') {
          enterView(state,'schools');
          state.schoolSearch='';state.schoolPage=0;
        }
        if (formValues.url!==undefined) state.url=String(formValues.url).trim();
        replaceForms.schoolSearch=state.schoolSearch;
        break;
      case 'goHome':
        state.view='home';state.choosingSchool=false;state.history=[];state.navigationDirection='back';
        break;
      case 'chooseGeneral': enterView(state,'general');break;
      case 'openAbout': enterView(state,'about');break;
      case 'openSource': {
        const chosen=selectedAdapter(state);
        const source=event.source==='adapter'&&!state.script?{title:'原始源码',url:schoolSource(chosen)}:
          event.source==='revision'?{title:'快照版本',url:snapshot.revision}:Object.hasOwn(projectSources,event.source)?projectSources[event.source]:null;
        if (source) {state.source=source;enterView(state,'source');}
        break;
      }
      case 'continueImport': enterView(state,state.input?'preview':'detail');break;
      case 'searchSchool': case 'schoolPage':
        state.schoolSearch=String(formValues.schoolSearch??state.schoolSearch??'').trim();
        state.schoolPage=event.type==='searchSchool'?0:event.page;
        break;
      case 'selectSchool': {
        const chosen=selectedAdapter({adapterId:event.id});
        if (!chosen) throw new Error('学校脚本不存在，请重新选择');
        if (state.view==='detail'&&chosen.id===state.adapterId) break;
        const url=await rememberedUrl(chosen);
        if (state.view==='preview') replaceView(state,'detail');
        else enterView(state,'detail');
        clearSourceDraft(state);
        state.adapterId=chosen.id;state.url=url;state.sourceKind='browser';
        delete state.script;delete state.notice;
        replaceForms.url=url;
        break;
      }
      case 'customScript':
        enterView(state,'paste');
        replaceForms.scriptText=state.script||'';
        break;
      case 'applyScript': {
        if (state.view!=='paste') break;
        const script=String(formValues.scriptText??'');
        if (!script.trim()) throw new Error('请粘贴完整的学校适配脚本');
        if (script.length>240000) throw new Error('学校脚本超过长度限制');
        clearSourceDraft(state);
        state.script=script;
        delete state.adapterId;
        state.sourceKind='browser';
        state.notice='已选用学校脚本，仅在本次运行会话中保留';
        replaceForms.scriptText='';
        if (['detail','preview'].includes(state.history.at(-1)?.view)) state.history.pop();
        replaceView(state,'detail');
        break;
      }
      case 'defaultScript':
        if (state.view==='preview') replaceView(state,'detail');
        else enterView(state,'detail');
        clearSourceDraft(state);delete state.script;delete state.adapterId;
        state.sourceKind='browser';state.notice='已切换为正方 HTML 通用脚本，原导入预览已清除';
        break;
      case 'json': case 'browser': {
        let payload;
        if (event.type==='json') {
          const raw=await files.readText();
          if (raw==null) {state.notice=state.input?'已取消文件选择，仍保留上一次导入草稿':'已取消文件选择';break;}
          payload=JSON.parse(raw);
        } else {
          const url=normalizeUrl(formValues.url??state.url);
          state.url=url;replaceForms.url=url;
          await rememberUrl(state);
          const chosen=state.adapterId?await loadAdapter(state.adapterId):null;
          payload=await browser.capture({url,script:captureScript(state.script||chosen?.script||zhengfang)});
          if (payload==null) {state.notice=state.input?'已取消采集，仍保留上一次导入草稿':'已取消采集';break;}
        }
        const sourcePayload=Array.isArray(payload)?{courses:payload}:payload;
        if (!await configure(sourcePayload,event.type,state,replaceForms)) state.notice=state.input?'已取消导入配置，仍保留上一次导入草稿':'已取消导入配置';
        break;
      }
      case 'configure':
        if (state.payload) await configure(state.payload,state.sourceKind,state,replaceForms,state.options);
        break;
      case 'semesterDate':
        if (state.view==='semester'&&event.value) {
          const monday=suggestedMonday({semesterStartDate:event.value,firstDayOfWeek:1});
          state.configuration.settings.firstMonday=monday;
          replaceForms.firstMonday=monday;
        }
        break;
      case 'editScope': {
        if (state.view!=='semester') break;
        const {settings}=state.configuration;
        const value=await ui.dialog({title:'来源标识',presentation:'compact',submitLabel:'应用',
          description:'默认自动识别学校与学期。同一学校有多个账号，或更新旧导入时，可填写固定标识。',
          fields:[field('scope','来源标识（可选）',settings.scope,'text',{maxLength:500})],
        });
        if (value) settings.scope=String(value.scope||'').trim();
        break;
      }
      case 'editImportMode': {
        if (state.view!=='semester'||!state.configuration.base) break;
        const {settings}=state.configuration;
        const result=await ui.dialog({title:'导入方式',presentation:'sheet',fullWidthActions:true,
          fields:[field('mode','',settings.mode,'select',{required:true,presentation:'list',options:modeOptions})],
        });
        if (result&&modeOptions.some(option=>option.value===result.mode)) settings.mode=result.mode;
        break;
      }
      case 'saveSemester':
        if (state.view==='semester') await saveConfiguration(state);
        break;
      case 'preview':
        if (state.input) await prepare(state);
        break;
      case 'locations': {
        const payload=state.configuration?.payload??state.payload;
        if (!payload) break;
        const options=state.configuration?.settings??state.options??{};
        state.locationDraft={locationMode:options.locationMode??'keep',campusNames:options.campusNames??suggestedCampusNames(payload)};
        replaceForms.campusNames=state.locationDraft.campusNames;
        enterView(state,'locations');
        break;
      }
      case 'locationMode':
        if (state.view==='locations'&&locationModes.some(mode=>mode.value===event.value)) state.locationDraft.locationMode=event.value;
        break;
      case 'applyLocations': {
        if (state.view!=='locations') break;
        const settings=locationSettings(state.locationDraft);
        if (state.configuration) Object.assign(state.configuration.settings,settings);
        else {
          const options={...state.options,...settings};
          const draft=convert({payload:state.payload,options});
          if (state.timezoneNotice) draft.warnings.push(`设备时区未能获取，当前使用 ${options.timezone}`);
          state.options=options;state.input={...state.input,draft,choices:{}};
          delete state.plan;
          delete state.notice;
        }
        delete state.locationDraft;
        back(state);
        break;
      }
      case 'conflicts':
        if (state.plan?.result?.conflicts?.length) {
          state.conflictChoices={...state.input.choices};
          for (const conflict of state.plan.result.conflicts) {
            if (conflict.key!=='timetable:timeBasis') state.conflictChoices[conflict.key]??=conflictOptions(conflict)[0].value;
          }
          enterView(state,'conflicts');
        }
        break;
      case 'pickConflict': {
        if (state.view!=='conflicts') break;
        const conflict=state.plan.result.conflicts[event.index];
        if (conflict&&conflictOptions(conflict).some(option=>option.value===event.value)) state.conflictChoices[conflict.key]=event.value;
        break;
      }
      case 'applyConflicts': {
        if (state.view!=='conflicts') break;
        if (state.plan.result.conflicts.some(conflict=>!state.conflictChoices[conflict.key])) throw new Error('请选择每项冲突的处理方式');
        state.input.choices=state.conflictChoices;
        delete state.conflictChoices;
        back(state);
        await prepare(state);
        break;
      }
      case 'clear':
        clearSourceDraft(state);delete state.notice;
        if (state.view==='preview') back(state);
        break;
    }
  } catch(error) {
    state.error=error.message;
  }
  return response(state,replaceForms);
}
function pageBody(state,chosen) {
  switch (state.view) {
    case 'schools': return {body:schoolPicker(state)};
    case 'general': return {body:generalPicker()};
    case 'about': return {body:aboutPage()};
    case 'source': return {body:column([card({type:'richText',text:state.source.url}),text('长按地址可复制。','muted')])};
    case 'paste': return pastePage(state);
    case 'semester': return semesterPage(state);
    case 'preview': return previewPage(state);
    case 'locations': return locationsPage(state);
    case 'conflicts': return conflictsPage(state);
    case 'detail': return detail(state,chosen);
    default: return {body:home(state,chosen)};
  }
}
function home(state,chosen) {
  const entry=(title,subtitle,icon,type)=>tile(title,{subtitle,icon,event:{type}});
  const pending=state.input?entry('继续本次导入',`${state.input.draft.courses.length} 门课程 · 查看导入预览`,'calendar','continueImport'):
    chosen||state.script?entry('继续上次选择',chosen?schoolTitle(chosen.school):'已粘贴的学校脚本','calendar','continueImport'):null;
  return column([
    ...(pending?[group(pending)]:[]),
    heading('从教务系统采集'),
    group(entry('按学校导入','搜索学校名称或缩写','school','chooseSchool'),entry('通用系统导入','正方、青果、URP、超星','importExport','chooseGeneral')),
    heading('从已有文件导入'),
    group(entry('粘贴学校脚本','使用学校提供的完整适配脚本','list','customScript'),entry('导入拾光 JSON 文件','适用于桌面端和已有导出文件','importExport','json')),
    group(entry('关于与致谢','源码地址、脚本贡献者与开源许可','info','openAbout')),
    text('采集后可预览课程并审核实际变更，再确认导入。','muted'),
  ]);
}
function detail(state,chosen) {
  const variants=chosen?.category!=='GENERAL_TOOL'&&chosen?schoolAdapters(chosen):[];
  const compatibility=chosen?compatibilityNote(chosen):state.script?'':'需教务页面提供 jQuery';
  const description=chosen?.description?.trim();
  const steps='进入个人课表，选择学年学期后执行采集。';
  const instructions=!description?'登录教务系统，'+steps:
    /^(?:点击)?统一身份认证登录[。！]?$/.test(description)?'使用统一身份认证登录，'+steps:
    description.length<=40&&!/课表|学期|导入|采集|查询/.test(description)?description.replace(/[。！]?$/,'。')+steps:description;
  return {
    footer:footer('打开教务浏览器','browser'),
    body:column([
      ...(variants.length>1?[
        heading('导入入口'),
        {type:'segmented',selectedIndex:variants.findIndex(a=>a.id===chosen.id),items:variants.map(a=>({label:entranceTitle(a,variants),event:{type:'selectSchool',id:a.id}}))},
      ]:[]),
      heading('教务登录'),
      input('url','教务登录网址',state.url||'',{inputMode:'url',presentation:'labeled'}),
      text('可直接输入域名，自动补全 https://。','muted'),
      card(column([
        text(instructions),
        ...(compatibility?[text(compatibility,'muted')]:[]),
        ...(chosen?.category==='GENERAL_TOOL'?[text('请填写本校教务网址。脚本的适用范围随系统版本而异。','muted')]:[]),
      ])),
      heading('脚本来源'),
      group(
        tile('维护者',{trailing:chosen?.maintainer||(state.script?'由你提供':'星河欲转')}),
        ...(!state.script?[tile('原始源码',{subtitle:'长按地址可复制',icon:'link',event:{type:'openSource',source:'adapter'}})]:[]),
        tile('关于与致谢',{icon:'info',event:{type:'openAbout'}}),
      ),
      text('教务浏览器当前支持 Android。','muted'),
    ]),
  };
}
