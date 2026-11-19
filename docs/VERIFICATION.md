# 当前版本与验收

## 最新公开发布

2026-11-16 发布 `v0.2.0-beta.27`。发布记录包含三个 Android ABI 的 APK、固定签名与摘要、独立模块版本、CI 和设备验收范围。[本版发布说明](releases/v0.2.0-beta.27.md) · [结构化报告](verification/release-20261116-beta27.json)

## 最近设备验收

2026-11-18，Android x86_64 模拟器覆盖安装同一 App 版本的开发验收构建 242（versionCode 4242），保留应用数据。设备 APK 的 SHA-256 为 `bb32c512b1ca6384725c5df347e20966db6a0f2c7f34b3fc5b9a0a80aa037753`。该次仅更新宿主 APK。

商店详情关闭、返回及重开，搜索与分类筛选，依赖详情跳转，离线恢复和进程冷启动通过。首轮未找到工作区，重新打开应用后复用同一 APK 完成验收。安装与首轮记录在 `dist/verification/20261118T115226.117111Z-emulator-update/`，通过的复验记录在 `dist/verification/20261118T115544.532033Z-emulator-update/`。

## 复验入口

- [模拟器更新与验收](EMULATOR_UPDATE.md)
- [首次安装复验](INSTALLATION.md#自动复验)
- [冷启动采样](PERFORMANCE.md#进程冷启动采样)
- [平台验收矩阵](PLATFORM_VERIFICATION.md)

设备日志、截图和快照保存在本机 `dist/verification/`，旧版发布记录可从对应 Git 标签查阅。
