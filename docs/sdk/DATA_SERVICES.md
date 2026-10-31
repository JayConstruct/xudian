# 数据、服务与模块生命周期

[SDK 入口与兼容要求](../MODULE_SDK.md)。各能力的最低宿主 API 在对应小节说明；旧调用的回退与权限边界继续适用。

## 数据和服务

- `data.get(collection,id)`：只读本模块已声明集合；不存在返回 null。
- `data.query(collection,{filter,sort,offset,limit})`：filter 支持 all/any 与 `{field,op,value}`；op 为 eq/ne/lt/lte/gt/gte/in/isNull。sort 为 `{field,direction}` 数组；分页上限 10000。
- `data.watch(collection,options,listener)`、`services.watch(ref,input,listener)`：返回可关闭订阅句柄；停用时自动释放。
- `services.directory()`：当前启用服务及 tool 元数据目录；目录不授予调用权限。
- `services.query(ref,input)`：只读，校验输入/输出 Schema。
- `services.prepare(ref,input)`：界面工作流返回 `{planId,result,writes}`；在命令准备中调用则组合受权子计划并返回子结果。
- `services.commit(planId)`：须先经 `ui.review`；重新检查权限和数据基线。
- `services.adopt(planId)`：提供者接收自己确认的外部导入计划；仅限写入自身集合且单一提供者确认的计划。保留原来源身份与读取基线，不能改变写集。
- `extensions.query(entity)` / `queryMany(entities)`：实体拥有者读取已启用扩展的定义和值；扩展服务声明 `extensionFor`，值归扩展自身。`extensionFor.commands` 可发布 set/clear/setMany 服务；实体视图声明 `extensions.command:<owner>/<collection>` 后可调用这些明确的扩展命令，不能借此调用任意服务或其他实体范围。
- `events.subscribe({moduleId,types},listener)`：需精确 `events.subscribe:<module>/<type>` 权限，提交后通知。

query/command 的 JSON Schema 使用明确子集：type、properties、required、additionalProperties、items、enum、min/maxLength、min/maxItems、minimum/maximum。不要使用未支持关键字；更复杂的业务约束在 JavaScript 中验证。唯一索引用 `{id,fields,unique:true}` 声明。

## 升级

提高数据版本时，在 `migrations` 中为旧数据版本声明 handler；处理程序读候选副本并返回正常写集，不使用外部能力。迁移成功才切换正式指针。不兼容回退必须经过快照恢复。停用不删除数据，卸载后重启不会自动安装。

模块包工具和原生源码来源见 [MODULE_HOST.md](../MODULE_HOST.md)。

## 受保护宿主服务

服务目录公开 `app.host/settings.get@1`、`settings.patch@1`、`layout.get@1`、`layout.patch@1`、`navigation.list@1` 和 `navigation.open@1`。它们与业务服务使用相同授权、实际变更审核、基线校验和条件撤销机制。布局编辑器存在未保存草稿时拒绝写入，页面参数不能扩大调用范围。

### 配置导出声明

“设置 → 导出所有配置”导出应用设置、模块清单与版本摘要、启停状态、仓库来源，以及所有模块的 `ui.preferences`。模块可在 `collections` 条目上声明 `"configuration": true`，将该集合当前数据空间内未删除的记录纳入配置 JSON；未声明的业务集合、历史快照和操作日志不导出。宿主按声明读取，不按模块 ID 判断。声明或内容变化仍须提升模块版本，已安装旧版本需先更新。

此标记应仅用于连接参数、显示设置、规则等配置；不要标记任务、课程安排或聊天记录。密钥应继续通过 `secrets` 保存在系统安全存储中。导出默认不读取安全存储；用户开启“包含 API 密钥”后，文件会额外包含宿主保存的连接密钥明文。数据库部分通过同一只读事务获取，安全存储在事务后单独读取，读取失败会终止导出。

文件标识为 `format: "xudian.configuration"`、`formatVersion: 1`，包含 `exportedAt`、`includesSecrets`、`appSettings`、`session`、`modules`、`hostSettings`、`moduleUiPreferences`、`moduleConfiguration` 和 `scope`；仅在显式选择时包含 `secrets`。三个 UI 设置值保留 JSON 结构，其余 `appSettings` 值保留数据库字符串；缺失的 UI 设置与更新渠道填入默认值。当前仅支持导出，尚未实现导入恢复。保存使用系统文件对话框，UTF-8 文件上限为 2 MiB。

## 模块包预览与安装

`packages.prepare({definition,files})` 编译并在隔离临时数据空间执行预览，返回摘要绑定的提案；`packages.review(id)` 再次核验基线、来源和摘要，审核后安装。普通服务授权不包含安装权限。预览不能联网、交互或修改正式数据。

## 可选服务（API 1.21）

`manifest.optionalServices` 可声明只读可选服务，且必须保留相同引用的精确查询权限：

```json
{
  "permissions": ["services.query:app.schedule/schedule.query.timetables@1"],
  "optionalServices": [{"moduleId":"app.schedule","serviceId":"schedule.query.timetables","majorVersion":1,"kind":"query"}]
}
```

该声明仅排除由精确查询权限推导的必需依赖；显式 `dependencies`、`serviceDependencies` 与 command 权限仍是必需依赖。提供者缺失、停用或服务不兼容不阻止可选调用方安装、启用；停用提供者不会级联停用可选调用方。可先通过 `services.directory()` 判断服务是否存在；实际查询仍校验精确权限、服务种类、主版本与 Schema，缺少服务时抛错。可选声明本身不授予权限，也不允许 command。

`services.directory()` 记录当前服务目录与实例代数作为 prepare 的读取基线，包含可选提供者尚未安装或启用的状态；目录变化后提交拒绝并要求重新准备。只读页面准备也记录声明的可选提供者 ID，即使提供者当前缺失，安装或启停后页面可重新查询。

## 可信时钟自动化（API 1.37）

API 1.37 支持可信 `app.host / host.clock.tick` 自动化事件：在宿主启动、恢复及前台每分钟检查时发出。
只有具有 `automation.execute` 且规则明确声明发布者 `app.host` 的模块参与；查询不能触发写入，
脚本伪造同名事件不执行自动规则。宿主暂停或关闭时停止定时检查，恢复后再次检查；不保证系统后台常驻。
处理程序须自行保证幂等，返回无写集且 `result.skipped:true` 时不产生提交／自动化历史。
