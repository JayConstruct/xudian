# 序点

面向 Android 与 Windows 的模块化个人任务管理 App，使用 Flutter/Dart、Riverpod、Drift/SQLite 和 QuickJS。当前生产入口采用 **v3 脚本模块宿主**：宿主提供导航、界面、数据和权限服务，业务通过独立 `.xmodule` 包运行。

源码仓库：[JayConstruct/xudian](https://github.com/JayConstruct/xudian)。

首次安装 Android App 并从模块商店安装功能，见 [安装指南](docs/INSTALLATION.md)。[Android Actions](https://github.com/JayConstruct/xudian/actions/workflows/android.yml) 自动检查源码并构建 ARMv7、ARM64 和 x86_64 APK。

## 当前能力

- 本地任务与今天视图；支持任务创建、完成、标题、优先级与日期编辑。收件箱和项目视图已移除，已有任务/项目数据保留。
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
| 开发、测试、构建与模拟器更新 | [开发指南](DEVELOPMENT.md) |
| 生产代码从哪里开始看 | [客户端说明](client/README.md) |
| 当前架构与后续设计边界 | [架构](docs/DESIGN.md) |
| 已确认决策与下一步工作 | [项目交接](PROJECT_HANDOFF.md) |
| 课表、拾光、SDK、发布及平台指南 | [文档导航](docs/README.md) |

## 目录

```text
client/             Flutter 宿主、Android/Windows 工程和测试
packages/modules/   业务脚本模块与界面包
packages/schemas/   版本化 JSON 契约
packages/catalog/   统一目录仓库内容
packages/xquickjs/  固定版本 QuickJS 原生引擎
module-index/       作者版本索引
releases/modules/   索引引用的版本化不可变模块包
docs/               当前专题说明；archive/ 保存历史
scripts/            开发、验证、打包与发布工具
assets/brand/       品牌资源
```

`.tools/`、`.cache/` 和 `dist/` 为本机 SDK、缓存与生成产物，不提交。公开模块包及保留规则见 [发布目录](releases/README.md)，历史实现及验收记录从 [归档索引](docs/archive/README.md) 查看。
