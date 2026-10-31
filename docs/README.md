# 文档导航

先按当前任务选择入口。现行规则由专题维护，发布版本、测试数量与平台覆盖见 [验证索引](VERIFICATION.md)，历史方案见 [归档](archive/README.md)。

## 使用 App

| 要做什么 | 入口 |
| --- | --- |
| 安装 App 和功能模块 | [首次安装](INSTALLATION.md) |
| 创建任务、按日浏览、安排与撤销 | [任务、日程与规划](TASKS_AND_PLANNING.md) |
| 配置课表和导入课程 | [课表](SCHEDULE.md) · [拾光导入](SHIGUANG_IMPORT.md) |
| 配置 AI 和管理对话 | [AI 助手](AI_ASSISTANT.md) |
| 查找设置或检查更新 | [设置层级](SETTINGS_HIERARCHY.md) · [App 更新](APP_UPDATES.md) |

## 开发模块

| 要做什么 | 入口 |
| --- | --- |
| 编写第一个脚本模块、查最低 API | [SDK 快速开始与能力索引](MODULE_SDK.md) |
| 查数据、页面、交互和平台接口 | SDK 内按功能链接到 `sdk/` 各专题 |
| 定义公共控件或无脚本界面包 | [公共 UI 与界面包](UI_COMPONENTS.md) |
| 贡献入口、嵌套页面和传递上下文 | [页面组合](UI_COMPOSITION.md) |
| 编写学校适配模块 | [拾光适配接口](SHIGUANG_ADAPTER_API.md) |
| 打包、收录与发布模块 | [模块目录与作者发布](MODULE_CATALOG.md) · [不可变发布包](../releases/README.md) |

## 维护宿主

| 要做什么 | 入口 |
| --- | --- |
| 配置环境、运行检查与构建 | [开发指南](../DEVELOPMENT.md) |
| 找生产入口与架构边界 | [客户端说明](../client/README.md) · [架构](DESIGN.md) · [模块宿主](MODULE_HOST.md) |
| 更新模拟器中的 APK 或模块 | [模拟器更新](EMULATOR_UPDATE.md) |
| 管理目录、提交范围和缓存 | [目录规范](REPOSITORY_LAYOUT.md) |
| 发布 Android App 与保管签名 | [App 发布](APP_UPDATES.md#发布-android-更新) · [签名保管](ANDROID_SIGNING.md) |
| 分析页面加载或冷启动 | [UI 加载性能](UI_LOADING_PERFORMANCE.md) · [启动采样](STARTUP_PERFORMANCE.md) |
| 开发其他设备环境 | [Windows Android](WINDOWS_ANDROID_DEVELOPMENT.md) · [VPS／WSL](MULTI_MACHINE_DEVELOPMENT.md) · [远程预览](REMOTE_ANDROID_DEVELOPMENT.md) |

## 设计、待办与验收

| 要做什么 | 入口 |
| --- | --- |
| 查看决策与下一步任务 | [项目交接](../PROJECT_HANDOFF.md) · [统一待办](BACKLOG.md) |
| 查看选稿、实现范围与页面顺序 | [设计入口](../design/README.md) · [页面清单](../design/PLAN.md) |
| 保存原图、提示词与批次 | [设计稿规范](DESIGN_ARTIFACTS.md) |
| 修改公共 UI 或具体交互 | [界面规则](UI_DESIGN_SYSTEM.md) · [Toast](design/TOAST.md) · [数据审核](design/DATA_CHANGE_REVIEW.md) |
| 核对规划需求或持续生成规则 | [规划交互](design/PLANNER_UX_REDESIGN.md) · [任务新建](design/TASK_CREATION.md) |
| 查性能排查入口、平台及视觉验收条件 | [体验与平台细则](design/UX_PLATFORM_BACKLOG.md) · [时区与显示诊断](design/TIMEZONE_DISPLAY.md) |
| 查历史运行结果 | [验证索引](VERIFICATION.md) · [历史归档](archive/README.md) |

一项能力只维护一份规则；当前宿主 API 由 SDK 标明并与代码检查，模块版本来自 `module.json`。任务状态只在统一待办更新，专题保留规则和验收条件。详细日志、截图与设备快照保存在本机，公开文档的链接检查自动在 CI 运行。
