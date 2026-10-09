# 拾光学校适配模块接口 v1

`app.import.shiguang` 1.3.0 提供公共兼容接口，继续兼容1.1系列调用方。宿主只提供浏览器、服务调用和页面导航；学校脚本保存在独立 `.xmodule` 中。正方通用入口已整合到拾光模块；下方代码仍可用于其他独立学校模块。

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

桥接对象包括 `window.shiguangBridgePromise` 与 `window.shiguangBridge`，兼容 `AndroidBridgePromise`／`AndroidBridge` 别名。Promise 接口支持 `showAlert`、`showPrompt`、`showSingleSelection`、`saveImportedCourses`、`saveCourseConfig`、`savePresetTimeSlots`、`saveComboSchedule`；同步接口支持 `showToast`、`notifyTaskCompletion`。保存类调用仅暂存 JSON，结束通知才向浏览器返回 `{courses,timeSlots,config,comboSchedule}`。空课程或任何失败的保存调用不会报告成功。提示／输入／单选使用浏览器内的原生对话框；单选以编号输入返回0开始的索引，取消为 `null`。命名输入校验函数在原适配脚本作用域解析；返回 `false`、空字符串或空值表示合法，错误文本表示需重新输入。

学校模块采集成功后以 `shiguangImport:{version:1,payload}` 导航到公共兼容页。此上下文按普通输入处理，不是授权或已验证数据；兼容页只消费一次，用户选择目标、配置来源及学期后才转换，随后进入课表预览，最终写入仍需用户确认。取消不写入课程，重新渲染不会重复弹出配置。导入计划的调用来源为执行准备的 `app.import.shiguang`，学校解析模块不获得写入或提交权。

需要自行组织页面的模块还可调用 `shiguang.convert@1`，输入 `{payload,options}`，输出标准 `ScheduleImportDraft v1`；须单独声明 `services.query:app.import.shiguang/shiguang.convert@1` 权限，再按课表导入协议处理预览。转换选项、单双周和稳定来源键规则见 [SHIGUANG_IMPORT.md](SHIGUANG_IMPORT.md)。

制作独立学校适配包时，声明自己的模块 ID、页面和入口，按上方示例保存 `adapter.js` 脚本文本并调用公共接口。使用本地已有、经过核对的拾光脚本，保留对应作者和许可。打包后先安装依赖，再导入学校包；不需重建 APK。1.2.0内置可搜索学校快照，不按域名自动匹配，也不会自动下载学校脚本。使用其他桥接方法、不能准确对应现有节次的自定义上课时刻或季节组合作息的脚本需要进一步适配，公共接口可用不代表所有学校脚本都已兼容。

验证包含公共桥接 UTF-8 限制、真实 QuickJS 跨模块调用、结果交接、取消、只消费一次、预览前无写入及学校模块无提交权限。该交接流程由测试内的临时学校模块验证，不再依赖独立正方生产包。

`shiguang.adapters.list@1`（1.2.0新增）提供只读学校目录：输入 `{search?:string,page?:integer}`，页码从0开始，每页30项；输出 `{snapshot,total,page,pages,items}`。搜索支持学校名、系统、分类和缩写，多个词同时匹配；页码越界会限制到有效范围。元数据包含学校、适配项ID、网址、描述、维护者、来源路径、脚本SHA-256及静态兼容特征，不返回可执行脚本。调用模块需声明 `services.query:app.import.shiguang/shiguang.adapters.list@1` 权限。

1.3.0 的目录查询新增可选 `kind: "all" | "school" | "general"`，默认 `all` 保留原269项语义。学校界面按学校分组，查询接口仍逐适配项返回，通用系统界面筛选GENERAL_TOOL。层级切换不会写入课程；学校或脚本切换仍清除旧来源的草稿。
