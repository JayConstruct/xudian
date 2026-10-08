import {ui} from '@xudian/sdk';
import {formKey, initialValue, tasks} from './catalog.js';
export const text = (value, style) => ({type:'text', text:value, ...(style ? {style} : {})});
export const button = (label, event, disabled=false, variant='tonal') => ({type:'button',text:label,event,disabled,variant});
export const column = children => ({type:'column',children});
const change = id => ({type:'changeDemo',id});
export function demoValue(item, state, forms) {
  const key = formKey(item.id);
  return Object.prototype.hasOwnProperty.call(forms,key) ? forms[key]
    : Object.prototype.hasOwnProperty.call(state.examples,item.id) ? state.examples[item.id] : initialValue(item);
}
function control(item, state, forms) {
  const id=item.id, value=demoValue(item,state,forms), mode=state.modes[id] || '默认';
  const props={label:item.title,value,disabled:mode==='禁用',clearable:true,
    ...(mode==='错误' ? {errorText:'演示错误：请检查输入值'} : {})};
  const component=(ref,extra={})=>ui.component(ref,{key:formKey(id),props:{...props,...extra},events:{change:change(id)}});
  switch(id) {
    case 'title':return column([component(item.ref),button('验证示例表单',{type:'validate',id},false,'outlined')]);
    case 'notes':return component(item.ref,{multiline:true,minLines:3,maxLines:5});
    case 'number':return component(item.ref,{min:0,max:100});
    case 'search':return component(item.ref,{inputMode:'search',helperText:'只演示输入，不请求网络'});
    case 'priority':return component(item.ref,{items:[{value:0,label:'低优先级'},{value:1,label:'普通优先级'},{value:2,label:'高优先级'}]});
    case 'tags':return component(item.ref,{items:['学习','工作','生活'].map(tag=>({value:tag,label:tag}))});
    case 'toggle':return component(item.ref);
    case 'slider':return component(item.ref,{divisions:10});
    case 'date':case 'datetime':case 'range':return component(item.ref,{minDate:'2020-01-01',maxDate:'2035-12-31'});
    case 'time':return component(item.ref);
    case 'button':return column([
      button('执行示例',{type:'action',id},props.disabled,'filled'),
      button('确认对话框',{type:'confirm',id},props.disabled,'outlined'),
    ]);
    case 'panel':return button('打开操作面板',{type:'panel',id},false,'outlined');
    case 'status':return column([
      {type:'tabs',key:formKey(id),selectedIndex:value,items:['空状态','加载中','错误','成功'].map((label,index)=>({label,event:{...change(id),value:index}}))},
      value===1?{type:'spinner'}:text(value===2?'示例加载失败':value===3?'示例操作成功':'暂无示例内容'),
      ...(value===2?[button('重试示例',{...change(id),value:3},false,'outlined')]:[]),
    ]);
    case 'tasks':return column([
      text(`共 ${tasks.length} 项，已完成 ${state.completed.length} 项`),
      {type:'progress',value:state.completed.length/tasks.length},
      {type:'checkbox',text:'只看未完成',value:state.onlyPending,event:{type:'value',key:'onlyPending'}},
      ...tasks.filter(([key])=>!state.onlyPending||!state.completed.includes(key)).map(([key,title,subtitle])=>column([
        {type:'checkbox',text:title,value:state.completed.includes(key),event:{type:'done',id:key}},text(subtitle,'muted'),
      ])),
      ...(state.onlyPending&&state.completed.length===tasks.length?[text('示例任务已完成，可重置后继续体验。')]:[]),
    ]);
    case 'composition':return button('打开页面槽位示例',{type:'composition'},false,'outlined');
    default:return text('暂无示例');
  }
}
export function exampleCard(item,state,forms) {
  const value=demoValue(item,state,forms),mode=state.modes[item.id]||'默认';
  const formatted=value==null||value===''?'未选择':item.id==='slider'?Math.round(Number(value)*100)+'%':typeof value==='object'?JSON.stringify(value):String(value);
  const instruction = item.id==='datetime' ? '值为本地日期时间 YYYY-MM-DDTHH:mm，不包含时区。'
    : item.id==='range' ? '值为 {start,end} 或 null，起止日均包含。'
    : item.id==='time' ? '值为 HH:mm 或 null。'
    : item.id==='date' ? '值为 YYYY-MM-DD 或 null；允许日期为 2020-01-01 至 2035-12-31。'
    : item.id==='number' ? '编辑原文保存在 formValues，验证通过后可转换为 number。'
    : item.id==='tags' ? 'change 回传完整选中数组，空选为 []。' : '所有操作仅影响本页演示数据。';
  return {type:'card',key:'example-'+item.id,children:[column([
    text(item.title,'heading'),text(item.description,'muted'),
    ...(item.modes ? [{type:'tabs',selectedIndex:item.modes.indexOf(mode),items:item.modes.map(label=>({label,event:{type:'mode',id:item.id,mode:label}}))}] : []),
    control(item,state,forms),
    ...(Object.prototype.hasOwnProperty.call(item,'initial') ? [text('当前值：'+formatted,'muted')] : []),
    ...(state.results[item.id]?[text(state.results[item.id])]:[]),
    {type:'row',children:[button('重置此项',{type:'resetOne',id:item.id},false,'text')]},
    {type:'disclosure',key:'help-'+item.id,text:'使用说明',children:[column([
      text('公共组件：'+item.ref,'muted'),text(instruction,'muted'),
      ...(Object.prototype.hasOwnProperty.call(item,'initial') ? [{type:'richText',text:
        `ui.component('${item.ref}', {\n  key: '${formKey(item.id)}',\n  props: {label: '${item.title}', value: /* 当前值 */},\n  events: {change: {type: 'changeDemo', id: '${item.id}'}}\n})`}] : []),
    ])]},
  ])]};
}
