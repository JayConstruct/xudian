# 当前版本与验收

## 最新公开发布

2026-11-19 发布 `v0.2.0-beta.29` Android 测试版。CI 全量 Flutter 回归通过 1929 项，三个 ABI 的 APK 已匿名下载并核对源码提交、固定签名、SHA-256 及六个内置模块包。四个独立模块包、九份作者索引和公开目录也已核对。[本版发布说明](releases/v0.2.0-beta.29.md) · [结构化报告](verification/release-20261119-beta29.json)

## 最近设备验收

2026-11-19，使用 `scripts/update-emulator.sh --force --verify-catalog --catalog-offline` 在 Android x86_64 模拟器覆盖安装 `0.2.0-beta.29` 构建 259（versionCode 4259），保留应用数据。设备 APK 的 SHA-256 为 `5126abec9fe9961e491759426a9c8e30cb097cb9d32a81551a1d66409b20d8a0`，与本机产物一致。

商店详情关闭、返回及重开，搜索与筛选，离线恢复、进程冷启动和关于页版本回读均通过。项目菜单、AI 拆解入口、设置、规划和课表的设备验收，以及四个已安装模块的摘要回读，在业务代码相同的 `beta.28` 候选上完成。最终安装与商店证据在 `dist/verification/20261119T064406.289255Z-emulator-update/`。

## 复验入口

- [模拟器更新与验收](EMULATOR_UPDATE.md)
- [首次安装复验](INSTALLATION.md#自动复验)
- [冷启动采样](PERFORMANCE.md#进程冷启动采样)
- [平台验收矩阵](PLATFORM_VERIFICATION.md)

设备日志、截图和快照保存在本机 `dist/verification/`，旧版发布记录可从对应 Git 标签查阅。
