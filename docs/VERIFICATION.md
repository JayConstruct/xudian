# 当前版本与验收

## 最新公开发布

2026-11-24 发布 Android 测试版 `v0.2.0-beta.35` 和想法模块 1.1.1，同步更新 AI、任务、课表、日程和 UI 示例。三组 CI 回归共通过 1966 项，三个公开 APK 已分别核对源码提交、ABI、固定签名、摘要和预装模块。模块商店已收录想法，八个公开模块包（含想法的两个历史版本）已匿名下载并核对。[本版说明](releases/v0.2.0-beta.35.md) · [结构化报告](verification/release-20261124-beta35.json)

## 最近设备验收

x86_64 模拟器保留已有数据，覆盖安装 `0.2.0-beta.35`，本机 versionCode 为 4294。已实测想法记录、按关键词搜索、返回与重开，核对了日程与课表切换、模块商店详情和离线恢复。最终候选复验了想法空态、收藏、重开和课表切换。[最终安装](../dist/verification/20261124T145503.202934Z-emulator-update/results.json) · [商店验收](../dist/verification/20261124T145503.202934Z-emulator-update/catalog/results.json) · [想法 18 个设计状态对照](../dist/verification/ideas-design-match/验收.md)

## 复验入口

- [模拟器更新与验收](EMULATOR_UPDATE.md)
- [首次安装复验](INSTALLATION.md#自动复验)
- [冷启动采样](PERFORMANCE.md#进程冷启动采样)
- [平台验收矩阵](PLATFORM_VERIFICATION.md)

设备日志、截图和快照保存在本机 `dist/verification/`，旧版发布记录可从对应 Git 标签查阅。
