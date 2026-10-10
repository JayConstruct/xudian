// Static coverage report; does not log into or run school websites.
import {writeFile,mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import vm from 'node:vm';
import {adapters,loadAdapter,snapshot} from '../../packages/modules/app.import.shiguang/warehouse/catalog.js';
import {compileBridge} from '../../packages/modules/app.import.shiguang/bridge.js';
let syntaxPassed=0,maxCaptureBytes=0;
for(const adapter of adapters) {
  const {script}=await loadAdapter(adapter.id);
  if(createHash('sha256').update(script).digest('hex')!==adapter.sha256)throw new Error('Source hash mismatch: '+adapter.id);
  const compiled=compileBridge({script});
  new vm.Script(compiled.script);syntaxPassed++;
  maxCaptureBytes=Math.max(maxCaptureBytes,Buffer.byteLength(compiled.script));
  if(adapter.unsupportedMethods.length)throw new Error('Unknown direct bridge method: '+adapter.id);
}
const packageBytes=await readFile(new URL('../../dist/modules/app.import.shiguang.xmodule',import.meta.url));
const definition=JSON.parse(await readFile(new URL('../../packages/modules/app.import.shiguang/module.json',import.meta.url),'utf8'));
const report={moduleVersion:definition.manifest.version,snapshot,
  staticChecks:{syntaxPassed,sourceHashesPassed:syntaxPassed,directUnsupportedBridgeReferences:0,maxCaptureBytes,
    featureFlags:Object.fromEntries(['customTime','comboSchedule','jquery'].map(feature=>[feature,adapters.filter(a=>a.features.includes(feature)).map(a=>a.id)]))},
  fixtureExecution:['YXHMC unchanged official adapter','NEU_2 unchanged official postgraduate adapter','legacy Zhengfang DOM fixture (previous emulator verification)'],
  realQuickJsChecks:['269-entry pagination and search','all five lazy bundles match pinned sources','school selection clears old draft and source options','cancellation writes no courses'],
  uiChecks:['320px width at 1.6 text scale'],
  limits:['Static method scanning detects direct named bridge references only. Feature flags are heuristics, not counts of unsupported schools.',
    'School sites and real accounts have not all been tested. Login, campus network, DOM changes and site-provided libraries affect execution.',
    'Custom times must exactly match period boundaries. Seasonal/date-based combo schedules need adaptation.',
    'Sunday-start first-week Sunday predates the first Monday and cannot currently be represented; conversion rejects the whole input.'],
  package:{bytes:packageBytes.length,sha256:createHash('sha256').update(packageBytes).digest('hex')}};
await mkdir(new URL('../../dist/verification/',import.meta.url),{recursive:true});
await writeFile(new URL('../../dist/verification/shiguang-warehouse-compatibility.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({schools:snapshot.schools,adapters:snapshot.adapters,syntaxPassed,maxCaptureBytes,package:report.package}));
