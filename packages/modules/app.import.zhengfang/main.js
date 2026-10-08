import {services,ui,browser} from '@xudian/sdk';
import script from './adapter.js';

// School adapters own their parser and browser permission. Shared bridge and
// import workflow remain in app.import.shiguang; no schedule write permission.
export async function render({state={},event,formValues={}}) {
  if (event?.type==='browser') {
    delete state.error;
    try {
      state.url=String(formValues.url||state.url||'').trim();
      const compiled=await services.query({moduleId:'app.import.shiguang',serviceId:'shiguang.bridge.compile',majorVersion:1},{script,bridgeVersion:1});
      const payload=await browser.capture({url:state.url,script:compiled.script});
      if (payload!=null) {
        await ui.navigate('app.import.shiguang.home',{shiguangImport:{version:1,payload}});
        state.notice='已打开导入配置与预览';
      }
    } catch(error) {state.error=error.message;}
  }
  return {state,tree:{type:'column',children:[
    {type:'text',text:'正方教务导入（通用）'},
    {type:'text',text:'登录教务系统，进入个人课表并选择学期，再执行采集。适用于含 jQuery 的正方表格或列表页面。'},
    {type:'input',key:'url',text:'教务登录网址',inputMode:'url',value:state.url||''},
    {type:'button',text:'打开教务浏览器',event:{type:'browser'}},
    ...(state.error?[{type:'text',text:'无法继续：'+state.error}]:[]),
    ...(state.notice?[{type:'text',text:state.notice}]:[]),
  ]}};
}
