part of 'planner_board.dart';

/// Retains the sheet through its exit without rebuilding its list on each tick.
/// The full-screen layer stays in place until this transition finishes.
class _PlannerDaySheetTransition extends StatefulWidget {
  const _PlannerDaySheetTransition({
    super.key,
    required this.visible,
    required this.onDismissed,
    required this.child,
  });

  final bool visible;
  final VoidCallback onDismissed;
  final Widget child;

  @override
  State<_PlannerDaySheetTransition> createState() =>
      _PlannerDaySheetTransitionState();
}

class _PlannerDaySheetTransitionState extends State<_PlannerDaySheetTransition>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
  )..addStatusListener(_status);
  late final _motion = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.enter,
    reverseCurve: AppMotion.leave,
  );
  bool? _reduced;

  void _status(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || widget.visible) return;
    // Reduced motion may finish during a parent build; remove after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.visible && _controller.isDismissed) {
        widget.onDismissed();
      }
    });
  }

  void _update() {
    if (_reduced == true) {
      _controller.value = widget.visible ? 1 : 0;
      if (!widget.visible) _status(AnimationStatus.dismissed);
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
      if (_controller.isDismissed) _status(AnimationStatus.dismissed);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = AppMotion.reduced(context);
    if (_reduced != reduced) {
      _reduced = reduced;
      _update();
    }
  }

  @override
  void didUpdateWidget(_PlannerDaySheetTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) _update();
  }

  @override
  void dispose() {
    _motion.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !widget.visible,
    child: ExcludeSemantics(
      excluding: !widget.visible,
      child: FadeTransition(
        key: const ValueKey('planner-day-fade'),
        opacity: _motion,
        child: SlideTransition(
          key: const ValueKey('planner-day-slide'),
          position: Tween(
            begin: const Offset(0, .025),
            end: Offset.zero,
          ).animate(_motion),
          child: ScaleTransition(
            key: const ValueKey('planner-day-scale'),
            scale: Tween(begin: .98, end: 1.0).animate(_motion),
            alignment: Alignment.topCenter,
            child: RepaintBoundary(child: widget.child),
          ),
        ),
      ),
    ),
  );
}

/// Compact day presentation. All changes remain proposals until the script's
/// existing preview, confirmation and transaction pipeline accepts them.
class _PlannerDaySheet extends StatefulWidget {
  const _PlannerDaySheet({
    required this.date,
    required this.candidates,
    required this.blocks,
    required this.options,
    required this.enabled,
    required this.canMove,
    required this.onEvent,
    required this.onClose,
    this.onPreview,
    this.onDragActiveChanged,
  });

  final DateTime date;
  final List<BoardItem> candidates, blocks;
  final BoardItem options;
  final bool enabled;
  final bool Function(BoardItem) canMove;
  final ValueChanged<Object?> onEvent;
  final VoidCallback onClose;
  final Future<BoardItem> Function(BoardItem)? onPreview;
  final ValueChanged<bool>? onDragActiveChanged;

  @override
  State<_PlannerDaySheet> createState() => _PlannerDaySheetState();
}

class _PlannerDayDurationDialog extends StatefulWidget {
  const _PlannerDayDurationDialog({required this.minutes});
  final int minutes;

  @override
  State<_PlannerDayDurationDialog> createState() =>
      _PlannerDayDurationDialogState();
}

class _PlannerDayDurationDialogState extends State<_PlannerDayDurationDialog> {
  late final _controller = TextEditingController(text: '${widget.minutes}');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('任务时长'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: '分钟', errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () {
          final value = int.tryParse(_controller.text);
          if (value == null || value < 1 || value > 10080) {
            setState(() => _error = '请输入1至10080分钟');
          } else {
            Navigator.pop(context, value);
          }
        },
        child: const Text('确定'),
      ),
    ],
  );
}

class _PlannerDaySheetState extends State<_PlannerDaySheet> {
  final _scroll = ScrollController();
  final _listKey = GlobalKey();
  Timer? _previewTimer, _scrollTimer;
  int _revision = 0;
  bool _expanded = true, _dragging = false, _checking = false;
  BoardItem? _submitted;
  Offset? _pointer;
  BoardItem? _draft, _validation;
  DateTime? _start;
  int _minutes = 5;

  // Wall-clock arithmetic matches PlannerBoard and never uses device DST.
  DateTime? _date(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    return parsed == null
        ? null
        : DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
          );
  }

  String _stamp(DateTime value) =>
      value.toIso8601String().replaceFirst('Z', '');
  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  DateTime get _day => widget.date;
  DateTime get _nextDay => _day.add(const Duration(days: 1));
  DateTime get _end => _start!.add(Duration(minutes: _minutes));

  List<BoardItem> get _items =>
      [
          for (final item in widget.blocks)
            if (_draft == null || item['id'] != _draft!['id']) item,
          if (_draft != null)
            {..._draft!, 'start': _stamp(_start!), 'end': _stamp(_end)},
        ].where((item) {
          final start = _date(item['start']), end = _date(item['end']);
          return start != null &&
              end != null &&
              start.isBefore(_nextDay) &&
              end.isAfter(_day);
        }).toList()
        ..sort((a, b) {
          final order = _date(a['start'])!.compareTo(_date(b['start'])!);
          return order != 0 ? order : '${a['id']}'.compareTo('${b['id']}');
        });

  int _duration(BoardItem item) {
    final start = _date(item['start']), end = _date(item['end']);
    if (start != null && end != null) {
      return math.max(1, end.difference(start).inMinutes);
    }
    return math.max(1, (item['durationMinutes'] as num? ?? 5).round());
  }

  BoardItem get _event => {
    ...Map<String, Object?>.from(_draft!['moveEvent'] as Map),
    'id': _draft!['id'],
    'intent': 'move',
    'start': _stamp(_start!),
    'end': _stamp(_end),
    'preserveDuration': _minutes == _duration(_draft!),
    'snapMinutes': 1,
  };

  List<BoardItem> get _overlaps => widget.blocks.where((item) {
    if (_draft == null || item['id'] == _draft!['id']) return false;
    final start = _date(item['start']), end = _date(item['end']);
    return start != null &&
        end != null &&
        start.isBefore(_end) &&
        end.isAfter(_start!);
  }).toList();

  DateTime? get _nextFree {
    var start = _start!;
    final occupied =
        widget.blocks
            .where((item) => item['id'] != _draft!['id'])
            .where(
              (item) =>
                  _date(item['start']) != null && _date(item['end']) != null,
            )
            .toList()
          ..sort((a, b) => _date(a['start'])!.compareTo(_date(b['start'])!));
    for (final item in occupied) {
      final from = _date(item['start'])!, to = _date(item['end'])!;
      if (from.isBefore(start.add(Duration(minutes: _minutes))) &&
          to.isAfter(start)) {
        start = to;
      }
    }
    return start.isBefore(_nextDay) && start != _start ? start : null;
  }

  @override
  void didUpdateWidget(_PlannerDaySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Drop drafts whose source was removed, locked or completed by a refresh.
    if (_draft != null && widget.enabled) {
      final sources = [
        ...widget.candidates,
        ...widget.blocks,
      ].where((item) => item['id'] == _draft!['id']).toList();
      if (sources.isEmpty || !widget.canMove(sources.first)) {
        _cancelDraft();
      } else if (_submitted != null &&
          _date(sources.first['start']) == _date(_submitted!['start']) &&
          _date(sources.first['end']) == _date(_submitted!['end'])) {
        _cancelDraft();
      } else if (!identical(oldWidget.blocks, widget.blocks) ||
          !identical(oldWidget.candidates, widget.candidates) ||
          oldWidget.options != widget.options) {
        _draft = sources.first;
        _validate();
      }
    }
  }

  void _cancelDraft() {
    _previewTimer?.cancel();
    _revision++;
    _draft = null;
    _submitted = null;
    _validation = null;
    _checking = false;
  }

  @override
  void dispose() {
    _revision++;
    _previewTimer?.cancel();
    _scrollTimer?.cancel();
    _scroll.dispose();
    // Defer host rebuilds until the departing widget is unmounted.
    if (_dragging) {
      final callback = widget.onDragActiveChanged;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => callback?.call(false),
      );
    }
    super.dispose();
  }

  void _edit(BoardItem item, {DateTime? start}) {
    final sources = [
      ...widget.candidates,
      ...widget.blocks,
    ].where((source) => source['id'] == item['id']);
    final source = sources.isEmpty ? item : sources.first;
    if (!widget.canMove(source)) {
      if (widget.enabled && item['event'] != null) {
        widget.onEvent(item['event']);
      }
      return;
    }
    final sameDraft = _draft?['id'] == source['id'];
    final minutes = sameDraft ? _minutes : _duration(source);
    final position =
        start ??
        (sameDraft ? _start : _date(source['start'])) ??
        _day.add(const Duration(hours: 9));
    setState(() {
      _draft = source;
      _submitted = null;
      _minutes = minutes;
      _start = position;
      _expanded = false;
      _validate();
    });
  }

  void _place(BoardItem item, int index) {
    if (!widget.canMove(item)) return;
    final items = _items;
    final before = items
        .take(index)
        .where((other) => other['id'] != item['id']);
    DateTime start;
    if (before.isNotEmpty) {
      start = _date(before.last['end'])!;
    } else {
      final after = items
          .skip(index)
          .where((other) => other['id'] != item['id']);
      start = after.isEmpty
          ? _day.add(const Duration(hours: 9))
          : _date(after.first['start'])!
                .subtract(Duration(minutes: _duration(item)));
    }
    if (start.isBefore(_day)) start = _day;
    if (!start.isBefore(_nextDay)) {
      start = _nextDay.subtract(const Duration(minutes: 1));
    }
    _edit(item, start: start);
  }

  void _validate() {
    _previewTimer?.cancel();
    final revision = ++_revision;
    _validation = null;
    _checking = widget.onPreview != null;
    if (!_checking || _draft == null) return;
    final event = _event;
    _previewTimer = Timer(const Duration(milliseconds: 200), () async {
      BoardItem validation;
      try {
        validation = await widget.onPreview!(event);
      } catch (_) {
        validation = {
          'valid': false,
          'previewLabel': '时间校验失败，请重试',
          'retry': true,
        };
      }
      if (!mounted || revision != _revision) return;
      setState(() {
        _validation = validation;
        _checking = false;
      });
    });
  }

  void _drag(bool active) {
    if (_dragging == active) return;
    setState(() => _dragging = active);
    widget.onDragActiveChanged?.call(active);
    _scrollTimer?.cancel();
    if (!active) {
      _pointer = null;
      return;
    }
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || _pointer == null || !_scroll.hasClients) return;
      final y = box.globalToLocal(_pointer!).dy;
      final delta = y < 40
          ? -8.0
          : y > box.size.height - 40
          ? 8.0
          : 0.0;
      if (delta != 0) {
        _scroll.jumpTo(
          (_scroll.offset + delta).clamp(0, _scroll.position.maxScrollExtent),
        );
      }
    });
  }

  Widget _card(
    BoardItem item, {
    bool candidate = false,
    bool feedback = false,
  }) {
    final theme = Theme.of(context), scheme = Theme.of(context).colorScheme;
    final accent = ContentColors.accent(
      item['colorKey'] ?? item['id'],
      color: item['color'],
    );
    final surface = ContentColors.surface(accent, scheme);
    final foreground = ContentColors.foreground(
      accent,
      surface,
      scheme.onSurface,
    );
    final selected = _draft?['id'] == item['id'];
    final start = selected ? _start : _date(item['start']);
    final end = selected ? _end : _date(item['end']);
    final canMove = widget.canMove(item);
    final height = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(14) * 1.5 +
          MediaQuery.textScalerOf(context).scale(12) * 1.3 +
          8,
    );
    String label(DateTime time) {
      final day = DateTime.utc(time.year, time.month, time.day);
      final difference = day.difference(_day).inDays;
      return '${difference == 0
          ? ''
          : difference == 1
          ? '次日 '
          : difference == -1
          ? '前日 '
          : '${time.month}/${time.day} '}${_time(time)}';
    }

    Widget card = Semantics(
      label:
          '${item['title']}，${candidate ? '待安排' : '${label(start!)}至${label(end!)}'}，${selected ? _minutes : _duration(item)}分钟${item['readOnly'] == true ? '，来源只读' : ''}',
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: item['readOnly'] == true ? _SourceHatching(accent) : null,
          child: InkWell(
            onTap: !widget.enabled || feedback ? null : () => _edit(item),
            child: Container(
              key: feedback ? null : ValueKey('planner-day-card:${item['id']}'),
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              foregroundDecoration: selected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: scheme.primary, width: 1.5),
                    )
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item['title'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (selected) ...[
                              const SizedBox(width: 6),
                              Text(
                                '待确认',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (!candidate)
                          Text(
                            '${label(start!)}–${label(end!)}',
                            key: feedback
                                ? null
                                : ValueKey('planner-day-times:${item['id']}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (item['overdue'] == true)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.circle, size: 6, color: scheme.error),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    '${selected ? _minutes : _duration(item)}分钟',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    canMove ? Icons.drag_indicator : Icons.lock_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!canMove || feedback) return card;
    card = LongPressDraggable<BoardItem>(
      data: item,
      maxSimultaneousDrags: 1,
      onDragStarted: () => _drag(true),
      onDragUpdate: (details) => _pointer = details.globalPosition,
      onDragEnd: (_) => _drag(false),
      onDraggableCanceled: (_, _) => _drag(false),
      feedback: SizedBox(
        width: math.min(320, MediaQuery.sizeOf(context).width - 48),
        child: Opacity(
          opacity: .9,
          child: _card(item, candidate: candidate, feedback: true),
        ),
      ),
      childWhenDragging: Opacity(opacity: .35, child: card),
      child: card,
    );
    return card;
  }

  Widget _slot(int index, {bool empty = false}) => DragTarget<BoardItem>(
    onWillAcceptWithDetails: (details) => widget.canMove(details.data),
    onAcceptWithDetails: (details) => _place(details.data, index),
    builder: (context, hovering, rejected) => AnimatedContainer(
      key: ValueKey('planner-day-slot:$index'),
      duration: const Duration(milliseconds: 120),
      height: empty ? 88 : 8,
      alignment: Alignment.center,
      decoration: hovering.isEmpty
          ? null
          : BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.primary),
            ),
      child: empty
          ? Text('拖到这里安排任务', style: Theme.of(context).textTheme.labelSmall)
          : hovering.isNotEmpty
          ? SizedBox(
              height: 2,
              width: double.infinity,
              child: ColoredBox(color: Theme.of(context).colorScheme.primary),
            )
          : null,
    ),
  );

  Future<void> _pickStart() async {
    final previous = _start!;
    final id = _draft!['id'];
    final picked = await showTimePicker(
      context: context,
      useRootNavigator: false,
      initialTime: TimeOfDay(hour: previous.hour, minute: previous.minute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!mounted || picked == null || _draft?['id'] != id) return;
    setState(() {
      _start = DateTime.utc(
        previous.year,
        previous.month,
        previous.day,
        picked.hour,
        picked.minute,
      );
      _validate();
    });
  }

  Future<void> _pickDuration() async {
    final id = _draft!['id'];
    final minutes = await showDialog<int>(
      context: context,
      useRootNavigator: false,
      builder: (context) => _PlannerDayDurationDialog(minutes: _minutes),
    );
    // Keep the local choice; confirmation still requires an active board and
    // service validation.
    if (!mounted || minutes == null || _draft?['id'] != id) {
      return;
    }
    setState(() {
      _minutes = minutes;
      _validate();
    });
  }

  Widget _editor() {
    final scheme = Theme.of(context).colorScheme;
    final overlaps = _overlaps;
    final conflicts = _validation?['conflicts'];
    final remoteError = conflicts is List && conflicts.isNotEmpty
        ? conflicts.join('；')
        : _validation?['valid'] == false
        ? '${_validation?['previewLabel'] ?? '当前时间不可安排'}'
        : null;
    final error = overlaps.isNotEmpty
        ? '与「${overlaps.first['title']}」时间重叠'
        : remoteError;
    final nextFree = overlaps.isEmpty ? null : _nextFree;
    final differentDay =
        _end.year != _day.year ||
        _end.month != _day.month ||
        _end.day != _day.day;
    return Padding(
      key: const ValueKey('planner-day-editor'),
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          Row(
            children: [
              Expanded(
                child: Text(
                  '调整时间 · ${_draft!['title']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                onPressed: () => setState(_cancelDraft),
                tooltip: '取消本次安排',
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('planner-day-start'),
                  onPressed: widget.enabled ? _pickStart : null,
                  icon: const Icon(Icons.schedule, size: 16),
                  label: Text(
                    '${_start!.day != _day.day ? '${_start!.month}/${_start!.day} ' : ''}${_time(_start!)}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('planner-day-duration'),
                  onPressed: widget.enabled ? _pickDuration : null,
                  icon: const Icon(Icons.timelapse, size: 16),
                  label: Text('$_minutes分钟'),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '结束于 ${differentDay ? '${_end.month}/${_end.day} ' : ''}${_time(_end)}',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (_checking) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    error,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: scheme.error),
                  ),
                ),
                if (nextFree != null)
                  TextButton(
                    onPressed: !widget.enabled
                        ? null
                        : () => setState(() {
                            _start = nextFree;
                            _validate();
                          }),
                    child: Text('移至 ${_time(nextFree)}'),
                  ),
                if (_validation?['retry'] == true)
                  TextButton(
                    onPressed: !widget.enabled
                        ? null
                        : () => setState(_validate),
                    child: const Text('重试'),
                  ),
              ],
            ),
          if (widget.options['errorText'] != null)
            Text(
              '${widget.options['errorText']}',
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.error),
            ),
          const SizedBox(height: 4),
          FilledButton.tonal(
            key: const ValueKey('planner-day-confirm'),
            onPressed: !widget.enabled || _checking || error != null
                ? null
                : () {
                    _submitted = _event;
                    widget.onEvent(_submitted);
                  },
            child: Text(widget.enabled ? '确认安排' : '正在处理…'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final items = _items;
    final candidates = widget.candidates
        .where((item) => item['id'] != _draft?['id'])
        .toList();
    final candidateCount =
        (widget.options['candidateCount'] as num? ?? widget.candidates.length)
            .toInt() -
        (widget.candidates.length - candidates.length);
    return Material(
      key: const ValueKey('planner-day-sheet'),
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_day.month}月${_day.day}日 ${const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][_day.weekday - 1]}',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            '当日任务',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      tooltip: '关闭当日任务',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(height: 12),
                Semantics(
                  key: const ValueKey('planner-day-candidates-toggle'),
                  container: true,
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            '待安排 $candidateCount',
                            style: theme.textTheme.titleSmall,
                          ),
                          Icon(
                            _expanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                          ),
                          const Spacer(),
                          Flexible(
                            child: Text(
                              '长按拖到下方安排',
                              maxLines: 1,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_expanded && candidates.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.min(208, constraints.maxHeight * .32),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      primary: false,
                      itemCount: candidates.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, index) =>
                          _card(candidates[index], candidate: true),
                    ),
                  ),
                if (_expanded && candidates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('暂无待安排任务'),
                  ),
                if (widget.options['candidatePageLabel'] != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.options['candidatePreviousEvent'] != null)
                        IconButton(
                          tooltip: '上一页待安排任务',
                          onPressed: !widget.enabled
                              ? null
                              : () => widget.onEvent(
                                  widget.options['candidatePreviousEvent'],
                                ),
                          icon: const Icon(Icons.chevron_left),
                        ),
                      Text(
                        '${widget.options['candidatePageLabel']}',
                        style: theme.textTheme.labelSmall,
                      ),
                      if (widget.options['candidateNextEvent'] != null)
                        IconButton(
                          tooltip: '下一页待安排任务',
                          onPressed: !widget.enabled
                              ? null
                              : () => widget.onEvent(
                                  widget.options['candidateNextEvent'],
                                ),
                          icon: const Icon(Icons.chevron_right),
                        ),
                    ],
                  ),
                const Divider(height: 16),
                Row(
                  children: [
                    Text(
                      '已安排 ${items.length}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const Spacer(),
                    Text(
                      '按时间排序',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView(
                    key: _listKey,
                    controller: _scroll,
                    padding: EdgeInsets.zero,
                    children: [
                      if (items.isEmpty) _slot(0, empty: true),
                      for (var index = 0; index < items.length; index++) ...[
                        _slot(index),
                        DragTarget<BoardItem>(
                          onWillAcceptWithDetails: (details) =>
                              widget.canMove(details.data) &&
                              details.data['id'] != items[index]['id'],
                          onAcceptWithDetails: (details) =>
                              _place(details.data, index + 1),
                          builder: (_, hovering, _) => DecoratedBox(
                            decoration: BoxDecoration(
                              border: hovering.isEmpty
                                  ? null
                                  : Border(
                                      bottom: BorderSide(
                                        color: scheme.primary,
                                        width: 3,
                                      ),
                                    ),
                            ),
                            child: _card(items[index]),
                          ),
                        ),
                      ],
                      if (items.isNotEmpty) _slot(items.length),
                    ],
                  ),
                ),
                if (_draft != null)
                  _editor()
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '点击任务可调整时间',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
