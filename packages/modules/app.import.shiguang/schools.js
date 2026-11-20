import {adapters,snapshot} from './warehouse/catalog.js';
import {button,card,column,group,heading,input,text,tile} from './ui.js';

export const categories={BACHELOR_AND_ASSOCIATE:'本科／专科',POSTGRADUATE:'研究生',GENERAL_TOOL:'通用教务'};
export const selectedAdapter=state=>adapters.find(a=>a.id===state.adapterId);
function matches(search,kind='all') {
  const terms=String(search).trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
  return adapters.filter(a=>(kind==='all' || (a.category==='GENERAL_TOOL')===(kind==='general')) && terms.every(term=>[a.school,a.name,a.schoolId,a.id,categories[a.category]||a.category].join(' ').toLocaleLowerCase().includes(term)));
}
function paginate(items,page) {
  const pages=Math.max(1,Math.ceil(items.length/30));
  const current=Math.min(pages-1,Math.max(0,Number.isInteger(page)?page:0));
  return {snapshot,total:items.length,page:current,pages,items:items.slice(current*30,(current+1)*30)};
}
export function listAdapters({search='',page=0,kind='all'}={}) {
  return paginate(matches(search,kind),page);
}
export function listSchools({search='',page=0}={}) {
  const groups=new Map();
  for (const adapter of matches(search,'school')) {
    if (!groups.has(adapter.schoolId)) groups.set(adapter.schoolId,{schoolId:adapter.schoolId,school:adapter.school,adapters:[]});
    groups.get(adapter.schoolId).adapters.push(adapter);
  }
  return paginate([...groups.values()],page);
}
export const schoolAdapters=adapter=>adapters.filter(a=>a.schoolId===adapter.schoolId);
export const schoolTitle=school=>school.replace(/\(([^()]*)\)/g,'（$1）');
const systems={zhengfang_01:'正方教务',qingguo_01:'青果教务',urp_01:'URP 教务',chaoxing:'超星教务系统'};
export const systemTitle=adapter=>systems[adapter.id]||adapter.name.replace('html通用获取','').replace('通用获取','');
export function entranceTitle(adapter,variants) {
  if (variants.filter(item=>item.category===adapter.category).length===1) {
    if (adapter.category==='BACHELOR_AND_ASSOCIATE') return '本科教务';
    if (adapter.category==='POSTGRADUATE') return '研究生教务';
  }
  return adapter.name;
}
export function compatibilityNote(adapter) {
  return [
    ...(adapter.features.includes('customTime')?['部分课程可能使用自定义时刻，需准确对应课表节次']:[]),
    ...(adapter.features.includes('comboSchedule')?['含季节或日期作息，目前需进一步适配']:[]),
    ...(adapter.features.includes('jquery')?['需教务页面提供 jQuery']:[]),
  ].join('；');
}
export function schoolPicker(state) {
  const result=listSchools({search:state.schoolSearch,page:state.schoolPage});
  const search=input('schoolSearch','搜索学校名称或缩写',state.schoolSearch||'',{
    inputMode:'search',presentation:'search',clearable:true,onChangeEvent:{type:'searchSchool'},
  });
  if (!result.items.length) return column([
    search,
    {...card({type:'emptyState',icon:'search',iconSurface:true,iconSurfaceSize:46,iconTone:'muted',padding:31,
      title:'没有找到学校',text:'试试学校全名或缩写，也可以选择其他导入方式。'}),padding:0},
    heading('其他导入方式'),
    group(
      tile('通用系统导入',{subtitle:'正方、青果、URP、超星',icon:'importExport',event:{type:'chooseGeneral'}}),
      tile('粘贴学校脚本',{subtitle:'使用已有的完整适配脚本',icon:'code',event:{type:'customScript'}}),
    ),
  ]);
  return column([
    search,
    heading('搜索结果',{count:`${result.total} 所学校`,countPosition:'end',compact:true,...(result.pages>1?{subtitle:`第 ${result.page+1}/${result.pages} 页`}:{})}),
    group(...result.items.map(s=>tile(schoolTitle(s.school),{
      subtitle:s.adapters.length>1?`${s.adapters.length} 个导入入口`:categories[s.adapters[0].category],
      icon:'school',event:{type:'selectSchool',id:s.adapters[0].id},
    }))),
    ...(result.pages>1?[{type:'row',layout:'flex',children:[
      button('上一页','schoolPage','outlined',{flex:1,disabled:result.page===0,event:{type:'schoolPage',page:result.page-1}}),
      button('下一页','schoolPage','outlined',{flex:1,disabled:result.page+1>=result.pages,event:{type:'schoolPage',page:result.page+1}}),
    ]}]:[]),
    heading('其他导入方式'),
    group(tile('找不到学校？',{subtitle:'尝试通用教务系统',icon:'importExport',event:{type:'chooseGeneral'}})),
  ]);
}
export function generalPicker() {
  const order=['正方教务','青果教务','URP 教务','超星教务系统'];
  const available=matches('','general');
  const ordered=[...order.flatMap(title=>available.filter(a=>systemTitle(a)===title)),...available.filter(a=>!order.includes(systemTitle(a)))];
  return column([
    heading('教务系统'),
    group(...ordered.map(a=>tile(systemTitle(a),{icon:'link',event:{type:'selectSchool',id:a.id}}))),
    text('选择学校使用的教务系统，下一步填写教务网址。适配情况取决于教务系统版本。','muted'),
    heading('其他导入方式'),
    group(tile('按学校导入',{icon:'school',event:{type:'chooseSchool'}}),tile('粘贴学校脚本',{icon:'code',event:{type:'customScript'}})),
  ]);
}
