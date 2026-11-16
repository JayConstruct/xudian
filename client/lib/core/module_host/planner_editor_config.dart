/// Presentation settings only. The module's service must validate every change.
class PlannerEditorConfig {
  PlannerEditorConfig(Object? value) : _value = value is Map ? value : const {};
  final Map _value;

  int get maxDurationMinutes {
    final value = _value['maxDurationMinutes'];
    return value is int && value >= 1 && value <= 525600 ? value : 10080;
  }

  String text(String key, [Map<String, Object?> values = const {}]) {
    final labels = _value['labels'];
    final value = labels is Map ? labels[key] : null;
    final template = value is String ? value : _defaults[key] ?? key;
    return template.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (match) => '${values[match[1]] ?? match[0]}',
    );
  }

  static const _defaults = {
    'validationFailed': '时间校验失败，请重试',
    'unavailable': '当前时间不可安排',
    'overlap': '与「{title}」时间重叠',
    'pending': '待确认',
    'duration': '{minutes}分钟',
    'moveTo': '移至 {time}',
    'candidateCount': '待安排 {count}',
    'dragHint': '长按拖到下方安排',
    'previousPage': '上一页待安排条目',
    'nextPage': '下一页待安排条目',
    'scheduledCount': '已安排 {count}',
    'sortHint': '按时间排序',
    'editHint': '点击条目可调整时间',
    'endsAt': '结束于 {time}',
    'durationTitle': '时长',
    'minutes': '分钟',
    'cancel': '取消',
    'confirm': '确定',
    'durationError': '请输入1至{max}分钟',
    'editTitle': '调整时间 · {title}',
    'cancelEdit': '取消调整',
    'apply': '确认',
    'busy': '正在处理…',
    'dayTitle': '当日条目',
    'closeDay': '关闭',
    'emptyCandidates': '暂无条目',
    'dropHint': '拖到这里',
    'retry': '重试',
  };
}
