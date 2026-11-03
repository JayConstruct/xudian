# 验证索引

本页只索引实际执行结果。记录中的版本、测试数量和设备状态属于对应日期，不能视为当前源码或当前安装状态。版本与 SHA-256 由各报告维护，运行复验仍按 [AGENTS.md](../AGENTS.md) 执行。

## 发布验收

报告分别记录本机安装、公开 APK／模块下载、签名与 CI 结果；有失败、未完成或平台限制时，以原报告为准。发布说明保留在 `docs/releases/`，由发布工作流读取。

| 发布批次 | 证据 |
| --- | --- |
| 2026-11-03 · beta.21，批量任务管理与优先时间点 | [版本、摘要、CI与设备范围](verification/release-20261103-beta21.json) |
| 2026-11-03 · beta.20，日程规划与模块商店缓存 | [版本、摘要、检查与设备范围](verification/release-20261103-beta20.json) |
| 2026-10-23 · beta.18，任务完成状态 | [版本、摘要、检查与设备范围](verification/release-20261023-beta18.json) |
| 2026-10-22 · beta.16，全屏当日任务视图 | [版本、摘要、检查与设备范围](verification/release-20261022-beta16.json) |
| 2026-10-22 · beta.15，当日任务清单 | [版本、摘要、检查与设备范围](verification/release-20261022-beta15.json) |
| 2026-10-22 · beta.14，规划标题 | [版本、摘要、检查与设备范围](verification/release-20261022-beta14.json) |
| 2026-10-22 · beta.13，启动检查更新 | [版本、摘要、检查与设备范围](verification/release-20261022-beta13.json) |
| 2026-10-21 · beta.12，任务新建与持续规划 | [版本、摘要、检查与设备范围](verification/release-20261021-beta12.json) |
| 2026-10-21 · beta.11，界面优化模块 | [版本、摘要、检查与设备范围](verification/release-20261021-beta11.json) |
| 2026-10-20 · beta.10，动态日期与跟手 | [版本、摘要、检查与设备范围](verification/release-20261020-beta10.json) |
| 2026-10-20 · beta.9，连续日期 | [版本、摘要、检查与设备范围](verification/release-20261020-beta9.json) |
| 2026-10-20 · beta.8 | [版本、摘要、检查与设备范围](verification/release-20261020-beta8.json) |
| 2026-10-20 · beta.6，彩色课表与规划 | [版本、摘要、检查与设备范围](verification/release-20261020.json) |
| 2026-10-20 · beta.7，固定签名 | [版本、摘要、检查与设备范围](verification/release-20261020-beta7.json) |
| 2026-10-17 · 发布与模块商店 | [版本、摘要、检查与设备范围](verification/release-20261017.json) |
| 2026-10-15 · beta.4，规划交互 | [版本、摘要、检查与设备范围](verification/release-20261015.json) |
| 2026-10-14 · beta.3，UI 加载 | [版本、摘要、检查与设备范围](verification/release-20261014.json) |
| 2026-10-13 · 模块商店发布 | [版本、摘要、检查与设备范围](verification/module-store-release-20261013.json) |
| 2026-10-13 · App 发布 | [版本、摘要、检查与设备范围](verification/app-release-20261013.json) |

## 功能与交互

| 日期 | 专题 | 已验证范围 | 限制与历史状态 |
| --- | --- | --- | --- |
| 2026-11-03 | [批量任务优先时间点](verification/PREFERRED_TASK_TIME.md) | 精确分钟、真实占用回退、规则修改清除、已有安排保留及冷启动 | 仅模块更新，设备覆盖x86_64 Android模拟器 |
| 2026-11-03 | [批量任务管理子界面](verification/BATCH_TASK_MANAGEMENT.md) | 模拟器搜索筛选、详情、暂停恢复、规则预览保存、多选取消、单次完成重开及冷启动 | 新增管理页按选稿实现；ARM／Windows未做本轮实机验收 |
| 2026-10-18 | [AI 紧凑界面验收](verification/AI_UI_COMPACT.md) | 模拟器聊天页、两处设置入口、连接／模式取消、返回与重启 | 未发送聊天，未覆盖底部停靠全键盘 |
| 2026-10-18 | [配置导出验收（2026-10-18）](verification/CONFIGURATION_EXPORT.md) | 导出范围、密钥选择、失败重试自动化及模拟器取消／返回 | 仅支持导出；文件不含任务／课程等完整业务数据 |
| 2026-10-19 | [课表与任务规划自动配色](verification/CONTENT_COLORS.md) | 自动／自定义配色和导入回归；模拟器课表、规划与重启 | 不以颜色代替文字及来源状态，历史默认蓝无法判定用户意图 |
| 2026-10-30 | [日程完成任务原位显示验证](verification/DAILY_COMPLETED_IN_PLACE.md) | 模拟器完成后原位显示、切日、编辑取消重开与恢复待办 | 旧调用的完成过滤保持兼容，不表示各平台均验收 |
| 2026-10-30 | [日程融合布局验证](verification/DAILY_FUSION_UI.md) | 模拟器切日、详情／编辑返回重开、快速添加草稿及菜单 | 只覆盖日程基础布局；部分时间边界仅由自动化覆盖 |
| 2026-10-30 | [模拟器冷启动脚本验证](verification/EMULATOR_COLD_BOOT.md) | 真实冷启动、目标拒绝、取消／复用，APK 摘要及数据不变 | 真实冷启动使用 --yes；交互确认由回归覆盖 |
| 2026-10-17～18 | [任务规划第五版界面实施](verification/PLANNER_CHROME_V5.md) | 模拟器菜单逐级返回、连续缩放、筛选、面板取消与重开 | 五天及候选布局为历史行为，后续连续日期方案已替代 |
| 2026-10-20 | [任务规划连续日期与紧凑布局验收](verification/PLANNER_CONTINUOUS_TIMELINE.md) | 模拟器连续日期、待安排浮层、调整开关、切页与重启记忆 | 对应当时构建；ARM 真机与 Windows 需单独验证 |
| 2026-10-20 | [任务规划动态日期窗口验收](verification/PLANNER_DYNAMIC_TIMELINE.md) | 动态窗口、短划及长距离浏览回归与模拟器操作 | 当时跟手问题后续另修，见横向拖动记录 |
| 2026-10-16 | [任务规划性能优化验收](verification/PLANNER_PERFORMANCE.md) | 工作量对比及模拟器长块滚动、拖动取消恢复 | 计数／静止像素比较不是真实 FPS 或掉帧统计 |
| 2026-10-20 | [任务规划横向拖动跟手修复验收](verification/PLANNER_SCROLL_FOLLOW.md) | 两组共八个实际按住、停手与反向拖动检查点 | 不代表其他卡顿、ARM 或 Windows 全部验收 |
| 2026-10-15 | [任务规划重构：第一阶段实施记录](verification/PLANNER_UX_STAGE1.md) | 核心任务／操作链与图形交互原型自动化 | 该阶段未安装设备，不代表整份方案完成 |
| 2026-10-15 | [任务规划第二阶段：拖动交互、并发与加载优化](verification/PLANNER_UX_STAGE2.md) | 拖动预览、并发版本、分页及加载自动化 | 当时为源码与候选包验证，后续继续阶段三 |
| 2026-10-15 | [任务规划第三阶段：可见区渲染与大批候选](verification/PLANNER_UX_STAGE3.md) | 672 任务／28 天、分页、DST 时长及撤销冲突自动化 | 未安装设备；卡片数量不代表帧率，内部仍扫描完整候选 |
| 2026-10-16～17 | [任务规划第四版界面实施验收](verification/PLANNER_UX_V4_IMPLEMENTATION.md) | 模拟器新增、移动、确认／取消、快速调整及撤销恢复 | 初始交互已被后续规则替代，不证明整份规划方案完成 |

规划基础协议与早期模块验收另见 [任务规划](archive/PLANNER_20261013.md)；UI 加载、源码及商店实现见 [加载性能](UI_LOADING_PERFORMANCE.md)。早期模块、课表和界面包记录从 [历史索引](archive/README.md) 查阅。2026-10-13 商店首批下载／安装反馈、第二批布局与数据审核、第三批时区及显示实现的自动化范围，结合下方 ARM 设备报告和 [当前安装规则](MODULE_CATALOG.md#安装流程反馈) 阅读，不能将当时的“待设备验证”继续当作当前状态。

## 性能与平台

| 批次 | 证据 |
| --- | --- |
| 2026-10-20 · 固定签名准备 | [结构化结果](verification/android-signing-20261020.json) |
| 2026-10-13 · ARM 显示及体验 | [结构化结果](verification/arm-ux-20261013.json) |
| 2026-10-22 · CI 并行及去重 | [结构化结果](verification/ci-speed-20261022.json) |
| 2026-10-12 · 日期动效 | [结构化结果](verification/date-motion-20261012.json) |
| 2026-10-12 · 日期波浪 | [结构化结果](verification/date-wave-20261012.json) |
| 2026-10-13 · 五日条与波浪 | [结构化结果](verification/five-day-wave-20261013.json) |
| 2026-10-10 · 首次安装 | [结构化结果](verification/fresh-install-20261010.json) |
| 2026-10-13 · 首装失败尝试（保留失败原因） | [结构化结果](verification/fresh-install-20261013-attempt-01.json) |
| 2026-10-13 · 首装后续验收 | [结构化结果](verification/fresh-install-20261013.json) |
| 2026-10-13 · 宿主导航错误 | [结构化结果](verification/host-navigation-errors-20261013.json) |
| 2026-10-12 · 工作区切换 | [结构化结果](verification/instant-workspace-20261012.json) |
| 2026-10-12 · 大数据日期切换 | [结构化结果](verification/large-date-wave-20261012.json) |
| 2026-10-14 · 深层启动优化（不证明稳定整机提速） | [结构化结果](verification/startup-deep-20261014.json) |
| 2026-10-14 · 首轮启动采样（无稳定提速结论） | [结构化结果](verification/startup-ui-20261014.json) |
| 2026-10-13 · 时区与显示 | [结构化结果](verification/timezone-display-20261013.json) |
| 2026-10-12 · 日程菜单 | [结构化结果](verification/today-menu-20261012.json) |
| 2026-10-14 · 页面读取与缓存 | [结构化结果](verification/ui-loading-20261014.json) |
| 2026-10-13 · 历史透镜方案 | [结构化结果](verification/water-lens-20261013.json) |

冷启动方法、TTID／TTFD 与业务就绪的区别见 [采样指南](STARTUP_PERFORMANCE.md)。模拟器微基准或调用次数减少不能换算 ARM 真机性能，Windows／读屏／弱网等尚未覆盖的场景统一见 [体验待办](design/UX_PLATFORM_BACKLOG.md)。

2026-10-13 ARM 显示及体验验收解释了 480／420 DPI 引起的逻辑视口差异，复验商店、长正文、审核、系统时区及取消路径；没有修改系统密度或禁用字体缩放，真机大字号、横屏、读屏和 Windows 仍未覆盖，细节见上方 `arm-ux-20261013` 报告。

## 仓库整理

| 日期 | 范围与结果 | 证据 |
| --- | --- | --- |
| 2026-10-20 | 本机产物与 Git 提交范围整理，保留公开模块及关键验收材料 | [精简记录](verification/repository-organization-20261020.json) |
| 2026-10-29 | 迁移 4,830 个文件并核对字节与 mtime，删除已核验分片及重复 ZIP；恢复限制见原报告 | [迁移记录](verification/dist-organization-20261029.json) |
| 2026-10-30 | 清理旧编译缓存及清单中的 373 个旧日志／脚本／APK，累计约 6.01 GiB；当前 APK、近期回退、源码及数据保留 | 本机 `dist/verification/repository/cache-cleanup-20261030-222911/` 与 `old-files-delete-20261030-223526/` |

历史本机原始报告中的旧路径保留原文；2026-10-30 删除的缓存日志与旧 APK 不再是可打开的证据，可按上述清单查询删除路径及摘要。源码、设计原图、已发布模块、完整验收报告和关键性能基线未随缓存清理删除。后续整理遵循 [目录规范](REPOSITORY_LAYOUT.md)。

## 复验入口

检查、打包和数据库生成见 [开发指南](../DEVELOPMENT.md)，APK／模块更新与版本摘要核对见 [模拟器更新](EMULATOR_UPDATE.md)。详细日志、截图与设备快照保存在本机 `dist/verification/`，文档只记录范围、结论、限制与入口；首次安装可使用 [安装复验](INSTALLATION.md#自动复验)。
