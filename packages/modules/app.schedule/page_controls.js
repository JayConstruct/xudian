import {listTile} from './view_helpers.js';

export const button=(text,event)=>({type:'button',text,event});
export const text=value=>({type:'text',text:value});
export const field=(key,label,value='',type='text',options)=>({key,label,value,type,...(options?{options}: {})});
export const go=(label,suffix,subtitle,icon='settings')=>listTile(label,subtitle,icon,{type:'navigate',page:suffix});
