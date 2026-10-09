# 设置与拾光导入更新（2026-10-09）

源码和作者索引发布到 `JayConstruct/xudian` 的 `module-catalog` 分支。新模块包使用固定 tag `modules-2026-10-09-shiguang`，统一目录为 `JayConstruct/xudian-modules`。

## 本次内容

- 设置使用分类首页和二级页；选择框采用圆角选项菜单。
- 页面右上角使用一个菜单按钮，汇集模块入口和设置。
- 课表 `app.schedule` 1.6.3 默认显示周一至周五，可手动显示周末；新版客户端使七列适配屏幕。
- 拾光 `app.import.shiguang` 1.3.1 提供学校搜索、通用系统、粘贴脚本、JSON 导入和关于与致谢。学校列表只显示名称、分类和入口数量，详情页显示说明、源码、维护者和不同入口。
- 上游快照为 `ShiGuangSchedule/shiguang_warehouse` 的 `c586957c077506a5182105ae3961ceff4d0223ce`，内置 243 所学校的 265 个入口及 4 个通用系统，共 269 个适配项。保留源 GitHub 地址、MIT 许可及致谢。
- 独立 `app.import.zhengfang` 从当前源码、作者索引和统一目录移除。正方通用导入在拾光模块内选择，已发布的历史 Release 不改写。
- 模拟器已安装客户端 build 36、拾光 1.3.1 和课表 1.6.3；独立正方已卸载，卸载记录保留。拾光通用正方入口和原有课程仍正常。

## 发布前验证

- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --concurrency=1`：607 项通过。
- JavaScript 兼容测试：19 项通过。
- `python3 -m unittest discover -s scripts/module_catalog -p 'test_*.py'`：21 项通过。
- 完整目录和作者包检查：10 个模块、22 个当前索引对应的包；当前 tag 仅选择拾光和课表的两个新包，包摘要、身份、清单及服务声明均通过校验。
- 269 个上游适配项语法及源码摘要检查通过；320 像素窄屏、1.6 倍字体下层级页面无溢出。模拟器验收见 `dist/verification/shiguang-hierarchy-emulator.json` 和 `zhengfang-module-removal-emulator.json`。

七列适配需要客户端 build 34 或更新版本，建议 build 36；仅更新模块不会为早期客户端增加这一宿主能力。本 Release 提供 `.xmodule`，客户端源码在发布分支。真实学校账号尚未逐校验收，登录、校园网、学校网页和季节作息会影响导入；完整边界见 [拾光导入](SHIGUANG_IMPORT.md)。

发布按先上线并重新下载验证新 Release、再公开作者索引、最后更新目录的顺序进行。已有版本资产和 tag 保持不可变。
