import {snapshot} from './warehouse/catalog.js';
export const repository=snapshot.repository;
export const upstreamApp='https://github.com/ShiGuangSchedule/shiguangschedule';
const text=(text,style)=>({type:'text',text,...(style?{style}:{})});
const source=(title,url)=>({type:'card',children:[text(title,'heading'),{type:'richText',text:url}]});
const license="MIT License\n\nCopyright (c) 2025 星河欲转\n\nPermission is hereby granted, free of charge, to any person obtaining a copy\nof this software and associated documentation files (the \"Software\"), to deal\nin the Software without restriction, including without limitation the rights\nto use, copy, modify, merge, publish, distribute, sublicense, and/or sell\ncopies of the Software, and to permit persons to whom the Software is\nfurnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all\ncopies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\nIMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\nFITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\nAUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\nLIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\nOUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\nSOFTWARE.\n";
export function aboutPage() {
  return {type:'column',children:[
    text('拾光教务导入 · 1.4.0','heading'),
    text('基于拾光开源适配脚本，将教务课程采集后转换为序点课表。'),
    text('源码地址','heading'),
    source('拾光学校适配脚本仓库',repository),
    source('拾光课表项目',upstreamApp),
    source('序点项目源码','https://github.com/JayConstruct/xudian'),
    text('长按地址可以复制。','muted'),
    {type:'card',children:[
      text('致谢','heading'),
      text('感谢星河欲转创建拾光课表及适配仓库，感谢所有学校脚本作者、维护者、贡献者和反馈问题的同学。'),
      text('所选脚本的维护者和原始源码地址会显示在导入详情中；原脚本作者注释与许可完整保留。'),
    ]},
    text('仓库快照','heading'),
    text(`${snapshot.schools} 个学校／系统，${snapshot.adapters} 个适配项。脚本随模块版本更新。`),
    {type:'richText',text:snapshot.revision},
    text('可用性说明','heading'),
    text('脚本能否运行取决于学校页面、登录状态和网络。自定义时刻需准确对应课表节次，季节或日期作息仍需适配。采集结果先预览，确认后才保存。'),
    text('开源许可','heading'),
    {type:'richText',text:license},
  ]};
}
