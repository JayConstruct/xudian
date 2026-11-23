# 当前版本与验收

## 最新公开发布

2026-11-24 发布 Android 测试版 `v0.2.0-beta.33` 与任务规划 `1.17.1`。CI 的三组 Flutter 回归共通过 1952 项。已分别下载三个 ABI 的公开 APK，核对源码提交、版本、固定签名证书、SHA-256 和预装模块。已核对公开模块包及模块商店作者索引。[本版说明](releases/v0.2.0-beta.33.md) · [结构化报告](verification/release-20261124-beta33.json)

## 最近设备验收

x86_64 模拟器保留原有数据，覆盖安装 `0.2.0-beta.33`，本机 versionCode 为 4286。上下边缘和拖动任务三条路径都验证了 48 dp 的提示和 72 dp 的全天展开。过去时段的任务确认一次即可保存，撤销后恢复为待安排，关闭并重新打开 App 后恢复智能时段。[安装记录](../dist/verification/20261123T194855.481795Z-emulator-update/results.json) · [手势与安排验收](../dist/verification/20261123T194855.481795Z-emulator-update/planner-72dp/verification.json)

## 复验入口

- [模拟器更新与验收](EMULATOR_UPDATE.md)
- [首次安装复验](INSTALLATION.md#自动复验)
- [冷启动采样](PERFORMANCE.md#进程冷启动采样)
- [平台验收矩阵](PLATFORM_VERIFICATION.md)

设备日志、截图和快照保存在本机 `dist/verification/`，旧版发布记录可从对应 Git 标签查阅。
