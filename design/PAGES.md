# UI 页面与设计稿映射表

按功能分类浏览页面，点击状态链接查看对应图片。每个页面按主要用途归入一个分类。页面标识是脚本使用的稳定英文名称，别名收录常用叫法。表中优先列现行选稿，也保留明确标注的试稿和历史参考。图片需要本机设计材料。

“待完善”记录待补的设计状态、待确认的试稿或待收录的图。“—”表示该栏暂无登记项。跨模块审核的设计缺口见[平台验收细则](../docs/PLATFORM_VERIFICATION.md#设备验收缺口)。实现缺陷和设备验收进度见[项目待办](../docs/BACKLOG.md)。查询命令和维护方式见[设计入口](README.md)。

| 功能分类 | 页面标识 | 页面名称 | 别名 | 设计稿与状态 | 待完善 |
| --- | --- | --- | --- | --- | --- |
| 日程与任务 | schedule-home | 日程首页 | 今天、日程 | [日程基础布局参考](styles/20261030-023219-917453-c-current-ui-fusion-v02.png) | — |
| 日程与任务 | planner | 任务规划看板 | 时间表、任务规划 | [历史参考 · 连续时间轴](../dist/design/planner-continuous-timeline/legacy-20261029/selected/approved-layout.png) | 核对连续时间轴的历史选稿，收录当前看板的单页稿。 |
| 日程与任务 | new-task | 新建任务 | 规划新建任务 | [表单试稿](new-task/20261106-155000-318838-screenshot-task-create-v01.png) | 确认现有表单试稿，补充草稿恢复状态的对应图。 |
| 日程与任务 | task-details | 任务详情与编辑 | 规划任务详情 | — | 收录规划入口的任务详情和编辑状态图。 |
| 日程与任务 | task-repeat | 任务重复设置 | 重复规则 | [历史参考 · 规则](../dist/design/task-create/legacy-20261029/drafts/task-rules-design-v1.png) | 核对当前重复设置表单，补录单页定稿。 |
| 日程与任务 | batch-tasks | 批量任务管理 | 批量生成任务 | [管理页选稿](batch-tasks/20261103-162137-563384-batch-management-mobile-light-v02.png) | — |
| 日程与任务 | planning-preview | 规划预览与提交确认 | 规划预览 | [历史参考 · 预览](../dist/design/task-create/legacy-20261029/drafts/task-flow-v3-preview.png) | 补录当前预览的冲突与提交确认状态。 |
| 日程与任务 | task-history | 完成历史 | 任务复盘、操作历史 | — | 收录完成记录列表和展开记录的页面稿。 |
| 课表与教务 | timetable | 课表周视图 | 课表、周课表 | [多课程试稿](timetable/20261106-155000-347985-screenshot-multicourse-timetable-v01.png) | 确认多课程试稿，补录空课表状态。 |
| 课表与教务 | courses | 课程详情与课程管理 | 课程详情、课程管理 | [课程管理／课程列表](timetable/20261120-184554-037605-courses-v01.png)<br>[课程管理／周期安排展开](timetable/20261120-184554-037605-arrangement-v01.png)<br>[课程管理／当前课表没有课程](timetable/20261120-184554-037605-courses-empty-v01.png)<br>[课程管理／编辑课程与安排](timetable/20261120-184554-037605-course-editor-v01.png) | 收录课程详情，以及调课或取消单次课程的状态图。 |
| 课表与教务 | timetable-settings | 课表设置 | — | [已选择课表](settings/20261120-001608-406068-schedule-v01.png) | — |
| 课表与教务 | timetable-manager | 课表管理 | — | [选择与管理课表](settings/20261119-163211-750631-timetables-v01.png) | — |
| 课表与教务 | timetable-display | 课表显示设置 | — | [课表同步预览](settings/20261119-163211-750631-schedule-display-v01.png) | — |
| 课表与教务 | semester-settings | 学期设置 | — | [编辑学期](settings/20261119-163211-750631-semester-v01.png)<br>[高级时区展开](settings/20261119-163211-750631-semester-zone-v01.png) | — |
| 课表与教务 | period-settings | 作息设置 | — | [上午时段](settings/20261119-163211-750631-periods-v01.png) | — |
| 课表与教务 | course-import | 拾光教务导入 | 课程导入、拾光导入 | [选择导入方式](settings/20261120-001608-406068-import-v01.png)<br>[选择学校／按名称搜索](course-import/20261120-184554-029987-schools-v01.png)<br>[选择学校／无匹配学校](course-import/20261120-184554-029987-school-empty-v01.png)<br>[通用系统导入／选择教务系统](course-import/20261120-184554-029987-systems-v01.png)<br>[中国石油大学（北京）／本科入口与教务网址](course-import/20261120-184554-029987-school-detail-v01.png)<br>[使用学校适配脚本／粘贴脚本](course-import/20261120-184554-029987-paste-v01.png)<br>[选择导入目标／已有课表](course-import/20261120-184554-029987-target-v01.png)<br>[确认学期配置／合并到已有课表](course-import/20261120-184554-029987-semester-v01.png)<br>[导入预览／已生成课程草稿](course-import/20261120-184554-029987-preview-v01.png)<br>[处理导入地点／去掉校区名称](course-import/20261120-184554-029987-location-v01.png)<br>[处理导入冲突／来源与本地值冲突](course-import/20261120-184554-029987-conflicts-v01.png)<br>[关于与致谢／来源与许可](course-import/20261120-184554-029987-about-v01.png) | — |
| 项目推进 | projects | 项目目录 | 项目推进、项目首页 | [目录／分类列表](projects/20261119-112135-597762-directory-v03.png)<br>[目录／长按分类](projects/20261119-122133-765524-folder-v01.png) | — |
| 项目推进 | project-activity | 项目待推进 | 待推进 | [待推进／最近优先](projects/20261119-112135-597762-activity-v03.png)<br>[待推进／排序菜单](projects/20261119-112135-597762-sort-v03.png)<br>[待推进／最久优先](projects/20261119-112135-597762-oldest-v03.png)<br>[待推进／加入待安排后返回](projects/20261119-112135-597762-updated-v03.png)<br>[待推进／空态](projects/20261119-112135-597762-empty-v03.png)<br>[待推进／长按项目](projects/20261119-122133-765524-activity-v01.png) | — |
| 项目推进 | project-follow | 项目跟进 | 跟进 | [跟进／固定项](projects/20261119-112135-597762-follow-v03.png)<br>[跟进／空态](projects/20261119-112135-597762-follow-empty-v03.png)<br>[跟进／空状态操作提示](projects/20261119-122133-765524-empty-v01.png)<br>[跟进／长按已固定的待安排任务](projects/20261119-122133-765524-queued-v01.png)<br>[跟进／长按已排期的任务](projects/20261119-122133-765524-scheduled-v01.png) | — |
| 项目推进 | project-category | 项目分类 | 分类内项目列表 | [分类／普通列表](projects/20261119-122133-765524-list-v01.png)<br>[分类／长按项目](projects/20261119-122133-765524-project-v01.png) | — |
| 项目推进 | project-details | 项目详情 | — | [项目详情／进行中](projects/20261119-112135-597762-project-v03.png)<br>[项目详情／预计延期](projects/20261119-112135-597762-late-v03.png)<br>[项目详情／已完结](projects/20261119-112135-597762-finished-v03.png)<br>[项目详情／完结后新增待办](projects/20261119-112135-597762-extra-v03.png)<br>[项目详情／更多操作](projects/20261119-112135-597762-menu-v03.png)<br>[项目详情／加入后可撤销](projects/20261119-112135-597762-queued-v03.png)<br>[项目详情／长按未安排任务](projects/20261119-122133-765524-task-v01.png) | — |
| 项目推进 | project-task-list | 项目任务分类 | — | [任务分类／返回来源定位](projects/20261119-112135-597762-source-v03.png)<br>[任务分类／左滑操作](projects/20261119-112135-597762-swipe-v03.png) | — |
| 项目推进 | project-task-details | 项目任务详情 | — | [任务详情／已排时段](projects/20261119-112135-597762-task-v03.png) | — |
| 项目推进 | project-pick | 挑任务 | 跨分类挑任务 | [挑任务／未选择](projects/20261119-112135-597762-pick-v03.png)<br>[挑任务／跨分类多选](projects/20261119-112135-597762-picked-v03.png) | — |
| 项目推进 | project-pick-review | 加入待安排 | 挑选确认 | [加入待安排／确认](projects/20261119-112135-597762-review-v04.png) | — |
| 项目推进 | project-new-category | 新建项目分类 | 新建分类 | [分类／新建](projects/20261119-112135-597762-new-folder-v03.png) | — |
| 项目推进 | project-category-settings | 项目分类设置 | 分类设置 | [分类／设置](projects/20261119-112135-597762-edit-folder-v03.png) | — |
| 项目推进 | project-create | 新建项目 | — | [项目／新建](projects/20261119-112135-597762-new-project-v03.png) | — |
| 项目推进 | project-settings | 项目设置 | — | [项目／设置](projects/20261119-112135-597762-settings-v03.png)<br>[项目设置／状态选择](projects/20261119-112135-597762-state-v03.png) | — |
| 项目推进 | project-new-task | 项目内新建任务 | 项目新建任务 | [任务／新建](projects/20261119-112135-597762-new-task-v03.png) | — |
| 项目推进 | project-task-import | 移入已有任务 | — | [任务／移入已有任务](projects/20261119-112135-597762-import-v03.png) | — |
| 项目推进 | project-task-move | 移动任务 | — | [任务／移动](projects/20261119-112135-597762-move-v03.png) | — |
| 项目推进 | project-scheduling | 项目任务排程 | 手动安排 | [待安排区](projects/20261119-002315-972281-pending-v02.png)<br>[拖入时间表](projects/20261119-002315-972281-drag-v02.png)<br>[确认时段](projects/20261119-002315-972281-schedule-v02.png)<br>[选中时间块](projects/20261119-002315-972281-selected-v02.png) | — |
| 项目推进 | project-ai | 项目 AI 拆解 | AI 拆解 | [AI 拆解草稿](projects/20261119-002315-972281-ai-draft-v02.png)<br>[审核 AI 拆解](projects/20261119-002315-972281-ai-review-v02.png) | — |
| 模块管理 | module-connections | 模块与连接 | — | [模块管理与连接入口](settings/20261120-001608-406068-modules-v01.png)<br>[已安装模块提供设置（示例）](settings/20261119-163211-750631-module-contributions-v01.png) | — |
| 模块管理 | module-manager | 模块管理 | 已安装模块管理 | [已安装模块](settings/20261120-001608-406068-manager-v01.png)<br>[模块操作面板](settings/20261119-163211-750631-manager-actions-v01.png)<br>[早期密度试稿](module-manager/20261106-155000-404779-screenshot-module-manager-v01.png) | — |
| 模块管理 | module-store | 模块商店 | — | [模块目录](settings/20261119-163211-750631-store-v01.png)<br>[商店设置面板](settings/20261119-163211-750631-store-settings-v01.png)<br>[编辑目录来源](settings/20261119-163211-750631-repository-v01.png)<br>[模块商店／默认目录](module-manager/20261120-184553-999294-catalog-v01.png)<br>[模块商店／分类筛选面板](module-manager/20261120-184553-999294-categories-v01.png)<br>[模块商店／离线缓存与筛选无结果](module-manager/20261120-184553-999294-offline-empty-v01.png)<br>[模块商店／商店设置面板](module-manager/20261120-184553-999294-store-settings-v01.png)<br>[模块商店／可安装模块详情](module-manager/20261120-184553-999294-detail-v01.png) | — |
| 模块管理 | module-details | 模块详情 | 商店详情 | [安装前查看模块详情](settings/20261119-163211-750631-store-detail-v01.png) | — |
| 模块管理 | module-install | 确认模块安装计划 | 安装审核 | [安装计划审核](settings/20261119-163211-750631-install-review-v01.png) | — |
| 模块管理 | module-permissions | 模块权限与服务调用 | 模块权限、服务调用 | — | 收录模块服务授权与拒绝时的状态图。 |
| 模块管理 | restore-modules | 恢复内置模块 | — | [随客户端发布的模块](settings/20261119-163211-750631-restore-v01.png) | — |
| 模块管理 | data-recovery | 模块数据恢复与版本回退 | 数据恢复、版本回退 | — | 收录模块快照选择和回退确认的页面稿。 |
| AI 助手 | ai-chat | AI 对话 | AI 助手、聊天 | [历史参考 · 四屏方案](../dist/design/ai-ui-layout/legacy-20261029/drafts/ai-ui-layout-v2.png) | 从历史多屏参考中核对当前对话页，补录单页操作反馈稿。 |
| AI 助手 | ai-settings | AI 设置 | — | [普通聊天，尚未配置模型](settings/20261120-001608-406068-ai-v01.png)<br>[工作模式选择](settings/20261119-163211-750631-ai-mode-v01.png) | — |
| AI 助手 | model-connections | 模型连接 | — | [已配置模型服务](settings/20261119-163211-750631-connection-v01.png)<br>[服务配置面板](settings/20261119-163211-750631-connection-edit-v01.png)<br>[展开连接帮助](settings/20261119-163211-750631-connection-help-v01.png) | — |
| 应用设置 | settings | 设置首页 | 应用设置、设置 | [手机浅色](settings/20261119-134247-173693-phone-light-v01.png)<br>[手机深色](settings/20261119-134247-173693-phone-dark-state-v01.png)<br>[宽屏浅色](settings/20261119-134247-173693-wide-light-v01.png)<br>[搜索框与入口目录](settings/20261119-163211-750631-home-search-v02.png)<br>[在实际打开位置高亮入口](settings/20261119-163211-750631-located-v02.png) | — |
| 应用设置 | settings-search | 搜索设置 | 设置搜索 | [搜索「更新」](settings/20261119-163211-750631-search-results-v02.png)<br>[没有匹配的设置，键盘收起](settings/20261120-001608-406068-search-empty-v01.png)<br>[搜索「界面风格」，键盘收起](settings/20261120-001608-406068-search-v01.png) | — |
| 应用设置 | appearance | 外观与交互 | 外观设置 | [手机浅色 · 跟随系统](settings/20261120-001608-406068-appearance-v01.png)<br>[手机深色 · 减少动画](settings/20261120-001608-406068-appearance-dark-v01.png) | — |
| 应用设置 | style-picker | 界面风格 | — | [当前风格](settings/20261120-001608-406068-style-v01.png)<br>[模块专属选择面板](settings/20261119-163211-750631-style-pick-v01.png)<br>[界面风格／待保存的全局风格](settings/20261120-184554-020015-style-v01.png)<br>[界面风格／模块专属选择面板](settings/20261120-184554-020015-style-module-v01.png) | — |
| 应用设置 | style-preview | 界面预览 | — | [列表页模拟预览](settings/20261119-163211-750631-style-preview-v01.png) | — |
| 应用设置 | layout-navigation | 布局与导航 | 布局设置 | [手机配置总览](settings/20261120-001608-406068-layout-v01.png)<br>[结构预览](settings/20261119-163211-750631-draft-v02.png)<br>[查看草稿变更](settings/20261119-163211-750631-diff-v02.png) | — |
| 应用设置 | entry-arranger | 编排入口 | 入口编排 | [手机配置 · 底部导航预览](settings/20261120-001608-406068-nav-v01.png)<br>[拖到左区，底栏切入](settings/20261119-163211-750631-hover-nav-v02.png)<br>[拖到中区，菜单切入](settings/20261119-163211-750631-switch-drag-v02.png)<br>[下方 App 右上角菜单](settings/20261119-163211-750631-menu-v02.png)<br>[菜单内的可放置位置](settings/20261119-163211-750631-insert-drag-v02.png)<br>[已放置模块，草稿待保存](settings/20261119-163211-750631-placed-v02.png)<br>[拖到右区，更多切入](settings/20261119-163211-750631-hover-more-v02.png)<br>[下方 App 更多页](settings/20261119-163211-750631-more-preview-v02.png)<br>[筛选可编排的入口](settings/20261119-163211-750631-tray-search-v02.png)<br>[更多页面与直显上限](settings/20261119-163211-750631-nav-options-v02.png)<br>[关闭更多后的底栏](settings/20261119-163211-750631-more-off-v02.png)<br>[关闭更多后的备用入口页](settings/20261119-163211-750631-overflow-v02.png)<br>[宽屏／图标库与侧栏预览](settings/20261119-163211-750631-wide-v02.png)<br>[点选图标／编辑入口](settings/20261119-163211-750631-entry-v02.png)<br>[选择兼容位置](settings/20261119-163211-750631-position-v02.png)<br>[选择排序参照](settings/20261119-163211-750631-order-v02.png)<br>[指定任务或项目](settings/20261119-163211-750631-context-v02.png)<br>[编辑直显上限](settings/20261119-163211-750631-limit-v02.png)<br>[搜索可选入口／打开](settings/20261120-184554-020015-entry-open-v01.png)<br>[搜索可选入口／搜索课表](settings/20261120-184554-020015-entry-match-v01.png)<br>[搜索可选入口／无匹配](settings/20261120-184554-020015-entry-empty-v01.png) | — |
| 应用设置 | entry-directory | 入口目录 | — | [打开入口](settings/20261120-001608-406068-directory-v01.png)<br>[查找位置](settings/20261120-001608-406068-directory-locate-v01.png)<br>[同一功能有多个打开路径](settings/20261119-163211-750631-locations-v02.png)<br>[主导航溢出到更多](settings/20261119-163211-750631-location-overflow-v02.png)<br>[已隐藏但可从目录打开](settings/20261119-163211-750631-location-hidden-v02.png) | — |
| 应用设置 | shortcuts | 常用与隐藏入口 | — | [常用与隐藏分组](settings/20261119-163211-750631-shortcuts-v01.png) | — |
| 应用设置 | page-layout | 页面内容布局 | — | [页面槽位编排](settings/20261119-163211-750631-page-layout-v01.png) | — |
| 应用设置 | layout-advanced | 高级编辑 | — | [选择贡献与槽位](settings/20261119-163211-750631-add-slot-v01.png)<br>[筛选与分组](settings/20261119-163211-750631-advanced-v01.png)<br>[存在失效配置](settings/20261119-163211-750631-issue-v01.png) | — |
| 应用设置 | update-settings | 更新设置 | — | [打开并定位到命中项](settings/20261119-163211-750631-search-target-v02.png)<br>[自动与手动检查](settings/20261120-001608-406068-updates-v01.png)<br>[更新设置／启动时检查更新已开启](settings/20261120-184554-020015-startup-v01.png) | — |
| 应用设置 | app-updates | 检查更新 | 检查 App 更新、应用更新 | [当前已是最新版本](settings/20261120-001608-406068-up-to-date-v01.png)<br>[发现新版本](settings/20261119-163211-750631-update-found-v01.png)<br>[检查未完成](settings/20261119-163211-750631-update-error-v01.png) | — |
| 应用设置 | config-export | 导出所有配置 | 配置导出 | [默认导出范围](settings/20261120-001608-406068-export-v01.png)<br>[已选包含 API 密钥](settings/20261120-001608-406068-export-keys-v01.png) | — |
| 应用设置 | support-tools | 辅助工具 | — | [标注关闭](settings/20261120-001608-406068-tools-v01.png) | — |
| 应用设置 | display-diagnostics | 显示与布局信息 | 显示诊断 | [实时显示指标](settings/20261120-001608-406068-diagnostics-v01.png)<br>[展开边距明细](settings/20261120-001608-406068-insets-v01.png) | — |
| 应用设置 | about | 关于序点 | 关于 | [版本、数据与仓库](settings/20261120-001608-406068-about-v01.png)<br>[宽屏 · 双栏](settings/20261120-001608-406068-about-wide-v01.png) | — |
| 全局与通用 | more | 更多 | 更多页 | [入口试稿](settings/20261106-155000-376270-screenshot-more-v02.png) | 核对更多页试稿与当前入口布局。 |
| 全局与通用 | data-change-review | 数据变更审核 | 查看变更详情 | — | 补充跨模块审核使用业务名称的设计，以及简洁确认和展开详情的状态稿。 |
| 全局与通用 | styles | 整体视觉风格 | 视觉基准 | [融合方案选稿](styles/20261030-013221-184495-c-legacy-fusion-v02.png) | — |
