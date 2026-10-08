import {ui} from '@xudian/sdk';
import {categories,examples,formKey,initialValue} from './catalog.js';
import {button,column,exampleCard,text} from './examples.js';
const defaults=()=>({section:'all',completed:['done'],onlyPending:false,examples:{},modes:{},results:{}});
export async function render({state={},event,formValues={},context={}}) {
  if(context.pageId==='app.ui.examples.composition')return {state,tree:{type:'column',children:[]}};
  if(context.pageId==='app.ui.examples.local')return {state,tree:column([
    text('此页面声明保留滚动位置，仅当前运行期间有效'),
    {type:'row',children:['安排明天','稍后处理'].map(action=>button(action,{type:'localAction',action},false,'outlined'))},
    ...(state.localAction?[text('已选择“'+state.localAction+'”示例')]:[]),
    ...Array.from({length:25},(_,i)=>text('演示条目 '+(i+1))),
  ])};
  state={...defaults(),...state,examples:{...state.examples},modes:{...state.modes},results:{...state.results}};
  let replaceForms={};
  const reset=item=>{
    state.examples[item.id]=initialValue(item);delete state.modes[item.id];delete state.results[item.id];
    if(Object.prototype.hasOwnProperty.call(item,'initial'))replaceForms[formKey(item.id)]=initialValue(item);
    if(item.id==='tasks'){state.completed=['done'];state.onlyPending=false;}
  };
  if(event?.type==='reset'||event?.type==='resetAll')examples.forEach(reset);
  if(event?.type==='resetOne'){const item=examples.find(item=>item.id===event.id);if(item)reset(item);}
  if(event?.type==='section')state.section=event.section;
  if(event?.type==='changeDemo'){state.examples[event.id]=event.value;delete state.results[event.id];}
  if(event?.type==='mode'){
    const item=examples.find(item=>item.id===event.id);
    if(item?.modes?.includes(event.mode)){
      state.modes[item.id]=event.mode;
      if(event.mode==='已选'||event.mode==='默认'){
        const value=event.mode==='已选'?item.selected:initialValue(item);
        state.examples[item.id]=value;replaceForms[formKey(item.id)]=value;
      }
    }
  }
  if(event?.type==='done')state.completed=event.value?[...new Set([...state.completed,event.id])]:state.completed.filter(id=>id!==event.id);
  if(event?.type==='value')state[event.key]=event.value;
  if(event?.type==='action')state.results[event.id]='已执行本地示例操作';
  if(event?.type==='validate')state.results[event.id]=(formValues[formKey(event.id)]??state.examples[event.id]??'').trim()?'示例表单已验证，未写入真实任务。':'请输入示例标题';
  if(event?.type==='confirm'){
    const result=await ui.dialog({title:'确认演示操作',fields:[{key:'name',label:'演示名称',value:'本地示例'}]});
    if(result)state.results[event.id]='已确认 '+result.name;
  }
  if(event?.type==='panel')await ui.panel('app.ui.examples.local',{}, {adaptive:true});
  if(event?.type==='composition')await ui.navigate('app.ui.examples.composition');
  if(event?.type==='localAction')state.localAction=event.action;
  const search=String(formValues['gallery.search']??'').trim().toLowerCase();
  const selected=categories.some(([id])=>id===state.section)?state.section:'all';
  const visible=examples.filter(item=>(selected==='all'||item.category===selected)&&
    `${item.title} ${item.description} ${item.ref}`.toLowerCase().includes(search));
  const filters={type:'inset',children:[column([
    ui.component('ui.input@1',{key:'gallery.search',props:{label:'搜索组件',inputMode:'search',clearable:true},events:{change:{type:'search'}}}),
    {type:'row',children:[text(`${visible.length} 个示例 · 仅使用演示数据`,'muted'),button('重置全部',{type:'resetAll'},false,'text')]},
    {type:'tabs',key:'gallery.categories',scrollable:true,selectedIndex:categories.findIndex(([id])=>id===selected),items:categories.map(([section,label])=>({label,event:{type:'section',section}}))},
  ])]};
  const items=visible.length?[{type:'grid',children:visible.map(item=>exampleCard(item,state,{...formValues,...replaceForms}))}]
    :[column([text('没有匹配的组件'),text('尝试清除搜索或切换分类。','muted'),button('清除搜索／查看全部',{type:'clearSearch'},false,'outlined')])];
  if(event?.type==='clearSearch')return render({state:{...state,section:'all'},formValues:{...formValues,'gallery.search':''},context,event:{type:'clearedSearch'}})
    .then(result=>({...result,replaceForms:{'gallery.search':''}}));
  return {state,...(Object.keys(replaceForms).length?{replaceForms}:{}),tree:ui.component('ui.page.list@1',{
    key:'ui-gallery',slots:{filters,items:{type:'list',scrollKey:selected+(search?':search':''),scrollRequest:search||null,children:items}},
  })};
}
