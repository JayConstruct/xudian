export const text=(text,style='body')=>({type:'text',text,style});
export const column=(children,options={})=>({type:'column',compact:true,spacing:10,trailingSpacing:false,children,...options});
export const heading=(title,options={})=>({type:'sectionHeader',title,...options});
export const tile=(title,{subtitle,icon,event,trailing,selected}={})=>({
  type:'listTile',title,subtitle,icon,...(icon?{iconTone:'muted'}:{}),event,trailing,selected,
});
export const group=(...rows)=>({type:'card',children:rows.flatMap((row,index)=>index?[{type:'divider',height:1},row]:[row])});
export const card=(...children)=>({type:'card',variant:'outlined',children});
export const button=(text,type,variant='outlined',options={})=>({type:'button',text,variant,event:{type},...options});
export const footer=(text,type)=>button(text,type,'filled');
export const input=(key,text,value,options={})=>({type:'input',key,text,value,...options});
