# 模块目录交付验证（2026-10-08）

交付为 build 29，源码与作者索引使用 `JayConstruct/xudian` 的 `module-catalog` 分支，首批模块固定 Release tag 为 `modules-2026-10-08`。统一目录使用公开仓库 `JayConstruct/xudian-modules`。协议与作者接入步骤见 [MODULE_CATALOG.md](MODULE_CATALOG.md)。

## 已完成的本地验证

- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --concurrency=1`：560 个测试通过，包含现有宿主、课表及导入测试。
- `python3 -m unittest discover -s scripts/module_catalog -p 'test_*.py'`：17 个测试通过。
  发布工具的草稿恢复修复后重新运行，共 19 个测试通过；新增完整草稿位于后续分页时的恢复，以及同一待发布 tag 对应多份 Release 时拒绝操作的回归。
- 作者索引、历史包与新包校验：11 个模块、22 个不可变资产；原历史包保持原字节。
- Android release APK：arm64-v8a、armeabi-v7a、x86_64 构建成功；8 个内置包的版本、说明、作者与摘要逐项匹配。

依赖验证包含不同作者仓库的“正方通用 → 拾光兼容 → 课表”，一次确认安装后进入真实导入页面；共享依赖去重、已安装版本复用、停用依赖启用、完整启用模块约束、版本冲突、循环依赖、服务主版本及类型不符。测试也覆盖取消下载、网络失败与重试、摘要或身份不符、确认期间安装状态变化、数据库和课程数据回滚、重启恢复、最终注册失败以及官方和签名发布者保护。

界面测试覆盖 320 像素窄屏、2 倍字体、详情依赖跳转、安装确认和下载取消。没有执行真机、模拟器或 Windows 运行验证；APK 使用工程现有开发签名密钥。

## APK 摘要

| 架构 | 文件字节数 | SHA-256 |
| --- | ---: | --- |
| arm64-v8a | 24273065 | `ac28d5430c6931ff48c33384b4d7d66130d20b92a83748df5f066c21ea41fd4d` |
| armeabi-v7a | 21877887 | `1fb1bcc0d820f5fa7b33c32f8fb68da72b55becfad3f80aa70b65e8ee1937e29` |
| x86_64 | 25872106 | `828697a151d84cb4bcf0cc4a2571c9e869e0ee94490ebf412c6f9b7f21e8646b` |

构建命令为 `flutter build apk --release --split-per-abi --build-number 29 --no-pub`。本地交付目录 `dist/module-catalog-delivery/` 保存 APK、分析和测试日志、构建日志及 `verification.json`。

远程发布采用先上传并重新下载校验 Release 资产、再匿名验证作者索引和全部包、最后上线目录的顺序。后续版本必须追加资产和索引，不能移动 tag 或覆盖已发布包；摘要校验不等于签名认证。
