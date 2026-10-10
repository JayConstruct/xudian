# 验证记录

本页索引实际执行证据，测试数量只代表对应日期和范围。生产代码的 `host_*`、`script_*`、`schedule_*` 等回归与旧行为夹具分别核对；Linux 测试不能替代各平台运行及性能验收。

## 最近记录

| 日期与范围 | 结果与证据 |
| --- | --- |
| 2026-10-09 完整 Android APK | 0.1.0 / build50 的 ARMv7、ARM64、x86_64 与通用 Release APK 构建完成，版本、签名、ABI/原生库及已移除模块资源核验通过；签名与模拟器 build50 一致，沿用项目测试密钥。源码未变，复用已有分析和 46 项相关回归；ARM 真机运行未验证。[构建记录](../dist/apk-build50/verification.json) / [完整下载包](../dist/xudian-0.1.0-build50-apks.zip) |
| 2026-10-09 布局设置子页面 | 46 项布局、设置与底栏相关测试通过；静态分析及架构检查通过。build50 将导航、右上角菜单和常用/隐藏入口分到子页，共用未保存草稿；补充延迟保存期间返回的回归，防止完成保存后多退一层。模拟器验证分类摘要、子页隔离及系统返回，未保存设备布局。[验收结果](../dist/verification/layout-subpages.json) |
| 2026-10-09 布局可视编辑 | 45 项布局、设置、底栏及新交互测试通过；静态分析与 78 文件架构检查通过。build48 展示底栏/侧栏及展开菜单，点选只编辑草稿；模拟器已验证入口检查器及高级模式往返，设备验收未保存布局配置。[验收结果](../dist/verification/layout-visual-editor.json) |
| 2026-10-09 移除收件箱与项目视图 | 45 项相关 Flutter 回归通过；静态/架构与 8 项模块目录检查通过。build47 覆盖安装后，两模块显示已卸载、数据保留；重启后导航及更多菜单入口消失，原有课表课程仍在。[验收结果](../dist/verification/remove-view-modules.json) |
| 2026-10-09 更新流程优化 | 36 项 Python 脚本测试、25 项页面回归通过；静态/架构检查通过，debug 热重载与模块摘要校验实测通过。[流程结果](../dist/verification/emulator-workflow/result.json) |
| 同轮模拟器 Release 更新 | build46 覆盖安装后课程保留；首次流程约 49 秒，无改动复用约 0.23 秒。[首次](../dist/verification/emulator-workflow/release-first.json) / [复用](../dist/verification/emulator-workflow/release-cached.json) / [模块摘要](../dist/verification/emulator-workflow/module-digest.json) |
| 设置与拾光发布 | 当时版本、全套回归及发布验收见 [发布记录](archive/MODULE_RELEASE_20261009.md) |
| 脚本宿主与迁移 | 初次交付和平台实施差异见 [宿主验收](archive/MODULE_HOST_VERIFICATION.md) |
| 公共 UI 与模块目录 | [界面包验收](archive/UI_PACK_VERIFICATION.md) / [目录验收](archive/MODULE_CATALOG_VERIFICATION.md) |

表中 build46 是该轮设备记录，不能用来替代后续设备查询；缓存耗时仅为当时模拟器与工作区条件。

## 复验入口

常用检查与更新命令统一见 [开发指南](../DEVELOPMENT.md) 和 [模拟器更新](EMULATOR_UPDATE.md)。课表及拾光的相关测试、只读复验脚本和历史运行范围保留在 [归档索引](archive/README.md)。需要 profile 模式与真实设备测量帧耗时、内存和启动/切换性能；功能测试不证明 FPS。

真实学校账号/网站、Android ARM64 真机、Windows 构建与安装的验证须分别记录。已有学校快照审计、模拟 DOM 采集和 x86_64 截图不代表这些场景已经通过。

新增验收时记录日期、版本、具体检查范围、结果、数据保留及证据路径，保留失败和未验证范围。验收产物位于 `dist/verification/`，归档中的本机构建/截图可能不在其他检出工作区。
