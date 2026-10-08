# 公共 UI 与界面包验证记录

日期：2026-10-08。使用说明、契约和包格式见 [公共 UI 与界面包](UI_COMPONENTS.md)。本轮没有安装 APK 到用户设备，也没有清除应用数据。

## 交付与使用

- 公共组件、五类页面模板与导航契约；声明式 UI 包的安装、停用、更新与回退。
- 设置 → 界面风格：全局选择、模块专属选择、模拟预览与恢复默认。审核、凭据和恢复控件保留内置 UI。
- [紧凑示例包](../dist/modules/example.ui.compact.xmodule)：可导入，或从模块管理的“恢复随客户端发布的模块”安装 `example.ui.compact`；安装后在界面风格中预览、选择并保存。
- [Android 调试 APK](../client/build/app/outputs/flutter-apk/app-debug.apk)：使用 `android-x64` 目标和 build number 6 构建。APK 的 8 项模块资源与当前分发包摘要一致，包含非默认安装的示例 UI 包，不包含独立课表包。

原有安装的业务包不会自动升级。任务视图的分页与公共列表模板使用此次分发的任务／视图 1.1.0；更新时先安装任务包，再安装视图包，宿主沿用已有业务数据。

## 自动化结果

`flutter analyze --no-pub` 无问题；`flutter test --no-pub` **502 项全部通过**；生产架构检查通过，覆盖从入口可达的 58 个 Dart 文件。Android 调试构建成功。

原始输出和产物摘要保存在 [验证目录](../dist/verification/ui-packs/verification.json)：[测试](../dist/verification/ui-packs/flutter-tests.txt)、[静态分析](../dist/verification/ui-packs/flutter-analyze.txt)、[架构](../dist/verification/ui-packs/architecture.txt)、[构建](../dist/verification/ui-packs/android-build.txt)。

| 范围 | 已验证行为 |
| --- | --- |
| 包与契约 | 无脚本工作线程、更新／回退／重启、依赖兼容、命名空间、分支必要槽位、循环／深度限制、拒绝重复原生控件与无约束滚动包装 |
| 选择与恢复 | 全局／模块覆盖、模块显式默认、停用和缺失包回退、保存失败不切换、并发基线、模拟预览不读取宿主业务数据 |
| 原生呈现 | 手机／桌面导航、底栏实际高度避让、大字课表与详情、表单校验、输入文本／选择范围／焦点、页面滚动状态 |
| 性能行为 | 千条记录只构建视口附近控件、UI 切换不执行页面脚本、无关数据变化不刷新页面、兼容 SQL 分页与原算法差异比较、集合修订缓存 |
| 业务分页 | 实际打包的收件箱首批 50 项、加载更多保留顺序且不重复、完成／归档／删除／子任务过滤、今天视图排除无日期任务 |

## 性能测量边界

UI 声明树在校验时编译；注册表与组件解析缓存供 Flutter 原生渲染使用。UI 包不创建 JavaScript 堆或线程。任务列表分页减少跨运行时传输和记录解析，兼容筛选／排序下推 SQLite；尚未增加按业务字段查询的数据库索引。

本轮验证了构建数量、刷新范围和状态保留，没有测量 Android 真机或 Windows 的帧时间、掉帧及峰值内存，也没有进行跨平台 profile 对比。因此不能据此宣称达到稳定 60／120fps。测量方式见 [性能与验证](UI_COMPONENTS.md#性能与验证)。
