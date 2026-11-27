# UI 页面与设计稿映射表

按功能分类查找页面，点击状态名称打开现行图稿。浅色、深色、空态、拖动和弹窗等独立状态分别登记。本机的[看图文件夹](看图目录/)和[离线看图页](看图目录/00-看图目录.html)均按功能、所属模块和页面归类。

“待审”表示该状态的设计待确认。“待完善”栏记录后续工作。查询命令见[设计入口](README.md)，设备验收待办见[项目待办](../docs/BACKLOG.md)与[平台验收细则](../docs/PLATFORM_VERIFICATION.md#设备验收缺口)。

## 日程与任务

| 功能分类 | 所属模块 | 页面标识 | 页面名称 | 别名 | 设计稿与状态 | 待完善 |
| --- | --- | --- | --- | --- | --- | --- |
| 日程与任务 | app.ideas | ideas | 想法 | 想法时间线、收藏想法 | [已确认 · 想法／全部记录](ideas/20261125-232953-233199-timeline-v01.png)<br>[已确认 · 搜索想法／正文匹配](ideas/20261125-232953-233199-search-results-v01.png)<br>[已确认 · 搜索想法／没有匹配](ideas/20261124-174952-691858-search-empty-v01.png)<br>[已确认 · 按日期查看／从日期标题打开](ideas/20261125-232953-233199-day-v01.png)<br>[已确认 · 按日期查看／选择指定日期](ideas/20261124-174952-691858-day-picker-v01.png)<br>[已确认 · 按日期查看／切换至指定日期](ideas/20261124-174952-691858-day-changed-v01.png)<br>[已确认 · 想法／输入与键盘](ideas/20261125-232953-233199-writing-v01.png)<br>[已确认 · 想法／首次记录前](ideas/20261125-232953-233199-empty-v01.png)<br>[已确认 · 想法／保存失败](ideas/20261125-232953-233199-save-error-v01.png)<br>[已确认 · 想法／收藏列表](ideas/20261125-232953-233199-favorites-v01.png)<br>[已确认 · 想法／暂无收藏](ideas/20261125-232953-233199-favorites-empty-v01.png)<br>[已确认 · 想法／长按条目菜单](ideas/20261125-232953-233199-menu-v01.png)<br>[已确认 · 编辑想法／修改正文](ideas/20261125-232953-233199-edit-v01.png)<br>[已确认 · 想法／编辑保存后](ideas/20261125-232953-233199-saved-v01.png)<br>[已确认 · 删除想法／确认删除](ideas/20261124-174952-691858-delete-v02.png)<br>[已确认 · 从想法创建任务／待填写名称](ideas/20261124-174952-691858-create-task-v02.png)<br>[已确认 · 从想法创建项目／待填写名称](ideas/20261124-174952-691858-create-project-v02.png)<br>[已确认 · 想法／展开创建记录](ideas/20261125-232953-233199-records-v01.png) | 时间顺序、底部留白、长按选中框与一次保存已确认。模块说明见[想法模块计划](../docs/features/IDEAS_PLAN.md)。 |
| 日程与任务 | app.views.today | schedule-home | 日程首页 | 今天、日程 | [待审 · 日程首页／时间轴方案](schedule-home/20261123-143359-881592-timeline-v02.png)<br>[待审 · 日程首页／展开添加任务与键盘](schedule-home/20261123-143359-881592-quick-v02.png)<br>[待审 · 日程首页／所选日期无安排](schedule-home/20261123-143359-881592-empty-v02.png)<br>[待审 · 日程首页／课程读取失败、保留任务](schedule-home/20261123-143359-881592-course-error-v02.png)<br>[待审 · 日程首页／深色主题与正在上课](schedule-home/20261123-143359-881592-night-v02.png)<br>[待审 · 日程首页／宽屏侧栏与双栏日程](schedule-home/20261123-143359-881592-desktop-v02.png)<br>[待审 · 日程首页／窄屏大字号](schedule-home/20261123-143359-881592-large-v02.png) | 已选时间轴。日期切换集中在顶栏，移除五天日期条的修订稿待确认。 |
| 日程与任务 | app.planner | planner | 任务规划看板 | 时间表、任务规划 | [已确认 · 任务规划／智能时段](planner/20261124-014806-190307-smart-range-v01.png)<br>[已确认 · 任务规划／上边界继续下拉](planner/20261124-014806-190307-smart-edge-top-v01.png)<br>[已确认 · 任务规划／下边界继续上拉](planner/20261124-014806-190307-smart-edge-bottom-v01.png)<br>[已确认 · 任务规划／拖动任务越过下边界](planner/20261124-014806-190307-smart-drag-task-v01.png)<br>[已确认 · 任务规划／展开全天后查看凌晨](planner/20261124-014806-190307-smart-full-day-v01.png) | 按可见内容与视口设置范围，越界拖动后在本次会话显示全天。 |
| 日程与任务 | app.planner | new-task | 新建任务 | 规划新建任务 | [待审 · 新建任务／基础表单](new-task/20261106-155000-318838-screenshot-task-create-v01.png) | 基础表单待确认，草稿恢复状态待补图。 |
| 日程与任务 | app.planner | task-details | 任务详情与编辑 | 规划任务详情 | [待审 · 任务详情／已排时间](planner/20261123-141956-658051-task-v01.png)<br>[待审 · 任务详情／展开描述与截止时间](planner/20261123-141956-658051-task-expanded-v01.png)<br>[待审 · 任务详情／从规划看板打开](planner/20261123-141956-658051-task-panel-v01.png)<br>[待审 · 任务详情／已完成](planner/20261123-141956-658051-done-v01.png)<br>[待审 · 任务详情／已取消](planner/20261123-141956-658051-stopped-v01.png)<br>[待审 · 编辑时间／调整任务起止](planner/20261123-141956-658051-task-time-v01.png) | 规划和批量任务入口的详情、编辑及面板稿待确认。 |
| 日程与任务 | app.planner | task-repeat | 任务重复设置 | 重复规则 | [待审 · 重复方式／最大间隔](planner/20261123-141956-658051-rule-repeat-v01.png) | 最大间隔规则稿待确认，其他重复方式继续复用同一表单。 |
| 日程与任务 | app.planner | batch-tasks | 批量任务管理 | 批量生成任务 | [管理页选稿](batch-tasks/20261103-162137-563384-batch-management-mobile-light-v02.png) | — |
| 日程与任务 | app.planner | planning-preview | 规划预览与提交确认 | 规划预览 | [待审 · 安排预览／存在未安排任务](planner/20261123-141956-658051-preview-v01.png)<br>[已确认 · 确认安排任务／普通安排](planner/20261124-014806-190307-confirm-schedule-v02.png)<br>[已确认 · 确认安排任务／过去时段](planner/20261124-014806-190307-confirm-schedule-past-v02.png)<br>[已确认 · 确认安排任务／超过截止时间](planner/20261124-014806-190307-confirm-schedule-overdue-v02.png) | 单次确认安排图稿已确认；独立安排预览稿待审。 |
| 日程与任务 | app.planner | task-history | 完成历史 | 任务复盘、操作历史 | [待审 · 完成复盘／按完成时间查看](planner/20261123-141956-658051-completed-review-v01.png "app.views.today")<br>[待审 · 操作历史／按本地日期分组](planner/20261123-141956-658051-history-v01.png)<br>[待审 · 操作历史／暂无记录](planner/20261123-141956-658051-history-empty-v01.png) | 完成复盘和操作历史待确认；沿用原有编辑与整次撤销入口。 |
| 日程与任务 | app.views.today | daily-task-edit | 日程内编辑任务 | — | [待审 · 编辑任务／从日程或完成复盘打开](planner/20261123-141956-658051-daily-edit-v01.png) | 等候本轮设计稿确认。 |
| 日程与任务 | app.planner | cancelled-tasks | 已取消任务 | — | [待审 · 已取消任务／原时段与恢复入口](planner/20261123-141956-658051-stopped-list-v01.png) | 等候本轮设计稿确认。 |
| 日程与任务 | app.planner | auto-plan | 自动安排 | — | [待审 · 自动安排／尚未选择](planner/20261123-141956-658051-choose-v01.png)<br>[待审 · 自动安排／已选两项](planner/20261123-141956-658051-choose-multi-v01.png) | 等候本轮设计稿确认。 |
| 日程与任务 | app.planner | planning-rules | 规划规则 | — | [待审 · 规划规则／规则列表](planner/20261123-141956-658051-rules-v01.png)<br>[待审 · 规划规则／模板展开](planner/20261123-141956-658051-templates-v01.png)<br>[待审 · 规划规则／规则操作展开](planner/20261123-141956-658051-rule-actions-v01.png) | 等候本轮设计稿确认。 |
| 日程与任务 | app.planner | edit-rule | 编辑规则 | — | [待审 · 编辑规则／规则概览](planner/20261123-141956-658051-rule-edit-v01.png) | 等候本轮设计稿确认。 |
| 日程与任务 | app.planner | rule-window | 规则允许安排时段 | — | [待审 · 允许安排时段／日期与星期](planner/20261123-141956-658051-rule-window-v01.png) | 等候本轮设计稿确认。 |
| 日程与任务 | app.planner | planner-settings | 规划设置 | — | [待审 · 规划设置／时间与规则入口](planner/20261123-141956-658051-planning-settings-v01.png) | 等候本轮设计稿确认。 |
| 日程与任务 | app.planner | weekly-availability | 每周可用时间 | — | [待审 · 每周可用时间／按星期编辑](planner/20261123-141956-658051-weekly-v01.png) | 等候本轮设计稿确认。 |
| 日程与任务 | app.planner | day-availability | 当天可用时间 | — | [待审 · 当天可用时间／填写时段](planner/20261123-141956-658051-exception-v01.png) | 等候本轮设计稿确认。 |
| 日程与任务 | app.planner | busy-time | 添加忙碌时段 | — | [待审 · 添加忙碌时段／填写时段](planner/20261123-141956-658051-busy-v01.png) | 等候本轮设计稿确认。 |
| 日程与任务 | app.planner | attach-task | 选择已有待办 | — | [待审 · 选择已有待办／填写时段](planner/20261123-141956-658051-attach-v01.png) | 等候本轮设计稿确认。 |
| 日程与任务 | app.planner | planner-instance | 编辑规划实例 | — | [待审 · 编辑规划／规则实例操作展开](planner/20261123-141956-658051-instance-v01.png) | 等候本轮设计稿确认。 |
| 日程与任务 | app.planner | planner-display | 详情显示 | — | [待审 · 详情显示／课程卡片与详情预览](planner/20261123-141956-658051-display-v01.png) | 等候本轮设计稿确认。 |

## 课表与教务

| 功能分类 | 所属模块 | 页面标识 | 页面名称 | 别名 | 设计稿与状态 | 待完善 |
| --- | --- | --- | --- | --- | --- | --- |
| 课表与教务 | app.schedule | timetable | 课表周视图 | 课表、周课表 | [现有界面参考 · 设备截图](timetable/.batches/20261123-141956-595143/references/android-schedule-week-grid-home.png) | — |
| 课表与教务 | app.schedule | courses | 课程详情与课程管理 | 课程详情、课程管理 | [课程管理／课程列表](timetable/20261120-184554-037605-courses-v01.png)<br>[课程管理／周期安排展开](timetable/20261120-184554-037605-arrangement-v01.png)<br>[课程管理／当前课表没有课程](timetable/20261120-184554-037605-courses-empty-v01.png)<br>[课程管理／编辑课程与安排](timetable/20261120-184554-037605-course-editor-v01.png)<br>[待审 · 课程详情／从日程打开](timetable/20261123-141956-595143-detail-v01.png)<br>[待审 · 课程详情／从课表打开](timetable/20261123-141956-595143-panel-v01.png)<br>[待审 · 课程详情／宽屏右侧面板](timetable/20261123-141956-595143-wide-v01.png)<br>[待审 · 课程详情／已调整](timetable/20261123-141956-595143-moved-v01.png)<br>[待审 · 课程详情／已取消](timetable/20261123-141956-595143-cancelled-v01.png)<br>[待审 · 课程详情／临时加课](timetable/20261123-141956-595143-extra-v01.png)<br>[待审 · 课程详情／该次课程已不存在](timetable/20261123-141956-595143-missing-v01.png) | 课程详情、已调整／取消状态和自适应面板待确认。 |
| 课表与教务 | app.schedule | timetable-settings | 课表设置 | — | [已选择课表](settings/20261120-001608-406068-schedule-v01.png) | — |
| 课表与教务 | app.schedule | timetable-manager | 课表管理 | — | [选择与管理课表](settings/20261119-163211-750631-timetables-v01.png) | — |
| 课表与教务 | app.schedule | timetable-display | 课表显示设置 | — | [课表同步预览](settings/20261119-163211-750631-schedule-display-v01.png) | — |
| 课表与教务 | app.schedule | semester-settings | 学期设置 | — | [编辑学期](settings/20261119-163211-750631-semester-v01.png)<br>[高级时区展开](settings/20261119-163211-750631-semester-zone-v01.png) | — |
| 课表与教务 | app.schedule | period-settings | 作息设置 | — | [上午时段](settings/20261119-163211-750631-periods-v01.png) | — |
| 课表与教务 | app.import.shiguang | course-import | 拾光教务导入 | 课程导入、拾光导入 | [选择导入方式](settings/20261120-001608-406068-import-v01.png)<br>[选择学校／按名称搜索](course-import/20261120-184554-029987-schools-v01.png)<br>[选择学校／无匹配学校](course-import/20261120-184554-029987-school-empty-v01.png)<br>[通用系统导入／选择教务系统](course-import/20261120-184554-029987-systems-v01.png)<br>[中国石油大学（北京）／本科入口与教务网址](course-import/20261120-184554-029987-school-detail-v01.png)<br>[使用学校适配脚本／粘贴脚本](course-import/20261120-184554-029987-paste-v01.png)<br>[选择导入目标／已有课表](course-import/20261120-184554-029987-target-v01.png)<br>[确认学期配置／合并到已有课表](course-import/20261120-184554-029987-semester-v01.png)<br>[导入预览／已生成课程草稿](course-import/20261120-184554-029987-preview-v01.png)<br>[处理导入地点／去掉校区名称](course-import/20261120-184554-029987-location-v01.png)<br>[处理导入冲突／来源与本地值冲突](course-import/20261120-184554-029987-conflicts-v01.png)<br>[关于与致谢／来源与许可](course-import/20261120-184554-029987-about-v01.png) | — |
| 课表与教务 | app.schedule | single-course-change | 单次调课 | — | [待审 · 单次调课／移动或换地点](timetable/20261123-141956-595143-change-v01.png)<br>[待审 · 单次调课／取消本次](timetable/20261123-141956-595143-cancel-v01.png) | 等候本轮设计稿确认。 |
| 课表与教务 | app.schedule | extra-course | 临时加课 | — | [待审 · 临时加课／填写本次安排](timetable/20261123-141956-595143-add-v01.png) | 等候本轮设计稿确认。 |
| 课表与教务 | app.schedule | course-changes | 调课记录 | — | [待审 · 调课记录／已有变更](timetable/20261123-141956-595143-changes-v01.png)<br>[待审 · 调课记录／无记录](timetable/20261123-141956-595143-changes-empty-v01.png)<br>[待审 · 调课记录／撤销单次变更前确认](timetable/20261123-141956-595143-undo-v02.png) | 撤销前展示本次课程与恢复结果，待确认。 |
| 课表与教务 | app.schedule | teaching-week-picker | 选择教学周 | — | [现有界面参考 · 设备截图](timetable/.batches/20261123-141956-595143/references/android-schedule-week-grid-picker.png) | — |
| 课表与教务 | app.schedule | timetable-switch | 切换课表 | — | [现有界面参考 · 设备截图](timetable/.batches/20261123-141956-595143/references/android-schedule-week-grid-switch.png) | — |
| 课表与教务 | app.schedule | new-timetable | 新建课表 | — | [待审 · 新建课表／学期与节次](timetable/20261123-141956-595143-new-table-v01.png) | 等候本轮设计稿确认。 |
| 课表与教务 | app.schedule | today-courses | 今日课程 | — | [待审 · 今日课程／当日课程列表](timetable/20261123-141956-595143-today-v01.png) | 等候本轮设计稿确认。 |
| 课表与教务 | app.schedule | schedule-backup | 导入与备份 | — | [待审 · 导入与备份／读取 JSON 备份](timetable/20261123-141956-595143-backup-v01.png)<br>[待审 · 导入与备份／处理来源与本地冲突](timetable/20261123-141956-595143-backup-conflict-v01.png) | 等候本轮设计稿确认。 |
| 课表与教务 | app.schedule | backup-mode | 备份导入方式 | — | [待审 · 导入方式／合并当前课表](timetable/20261123-141956-595143-backup-mode-v01.png) | 等候本轮设计稿确认。 |

## 项目推进

| 功能分类 | 所属模块 | 页面标识 | 页面名称 | 别名 | 设计稿与状态 | 待完善 |
| --- | --- | --- | --- | --- | --- | --- |
| 项目推进 | app.tasks | projects | 项目目录 | 项目推进、项目首页 | [目录／分类列表](projects/20261119-112135-597762-directory-v03.png)<br>[目录／长按分类](projects/20261119-122133-765524-folder-v01.png) | — |
| 项目推进 | app.tasks | project-activity | 项目待推进 | 待推进 | [待推进／最近优先](projects/20261119-112135-597762-activity-v03.png)<br>[待推进／排序菜单](projects/20261119-112135-597762-sort-v03.png)<br>[待推进／最久优先](projects/20261119-112135-597762-oldest-v03.png)<br>[待推进／加入待安排后返回](projects/20261119-112135-597762-updated-v03.png)<br>[待推进／空态](projects/20261119-112135-597762-empty-v03.png)<br>[待推进／长按项目](projects/20261119-122133-765524-activity-v01.png)<br>[待推进／新增待办全部完成后返回列表](projects/20261119-002315-972281-activity-after-v02.png) | — |
| 项目推进 | app.tasks | project-follow | 项目跟进 | 跟进 | [跟进／固定项](projects/20261119-112135-597762-follow-v03.png)<br>[跟进／空状态操作提示](projects/20261119-122133-765524-empty-v01.png)<br>[跟进／长按已固定的待安排任务](projects/20261119-122133-765524-queued-v01.png)<br>[跟进／长按已排期的任务](projects/20261119-122133-765524-scheduled-v01.png) | — |
| 项目推进 | app.tasks | project-category | 项目分类 | 分类内项目列表 | [分类／普通列表](projects/20261119-122133-765524-list-v01.png)<br>[分类／长按项目](projects/20261119-122133-765524-project-v01.png) | — |
| 项目推进 | app.tasks | project-details | 项目详情 | — | [项目详情／进行中](projects/20261119-112135-597762-project-v03.png)<br>[项目详情／预计延期](projects/20261119-112135-597762-late-v03.png)<br>[项目详情／已完结](projects/20261119-112135-597762-finished-v03.png)<br>[项目详情／完结后新增待办](projects/20261119-112135-597762-extra-v03.png)<br>[项目详情／更多操作](projects/20261119-112135-597762-menu-v03.png)<br>[项目详情／加入后可撤销](projects/20261119-112135-597762-queued-v03.png)<br>[项目详情／长按未安排任务](projects/20261119-122133-765524-task-v01.png) | — |
| 项目推进 | app.tasks | project-task-list | 项目任务分类 | — | [任务分类／返回来源定位](projects/20261119-112135-597762-source-v03.png)<br>[任务分类／左滑操作](projects/20261119-112135-597762-swipe-v03.png) | — |
| 项目推进 | app.tasks | project-task-details | 项目任务详情 | — | [任务详情／已排时段](projects/20261119-112135-597762-task-v03.png) | — |
| 项目推进 | app.tasks | project-pick | 挑任务 | 跨分类挑任务 | [挑任务／未选择](projects/20261119-112135-597762-pick-v03.png)<br>[挑任务／跨分类多选](projects/20261119-112135-597762-picked-v03.png) | — |
| 项目推进 | app.tasks | project-pick-review | 加入待安排 | 挑选确认 | [加入待安排／确认](projects/20261119-112135-597762-review-v04.png) | — |
| 项目推进 | app.tasks | project-new-category | 新建项目分类 | 新建分类 | [分类／新建](projects/20261119-112135-597762-new-folder-v03.png) | — |
| 项目推进 | app.tasks | project-category-settings | 项目分类设置 | 分类设置 | [分类／设置](projects/20261119-112135-597762-edit-folder-v03.png) | — |
| 项目推进 | app.tasks | project-create | 新建项目 | — | [项目／新建](projects/20261119-112135-597762-new-project-v03.png) | — |
| 项目推进 | app.tasks | project-settings | 项目设置 | — | [项目／设置](projects/20261119-112135-597762-settings-v03.png)<br>[项目设置／状态选择](projects/20261119-112135-597762-state-v03.png) | — |
| 项目推进 | app.tasks | project-new-task | 项目内新建任务 | 项目新建任务 | [任务／新建](projects/20261119-112135-597762-new-task-v03.png) | — |
| 项目推进 | app.tasks | project-task-import | 移入已有任务 | — | [任务／移入已有任务](projects/20261119-112135-597762-import-v03.png) | — |
| 项目推进 | app.tasks | project-task-move | 移动任务 | — | [任务／移动](projects/20261119-112135-597762-move-v03.png) | — |
| 项目推进 | app.planner | project-scheduling | 项目任务排程 | 手动安排 | [待安排区](projects/20261119-002315-972281-pending-v02.png)<br>[拖入时间表](projects/20261119-002315-972281-drag-v02.png)<br>[确认时段](projects/20261119-002315-972281-schedule-v02.png)<br>[选中时间块](projects/20261119-002315-972281-selected-v02.png) | — |
| 项目推进 | app.ai | project-ai | 项目 AI 拆解 | AI 拆解 | [AI 拆解草稿](projects/20261119-002315-972281-ai-draft-v02.png)<br>[审核 AI 拆解](projects/20261119-002315-972281-ai-review-v02.png) | — |

## 模块管理

| 功能分类 | 所属模块 | 页面标识 | 页面名称 | 别名 | 设计稿与状态 | 待完善 |
| --- | --- | --- | --- | --- | --- | --- |
| 模块管理 | 宿主 | module-connections | 模块与连接 | — | [模块管理与连接入口](settings/20261120-001608-406068-modules-v01.png)<br>[已安装模块提供设置（示例）](settings/20261119-163211-750631-module-contributions-v01.png) | — |
| 模块管理 | 宿主 | module-manager | 模块管理 | 已安装模块管理 | [已安装模块](settings/20261120-001608-406068-manager-v01.png)<br>[模块操作面板](settings/20261119-163211-750631-manager-actions-v01.png) | — |
| 模块管理 | 宿主 | module-store | 模块商店 | — | [编辑目录来源](settings/20261119-163211-750631-repository-v01.png)<br>[模块商店／默认目录](module-manager/20261120-184553-999294-catalog-v01.png)<br>[模块商店／分类筛选面板](module-manager/20261120-184553-999294-categories-v01.png)<br>[模块商店／离线缓存与筛选无结果](module-manager/20261120-184553-999294-offline-empty-v01.png)<br>[模块商店／商店设置面板](module-manager/20261120-184553-999294-store-settings-v01.png) | — |
| 模块管理 | 宿主 | module-details | 模块详情 | 商店详情 | [安装前查看模块详情](module-manager/20261120-184553-999294-detail-v01.png) | — |
| 模块管理 | 宿主 | module-install | 确认模块安装计划 | 安装审核 | [安装计划审核](settings/20261119-163211-750631-install-review-v01.png) | — |
| 模块管理 | 宿主 | module-permissions | 模块权限与服务调用 | 模块权限、服务调用 | [待审 · 模块调用授权／核对服务与额度](module-manager/20261123-141956-690919-access-v01.png)<br>[待审 · 模块调用授权／拒绝后返回对话](module-manager/20261123-141956-690919-access-denied-v01.png "app.ai") | 工具范围、额度与拒绝反馈待确认。 |
| 模块管理 | 宿主 | restore-modules | 恢复内置模块 | — | [随客户端发布的模块](settings/20261119-163211-750631-restore-v01.png) | — |
| 模块管理 | 宿主 | data-recovery | 模块数据恢复与版本回退 | 数据恢复、版本回退 | [待审 · 数据快照恢复／选择历史快照](module-manager/20261123-141956-690919-snapshots-v01.png)<br>[待审 · 数据快照恢复／暂无快照](module-manager/20261123-141956-690919-snapshots-empty-v01.png)<br>[待审 · 数据快照恢复／确认恢复旧快照](module-manager/20261123-141956-690919-recover-v01.png)<br>[待审 · 版本历史／选择历史版本](module-manager/20261123-141956-690919-versions-v01.png)<br>[待审 · 版本回退／确认版本和数据影响](module-manager/20261123-141956-690919-rollback-v01.png) | 版本选择、快照选择与二次确认稿待确认。 |
| 模块管理 | 宿主 | rule-runs | 规则执行记录 | — | [待审 · 规则执行记录／记录与重试](module-manager/20261123-141956-690919-runs-v01.png) | 等候本轮设计稿确认。 |

## AI 助手

| 功能分类 | 所属模块 | 页面标识 | 页面名称 | 别名 | 设计稿与状态 | 待完善 |
| --- | --- | --- | --- | --- | --- | --- |
| AI 助手 | app.ai | ai-chat | AI 对话 | AI 助手、聊天 | — | 待补 AI 对话页和操作反馈的单界面图。 |
| AI 助手 | app.ai | ai-settings | AI 设置 | — | [普通聊天，尚未配置模型](settings/20261120-001608-406068-ai-v01.png)<br>[工作模式选择](settings/20261119-163211-750631-ai-mode-v01.png) | — |
| AI 助手 | app.ai | model-connections | 模型连接 | — | [已配置模型服务](settings/20261119-163211-750631-connection-v01.png)<br>[服务配置面板](settings/20261119-163211-750631-connection-edit-v01.png)<br>[展开连接帮助](settings/20261119-163211-750631-connection-help-v01.png) | — |

## 应用设置

| 功能分类 | 所属模块 | 页面标识 | 页面名称 | 别名 | 设计稿与状态 | 待完善 |
| --- | --- | --- | --- | --- | --- | --- |
| 应用设置 | 宿主 | settings | 设置首页 | 应用设置、设置 | [手机浅色 · 搜索与入口目录](settings/20261119-163211-750631-home-search-v02.png)<br>[手机深色](settings/20261119-134247-173693-phone-dark-state-v01.png)<br>[宽屏浅色](settings/20261119-134247-173693-wide-light-v01.png)<br>[在实际打开位置高亮入口](settings/20261119-163211-750631-located-v02.png) | — |
| 应用设置 | 宿主 | settings-search | 搜索设置 | 设置搜索 | [搜索「更新」](settings/20261119-163211-750631-search-results-v02.png)<br>[没有匹配的设置，键盘收起](settings/20261120-001608-406068-search-empty-v01.png)<br>[搜索「界面风格」，键盘收起](settings/20261120-001608-406068-search-v01.png) | — |
| 应用设置 | 宿主 | appearance | 外观与交互 | 外观设置 | [手机浅色 · 跟随系统](settings/20261120-001608-406068-appearance-v01.png)<br>[手机深色 · 减少动画](settings/20261120-001608-406068-appearance-dark-v01.png) | — |
| 应用设置 | 宿主 | style-picker | 界面风格 | — | [当前风格](settings/20261120-001608-406068-style-v01.png)<br>[界面风格／待保存的全局风格](settings/20261120-184554-020015-style-v01.png)<br>[界面风格／模块专属选择面板](settings/20261120-184554-020015-style-module-v01.png) | — |
| 应用设置 | 宿主 | style-preview | 界面预览 | — | [列表页模拟预览](settings/20261119-163211-750631-style-preview-v01.png) | — |
| 应用设置 | 宿主 | layout-navigation | 布局与导航 | 布局设置 | [手机配置总览](settings/20261120-001608-406068-layout-v01.png)<br>[结构预览](settings/20261119-163211-750631-draft-v02.png)<br>[查看草稿变更](settings/20261119-163211-750631-diff-v02.png) | — |
| 应用设置 | 宿主 | entry-arranger | 编排入口 | 入口编排 | [已确认 · 编排入口／底部导航／查看与排序](more/20261125-131639-563664-arranger-nav-v04.png)<br>[已确认 · 编排入口／底部导航／拖动图标](more/20261125-131639-563664-arranger-nav-drag-v04.png)<br>[已确认 · 编排入口／底部导航／添加入口后](more/20261125-131639-563664-arranger-nav-added-v04.png)<br>[已确认 · 编排入口／底部导航／从其他分区移入](more/20261125-131639-563664-arranger-nav-moved-v04.png)<br>[已确认 · 编排入口／底部导航／入口操作面板](more/20261125-131639-563664-arranger-nav-actions-v04.png)<br>[已确认 · 编排入口／底部导航／移除与撤销](more/20261125-131639-563664-arranger-nav-removed-v04.png)<br>[已确认 · 编排入口／底部导航／超出直显上限](more/20261125-131639-563664-arranger-nav-overflow-v04.png)<br>[已确认 · 编排入口／右上角菜单／菜单项与固定项](more/20261125-131639-563664-arranger-menu-v04.png)<br>[已确认 · 编排入口／更多／常用工具](more/20261125-131639-563664-arranger-more-v04.png)<br>[已确认 · 编排入口／更多／拖动条目](more/20261125-131639-563664-arranger-more-drag-v04.png)<br>[已确认 · 编排入口／更多／移除最后一个工具](more/20261125-131639-563664-arranger-more-empty-v04.png)<br>[已确认 · 编排入口／侧栏导航／宽屏编排](more/20261125-131639-563664-arranger-side-v04.png) | 已确认。拖动移除使用编排页底部的移除区。 |
| 应用设置 | 宿主 | entry-directory | 入口目录 | — | [打开入口](settings/20261120-001608-406068-directory-v01.png)<br>[查找位置](settings/20261120-001608-406068-directory-locate-v01.png)<br>[同一功能有多个打开路径](settings/20261119-163211-750631-locations-v02.png)<br>[主导航溢出到更多](settings/20261119-163211-750631-location-overflow-v02.png)<br>[已隐藏但可从目录打开](settings/20261119-163211-750631-location-hidden-v02.png) | — |
| 应用设置 | 宿主 | shortcuts | 常用与隐藏入口 | — | [常用与隐藏分组](settings/20261119-163211-750631-shortcuts-v01.png) | — |
| 应用设置 | 宿主 | page-layout | 页面内容布局 | — | [页面槽位编排](settings/20261119-163211-750631-page-layout-v01.png) | — |
| 应用设置 | 宿主 | layout-advanced | 高级编辑 | — | [选择贡献与槽位](settings/20261119-163211-750631-add-slot-v01.png)<br>[筛选与分组](settings/20261119-163211-750631-advanced-v01.png)<br>[存在失效配置](settings/20261119-163211-750631-issue-v01.png) | — |
| 应用设置 | 宿主 | update-settings | 更新设置 | — | [打开并定位到命中项](settings/20261119-163211-750631-search-target-v02.png)<br>[自动与手动检查](settings/20261120-001608-406068-updates-v01.png)<br>[更新设置／启动时检查更新已开启](settings/20261120-184554-020015-startup-v01.png) | — |
| 应用设置 | 宿主 | app-updates | 检查更新 | 检查 App 更新、应用更新 | [当前已是最新版本](settings/20261120-001608-406068-up-to-date-v01.png)<br>[发现新版本](settings/20261119-163211-750631-update-found-v01.png)<br>[检查未完成](settings/20261119-163211-750631-update-error-v01.png) | — |
| 应用设置 | 宿主 | config-export | 导出所有配置 | 配置导出 | [默认导出范围](settings/20261120-001608-406068-export-v01.png)<br>[已选包含 API 密钥](settings/20261120-001608-406068-export-keys-v01.png) | — |
| 应用设置 | 宿主 | support-tools | 辅助工具 | — | [标注关闭](settings/20261120-001608-406068-tools-v01.png) | — |
| 应用设置 | 宿主 | display-diagnostics | 显示与布局信息 | 显示诊断 | [实时显示指标](settings/20261120-001608-406068-diagnostics-v01.png)<br>[展开边距明细](settings/20261120-001608-406068-insets-v01.png) | — |
| 应用设置 | 宿主 | about | 关于序点 | 关于 | [版本、数据与仓库](settings/20261120-001608-406068-about-v01.png)<br>[宽屏 · 双栏](settings/20261120-001608-406068-about-wide-v01.png) | — |

## 全局与通用

| 功能分类 | 所属模块 | 页面标识 | 页面名称 | 别名 | 设计稿与状态 | 待完善 |
| --- | --- | --- | --- | --- | --- | --- |
| 全局与通用 | 宿主 | more | 更多 | 更多页 | [待审 · 更多／已配置常用入口](more/20261123-141956-563463-tools-v01.png)<br>[待审 · 更多／无常用入口](more/20261123-141956-563463-empty-v01.png)<br>[待审 · 更多／深色主题](more/20261123-141956-563463-dark-v01.png)<br>[已确认 · 更多／安装想法后](ideas/20261124-174952-691858-entry-v01.png) | 待确认常用入口、空态和深色主题。 |
| 全局与通用 | 宿主 | data-change-review | 数据变更审核 | 简洁确认 | [已确认 · 撤销安排／恢复为待安排](module-manager/20261124-013320-868834-compact-undo-v01.png)<br>[已确认 · 通用变更确认／包含删除](module-manager/20261124-013320-868834-compact-changes-v01.png) | 撤销安排与通用变更采用已确认的简洁弹窗。 |
| 全局与通用 | 宿主 | all-entries | 全部入口 | — | [待审 · 全部入口／关闭更多后的备用入口](more/20261123-141956-563463-all-v01.png) | 等候本轮设计稿确认。 |
| 全局与通用 | 宿主 | date-picker | 日期选择器 | — | [待审 · 日期选择器／月历](temporal-input/20261123-141956-625755-calendar-v01.png)<br>[待审 · 日期选择器／深色月历](temporal-input/20261123-141956-625755-calendar-dark-v01.png)<br>[待审 · 日期选择器／年份选择](temporal-input/20261123-141956-625755-years-v01.png)<br>[待审 · 日期选择器／手动输入](temporal-input/20261123-141956-625755-input-v01.png)<br>[待审 · 日期选择器／无效日期](temporal-input/20261123-141956-625755-invalid-v01.png)<br>[待审 · 日期选择器／从日程标题打开](temporal-input/20261123-141956-625755-daily-v02.png) | 等候本轮设计稿确认。 |
| 全局与通用 | 宿主 | date-range-picker | 起止日期 | — | [待审 · 起止日期／选择开始日期](temporal-input/20261123-141956-625755-start-v01.png)<br>[待审 · 起止日期／选择结束日期](temporal-input/20261123-141956-625755-end-v01.png) | 等候本轮设计稿确认。 |
| 全局与通用 | 宿主 | time-picker | 时间选择器 | — | [待审 · 时间选择器／小时与分钟滚轮](temporal-input/20261123-141956-625755-time-v01.png) | 等候本轮设计稿确认。 |
| 全局与通用 | 宿主 | workspace-header | App 顶栏 | — | [日程顶栏／日期切换与页面菜单](schedule-home/20261123-143359-881592-timeline-v02.png) | — |
