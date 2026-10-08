import {data,services,ui,http,secrets,grants,packages,clock,ids} from '@xudian/sdk';
const ref=id=>({moduleId:'app.ai',serviceId:id,majorVersion:1});
let cancelled=false,requestId=null,currentGrant=null;
const button=(text,event,extra={})=>({type:'button',text,event,...extra});
async function persistUndo(undo) { const plan=await services.prepare(undo.ref,undo.input);if(await ui.review(plan.planId)) return services.commit(plan.planId); }
async function persist(id,input) { const p=await services.prepare(ref(id),input); if(await ui.review(p.planId)) return services.commit(p.planId); }
export async function saveConnection({connection}) {
  if(typeof connection.endpoint!=='string'||typeof connection.model!=='string'||!connection.model.trim()) throw new Error('连接地址和模型不能为空');
  const value={...connection,id:'default'};
  return {writes:[{collection:'connections',id:'default',value}],events:[],result:{id:'default'}};
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
function parseBody(body) {
  let response;
  try { response=JSON.parse(body); } catch { throw new Error('模型服务返回的内容不是 JSON'); }
  const message=response.choices?.[0]?.message;
  if(!message||typeof message!=='object'||!('content' in message||'tool_calls' in message)) throw new Error('模型响应缺少消息');
  return message;
}
async function model(connection,messages,tools) {
  check(); requestId=await ids.new();
  const base=connection.endpoint.replace(/\/$/,'');
  const url=base.endsWith('/chat/completions')?base:base+'/chat/completions';
  const response=await http.request({id:requestId,url,method:'POST',credential:connection.credential,
    body:{model:connection.model,messages,temperature:0.3,...(tools.length?{tools}: {})}});
  requestId=null; check();
  if(response.status<200||response.status>=300) throw new Error(`模型服务请求失败（HTTP ${response.status}）`);
  return parseBody(response.body);
}
function undoInput(spec,scope) {
  if(spec&&typeof spec==='object'&&!Array.isArray(spec)) {
    if(spec.bind) { let value=scope;for(const key of spec.bind) value=value?.[key];return spec.boolean?!!value:value; }
    if(spec.beforeChangedFields) return Object.fromEntries(Object.keys(scope.input.changes||{}).map(key=>[key,scope.before[key]]));
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
export async function render({state={},event,formValues={}}) {
  state={...state}; let sent=false;
  let connection=await data.get('connections','default');
  let messages=state.messages || (await data.get('history','conversation'))?.messages || [];
  if(event?.type==='configure') {
    const values=await ui.dialog({title:'AI 连接',fields:[{key:'endpoint',label:'HTTPS 或本机 HTTP 地址',value:connection?.endpoint||''},{key:'model',label:'模型名称',value:connection?.model||''}]});
    if(values) {
      const credential=await secrets.configure({endpoint:values.endpoint,label:'AI API Key'});
      if(credential) { await persist('ai.connection.save',{connection:{...values,credential}}); connection=await data.get('connections','default'); }
    }
  }
  if(event?.type==='advanced') state.advanced=!state.advanced;
  if(event?.type==='undo'&&state.lastUndo) {
    await persistUndo(state.lastUndo); delete state.lastUndo;
  }
  if(event?.type==='clear') { messages=[]; state.messages=[]; await persist('ai.history.save',{messages}); }
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
  const children=[{type:'row',children:[button('模型连接',{type:'configure'}),button(state.advanced?'切换普通聊天':'高级模块开发',{type:'advanced'}),button('清空历史',{type:'clear'}),button('取消当前操作',{type:'cancel'},{interrupt:'cancel'})]}];
  if(state.lastUndo) children.push(button('撤销上次操作（校验当前状态）',{type:'undo'}));
  for(const message of messages) children.push({type:'card',children:[{type:'text',text:message.role==='user'?'你':'AI'},{type:'richText',text:message.content}]});
  const footer={type:'column',children:[{type:'input',key:'message',text:state.advanced?'描述要生成或更新的模块':'输入消息',multiline:true,minLines:1,maxLines:5,event:{type:'send'}},button('发送',{type:'send'})]};
  if(state.advanced) children.push({type:'sourceEditor',key:'moduleSource',text:'模块 definition 与源码 JSON',value:state.moduleSource||'',multiline:true},button('审核并安装源码',{type:'installSource'}));
  return {state,clearForms:sent?['message']:[],replaceForms:state.advanced?{moduleSource:state.moduleSource||''}:{},tree:{type:'column',children,footer}};
}
