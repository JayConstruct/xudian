// Bridge compatibility stays in the adapter; the native browser only transports JSON.
export function captureScript(adapter) {
  // Resolve named validators in the adapter's own scope, including when the
  // host executes the full capture through new Function instead of global eval.
  return '(function(){\n('+installBridge.toString()+')(expression=>eval(expression));\n'+adapter+'\n})();';
}
// Pure service for independent adapter modules. This does not run the script.
export function compileBridge({script,bridgeVersion=1}={}) {
  if (bridgeVersion!==1) throw new Error('不支持的拾光桥接版本');
  if (typeof script!=='string' || !script.trim()) throw new Error('学校适配脚本不能为空');
  const wrapped=captureScript(script);
  let bytes=0;
  for (const char of wrapped) {
    const code=char.codePointAt(0);
    bytes+=code<=0x7f?1:code<=0x7ff?2:code<=0xffff?3:4;
  }
  if (bytes>256*1024) throw new Error('桥接与学校脚本合计超过256 KiB');
  return {bridgeVersion:1,script:wrapped};
}
function installBridge(resolveValidator) {
  const captured={courses:[],timeSlots:[],config:null,comboSchedule:null};
  let failed=false,finished=false;
  const parse=value=>typeof value==='string'?JSON.parse(value):JSON.parse(JSON.stringify(value));
  const transport=window.xudianCapture;
  const send=(type,value)=>transport.send(type,value);
  const stage=async (key,value,array)=>{
    try {
      const parsed=parse(value);
      if (array?!Array.isArray(parsed):(!parsed||typeof parsed!=='object'||Array.isArray(parsed))) throw new Error('导入数据类型无效');
      captured[key]=parsed;
      return true;
    } catch(error) {failed=true;throw error;}
  };
  const promise={
    showAlert:async (title,content,confirm)=>window.confirm(String(title)+'\n'+String(content)+(confirm?'\n'+confirm:'')),
    showPrompt:async (title,tip,initial='',validator)=>{
      for (;;) {
        const value=window.prompt(String(title)+'\n'+String(tip),String(initial));
        if (value===null) return null;
        if (!validator) return value;
        const validate=typeof validator==='function'?validator:resolveValidator('('+validator+')');
        if (typeof validate!=='function') throw new Error('输入校验器需为函数');
        const error=await validate(value);
        if (error===false || error===undefined || error===null || error==='' || error==='false') return value;
        window.alert(typeof error==='string'?error:'输入无效，请重新输入');initial=value;
      }
    },
    showSingleSelection:async (title,items,selected=-1)=>{
      const choices=parse(items);
      if (!Array.isArray(choices)) throw new Error('选项需为数组');
      for (;;) {
        const value=window.prompt(String(title)+'\n'+choices.map((item,i)=>`${i+1}. ${item}`).join('\n'),selected>=0?String(selected+1):'');
        if (value===null) return null;
        const index=Number(value)-1;
        if (value.trim() && Number.isInteger(index) && index>=0 && index<choices.length) return index;
        window.alert('请输入有效选项编号');
      }
    },
    saveImportedCourses:value=>stage('courses',value,true),
    saveCourseConfig:value=>stage('config',value,false),
    savePresetTimeSlots:value=>stage('timeSlots',value,true),
    saveComboSchedule:value=>stage('comboSchedule',value,false),
  };
  const bridge={
    showToast:message=>send('status',String(message)),
    notifyTaskCompletion:()=>{
      if (finished) return;
      if (failed) {send('error','脚本存在失败的保存调用，请重新采集');return;}
      if (!captured.courses.length) {send('error','未采集到课程，请检查学期和课表页面');return;}
      finished=true;send('complete',captured);
    },
  };
  window.shiguangBridgePromise=window.AndroidBridgePromise=promise;
  window.shiguangBridge=window.AndroidBridge=bridge;
}
