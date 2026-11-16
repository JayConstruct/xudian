// Module-owned editor copy and native capability references.
export const plannerEditor = {maxDurationMinutes: 10080, labels: {
        durationTitle: '任务时长', minutes: '分钟', cancel: '取消', confirm: '确定',
        durationError: '请输入1至{max}分钟', editTitle: '调整时间 · {title}',
        cancelEdit: '取消本次安排', apply: '确认安排', busy: '正在处理…',
        dayTitle: '当日任务', closeDay: '关闭当日任务', emptyCandidates: '暂无待安排任务',
        dropHint: '拖到这里安排任务', retry: '重试',
        validationFailed: '时间校验失败，请重试', unavailable: '当前时间不可安排', overlap: '与「{title}」时间重叠', pending: '待确认', duration: '{minutes}分钟', moveTo: '移至 {time}', candidateCount: '待安排 {count}', dragHint: '长按拖到下方安排', previousPage: '上一页待安排任务', nextPage: '下一页待安排任务', scheduledCount: '已安排 {count}', sortHint: '按时间排序', editHint: '点击任务可调整时间', endsAt: '结束于 {time}',
      }};

export const quickAdjustmentContract = {contract: 'time-range/2', records: {subject: 'time', journal: 'journal', receipt: 'receipt', occurrence: 'occurrence'}, taskModuleId: 'app.tasks', applyServiceId: 'planner.operation.apply', undoServiceId: 'planner.batch.undo'};
