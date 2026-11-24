part of 'temporal_input.dart';

Future<DateTime?> showAppDateSheet({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String helpText = '选择日期',
  String confirmLabel = '确定',
  String? rangeHint,
}) => showSettingsModal<DateTime>(
  compactFrame: true,
  context: context,
  builder: (_) => DateSelectionSheet(
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    title: helpText,
    confirmLabel: confirmLabel,
    rangeHint: rangeHint,
  ),
);

enum _DateSheetMode { month, years, input }

class DateSelectionSheet extends StatefulWidget {
  const DateSelectionSheet({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
    required this.confirmLabel,
    this.rangeHint,
  });
  final DateTime initialDate, firstDate, lastDate;
  final String title, confirmLabel;
  final String? rangeHint;
  @override
  State<DateSelectionSheet> createState() => _DateSelectionSheetState();
}

class _DateSelectionSheetState extends State<DateSelectionSheet> {
  late DateTime selected = widget.initialDate;
  late DateTime month = DateTime(selected.year, selected.month);
  late int firstYear = _yearPage(month.year);
  late final input = TextEditingController(text: formatInputDate(selected));
  var mode = _DateSheetMode.month;
  static const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  int _yearPage(int year) => (year - 7).clamp(
    widget.firstDate.year,
    (widget.lastDate.year - 14).clamp(
      widget.firstDate.year,
      widget.lastDate.year,
    ),
  );
  bool inBounds(DateTime date) =>
      !date.isBefore(widget.firstDate) && !date.isAfter(widget.lastDate);
  String? get inputError {
    final raw = input.text.trim();
    final date = parseInputDate(raw);
    if (date != null) return inBounds(date) ? null : '请选择允许范围内的日期';
    final parts = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (parts != null) {
      final m = int.parse(parts[2]!);
      if (m >= 1 && m <= 12) {
        final count = DateUtils.getDaysInMonth(int.parse(parts[1]!), m);
        if (int.parse(parts[3]!) > count) return '$m 月只有 $count 天，请输入有效日期。';
      }
    }
    return '请输入有效 YYYY-MM-DD 日期';
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void editDate() => setState(() {
    input.text = formatInputDate(selected);
    mode = _DateSheetMode.input;
  });
  void showMonth() {
    final parsed = parseInputDate(input.text.trim());
    setState(() {
      if (mode == _DateSheetMode.input && parsed != null && inBounds(parsed)) {
        selected = parsed;
        month = DateTime(parsed.year, parsed.month);
      }
      mode = _DateSheetMode.month;
    });
  }

  Widget periodBar(
    String label,
    VoidCallback? previous,
    VoidCallback? next, {
    VoidCallback? onLabel,
  }) {
    final years = mode == _DateSheetMode.years;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: onLabel == null
                ? Text(label, style: Theme.of(context).textTheme.titleMedium)
                : TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: onLabel,
                    iconAlignment: IconAlignment.end,
                    icon: const UiIcon(Icons.expand_more, size: 18),
                    label: Text(label),
                  ),
          ),
        ),
        IconButton(
          tooltip: years ? '前十五年' : '上个月',
          onPressed: previous,
          icon: const UiIcon(Icons.chevron_left, size: 18),
        ),
        IconButton(
          tooltip: years ? '后十五年' : '下个月',
          onPressed: next,
          icon: const UiIcon(Icons.chevron_right, size: 18),
        ),
      ],
    );
  }

  Widget grid(List<Widget> items, int columns) => Column(
    children: [
      for (int i = 0; i < items.length; i += columns)
        Row(
          children: [
            for (int j = 0; j < columns; j++)
              Expanded(
                child: i + j < items.length
                    ? items[i + j]
                    : const SizedBox.shrink(),
              ),
          ],
        ),
    ],
  );

  Widget choice(
    String label,
    bool active,
    VoidCallback? choose, {
    bool today = false,
    String? semantics,
  }) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      selected: active,
      label: semantics,
      child: Padding(
        padding: mode == _DateSheetMode.years
            ? const EdgeInsets.all(3)
            : EdgeInsets.zero,
        child: TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 48),
            textStyle: TextStyle(
              fontSize: 15,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
            foregroundColor: active ? c.onPrimary : c.onSurface,
            backgroundColor: active ? c.primary : null,
            shape: AppDesign.smoothShape(
              radius: 12,
              side: today && !active
                  ? BorderSide(color: c.primary)
                  : BorderSide.none,
            ),
          ),
          onPressed: choose,
          child: Text(label),
        ),
      ),
    );
  }

  Widget calendar() {
    final before = DateTime(month.year, month.month - 1);
    final after = DateTime(month.year, month.month + 1);
    final lastDay = DateUtils.getDaysInMonth(month.year, month.month);
    final day = clock.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${selected.month}月${selected.day}日',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text('周${weekdays[selected.weekday - 1]}'),
                ],
              ),
            ),
            IconButton.filledTonal(
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHigh,
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                minimumSize: const Size(48, 48),
                shape: AppDesign.smoothShape(radius: 14),
              ),
              tooltip: '输入日期',
              onPressed: editDate,
              icon: const UiIcon(Icons.edit_outlined),
            ),
          ],
        ),
        if (widget.rangeHint != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(widget.rangeHint!),
          ),
        const SizedBox(height: 12),
        const Divider(),
        periodBar(
          '${month.year}年${month.month}月',
          month.isAfter(widget.firstDate)
              ? () => setState(() => month = before)
              : null,
          after.isAfter(widget.lastDate)
              ? null
              : () => setState(() => month = after),
          onLabel: () => setState(() {
            firstYear = _yearPage(month.year);
            mode = _DateSheetMode.years;
          }),
        ),
        Row(
          children: [
            for (final weekday in weekdays)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    weekday,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
          ],
        ),
        grid([
          for (int i = 1; i < month.weekday; i++) const SizedBox.shrink(),
          for (int i = 1; i <= lastDay; i++)
            Builder(
              builder: (context) {
                final date = DateTime(month.year, month.month, i);
                return choice(
                  '$i',
                  DateUtils.isSameDay(selected, date),
                  inBounds(date) ? () => setState(() => selected = date) : null,
                  today: DateUtils.isSameDay(date, day),
                  semantics: MaterialLocalizations.of(context)
                      .formatFullDate(date),
                );
              },
            ),
        ], 7),
      ],
    );
  }

  Widget years() {
    final lastYear = (firstYear + 14).clamp(firstYear, widget.lastDate.year);
    return Column(
      children: [
        periodBar(
          '$firstYear–$lastYear',
          firstYear <= widget.firstDate.year
              ? null
              : () => setState(
                  () => firstYear = (firstYear - 15).clamp(
                    widget.firstDate.year,
                    widget.lastDate.year,
                  ),
                ),
          lastYear >= widget.lastDate.year
              ? null
              : () => setState(() => firstYear += 15),
        ),
        grid([
          for (int year = firstYear; year <= lastYear; year++)
            choice(
              '$year',
              year == month.year,
              () => setState(() {
                final min = year == widget.firstDate.year
                    ? widget.firstDate.month
                    : 1;
                final max = year == widget.lastDate.year
                    ? widget.lastDate.month
                    : 12;
                month = DateTime(year, month.month.clamp(min, max));
                mode = _DateSheetMode.month;
              }),
            ),
        ], 3),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final manual = mode == _DateSheetMode.input;
    final selectingYear = mode == _DateSheetMode.years;
    void confirm() => Navigator.pop(
      context,
      manual ? parseInputDate(input.text.trim()) : selected,
    );
    return SettingsSheet(
      showClose: true,
      title: Text(
        manual
            ? '输入日期'
            : selectingYear
            ? '选择年份'
            : widget.title,
      ),
      expandedActions: true,
      content: SingleChildScrollView(
        child: manual
            ? ScriptFieldLabel(
                label: '日期',
                child: TextField(
                  controller: input,
                  autofocus: true,
                  keyboardType: TextInputType.datetime,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (inputError == null) confirm();
                  },
                  decoration: AppDesign.outlinedField(context).copyWith(
                    helperText: '格式为 YYYY-MM-DD',
                    errorText: inputError,
                    suffixIcon: IconButton(
                      tooltip: '返回月历',
                      onPressed: showMonth,
                      icon: const UiIcon(Icons.calendar_month_outlined),
                    ),
                  ),
                ),
              )
            : selectingYear
            ? years()
            : calendar(),
      ),
      actions: selectingYear
          ? [OutlinedButton(onPressed: showMonth, child: const Text('返回月历'))]
          : [
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: manual && inputError != null ? null : confirm,
                child: Text(widget.confirmLabel),
              ),
            ],
    );
  }
}
