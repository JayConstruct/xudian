# 当前版本文档

仓库最近发布的 App 版本是 **v0.2.0-beta.29**，对应宿主 API **1.54.0**。安装包的变更和对应模块版本见[本版说明](releases/v0.2.0-beta.29.md)，安装摘要与实测范围见[验证记录](VERIFICATION.md)。

功能说明按工作区源码维护。以下两个模块的源码版本高于仓库作者索引中的最高版本；设备实际版本可在模块管理中查看。

| 模块 | 工作区清单 | 作者版本索引 |
| --- | --- | --- |
| 任务规划 | [1.15.3](../packages/modules/app.planner/module.json) | [1.15.1](../module-index/app.planner.json) |
| 课表 | [1.16.6](../packages/modules/app.schedule/module.json) | [1.16.5](../module-index/app.schedule.json) |

## 功能使用

| 功能 | 可以查什么 |
| --- | --- |
| [日程](features/DAILY.md) | 按日期查看任务与课程，快速添加、编辑和完成任务 |
| [任务规划](features/TASK_PLANNING.md) | 在看板上安排、调整和撤销任务。[新建、模板与批量规则](features/TASK_CREATION.md) |
| [课表](features/SCHEDULE.md) | 切换教学周、编辑课程、调整节次、设置时区、导入与备份 |
| [拾光导入](features/SHIGUANG_IMPORT.md) | 选择学校、采集课表、核对来源及变更 |
| [AI 助手](features/AI_ASSISTANT.md) | 配置模型、调用工具、审核写入和管理对话 |
| [设置](features/SETTINGS_HIERARCHY.md) | 外观、导航、减少动画和[显示诊断](features/SETTINGS_HIERARCHY.md#显示与布局诊断) |
| [安装与更新](INSTALLATION.md) | 首次安装 App、从商店安装模块、检查更新和切换通道 |

## UI 与动画

| 要做什么 | 入口 |
| --- | --- |
| 调整图标、间距、文字、布局或无障碍 | [界面设计系统](ui/DESIGN_SYSTEM.md) · [当前选稿](../design/README.md) |
| 替换公共控件、模板和界面风格 | [公共 UI 与界面包](ui/UI_PACKS.md) |
| 组合页面入口、槽位与上下文 | [入口与页面组合](ui/PAGE_COMPOSITION.md) |
| 实现显示与折叠、页面切换、按压反馈或滑动操作 | [动画与手势](ui/MOTION.md) |
| 展示操作结果，或在写入前让用户核对变更 | [短暂反馈](ui/TOAST.md) · [数据变更审核](ui/DATA_CHANGE_REVIEW.md) |

## 模块开发

| 要做什么 | 入口 |
| --- | --- |
| 编写第一个模块、确定最低宿主 API | [SDK 快速开始与能力表](MODULE_SDK.md) |
| 查数据、表单、日期、时间轴和平台接口 | [按功能查阅 SDK](MODULE_SDK.md#按功能查阅) |
| 接入学校适配器 | [拾光适配接口](SHIGUANG_ADAPTER_API.md) |
| 打包模块、发布到商店 | [模块宿主](MODULE_HOST.md#构建和验证) · [模块目录与作者发布](MODULE_CATALOG.md) · [发布包](../releases/README.md) |

## 宿主开发与验收

| 要做什么 | 入口 |
| --- | --- |
| 了解架构、代码入口和目录职责 | [架构](ARCHITECTURE.md) · [客户端](../client/README.md) · [目录规范](REPOSITORY_LAYOUT.md) |
| 配置工具、运行测试或更新模拟器 | [开发指南](../DEVELOPMENT.md) · [Android 环境](ANDROID_DEVELOPMENT.md) · [模拟器更新](EMULATOR_UPDATE.md) |
| 排查启动、加载或平台问题 | [性能测量](PERFORMANCE.md) · [平台验收](PLATFORM_VERIFICATION.md) |
| 提交和发布 APK | [发布流程](RELEASE_WORKFLOW.md) · [签名保管](ANDROID_SIGNING.md) |
| 核对本版结果和剩余验证范围 | [验证记录](VERIFICATION.md) · [待核验事项](BACKLOG.md) |

SDK 能力表列出各接口所需的最低宿主版本。查阅旧版 App 时，在对应的 Git 标签下打开本页。
