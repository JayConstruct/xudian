import {ui,http,secrets,ids} from '@xudian/sdk';

export const providerName=connection=>connection?.provider==='cliproxyapi'?'CLIProxyAPI':'OpenAI 兼容接口';

export function apiBase(value) {
  const match=typeof value==='string'&&value.trim().match(/^(https?):\/\/(\[[0-9a-f:]+\]|[a-z0-9.-]+)(:\d{1,5})?(\/[^?#\s]*)?$/i);
  if(!match) throw new Error('请输入服务地址，不要包含密钥、查询参数或片段');
  const scheme=match[1].toLowerCase(),host=match[2].toLowerCase(),port=match[3]||'';
  if(port&&(Number(port.slice(1))<1||Number(port.slice(1))>65535)) throw new Error('服务端口无效');
  if(scheme!=='https'&& !['localhost','127.0.0.1','[::1]'].includes(host)) throw new Error('远程服务请使用 HTTPS；本机地址可使用 HTTP');
  let path=(match[4]||'').replace(/\/+$/,'').replace(/\/(chat\/completions|models)$/,'');
  if(!path) path='/v1';
  return `${scheme}://${host}${port}${path}`;
}

export function connectionValue(connection) {
  if(!connection||typeof connection.model!=='string'||typeof connection.credential!=='string'||!connection.credential) throw new Error('请配置服务地址和 API Key');
  const provider=connection.provider||'openai';
  if(!['openai','cliproxyapi'].includes(provider)) throw new Error('不支持的模型服务');
  return {id:'default',provider,endpoint:apiBase(connection.endpoint),model:connection.model.trim(),credential:connection.credential};
}

export async function editConnection(previous,provider,persist) {
  const same=previous&&(previous.provider||'openai')===provider;
  const values=await ui.dialog({title:providerName({provider}),fields:[
    {key:'endpoint',label:'服务地址',value:same?previous.endpoint:provider==='cliproxyapi'?'http://127.0.0.1:8317/v1':'',required:true,maxLength:2048},
    {key:'model',label:'模型 ID（可留空，保存后获取模型）',value:same?previous.model:'',maxLength:256},
    {key:'keyMode',label:'API Key',type:'select',value:same&&previous.credential?'keep':'replace',required:true,options:[
      ...(same&&previous.credential?[{value:'keep',label:'保留已保存的密钥（地址不变）'}]:[]),
      {value:'replace',label:'输入新的客户端 API Key'}
    ]}
  ]});
  if(!values) return false;
  const endpoint=apiBase(values.endpoint);
  let credential=previous?.credential,newCredential=null,saved=false;
  if(values.keyMode==='keep') {
    if(!same||!credential||endpoint!==previous.endpoint.replace(/\/+$/,'')) throw new Error('地址已变化，请选择输入新的 API Key');
  } else {
    newCredential=await secrets.configure({endpoint,label:`${providerName({provider})} 客户端 API Key`});
    if(!newCredential) return false;
    credential=newCredential;
  }
  try {
    saved=!!await persist({connection:connectionValue({provider,endpoint,model:values.model||'',credential})});
  } finally {
    if(newCredential&&!saved) await secrets.delete(newCredential);
  }
  if(saved&&previous?.credential&&previous.credential!==credential) await secrets.delete(previous.credential);
  return saved;
}

export function httpError(status) {
  const hint=status===401||status===403?'请检查客户端 API Key（不是管理密钥）':status===404?'请检查服务地址和模型 ID':status===429?'额度或请求频率受限，请稍后重试':status>=500?'代理或上游服务暂时不可用，请检查服务状态':'请检查服务配置';
  return `模型服务请求失败（HTTP ${status}）：${hint}`;
}

export async function requestJson(connection,path,body,lifecycle) {
  lifecycle.check();
  const id=await ids.new();lifecycle.start(id);
  try {
    const response=await http.request({id,url:apiBase(connection.endpoint)+path,method:body?'POST':'GET',credential:connection.credential,...(body?{body}:{})});
    lifecycle.check();
    if(response.status<200||response.status>=300) throw new Error(httpError(response.status));
    try { return JSON.parse(response.body); } catch { throw new Error('模型服务返回的内容不是 JSON'); }
  } finally { lifecycle.finish(id); }
}

export async function chooseModel(connection,lifecycle,persist) {
  const response=await requestJson(connection,'/models',null,lifecycle);
  if(!Array.isArray(response?.data)) throw new Error('模型列表格式无效，需要 OpenAI 兼容的 data 数组');
  const models=[...new Set(response.data.filter(v=>v&&typeof v.id==='string'&&v.id.trim()).map(v=>v.id))].sort();
  if(!models.length) throw new Error('服务未返回可用模型，请先在 CLIProxyAPI 中配置上游账号或手动填写模型 ID');
  const values=await ui.dialog({title:'选择模型',fields:[{key:'model',label:'可用模型',type:'select',value:models.includes(connection.model)?connection.model:models[0],required:true,options:models.map(value=>({value,label:value}))}]});
  lifecycle.check();
  if(!values) return false;
  if(!models.includes(values.model)) throw new Error('请选择服务返回的模型');
  return !!await persist({connection:{...connection,model:values.model}});
}

export function connectionTree(connection,status) {
  const button=(text,type,extra={})=>({type:'button',text,event:{type},variant:'text',...extra});
  const children=[
    {type:'card',children:[{type:'listTile',icon:'link',title:connection?providerName(connection):'选择模型服务',subtitle:'支持 OpenAI 兼容接口与 CLIProxyAPI',event:{type:'configureService'}}]},
    {type:'card',children:[
      {type:'listTile',title:'接口地址',subtitle:connection?.endpoint||'尚未配置',event:{type:'configureCurrent'}},
      {type:'divider'},
      {type:'listTile',title:'API Key',subtitle:connection?.credential?'已安全保存 · 点击更换':'尚未配置',event:{type:'configureCurrent'}},
      {type:'divider'},
      {type:'listTile',title:'模型',subtitle:connection?.model||'保存连接后获取并选择',...(connection?{event:{type:'chooseModel'}}:{})}
    ]},
    {type:'text',text:'密钥保存在系统安全存储，模块无法读取密钥正文。',style:'muted'}
  ];
  if(connection) children.push({type:'row',children:[button('获取并选择模型','chooseModel'),button('测试连接','testConnection',{variant:'outlined'})]});
  if(status) children.push({type:'text',text:status,style:'muted'});
  children.push(button(connection?'编辑连接':'配置连接','configureCurrent',{variant:'filled'}));
  children.push({type:'disclosure',text:'连接帮助',children:[
    {type:'text',text:'支持服务根地址、/v1 地址或完整聊天地址。CLIProxyAPI 默认端口 8317，请填写客户端 API Key。模型 ID 以服务返回的列表为准。',style:'muted'},
    {type:'text',text:'远程服务使用 HTTPS。本机代理可用 HTTP；Android 的 127.0.0.1 指向设备自身，连接电脑上的代理需要先转发端口。',style:'muted'},
    button('取消当前操作','cancel',{interrupt:'cancel'})
  ]});
  return {type:'column',compact:true,spacing:8,children};
}
