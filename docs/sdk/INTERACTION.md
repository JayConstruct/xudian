# 导航、审核与原生命令确认

[SDK 入口与兼容要求](../MODULE_SDK.md)。各能力的最低宿主 API 在对应小节说明；旧调用的回退与权限边界继续适用。

## 交互和外部操作

`ui.navigate(pageId,context)`、`ui.panel(pageId,context)`、`ui.dialog({title,fields})` 使用宿主交互；表单支持 text/multiline、number、date/datetime、boolean、select/multiSelect 与安全输入；可声明 required/maxLength，非法输入留在对话框中。`ui.review(planId)` 展示真实写集和结果，宿主控制最终确认。当前合法计划先展示增改删摘要与记录前后对比，完整原始计划可展开；未知结构回退原始审核。取消不提交，过期快照仍由提交校验拒绝，规则见 [实际数据审核](../design/DATA_CHANGE_REVIEW.md)。

宿主API `^1.27.0` 支持 `ui.review(planId, {title, message, confirmLabel, acknowledgement?})`，将日常操作显示为简洁确认框。标题、说明和按钮文字由模块从当前已校验预览生成，宿主绑定原冻结计划并负责最终确认；真实写集与完整前后值收进“查看变更详情”，存在真实删除时仍显示删除提醒。`acknowledgement` 是可选的风险确认文字，初始未勾选，勾选前确认按钮不可用，适合“安排超出截止”等需要明确接受的情况。不能用该参数绕过准备、权限、审核或提交前快照检查；未知计划结构继续回退原始审核。所有参数是非空纯文本，长度上限分别为120／6000／48／1000，未知参数拒绝；省略第二个参数保持原审核行为。

宿主 API `^1.33.0` 支持根节点 `planReview:{planId,eventType}` 配合 `footer:{type:"row",children:[...按钮]}`：宿主读取当前调用者的冻结计划，固定展示实际增改删数量及可打开的完整详情，并接管对应确认按钮。只有用户点击该原生按钮，才对当前页面、当前计划的一次 `ui.review` 授权，随后仍通过 `services.commit` 校验权限和数据快照。正文中的同名脚本事件、不同计划、重复请求、失效页面及需要额外风险勾选的确认继续使用普通审核。仅声明字段不会授权。确认和取消始终位于滚动内容之外。

宿主 API `^1.38.0` 支持 `button.command`、`taskItem.command`、输入框提交的 `input.command`，以及规划区块 `actions[].command`。格式为 `{ref:{moduleId,serviceId,majorVersion},input:{...完整命令输入}}`，输入允许使用现有 `{bind:['formValues',字段名]}` 绑定。用户实际点击原生按钮、勾选框或提交输入框时，宿主冻结当时的输入，只对当前页面工作流中第一次 `ui.review` 的相同服务版本及完整规范输入授予一次确认；脚本自行触发同名事件或声明 `command` 不会授权。冻结写集必须恰有一条非删除 upsert；物理删除、`deletedAt`／`deleted:true` 软删除、多条写入、额外风险勾选、输入错配及重复请求仍展示确认。`services.prepare` 的权限、数据基线和 `services.commit` 的验证保持不变。

原生表单 `ui.dialog` 也支持 `command:{ref,input:固定输入,fields:{服务输入字段名:'表单输出字段key'}}`。用户提交后，宿主把映射的原始表单结果合并到固定输入并冻结，供同一工作流下一次审核精确匹配；取消、缺失输出字段、离开页面或下一工作流均不能复用。模块若需要转换输入，应将转换结果在提交前明确表达，或沿用普通审核，不能把不同的实际输入作为同一次确认。

`ui.navigate` 指向可用工作区时，宿主关闭覆盖工作区的详情路由和模态面板，再激活目标并传递上下文；目标不可用时保留当前页面。目标模块随后打开的确认详情页直接显示，不需要用户手动返回工作区。`ui.panel` 继续打开面板，不切换工作区。

跨宿主调用被拒绝时，脚本捕获的 Error 的 `message` 和 `String(error)` 提供业务正文，去除重复异常前缀与调用堆栈；原始异常文本保存在 `error.diagnostic` 供诊断使用，不应展示给用户。未捕获的页面异常也以业务正文和重试操作显示，原始异常仍供宿主诊断。
