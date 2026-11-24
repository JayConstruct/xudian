import {weekday} from './calendar.js';
import {button} from './page_controls.js';
import {listTile} from './view_helpers.js';

export const weekdayNames=['周一','周二','周三','周四','周五','周六','周日'];
export const shortDate=date=>`${Number(date.slice(5,7))}月${Number(date.slice(8))}日`;
export const lessonDate=date=>shortDate(date)+' · '+weekdayNames[weekday(date)-1];
export const periodLabel=(first,last)=>`第 ${first===last?first:first+'–'+last} 节`;

export const card=(children,padding=0)=>({type:'card',variant:'outlined',padding,children});
export const divider={type:'divider',height:1};
export const divided=rows=>rows.flatMap((row,index)=>index?[divider,row]:[row]);
export const pair=(...children)=>({type:'row',layout:'flex',spacing:10,crossAxisAlignment:'start',children:children.map(child=>({...child,flex:1}))});
export const fixedActions=(...buttons)=>({footerStyle:'edge',footer:pair(...buttons)});
export const action=(label,event,secondary=false)=>({...button(label,event),variant:secondary?'outlined':'filled'});
export const summary=(title,subtitle,icon,badge,muted=false,event)=>({
  ...card([{type:'inset',padding:[0,4,0,4],children:[{type:'row',layout:'flex',spacing:13,children:[
    {type:'icon',icon,surface:true,surfaceSize:45,size:23,tone:'accent'},
    {type:'column',spacing:3,trailingSpacing:false,flex:1,children:[
      {type:'text',text:title,style:'title',weight:'bold'},
      ...(subtitle?[{type:'text',text:subtitle,style:'caption',color:'muted'}]:[]),
    ]},
    ...(badge?[{type:'badge',text:badge,tone:muted?'muted':'accent'}]:[])
  ]}]}],15),
  ...(event?{event}:{})
});
export const section=(title,rows,count)=>({type:'column',spacing:6,trailingSpacing:false,children:[
  {type:'sectionHeader',title,compact:true,...(count?{count,countPosition:'end'}:{})},card(divided(rows))
]});
export const fact=(label,value)=>({type:'inset',padding:[15,11,15,11],children:[{
  type:'row',layout:'flex',spacing:12,children:[
    {type:'text',text:label,style:'body'},
    {type:'text',text:value,style:'body',color:'muted',align:'end',flex:1}
  ]
}]});
export const courseRow=(title,subtitle,icon,event,trailing)=>({
  ...listTile(title,subtitle,icon,event,trailing),iconTone:'muted',iconSurfaceSize:32,minHeight:64,minVerticalPadding:8
});
export const pageResult=(state,title,children,props={})=>({
  state,header:{title,minHeight:72,compact:true,titleStyle:'large'},tree:{type:'column',edgeToEdge:true,trailingSpacing:false,
    children:[{type:'inset',padding:[20,6,20,0],children:[{type:'column',spacing:12,trailingSpacing:false,children}]}],...props}
});
