import {adapters,snapshot} from './warehouse/catalog.js';

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
export function compatibilityNote(adapter) {
  return [
    ...(adapter.features.includes('customTime')?['部分课程可能使用自定义时刻，需准确对应课表节次']:[]),
    ...(adapter.features.includes('comboSchedule')?['含季节或日期作息，目前需进一步适配']:[]),
    ...(adapter.features.includes('jquery')?['需教务页面提供 jQuery']:[]),
  ].join('；');
}
export function schoolPicker(state) {
  const result=listSchools({search:state.schoolSearch,page:state.schoolPage});
  return {type:'column',children:[
    ...(state.error?[{type:'text',text:state.error}]:[]),
    {type:'input',key:'schoolSearch',text:'搜索学校名称或缩写',inputMode:'search',clearable:true,value:state.schoolSearch||'',onChangeEvent:{type:'searchSchool'}},
    {type:'text',text:`找到 ${result.total} 所学校 · 第 ${result.page+1}/${result.pages} 页`,style:'muted'},
    ...(result.items.length?result.items.map(s=>({
      type:'listTile',title:s.school,icon:'school',
      subtitle:s.adapters.length>1?`${s.adapters.length} 个导入入口`:categories[s.adapters[0].category],
      event:{type:'selectSchool',id:s.adapters[0].id},
    })):[{type:'card',children:[
      {type:'text',text:'没有找到学校',style:'heading'},
      {type:'text',text:'可以换用学校全名或缩写搜索；也可以尝试正方、青果、URP、超星等通用脚本。'},
      {type:'button',text:'尝试通用系统导入',event:{type:'chooseGeneral'}},
      {type:'button',text:'粘贴学校脚本',event:{type:'customScript'}},
    ]}]),
    ...(result.pages>1?[{
      type:'row',children:[
        {type:'button',text:'上一页',disabled:result.page===0,event:{type:'schoolPage',page:result.page-1}},
        {type:'button',text:'下一页',disabled:result.page+1>=result.pages,event:{type:'schoolPage',page:result.page+1}},
      ],
    }]:[]),
    ...(result.items.length?[{type:'listTile',title:'找不到学校？',subtitle:'尝试通用教务系统脚本',icon:'importExport',event:{type:'chooseGeneral'}}]:[]),
  ]};
}
export function generalPicker() {
  return {type:'column',children:[
    {type:'text',text:'根据学校使用的教务系统选择脚本。具体说明和网址在下一页填写。'},
    ...matches('','general').map(a=>({type:'listTile',title:a.name.replace('html通用获取','').replace('通用获取',''),icon:'importExport',event:{type:'selectSchool',id:a.id}})),
    {type:'text',text:'通用脚本适用于对应系统的部分版本；如果不匹配，可按学校导入或粘贴学校脚本。',style:'muted'},
    {type:'row',children:[
      {type:'button',text:'按学校导入',event:{type:'chooseSchool'}},
      {type:'button',text:'粘贴学校脚本',event:{type:'customScript'}},
    ]},
  ]};
}
