# 序点

面向 Android 与 Windows 的模块化个人任务管理 App，使用 Flutter/Dart、Riverpod、Drift/SQLite 和 QuickJS。当前采用 **v3 脚本模块宿主**：宿主提供导航、界面、数据和权限服务，业务通过独立 `.xmodule` 包运行。

源码仓库：[JayConstruct/xudian](https://github.com/JayConstruct/xudian)。

App 支持从“设置 → 关于序点 → 检查更新”查询 GitHub 正式发布，也可开启测试通道接收测试版，查看更新说明并打开下载页。更新规则见 [安装与更新](docs/INSTALLATION.md#检查-app-更新)，发布流程见 [Android 发布版本与资产](docs/RELEASE_WORKFLOW.md#android-发布版本与资产)。

首次安装 Android App 并从模块商店安装功能，见 [安装指南](docs/INSTALLATION.md)。[Android Actions](https://github.com/JayConstruct/xudian/actions/workflows/android.yml) 自动检查源码并构建 ARMv7、ARM64 和 x86_64 APK。

## 当前能力

- 本地任务与日程视图；可切换过去和未来日期，顶栏显示所选日期，同步查看任务、课程，并为所选日期添加任务。支持任务完成、标题、优先级与日期编辑。收件箱和项目视图已移除，已有任务/项目数据保留。
- 任务规划支持批量任务管理、完成历史、暂停恢复和规则变更预览；可设置优先时间点，冲突时在允许时段内就近安排，保留已有任务。
- 模块安装、启停、依赖检查、版本更新、回退与保留数据卸载。
- 分类设置、入口编排、公共 UI 契约、界面风格与恢复。
- AI 设备直连用户配置的模型接口，支持服务工具、变更审核、本地历史及有限条件撤销。
- 独立课表与拾光教务导入：课表默认显示工作日，学校搜索、通用系统和粘贴脚本共用导入流程。
- 模块商店使用统一目录、作者索引及 GitHub Releases 分发，安装和更新由用户发起。

端到端加密同步、账号服务、签名审核市场服务端和 Windows 安装包流程仍待实现。各平台运行与性能验证范围见 [验证记录](docs/VERIFICATION.md)。

## 快速开始

Linux / WSL 工作区已准备项目 SDK 时：

```bash
source scripts/dev-env.sh
cd client
flutter pub get
cd ..
scripts/update-emulator.sh --dev
```

命令更新 x86_64 Android 模拟器并连接热重载，按 `r` 刷新。正式效果验收运行 `scripts/update-emulator.sh`；只更新课表运行 `scripts/update-emulator.sh --modules-only --module app.schedule`。环境、其他设备及构建说明见 [开发指南](DEVELOPMENT.md)。

## 文档入口

| 想了解什么 | 入口 |
| --- | --- |
| 日程、任务、课表与 AI 怎么用 | [按功能查阅](docs/README.md#功能使用) |
| 各页面的 UI 设计稿在哪里 | [页面与设计稿映射表](design/PAGES.md) · [查询命令](design/README.md#按页面查询) |
| UI 规范、动画和操作反馈怎么实现 | [UI 与动画](docs/README.md#ui-与动画) |
| 开发、测试、构建与模拟器更新 | [开发指南](DEVELOPMENT.md) |
| 宿主、模块和发布包分别在哪里 | [目录与提交清单](docs/REPOSITORY_LAYOUT.md) · [客户端代码入口](client/README.md#代码入口) |
| 宿主、模块与数据边界 | [架构](docs/ARCHITECTURE.md) |
| 本版待核验事项 | [统一待办](docs/BACKLOG.md) |
| 课表、拾光、SDK、发布及平台指南 | [文档导航](docs/README.md) |
