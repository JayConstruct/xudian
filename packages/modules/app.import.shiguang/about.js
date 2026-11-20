import {snapshot} from './warehouse/catalog.js';
import {card,column,group,heading,text,tile} from './ui.js';
export const repository=snapshot.repository;
export const upstreamApp='https://github.com/ShiGuangSchedule/shiguangschedule';
export const projectSources={
  warehouse:{title:'拾光学校适配脚本仓库',url:repository},
  upstream:{title:'拾光课表项目',url:upstreamApp},
  xudian:{title:'序点项目源码',url:'https://github.com/JayConstruct/xudian'},
};
const source=(key,icon,subtitle)=>tile(projectSources[key].title,{icon,subtitle,event:{type:'openSource',source:key}});
const license="MIT License\n\nCopyright (c) 2025 星河欲转\n\nPermission is hereby granted, free of charge, to any person obtaining a copy\nof this software and associated documentation files (the \"Software\"), to deal\nin the Software without restriction, including without limitation the rights\nto use, copy, modify, merge, publish, distribute, sublicense, and/or sell\ncopies of the Software, and to permit persons to whom the Software is\nfurnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all\ncopies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\nIMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\nFITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\nAUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\nLIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\nOUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\nSOFTWARE.\n";
export function aboutPage() {
  return column([
    heading('项目与源码'),
    group(source('warehouse','code','学校与通用系统适配器'),source('upstream','school'),source('xudian','modules')),
    heading('致谢'),
    card(column([
      text('感谢星河欲转及学校适配脚本的作者、维护者和贡献者。'),
      text('每个脚本的维护者与原始地址可在导入详情查看。','muted'),
    ])),
    heading('仓库快照'),
    group(
      tile('学校及通用系统',{trailing:`${snapshot.schools} 个`}),
      tile('适配项',{trailing:`${snapshot.adapters} 个`}),
      tile('快照版本',{trailing:`${snapshot.revision.slice(0,8)}…`,event:{type:'openSource',source:'revision'}}),
    ),
    heading('许可与可用性'),
    card(
      {type:'disclosure',key:'shiguangLicense',text:'MIT 开源许可',subtitle:'查看完整许可正文',icon:'description',children:[{type:'richText',text:license}]},
      text('脚本可用性与学校页面、登录状态和网络有关。','muted'),
    ),
  ]);
}
