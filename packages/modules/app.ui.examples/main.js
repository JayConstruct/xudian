import {ui,clock} from '@xudian/sdk';
import {categories,examples,formKey,initialValue,demoPage,pinnedKey} from './catalog.js';
import {button,column,control,demoValue,callCode,group,text,tile} from './examples.js';
const defaults=()=>({completed:['done'],onlyPending:false,examples:{},modes:{},results:{}});
const registeredPage='app.ui.examples.registered';
const categoryFor=value=>categories.some(([id])=>id===value)?value:'layout';
const identity=sample=>'component:'+sample.providerId+'|'+sample.ref;
const registeredItem=sample=>({id:identity(sample),category:categoryFor(sample.category),title:sample.name,description:sample.description||sample.ref,ref:sample.ref,sample});
async function registeredExamples() {
  // Module installation previews cannot acquire live UI capabilities.
  try {return (await ui.examples()).map(registeredItem);} catch (_) {return [];}
}
async function readPins() {
  const value=await ui.preferences.get(pinnedKey);
  return Array.isArray(value)?[...new Set(value.filter(id=>typeof id==='string'))]:[];
}
function selectedValue(item,today) {
  if(item.id==='date')return today;
  if(item.id==='datetime')return today+'T09:30';
  if(item.id==='range')return {start:today,end:new Date(Date.parse(today+'T00:00:00Z')+2*86400000).toISOString().slice(0,10)};
  return item.selected;
}
function codeSections(item,state,forms) {
  if(!item.sample) {
    const code=callCode(item,state,forms);
    return [{title:'组件或接口调用',code:code.call},{title:'事件处理',code:code.handler}];
  }
  const sample=item.sample,events=Object.fromEntries((sample.events||[]).map(port=>[port,{type:'registeredAction',port}]));
  return [
    {title:'依赖声明',code:JSON.stringify({manifest:{dependencies:[sample.providerId]}},null,2)},
    ...(sample.ref.startsWith('ui.')?[{title:'界面风格选择',code:'此处预览指定界面包的真实实现。普通公共组件调用会遵循当前模块或全局的界面风格选择；要使用此实现，请在“设置 → 外观与交互 → 界面风格”选择 '+sample.providerId+'。添加依赖不会切换风格。'}]:[]),
    {title:'组件调用',code:`ui.component('${sample.ref}', ${JSON.stringify({props:sample.props||{},slots:sample.slots||{},events},null,2)})`},
    {title:'事件处理',code:"if (event?.type === 'registeredAction') {\n  state.result = {port: event.port, value: event.value};\n}"},
  ];
}
export async function render({state={},event,formValues={},context={}}) {
  state={...defaults(),...state,examples:{...state.examples},modes:{...state.modes},results:{...state.results}};
  state.demoDate=await clock.today();
  const page=context.pageId||'app.ui.examples.page',registered=await registeredExamples(),catalog=[...examples,...registered];
  let pins=[];
  delete state.preferenceError;
  try {pins=await readPins();}catch(error){state.preferenceError='快捷入口暂时不可用：'+error.message;}
  const demoId=page.startsWith('app.ui.examples.demo.')?page.slice('app.ui.examples.demo.'.length):null;
  const current=page===registeredPage?registered.find(item=>item.sample.providerId===context.providerId&&item.ref===context.componentRef):examples.find(item=>item.id===demoId);
  const reset=item=>{
    state.examples[item.id]=initialValue(item);delete state.modes[item.id];delete state.results[item.id];
    if(item.id==='tasks'){state.completed=['done'];state.onlyPending=false;}
    if(item.id==='floating')delete state.floating;
    if(item.id==='progress')delete state.indeterminate;
    if(item.id==='animation'){state.animationVisible=true;state.animationReplay=(state.animationReplay||0)+1;}
  };
  let replaceForms={};
  if(event?.type==='reset'||event?.type==='resetAll')examples.forEach(item=>{reset(item);if('initial'in item)replaceForms[formKey(item.id)]=initialValue(item);});
  if(event?.type==='resetOne'){
    const item=examples.find(item=>item.id===event.id);if(item){reset(item);if('initial'in item)replaceForms[formKey(item.id)]=initialValue(item);}
  }
  if(event?.type==='openDemo'){
    const item=catalog.find(item=>item.id===event.id);
    if(item)await ui.navigate(item.sample?registeredPage:demoPage(item.id),item.sample?{providerId:item.sample.providerId,componentRef:item.ref}:{});
  }
  if(event?.type==='pin') {
    const item=catalog.find(item=>item.id===event.id);
    if(item)try {
      // Read the current persisted list again when acting from a retained page.
      const latest=await readPins(),next=event.remove?latest.filter(id=>id!==item.id):[...new Set([...latest,item.id])];
      pins=await ui.preferences.set(pinnedKey,next);delete state.pinError;
      state.pinNotice=event.remove?'已取消固定':'已固定到首页';
    }catch(error){state.pinError='无法保存快捷入口：'+error.message;}
  }
  if(event?.type==='changeDemo'){state.examples[event.id]=event.value;delete state.results[event.id];}
  if(event?.type==='mode') {
    const item=examples.find(item=>item.id===event.id);
    if(item?.modes?.includes(event.mode)) {
      state.modes[item.id]=event.mode;
      if(event.mode==='默认'||event.mode==='已选') {
        const value=event.mode==='已选'?selectedValue(item,await clock.today()):initialValue(item);
        state.examples[item.id]=value;if('initial'in item)replaceForms[formKey(item.id)]=value;
      }
    }
  }
  if(event?.type==='done')state.completed=event.value?[...new Set([...state.completed,event.id])]:state.completed.filter(id=>id!==event.id);
  if(event?.type==='value')state[event.key]=event.value;
  if(event?.type==='action')state.results[event.id]='已执行：'+(event.action||'本地示例操作');
  if(event?.type==='validate')state.results[event.id]=String(formValues[formKey(event.id)]??state.examples[event.id]??'').trim()?'示例表单已验证':'请输入示例标题';
  if(event?.type==='confirm') {
    const result=await ui.dialog({title:'确认演示操作',fields:[{key:'name',label:'演示名称',value:'本地示例',required:true}]});
    state.results[event.id]=result?'已确认 '+result.name:'已取消演示';
  }
  if(event?.type==='panel')await ui.panel('app.ui.examples.local',{}, {adaptive:true});
  if(event?.type==='composition')await ui.navigate('app.ui.examples.composition');
  if(event?.type==='localAction')state.localAction=event.action;
  if(event?.type==='floating')state.floating=event.visible;
  if(event?.type==='animationEffect'&&['fade','scale','slide'].includes(event.effect))state.examples.animation=event.effect;
  if(event?.type==='replay'){state.animationReplay=(state.animationReplay||0)+1;state.animationVisible=true;}
  if(event?.type==='notify')await ui.notify({message:{info:'这是一条演示消息',success:'演示操作已完成',error:'演示操作失败，请重试'}[event.kind],kind:event.kind,duration:3000});
  if(event?.type==='registeredAction')state.registeredResult={port:event.port,value:event.value??null};
  if(event?.type==='showCode') {
    const sections=current?codeSections(current,state,{...formValues,...replaceForms}):page==='app.ui.examples.local'?[{title:'打开操作面板',code:"await ui.panel('app.ui.examples.local', {}, {adaptive: true});"}]:null;
    if(sections)try {await ui.showCode({title:(current?.title||'操作面板')+' · 调用方式',sections});delete state.codeError;}catch(error){state.codeError='无法显示调用方式：'+error.message;}
  }
  if(page==='app.ui.examples.composition')return {state,tree:column([])};
  if(page==='app.ui.examples.local')return {state,tree:column([
    text('面板内容与局部位置演示','heading'),text('此页面保留当前运行期间的局部滚动位置。','muted'),
    {type:'row',children:['安排明天','稍后处理'].map(action=>button(action,{type:'localAction',action},false,'outlined'))},
    ...(state.localAction?[text('已选择：'+state.localAction)]:[]),...Array.from({length:25},(_,i)=>tile('演示条目 '+(i+1),'本地内容')),
    ...(state.codeError?[text(state.codeError)]:[]),button('查看调用方式',{type:'showCode'},false,'outlined'),
  ])};
  const notices=[...(state.pinError?[text(state.pinError)]:[]),...(state.preferenceError?[text(state.preferenceError,'muted')]:[]),...(state.codeError?[text(state.codeError)]:[])];
  if(page===registeredPage&&!current)return {state,tree:column([text('这个 UI 示例暂时不可用'),text('提供模块可能已停用或移除了示例注册。','muted'),...notices])};
  if(current) {
    const pinned=pins.includes(current.id),forms={...formValues,...replaceForms};
    const children=[text(current.description,'muted'),{type:'row',children:[button(pinned?'取消固定':'固定到首页',{type:'pin',id:current.id,remove:pinned},false,'outlined')]},...notices];
    if(state.pinNotice)children.push(text(state.pinNotice,'muted'));
    if(current.sample) {
      const sample=current.sample,events=Object.fromEntries((sample.events||[]).map(port=>[port,{type:'registeredAction',port}]));
      children.unshift(text(sample.name,'heading'),text('来自 '+sample.providerId,'muted'));
      children.push(group('演示区域',[{type:'componentExample',key:current.id,providerId:sample.providerId,ref:sample.ref,events}]));
      if(state.registeredResult)children.push(text('事件：'+state.registeredResult.port+' · '+JSON.stringify(state.registeredResult.value),'muted'));
    } else {
      const mode=state.modes[current.id]||'默认';
      if(current.modes)children.push({type:'tabs',selectedIndex:current.modes.indexOf(mode),scrollable:true,items:current.modes.map(label=>({label,event:{type:'mode',id:current.id,mode:label}}))});
      children.push(group('演示区域',[control(current,state,forms)]));
      if('initial'in current){const value=demoValue(current,state,forms);children.push(text('当前值：'+(value==null||value===''?'未选择':typeof value==='object'?JSON.stringify(value):String(value)),'muted'));}
      if(state.results[current.id])children.push(text(state.results[current.id]));
      children.push(button('重置此项',{type:'resetOne',id:current.id},false,'text'));
    }
    children.push(button('查看调用方式',{type:'showCode'},false,'outlined'));
    const tree=column(children);
    if(current.id==='floating'&&state.floating)tree.floatingPanel={title:'悬浮窗示例',closeLabel:'关闭悬浮窗',closeEvent:{type:'floating',visible:false},top:16,child:column([text('此内容位于当前页面上方'),button('完成演示',{type:'floating',visible:false})])};
    return {state,...(Object.keys(replaceForms).length?{replaceForms}:{}),tree};
  }
  const search=String(formValues['gallery.search']??'').trim().toLowerCase();
  const visible=catalog.filter(item=>`${item.title} ${item.description} ${item.ref} ${item.sample?.providerId||''}`.toLowerCase().includes(search));
  const children=[ui.component('ui.input@1',{key:'gallery.search',props:{label:'搜索 UI 与动画',inputMode:'search',clearable:true},events:{change:{type:'search'}}}),text(`${examples.length} 个基础演示 · ${registered.length} 个模块注册 UI`,'muted'),...notices];
  const pinnedItems=pins.map(id=>catalog.find(item=>item.id===id)).filter(Boolean);
  if(pinnedItems.length)children.push({type:'sectionHeader',title:'已固定'},...pinnedItems.map(item=>column([tile(item.title,item.sample?item.sample.providerId:item.description,{type:'openDemo',id:item.id}),button('取消固定',{type:'pin',id:item.id,remove:true},false,'text')])));
  for(const [category,label]of categories) {
    const items=visible.filter(item=>item.category===category);
    if(items.length)children.push({type:'sectionHeader',title:label},...items.map(item=>tile(item.title,item.sample?`${item.description}\n${item.sample.providerId}`:item.description,{type:'openDemo',id:item.id})));
  }
  if(!visible.length)children.push(group('没有匹配的示例',[text('尝试清除搜索。'),button('清除搜索',{type:'clearSearch'},false,'outlined')]));
  if(event?.type==='clearSearch')replaceForms['gallery.search']='';
  if(event?.type==='clearSearch')return render({state,formValues:{...formValues,'gallery.search':''},context}).then(result=>({...result,replaceForms:{'gallery.search':''}}));
  // Keep categories flat so the page list builds only visible examples.
  const items={type:'list',scrollKey:'gallery',children};
  if(event?.type==='search')items.scrollRequest=search;
  return {state,...(Object.keys(replaceForms).length?{replaceForms}:{}),tree:{...ui.component('ui.page.list@1',{key:'gallery',slots:{items}}),underlapChrome:true}};
}
