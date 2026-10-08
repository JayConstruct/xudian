# 拾光学校适配模块接口 v1

`app.import.shiguang` 1.1.0 提供公共兼容接口。宿主只提供浏览器、服务调用和页面导航；学校脚本保存在独立 `.xmodule` 中。完整可用示例为 [app.import.zhengfang](../packages/modules/app.import.zhengfang/main.js)。

学校模块声明依赖 `app.import.shiguang: ^1.1.0`，宿主 API `^1.8.0`，权限 `ui`、`browser.capture` 和 `services.query:app.import.shiguang/shiguang.bridge.compile@1`，不需要课表写入权限。通过 settings 或 `app.schedule.imports` 的 `importers` 槽位注册自己的页面。

调用流程：

```js
import {services, browser, ui} from '@xudian/sdk';
import schoolScript from './adapter.js'; // export default 一个脚本文本字符串

const {script} = await services.query({
  moduleId: 'app.import.shiguang',
  serviceId: 'shiguang.bridge.compile',
  majorVersion: 1,
}, {bridgeVersion: 1, script: schoolScript});

const payload = await browser.capture({url: loginUrl, script});
if (payload !== null) {
  await ui.navigate('app.import.shiguang.home', {
    shiguangImport: {version: 1, payload},
  });
}
```

`shiguang.bridge.compile@1` 是纯查询：输入原始脚本及可选 `bridgeVersion:1`，输出 `{bridgeVersion:1, script}`。仅拼接桥接，不执行或下载脚本；拒绝空脚本、不支持版本，以及桥接与脚本合计超过256 KiB UTF-8的数据。执行须由有 `browser.capture` 权限的学校模块打开浏览器，并由用户点击「执行采集」。

桥接对象包括 `window.shiguangBridgePromise` 与 `window.shiguangBridge`，兼容 `AndroidBridgePromise`／`AndroidBridge` 别名。Promise 接口支持 `showAlert`、`showPrompt`、`showSingleSelection`、`saveImportedCourses`、`saveCourseConfig`、`savePresetTimeSlots`、`saveComboSchedule`；同步接口支持 `showToast`、`notifyTaskCompletion`。保存类调用仅暂存 JSON，结束通知才向浏览器返回 `{courses,timeSlots,config,comboSchedule}`。空课程或任何失败的保存调用不会报告成功。提示／输入／单选使用浏览器内的原生对话框；单选以编号输入返回0开始的索引，取消为-1。

学校模块采集成功后以 `shiguangImport:{version:1,payload}` 导航到公共兼容页。此上下文按普通输入处理，不是授权或已验证数据；兼容页只消费一次，用户选择目标、配置来源及学期后才转换，随后进入课表预览，最终写入仍需用户确认。取消不写入课程，重新渲染不会重复弹出配置。导入计划的调用来源为执行准备的 `app.import.shiguang`，学校解析模块不获得写入或提交权。

需要自行组织页面的模块还可调用 `shiguang.convert@1`，输入 `{payload,options}`，输出标准 `ScheduleImportDraft v1`；须单独声明 `services.query:app.import.shiguang/shiguang.convert@1` 权限，再按课表导入协议处理预览。转换选项、单双周和稳定来源键规则见 [SHIGUANG_IMPORT.md](SHIGUANG_IMPORT.md)。

制作另一学校适配包时，复制正方模块目录，修改模块 ID、名称、页面和入口 ID，替换 `adapter.js` 的脚本文本字符串。使用本地已有、经过核对的拾光脚本，保留对应作者和许可。打包后先安装依赖，再导入学校包；不需重建 APK。当前不会自动下载学校脚本或按域名匹配。使用其他桥接方法、自定义上课时刻或季节组合作息的脚本需要进一步适配，公共接口可用不代表所有学校脚本都已兼容。

验证：8项 JavaScript 测试与26项 Flutter 测试包含公共桥接 UTF-8 限制、真实 QuickJS 跨模块调用、结果交接、取消、只消费一次、预览前无写入及学校模块无提交权限。Android 独立适配流程复验命令为 `python3 scripts/module_host/verify_shiguang_browser.py --install --release --adapter-module --public-url https://example.com`。

该流程已在原 build34 Release APK 上通过模拟器验证：独立正方入口调用共享桥接服务，运行上游 DOM 解析器后进入公共课表配置并取消，未提交课程。APK 未重建。记录见 [shiguang-adapter-browser.json](../dist/verification/shiguang-adapter-browser.json)。
