# 序点 Flutter 客户端

生产入口为 `main.dart → XudianApp → AppShell → moduleHostProvider`。原生注册受保护的模块管理界面；任务、视图、AI 和组件示例运行 v3 JavaScript 模块。宿主 API 当前为 **1.10.0**，模块包格式为 `packageFormat: 2`，定义为 `formatVersion: 3`。

## 代码入口

| 路径 | 职责 |
| --- | --- |
| `lib/main.dart`、`lib/app/app.dart` | Flutter、Riverpod、主题及受保护模块注册 |
| `lib/app/app_shell.dart` | 工作区导航、模块启动及宿主服务连接 |
| `lib/core/module_host/module_host.dart` | 模块实例、服务、准备/提交、生命周期 |
| `lib/core/module_host/module_package.dart` | 包身份、文件、摘要及来源校验 |
| `lib/core/module_host/script_page.dart` | 脚本页面与公共控件渲染 |
| `lib/core/module_host/host_settings_page.dart` | 生产设置分类与二级页 |
| `lib/core/module_host/collection_store.dart` | 通用集合、记录与查询 |
| `lib/core/module_catalog/` | 商店、作者目录、版本及依赖解析 |
| `lib/core/ui/` | 页面组合、界面包、顶栏和宿主导航 |
| `lib/data/app_database.dart` | Drift 数据库、迁移与旧表档案 |
| `assets/modules/catalog.json`、`retired.json` | 随 APK 发布的模块清单、默认状态及退出分发的视图 |
| `../packages/modules/` | 生产业务代码；课表与拾光单独安装 |
| `test/`、`test/support/` | 生产链回归与旧行为基准夹具 |

`lib/features/` 保留兼容、共用组件及旧行为实现；修改业务前先核对生产模块和调用链。旧测试通过不能替代真实宿主验收。收件箱和项目视图不再分发；退出默认分发的模块首次升级保留数据卸载，处理标记防止后续用户手动恢复被重复卸载。

## 数据与调用

脚本通过 `@xudian/sdk` 调用数据、服务和 UI；跨模块访问检查实际调用实例及精确权限。命令先在快照上准备写集，宿主审核并核验基线后事务提交，事件在提交后发布。UI 包只描述呈现，不创建 JavaScript 工作线程。

数据库为 `xudian_v9.sqlite`，Drift schema 为 **2**。schema 1 升级前创建备份并迁移至通用 `host_*` 集合；旧表与来源保留为档案。文件名中的 v9 不代表迁移版本。AI 连接配置由 AI 模块集合保存，密钥位于系统安全存储。

## 开发入口

在 Android Studio 打开本目录，启动文件选择 `lib/main.dart`。环境、测试和构建命令统一见 [开发指南](../DEVELOPMENT.md)；宿主限制见 [模块宿主](../docs/MODULE_HOST.md)，开发契约见 [SDK](../docs/MODULE_SDK.md)。

当前能力与边界见 [项目首页](../README.md)，旧架构说明及验证历史见 [客户端历史](../docs/archive/CLIENT_OVERVIEW_20261009.md)。
