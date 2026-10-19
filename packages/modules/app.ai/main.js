import {data,services,ui,http,grants,packages} from '@xudian/sdk';
import {connectionValue,editConnection,chooseModel,connectionTree,requestJson,providerName} from './connection.js';
const ref=id=>({moduleId:'app.ai',serviceId:id,majorVersion:1});
let cancelled=false,requestId=null,currentGrant=null;
const button=(text,event,extra={})=>({type:'button',text,event,variant:'text',...extra});
async function persistUndo(undo) { const plan=await services.prepare(undo.ref,undo.input);if(await ui.review(plan.planId)) return services.commit(plan.planId); }
async function persist(id,input) { const p=await services.prepare(ref(id),input); if(await ui.review(p.planId)) return services.commit(p.planId); }
export async function saveConnection({connection}) {
  const value=connectionValue(connection);
  return {writes:[{collection:'connections',id:'default',value}],events:[],result:{id:'default'}};
}
export async function savePreferences({advanced}) {
  if(typeof advanced!=='boolean') throw new Error('工作模式无效');
  return {writes:[{collection:'preferences',id:'default',value:{id:'default',advanced}}],events:[],result:{advanced}};
}
export async function saveHistory({messages}) {
  if(!Array.isArray(messages)) throw new Error('历史记录无效');
  return {writes:[{collection:'history',id:'conversation',value:{id:'conversation',messages:messages.slice(-100)}}],events:[],result:{id:'conversation'}};
}
export async function cancel() {
  cancelled=true;
  if(requestId) await http.cancel(requestId);
  if(currentGrant) await grants.revoke(currentGrant);
  currentGrant=null;
  return true;
}
function check() { if(cancelled) throw new Error('已取消'); }
function parseBody(response) {
  const message=response?.choices?.[0]?.message;
  if(!message||typeof message!=='object'||!('content' in message||'tool_calls' in message)) throw new Error('模型响应缺少消息');
  return message;
}
async function model(connection,messages,tools) {
  return parseBody(await requestJson(connection,'/chat/completions',
    {model:connection.model,messages,stream:false,...(connection.provider==='cliproxyapi'?{}:{temperature:0.3}),...(tools.length?{tools}: {})},lifecycle));
}
const lifecycle={check,start:id=>{requestId=id;},finish:id=>{if(requestId===id)requestId=null;}};
function undoInput(spec,scope) {
  if(spec&&typeof spec==='object'&&!Array.isArray(spec)) {
    if(spec.when&&!undoInput(spec.when,scope))return undefined;
    if(spec.bind) { let value=scope;for(const key of spec.bind) value=value?.[key];return spec.boolean?!!value:spec.nullIfMissing&&value==null?null:value; }
    if(spec.beforeChangedFields) {
      const changed=scope.input.changes||{},keys=new Set(Object.keys(changed));
      for(const [trigger,fields] of Object.entries(spec.includeWhenChanged||{}))if(trigger in changed)for(const key of fields)keys.add(key);
      return Object.fromEntries([...keys].map(key=>[key,scope.before[key]??null]));
    }
    return Object.fromEntries(Object.entries(spec).map(([key,value])=>[key,undoInput(value,scope)]));
  }
  return spec;
}
function canonical(value) { if(Array.isArray(value)) return '['+value.map(canonical).join(',')+']';if(value&&typeof value==='object') return '{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}';return JSON.stringify(value); }
function proposal(text) {
  const clean=text.trim().replace(/^```(?:json)?\s*/,'').replace(/\s*```$/,'');
  const v=JSON.parse(clean);
  if(!v.definition||!v.files) throw new Error('高级模式需输出 definition 和 files');
  return v;
}
export async function render({state={},event,formValues={},context={}}) {
  state={...state}; let sent=false;
  let connection=await data.get('connections','default');
  let messages=(await data.get('history','conversation'))?.messages || state.messages || [];
  const preferences=await data.get('preferences','default');
  state.advanced=preferences?.advanced ?? state.advanced ?? false;
  if(event?.type==='settings') await ui.navigate('app.ai.settings');
  if(event?.type==='configure') {
    state.connectionSettings=true;
  }
  if(event?.type==='connectionBack') state.connectionSettings=false;
  if(['configureCliProxy','configureOpenAi','configureService','configureCurrent','chooseModel','testConnection'].includes(event?.type)) {
    state.connectionSettings=true;cancelled=false;delete state.connectionStatus;
    try {
      const save=input=>persist('ai.connection.save',input);
      if(['configureCliProxy','configureOpenAi','configureService','configureCurrent'].includes(event.type)) {
        let provider=event.type==='configureCliProxy'?'cliproxyapi':event.type==='configureCurrent'?(connection?.provider||'openai'):'openai';
        if(event.type==='configureService') {
          const values=await ui.dialog({title:'模型服务',fields:[{key:'provider',label:'服务类型',type:'select',required:true,value:connection?.provider||'openai',options:[{value:'openai',label:'OpenAI 兼容服务'},{value:'cliproxyapi',label:'CLIProxyAPI'}]}]});
          provider=values?.provider;
        }
        if(provider && await editConnection(connection,provider,save)) state.connectionStatus='连接已保存，可获取模型并测试连接';
      } else {
        if(!connection?.endpoint) throw new Error('请先接入模型服务');
        if(event.type==='chooseModel') {
          if(await chooseModel(connection,lifecycle,save)) state.connectionStatus='模型已保存，可测试连接或返回对话';
        } else {
          if(!connection.model) throw new Error('请先获取并选择模型，或手动填写模型 ID');
          const reply=await model(connection,[{role:'user',content:'请只回复 OK。'}],[]);
          if(typeof reply.content!=='string'||!reply.content.trim()) throw new Error('服务未返回文字回复，请检查所选模型是否支持聊天');
          state.connectionStatus=`连接成功：${providerName(connection)} · ${connection.model} 已返回聊天回复`;
        }
      }
    } catch(error) {
      state.connectionStatus=cancelled?'已取消连接操作':error.message||'无法连接服务，请检查地址、端口转发和服务状态';
    }
    connection=await data.get('connections','default');
  }
  if(state.connectionSettings) return {state,header:{title:'模型连接',backEvent:{type:'connectionBack'}},tree:connectionTree(connection,state.connectionStatus)};
  if(event?.type==='advanced') {
    const values=await ui.dialog({title:'工作模式',fields:[{key:'mode',label:'模式',type:'select',value:state.advanced?'advanced':'chat',required:true,options:[{value:'chat',label:'普通聊天'},{value:'advanced',label:'高级模块开发'}]}]});
    if(values) {
      await persist('ai.preferences.save',{advanced:values.mode==='advanced'});
      state.advanced=(await data.get('preferences','default'))?.advanced ?? state.advanced;
    }
  }
  if(event?.type==='undo'&&state.lastUndo) {
    await persistUndo(state.lastUndo); delete state.lastUndo;
  }
  if(event?.type==='clear' && await persist('ai.history.save',{messages:[]})) { messages=[]; state.messages=[]; }
  if(event?.type==='installSource') {
    const p=await packages.prepare(proposal(formValues.moduleSource||state.moduleSource||''));
    await packages.review(p.id);
  }
  if(event?.type==='send') {
    if(!connection?.endpoint||!connection.model) throw new Error('请先配置 AI 连接');
    const text=(formValues.message||event.value||'').trim(); if(!text) throw new Error('请输入消息');
    cancelled=false;
    const directory=await services.directory(),toolServices=directory.filter(s=>s.tool&&s.moduleId!=='app.ai');
    const modelTools=toolServices.map((s,i)=>({type:'function',function:{name:`service_${i}`,description:s.tool.description||s.id,parameters:s.input}}));
    const system=state.advanced?
      '你为序点生成可安装的 JavaScript 模块。只输出 JSON {definition, files}。definition: formatVersion=3, manifest含id、name、version（三段数字）、hostApi="^1.0.0"、dataVersion=1、permissions、dependencies。entryPoint="main.js"，collections是{id,schema}数组，pages是{id,title,handler,entry:{id,opening:"workspace",placement:"main"}}数组，services是{id,major:1,handler,kind:"query"或"command",input:JSON Schema,output:JSON Schema}数组。files映射main.js等路径到JavaScript源码。仅可import包内文件和@xudian/sdk。SDK有data.get/query、services.query/prepare/commit、ui.dialog/review、clock.today/now、ids.new。命令返回{writes:[{collection,id,value}],events:[],result}，写入仅本模块集合。render({state,event,context,formValues})返回{state,tree}，tree是column,row,text,card,button,input,list,timeGrid等组件。button包含text和event对象，input包含key和text。高级更新必须增加版本。不要读取系统或联网。已启用服务目录：'+JSON.stringify(directory):
      '你是序点助手。只通过已提供服务工具查询和准备变更。不得虚构已完成操作。工具调用受宿主授权和变更确认。没有任务或课表工具时继续普通聊天。';
    const conversation=[{role:'system',content:system},...messages.slice(-40),{role:'user',content:text}];
    const cache=new Map(),toolsSeen=new Map(); let calls=0,writes=0,reply='';
    for(let round=0;round<8;round++) {
      check(); const message=await model(connection,conversation,state.advanced?[]:modelTools); conversation.push(message);
      if(!message.tool_calls?.length) { reply=typeof message.content==='string'?message.content:''; break; }
      if(state.advanced) throw new Error('高级模块生成不允许调用业务工具');
      for(const call of message.tool_calls) {
        if(++calls>24) throw new Error('已达到24次工具调用限制');
        check(); const index=Number((call.function?.name||'').replace('service_','')),service=toolServices[index];
        if(!service) throw new Error('模型请求了未知工具');
        const input=JSON.parse(call.function.arguments||'{}'),fingerprint=canonical([service.moduleId,service.id,input]);
        if(toolsSeen.has(call.id)&&toolsSeen.get(call.id)!==fingerprint) throw new Error('工具调用ID内容变化');
        toolsSeen.set(call.id,fingerprint);
        let result;
        if(cache.has(fingerprint)) result=cache.get(fingerprint);
        else {
          if(!currentGrant) {
            const grant=await grants.request({scopes:toolServices.map(s=>`${s.moduleId}/${s.id}@${s.major}`)});
            if(!grant) throw new Error('未获得工具授权'); currentGrant=grant.id;
          }
          const target={moduleId:service.moduleId,serviceId:service.id,majorVersion:service.major};
          if(service.kind==='query') result=await services.query(target,input);
          else {
            if(++writes>20) throw new Error('本次授权最多20次写入');
            const plan=await services.prepare(target,input);
            if(await ui.review(plan.planId)) { check(); result=await services.commit(plan.planId);
              if(result?.navigate) await ui.navigate(result.navigate);
              if(service.tool.undo&&plan.writes.length===1&&plan.writes[0].before) state.lastUndo={ref:{...target,serviceId:service.tool.undo.serviceId},input:undoInput(service.tool.undo.input,{input,result,before:plan.writes[0].before})};
            }
            else result={cancelled:true};
          }
          cache.set(fingerprint,result);
        }
        conversation.push({role:'tool',tool_call_id:call.id,content:JSON.stringify(result)});
      }
      if(round===7) throw new Error('已达到8轮模型调用限制');
    }
    messages=[...messages,{role:'user',content:text},{role:'assistant',content:reply}]; state.messages=messages;
    await persist('ai.history.save',{messages});
    sent=true;
    if(state.advanced) { state.moduleSource=JSON.stringify(proposal(reply),null,2); const p=await packages.prepare(proposal(reply)); await packages.review(p.id); }
  }
  if(context.aiSettings) return {state,header:{title:'AI 设置'},tree:{type:'column',compact:true,spacing:8,children:[
    {type:'text',text:'模型与连接',style:'muted'},
    {type:'card',children:[{type:'listTile',icon:'link',title:'模型连接',subtitle:connection?.model?`${providerName(connection)} · ${connection.model}`:'配置模型服务与密钥',event:{type:'configure'}}]},
    {type:'text',text:'对话',style:'muted'},
    {type:'card',children:[
      {type:'listTile',icon:'ai',title:'工作模式',subtitle:state.advanced?'高级模块开发':'普通聊天',event:{type:'advanced'}},
      {type:'divider'},
      {type:'listTile',icon:'delete',title:'清空对话记录',subtitle:'清除本机历史，保留连接配置',event:{type:'clear'}}
    ]}
  ]}};
  const children=[];
  if(!messages.length) children.push({type:'card',children:[
    {type:'text',text:state.advanced?'描述要生成或更新的模块':'有什么需要我帮忙的？',style:'heading'},
    {type:'text',text:connection?.model?'可以直接聊天，或让我协助查看任务与安排。':'点击右上角设置，连接模型后开始对话。',style:'muted'}
  ]});
  if(state.lastUndo) children.push(button('撤销上次操作',{type:'undo'}));
  for(const [index,message] of messages.entries()) children.push({type:'chatMessage',key:`message:${index}`,role:message.role,label:message.role==='user'?'你':'AI 助手',text:message.content});
  const footer={type:'messageComposer',key:'message',text:state.advanced?'描述要生成或更新的模块…':'输入消息…',event:{type:'send'},interrupt:'cancel'};
  if(state.advanced) children.push({type:'disclosure',key:'moduleSourceSection',text:'模块源码',children:[{type:'sourceEditor',key:'moduleSource',text:'模块 definition 与源码 JSON',value:state.moduleSource||'',multiline:true},button('审核并安装源码',{type:'installSource'})]});
  return {state,clearForms:sent?['message']:[],replaceForms:state.advanced?{moduleSource:state.moduleSource||''}:{},tree:{type:'column',compact:true,spacing:12,followEnd:messages.length,header:{type:'pageHeader',title:'AI 助手',subtitle:connection?.model?`${state.advanced?'高级模式':'普通聊天'} · ${connection.model}`:'尚未配置模型',actions:[{icon:'settings',label:'AI 设置',event:{type:'settings'}}]},children,footer}};
}
export async function renderSettings(args) {
  return render({...args,context:{...args.context,aiSettings:true}});
}
