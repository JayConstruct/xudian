# 当前版本与验收

## 最新公开发布

2026-11-20 发布 Android 测试版 `v0.2.0-beta.31`。CI 的三组 Flutter 回归共通过 1941 项。三个 ABI 的 APK 已匿名下载，核对了源码提交、版本、ABI、固定证书、SHA-256 和六个内置模块。三个独立模块、九份作者索引和公开目录也已核对。[本版说明](releases/v0.2.0-beta.31.md) · [结构化报告](verification/release-20261120-beta31.json)

## 最近设备验收

2026-11-20，使用 `scripts/update-emulator.sh --force --verify-catalog --catalog-offline` 在 x86_64 模拟器上覆盖安装 `0.2.0-beta.31`。本地构建号为 275，设备 versionCode 为 4275，APK 的 SHA-256 为 `588184474d947a6adf3f31221b8ff2935b6810657587251d4d75b95cad3dedd2`。三个模块已在前一候选构建 4274 上读回版本和包摘要。[安装与检查记录](../dist/verification/20261120T134439.844265Z-emulator-update/results.json) · [模块读回](../dist/verification/20261120T132038.379961Z-emulator-update/results.json)

商店的搜索、筛选、详情返回与重开、离线缓存和在线恢复均已通过，App 冷启动正常。设备复验还覆盖了设置搜索与 AI 模型连接、入口目录与编排、界面风格、更新设置、课表周选择与课程安排编辑，以及拾光学校搜索和导入页导航。[商店验收](../dist/verification/20261120T134439.844265Z-emulator-update/catalog/results.json) · [页面验收](../dist/verification/releases/release-20261120-beta30/device/results.json) · [最终版本页](../dist/verification/releases/release-20261120-beta31/device/results.json)

同轮另有 26 个界面状态的逐图对照。教务登录后的预览与冲突处理采用隔离样例数据，真实学校账号验收仍由 IMPORT-01 跟踪。[逐图对照](../dist/verification/20261120-unified-pages/compare.html) · [页面与模块验收记录](../dist/verification/20261120-unified-pages/verification.json)

## 复验入口

- [模拟器更新与验收](EMULATOR_UPDATE.md)
- [首次安装复验](INSTALLATION.md#自动复验)
- [冷启动采样](PERFORMANCE.md#进程冷启动采样)
- [平台验收矩阵](PLATFORM_VERIFICATION.md)

设备日志、截图和快照保存在本机 `dist/verification/`，旧版发布记录可从对应 Git 标签查阅。
