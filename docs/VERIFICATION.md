# 当前版本与验收

## 最新公开发布

2026-11-19 发布 `v0.2.0-beta.29` Android 测试版。CI 全量 Flutter 回归通过 1929 项，三个 ABI 的 APK 已匿名下载并核对源码提交、固定签名、SHA-256 及六个内置模块包。四个独立模块包、九份作者索引和公开目录也已核对。[本版发布说明](releases/v0.2.0-beta.29.md) · [结构化报告](verification/release-20261119-beta29.json)

## 最近设备验收

2026-11-20，在 Android x86_64 模拟器上使用 `scripts/update-emulator.sh --verify-catalog --catalog-offline` 覆盖安装本地构建 273（`0.2.0-beta.29`，versionCode 4273）。设备 APK 与构建产物的 SHA-256 均为 `deb5000dc4a0bac198fc8f8b455e62d0eea4389d573f859536f1b8b3708a5ae8`。[安装与检查记录](../dist/verification/20261120T123529.968161Z-emulator-update/results.json)

57 项商店及界面包专项测试通过。模拟器验证了商店搜索、筛选、详情关闭与重开、离线缓存恢复和进程冷启动。切换内置默认与红色 UI 包后，商店首页、分类、设置、目录仓库编辑和详情均跟随全局配色。验收结束时恢复了原先选用的红色包。[商店配色对照图](../dist/verification/20261120-catalog-global-ui/store-comparison.png) · [配色与恢复记录](../dist/verification/20261120-catalog-global-ui/theme-check.json)

同轮构建 4270 至 4272 验收了六处 UI 的 26 个状态。大学课表模块为 `1.17.2`，拾光教务导入为 `1.9.1`。教务登录后的预览和冲突处理使用隔离实例及样例数据，真实学校账号验收仍由 IMPORT-01 跟踪。[逐图对照](../dist/verification/20261120-unified-pages/compare.html) · [页面与模块验收记录](../dist/verification/20261120-unified-pages/verification.json)

## 复验入口

- [模拟器更新与验收](EMULATOR_UPDATE.md)
- [首次安装复验](INSTALLATION.md#自动复验)
- [冷启动采样](PERFORMANCE.md#进程冷启动采样)
- [平台验收矩阵](PLATFORM_VERIFICATION.md)

设备日志、截图和快照保存在本机 `dist/verification/`，旧版发布记录可从对应 Git 标签查阅。
