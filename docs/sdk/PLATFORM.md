# 网络、文件、时区与网页采集

[SDK 入口与兼容要求](../MODULE_SDK.md)。各能力的最低宿主 API 在对应小节说明；旧调用的回退与权限边界继续适用。

## 文件、网络、凭据与系统时间

`http.request({id,url,method,headers,body,credential})`、`http.cancel(id)` 受网络许可、地址和容量限制。`secrets.configure({endpoint,label})` 通过安全输入返回凭据句柄；`secrets.delete(handle)` 删除自身凭据。`grants.request({scopes})` / `revoke(id)` 经宿主审核，默认 30 分钟及 20 次写入。

`files.readText()` / `saveText(name,text)` 为用户选择的 JSON 文本交换。`clock.today(ianaZone)`、`clock.now()` 和 `ids.new()` 由宿主提供。API 1.1 增加 `clock.local(ianaZone)`，返回 `{date,time,weekday}`，分别为民用日期、`HH:mm` 和星期 1–7，按指定时区计算。JavaScript 不读取设备文件路径、进程、系统命令或凭据明文。

API 1.22 增加 `await clock.systemTimezone()`，无参数，返回 `{zone,source}`。`zone` 是宿主时区库认可的 IANA 名称；`source` 为 `system` 或 `fallback`。每次调用重新读取系统设置，读取失败、无支持、无效名称或超时使用明确的 `Asia/Shanghai` 回退。`GMT`、`Etc/GMT` 和 `Etc/UTC` 等明确零时区别名规范为库支持的 `UTC`；不从数字偏移或 `CST` 等歧义缩写猜测地区。

该调用需要 `clock.today`、`clock` 或精确 `clock.systemTimezone` 权限，可用于有权限的查询、命令准备和只读页面准备；隔离预览、迁移与安装验证不能访问真实系统能力。异步读取完成后重新核对调用者是否仍启用。结果用于新记录默认值，已有记录应保留存储的时区，不能因系统设置变化自动改写；`source: 'fallback'` 应向用户说明。Android 及 Windows 实现与实测限制见 [时区与显示诊断](../design/TIMEZONE_DISPLAY.md)。

## API 1.8 的通用网页采集

`browser.capture({url,script})` 需要明确的 `browser.capture` 权限，Android 打开用户可操作的 WebView。用户登录、导航后点击「执行采集」才运行模块传入的脚本。只接受 HTTP/HTTPS URL（不含内嵌凭据）及最多256 KiB的脚本。关闭返回 null；其他平台明确报不支持，可使用文件导入。允许 HTTP 以兼容旧教务入口；现有宿主 HTTP 服务仍独立校验其许可和地址。

WebView 使用设备提供的内核和网络解析。主页面加载失败会保留 DNS、连接、HTTP 或证书错误提示，并禁用执行；页面重新加载成功后恢复。证书验证失败时取消加载。

网页脚本调用 `window.xudianCapture.send(type,value)`。type 为 status 显示状态，为 error 标记该执行失败，为 complete 返回 JSON 对象；结果上限2 MiB。每次执行独立标识，导航、关闭和新执行使旧结果失效。此接口没有数据库、服务提交或文件能力。宿主返回后重新核验调用实例，停用模块关闭采集窗口。业务兼容桥接由独立模块注入，宿主不识别拾光或正方数据结构。

课表1.6.1的 `app.schedule/schedule.query.timetables@1` 返回 `{timetables:[...]}`，供导入适配器选择目标和读取课表作息；需要精确 query 权限，不返回导入凭据。正方导入兼容包用法见 [SHIGUANG_IMPORT.md](../SHIGUANG_IMPORT.md)。

兼容模块1.1.0的 `app.import.shiguang/shiguang.bridge.compile@1` 接受 `{script,bridgeVersion:1}`，返回含公共桥接的浏览器脚本文本。独立学校模块采集后通过导航上下文 `shiguangImport:{version:1,payload}` 交给兼容页的配置和预览流程；协议见 [SHIGUANG_ADAPTER_API.md](../SHIGUANG_ADAPTER_API.md)。
## API 1.21 的纯时区转换与可选查询

同一引入版本的可选依赖与服务目录基线见 [可选服务](DATA_SERVICES.md#可选服务api-121)。

API 1.23 新增 `await clock.toLocalMany([{utc, zone}, ...])`，返回与输入顺序相同的本地时间数组。最多 256 项，空数组返回空数组；每项复用 `clock.toLocal` 的日期、时区与夏令时规则，任一项无效则整批失败。页面、只读准备、query、command prepare 均可调用且无需额外权限。使用它的模块需声明 `hostApi: '^1.23.0'`。日程 `app.views.today 1.8.0` 使用批量转换，50 个精确计划的时间转换桥接从 100 次减少至 1 次，超过 128 个计划分批处理。

声明 `hostApi: '^1.21.0'` 后可使用两项无副作用转换，在页面、只读页面准备、query 和 command prepare 中均可调用，不需要额外权限，也不读取宿主当前时间：

```js
await clock.toLocal({utc: '2026-11-01T05:30:00.000Z', zone: 'America/New_York'});
// {date:'2026-11-01', time:'01:30', weekday:7}
await clock.toUtc({date: '2026-11-01', time: '01:30', zone: 'America/New_York'});
// {status:'ambiguous', instants:['2026-11-01T05:30:00.000Z','2026-11-01T06:30:00.000Z']}
```

`zone` 必填，为有效 IANA 时区名；`utc` 必须是以 `Z` 结尾、包含秒的 ISO UTC 时间戳，可含 1–6 位小数。输出日期为 `YYYY-MM-DD`、时间为 `HH:mm`，星期一为 1、星期日为 7。反向输入仅接受有效的 `YYYY-MM-DD` 日期与 `HH:mm` 时间；非法日期、时刻和时区报错。`clock.toUtc` 的 `status` 为 `unique`（一个候选）、`ambiguous`（多个候选，UTC 升序）或 `nonexistent`（空数组）。夏令时跳跃、重复与整日跳过均返回明确状态，不替调用者选候选或移动时间。
