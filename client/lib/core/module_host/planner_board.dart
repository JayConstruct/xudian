import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../ui/content_colors.dart';

typedef BoardItem = Map<String, Object?>;

/// A presentation-only date/time board. Scripts own scheduling, validation,
/// source writes, confirmation and undo; dropping emits a proposal, never edits
/// the supplied blocks. Preview blocks can contain both ends of a swap or an
/// entire insertion chain supplied by the script.
class PlannerBoard extends StatefulWidget {
  const PlannerBoard({
    super.key,
    this.days = const [],
    this.candidates = const [],
    this.blocks = const [],
    this.previewBlocks = const [],
    this.previewLabel,
    this.selectedIds = const [],
    this.selectEvent,
    this.onPreview,
    this.enabled = true,
    this.bottomInset = 0,
    this.onDragActiveChanged,
    this.quickAdjust = false,
    this.onQuickAdjustChanged,
    this.pendingAdjustment,
    this.previewIdentity,
    this.options = const {},
    required this.onEvent,
  });

  final List<BoardItem> days, candidates, blocks, previewBlocks;
  final BoardItem options;
  final String? previewLabel;
  final List<Object?> selectedIds;
  final BoardItem? selectEvent;
  final ValueChanged<Object?> onEvent;

  /// Debounced display-only validation. Replies may contain previewBlocks,
  /// previewLabel, conflicts and valid; the drop event must still be validated
  /// by its service. Only the newest proposal in the current gesture is shown.
  final Future<BoardItem> Function(BoardItem proposal)? onPreview;
  final bool enabled;
  final double bottomInset;
  final ValueChanged<bool>? onDragActiveChanged;
  final bool quickAdjust;
  final ValueChanged<bool>? onQuickAdjustChanged;

  /// Display-only in-flight placement. The original task data remains unchanged.
  final BoardItem? pendingAdjustment;
  final Object? previewIdentity;

  @override
  State<PlannerBoard> createState() => _PlannerBoardState();
}

class _Proposal {
  const _Proposal(
    this.item,
    this.start,
    this.end,
    this.snap, {
    this.intent = 'move',
    this.targetId,
  });
  final BoardItem item;
  final DateTime start, end;
  final int snap;
  final String intent;
  final Object? targetId;
}

class _BoardSegment {
  _BoardSegment(
    this.item,
    this.start,
    this.end,
    this.dayIndex,
    this.day,
    this.from,
    this.to,
    this.top,
    this.bottom,
  );
  final BoardItem item;
  final DateTime start, end, from, to;
  final int dayIndex;
  final String day;
  final double top, bottom;
  int lane = 0;
  String get key => '${item['id']}:$day';
}

class _BoardGroup {
  _BoardGroup(this.segments, this.top, this.bottom, this.lanes);
  final List<_BoardSegment> segments;
  final double top, bottom;
  final int lanes;
}

class _BoardGeometry {
  _BoardGeometry(this.days, this.byKey, this.byId);
  final List<List<_BoardGroup>> days;
  final Map<String, _BoardGroup> byKey;
  final Map<Object?, BoardItem> byId;
}

class _PlannerBoardState extends State<PlannerBoard> {
  final _horizontal = ScrollController();
  final _header = ScrollController();
  final _candidatesScroll = ScrollController();
  bool _candidatesExpanded = true;
  final _candidateLink = LayerLink();
  final _candidateTapGroup = Object();
  bool _timelinePositioned = false, _timelineRepositioning = false;
  bool _synchronizingTimeline = false;
  bool _closeCandidatesAfterDrag = false;
  DateTime? _reportedTimelineDate;
  double _timelineColumnWidth = 0;
  DateTime? _timelineRestoreDate;
  double _timelineRestoreFraction = 0;
  double? _timelineRestoreMinute;
  final _clockElapsed = Stopwatch();
  Timer? _clockTimer;
  double _candidateScrollOffset = 0;
  final _vertical = ScrollController();
  final _gridKey = GlobalKey();
  final _viewportKey = GlobalKey();
  final _proposal = ValueNotifier<_Proposal?>(null);
  final _feedbackPointer = ValueNotifier<Offset>(Offset.zero);
  final _dragActive = ValueNotifier<bool>(false);
  final _validation = ValueNotifier<BoardItem?>(null);
  final _window = ValueNotifier<Rect>(const Rect.fromLTWH(0, 0, 800, 600));
  List<BoardItem>? _geometrySource;
  Object? _geometrySettings;
  _BoardGeometry? _geometry;
  final _parsedDates = <String, DateTime?>{};
  final _textHeights = <Object, double>{};
  List<BoardItem>? _daySource, _validatedDays;
  List<BoardItem>? _outsideSource;
  Object? _outsideSettings;
  List<BoardItem> _outsideItems = const [];
  final _dailyOccupancy =
      <(DateTime, DateTime), List<(Object?, DateTime, DateTime)>>{};

  String? _pinnedSegment;
  Timer? _fineTimer, _intentTimer, _scrollTimer, _previewTimer;
  int _fineStep = 1;
  double get _finePixels =>
      _dashboard ? math.max(_scale, _fineStep == 1 ? 4 : 2) : _scale;
  int get _snap => _fine ? _fineStep : (_dashboard ? 5 : 15);
  String _snapLabel(int step) => step == 1
      ? (_dashboard ? '1分钟精调' : '1分钟细调')
      : step == 5
      ? '5分钟吸附'
      : '15分钟吸附';
  Offset? _anchor, _lastPosition, _pointerPosition;
  DateTime? _fineStart, _moveOrigin, _movePointerOrigin;
  DateTime? _gestureTime;
  Offset? _gesturePointer, _horizontalIntentAnchor;
  double _gestureScroll = 0, _horizontalIntentScroll = 0;
  int? _gestureDay;
  String _intent = 'move';
  Object? _targetId;
  String? _pendingIntent;
  Object? _pendingTargetId;
  bool _fine = false;
  bool _resizing = false;
  BoardItem? _activeItem;
  Offset? _resizeDown, _resizeBasePoint;
  DateTime? _resizeBaseEnd;
  double _fineScrollAnchor = 0;
  int _fineDayAnchor = 0,
      _dragSession = 0,
      _previewRevision = 0,
      _viewGeneration = 0;
  String? _previewSignature;
  double _columnWidth = 112;
  double _cardHeight = 48;
  BoardItem? _selectedItem;
  List<BoardItem>? _focusDays;
  List<BoardItem> _focusItems = const [];
  int? _focusStart, _focusEnd;
  double? _focusScale;
  String _weekday(DateTime day) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day.weekday - 1];

  bool _today(BoardItem day) =>
      _date(day['date']) ==
      _midnight(_date(widget.options['today']) ?? DateTime.now());
  bool get _dashboard => widget.options['dashboard'] == true;
  bool get _timeline =>
      _dashboard &&
      _focusDays == null &&
      widget.options['continuousDates'] == true;
  int get _visibleDayCount => _number('visibleDays', 3, 1, 7).round();
  DateTime? get _timelineNow =>
      _date(widget.options['now'])?.add(_clockElapsed.elapsed);

  DateTime? get _leftDate {
    if (_days.isEmpty) return null;
    final first = _date(_days.first['date']);
    final offset = _horizontal.hasClients ? _horizontal.offset : 0.0;
    return first?.add(Duration(days: (offset / _columnWidth + .001).floor()));
  }

  void _positionTimeline(DateTime date, {double fraction = 0}) {
    _timelineRepositioning = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_timeline || !_horizontal.hasClients) return;
      final index = _days.indexWhere(
        (day) => _midnight(_date(day['date'])!) == _midnight(date),
      );
      if (index >= 0) {
        _horizontal.jumpTo(
          ((index + fraction) * _columnWidth).clamp(
            0,
            _horizontal.position.maxScrollExtent,
          ),
        );
        _reportedTimelineDate = _leftDate;
        _syncHeader();
        _refreshWindow();
      }
      _timelineRepositioning = false;
    });
  }

  void _reportTimelineViewport() {
    if (!_timeline ||
        _timelineRepositioning ||
        _synchronizingTimeline ||
        _dragActive.value ||
        !widget.enabled) {
      return;
    }
    final date = _leftDate;
    final event = widget.options['viewportEvent'];
    if (date == null || date == _reportedTimelineDate || event is! Map) return;
    _reportedTimelineDate = date;
    widget.onEvent({
      ...Map<String, Object?>.from(event),
      'startDate': _stamp(date).substring(0, 10),
      'visibleDays': _visibleDayCount,
    });
  }

  void _optionEvent(String name) {
    final event = widget.options[name];
    if (widget.enabled && event is Map) {
      widget.onEvent(Map<String, Object?>.from(event));
    }
  }

  void _toggleCandidates() {
    if (_candidatesExpanded && _candidatesScroll.hasClients) {
      _candidateScrollOffset = _candidatesScroll.offset;
    }
    setState(() => _candidatesExpanded = !_candidatesExpanded);
    if (_candidatesExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _candidatesScroll.hasClients) {
          _candidatesScroll.jumpTo(
            _candidateScrollOffset.clamp(
              0,
              _candidatesScroll.position.maxScrollExtent,
            ),
          );
        }
      });
    }
  }

  String _elapsed(Duration duration) {
    final minutes = duration.inMicroseconds / Duration.microsecondsPerMinute;
    if (minutes < 1) return '${duration.inSeconds}秒';
    if (minutes < 60) {
      return '${minutes.toStringAsFixed(minutes == minutes.roundToDouble() ? 0 : 1)}分钟';
    }
    final hours = minutes / 60;
    return '${hours.toStringAsFixed(hours == hours.roundToDouble() ? 0 : 1)}h';
  }

  String _summary(BoardItem item) {
    if (item['overdue'] == true) return '已逾期';
    final preferred = item['preferredSummary'] ?? item['summary'];
    if (preferred is String && preferred.isNotEmpty) return preferred;
    final deadline = item['deadlineSummary'];
    if (deadline is String && deadline.isNotEmpty) {
      return deadline.startsWith('截') ? '${deadline.substring(1)}截止' : deadline;
    }
    final duration = _duration(item);
    return duration == null
        ? '待安排'
        : '耗时${_elapsed(duration).replaceAll('分钟', 'min')}';
  }

  Color _accent(BoardItem item) => ContentColors.accent(
    item['colorKey'] ??
        item['courseId'] ??
        item['taskId'] ??
        item['id'] ??
        item['title'],
    color: item['color'],
  );

  Color _surface(BoardItem item) =>
      ContentColors.surface(_accent(item), Theme.of(context).colorScheme);

  void _activate(BoardItem item) {
    if (!widget.enabled) return;
    if (_dashboard && _date(item['start']) != null) {
      setState(() => _selectedItem = item);
    } else if (item['event'] != null) {
      widget.onEvent(item['event']);
    }
  }

  List<BoardItem>? _presentationBlockSource, _presentationCandidateSource;
  BoardItem? _presentationPendingSource;
  List<BoardItem> _presentationBlocks = const [],
      _presentationCandidates = const [];
  bool _pendingCandidateRemoved = false;

  // Reuse immutable display snapshots across scroll/chrome rebuilds. A pending
  // placement never edits a task, creates a plan, or writes to the supplied maps.
  void _refreshPresentation() {
    if (identical(_presentationBlockSource, widget.blocks) &&
        identical(_presentationCandidateSource, widget.candidates) &&
        identical(_presentationPendingSource, widget.pendingAdjustment)) {
      return;
    }
    _presentationBlockSource = widget.blocks;
    _presentationCandidateSource = widget.candidates;
    _presentationPendingSource = widget.pendingAdjustment;
    _presentationBlocks = widget.blocks;
    _presentationCandidates = widget.candidates;
    _pendingCandidateRemoved = false;
    final pending = widget.pendingAdjustment;
    if (pending == null || pending['id'] == null) return;
    final start = _date(pending['start']), end = _date(pending['end']);
    if (start == null || end == null || !end.isAfter(start)) return;
    BoardItem? source;
    for (final block in widget.blocks) {
      if (block['id'] == pending['id']) {
        source = block;
        break;
      }
    }
    for (final candidate in widget.candidates) {
      if (candidate['id'] == pending['id']) {
        source ??= candidate;
        _pendingCandidateRemoved = true;
      }
    }
    if (source == null) return;
    final display = <String, Object?>{...source, ...pending, '_saving': true};
    _presentationBlocks = List.unmodifiable([
      for (final block in widget.blocks)
        if (block['id'] != pending['id']) block,
      display,
    ]);
    if (_pendingCandidateRemoved) {
      _presentationCandidates = List.unmodifiable([
        for (final candidate in widget.candidates)
          if (candidate['id'] != pending['id']) candidate,
      ]);
    }
  }

  List<BoardItem> get _blocks {
    _refreshPresentation();
    return _presentationBlocks;
  }

  List<BoardItem> get _candidates {
    _refreshPresentation();
    return _presentationCandidates;
  }

  Object get _candidateCount {
    _refreshPresentation();
    final count = widget.options['candidateCount'];
    return count is num
        ? math.max(0, count.toInt() - (_pendingCandidateRemoved ? 1 : 0))
        : _candidates.length;
  }

  double _number(String key, double fallback, double min, double max) =>
      (widget.options[key] as num? ?? fallback).toDouble().clamp(min, max);
  int get _startMinute =>
      _focusStart ?? _number('startMinute', 0, 0, 1439).round();
  int get _endMinute {
    final value = _focusEnd ?? _number('endMinute', 1440, 1, 1440).round();
    return value > _startMinute ? value : 1440;
  }

  double get _scale => _focusScale ?? _number('pixelsPerMinute', 1, .5, 3);
  // The script supplies floating wall-clock ISO values in its planning zone.
  // UTC is only an arithmetic container here, so the device timezone and its
  // DST rules cannot alter geometry; scripts resolve actual instants.
  DateTime? _date(Object? value) {
    if (value is! String) return null;
    // Wall-clock values recur in labels, hit testing, gaps and geometry. Keep
    // this bounded so a long editing session cannot retain every drag instant.
    if (_parsedDates.length >= 2048) _parsedDates.clear();
    return _parsedDates.putIfAbsent(value, () {
      final parsed = DateTime.tryParse(value);
      return parsed == null
          ? null
          : DateTime.utc(
              parsed.year,
              parsed.month,
              parsed.day,
              parsed.hour,
              parsed.minute,
              parsed.second,
              parsed.millisecond,
              parsed.microsecond,
            );
    });
  }

  DateTime _midnight(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);
  List<BoardItem> get _days {
    if (_focusDays != null) return _focusDays!;
    if (identical(_daySource, widget.days) && _validatedDays != null) {
      return _validatedDays!;
    }
    _daySource = widget.days;
    if (widget.days.isNotEmpty) {
      return _validatedDays = widget.days
          .where((day) => _date(day['date']) != null)
          .toList();
    }
    final today = _midnight(DateTime.now());
    return _validatedDays = List.generate(5, (i) {
      final day = DateTime.utc(today.year, today.month, today.day + i);
      return {
        'date': _stamp(day).substring(0, 10),
        'label': '${day.month}/${day.day}',
      };
    });
  }

  String _stamp(DateTime value) =>
      value.toIso8601String().replaceFirst(RegExp(r'Z$'), '');
  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  String _full(DateTime value) => '${value.month}/${value.day} ${_time(value)}';
  Duration? _duration(BoardItem item) {
    final minutes = item['durationMinutes'];
    if (minutes is num && minutes.isFinite && minutes > 0) {
      return Duration(
        microseconds: (minutes * Duration.microsecondsPerMinute).round(),
      );
    }
    final start = _date(item['start']), end = _date(item['end']);
    if (start != null && end != null && end.isAfter(start)) {
      return end.difference(start);
    }
    return null;
  }

  bool _movable(BoardItem item) =>
      widget.enabled &&
      (item['_boardGeneration'] == null ||
          item['_boardGeneration'] == _viewGeneration) &&
      item['fixed'] != true &&
      item['readOnly'] != true &&
      item['moveEvent'] is Map &&
      _duration(item) != null;

  @override
  void initState() {
    super.initState();
    _clockElapsed.start();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _timeline) setState(() {});
    });
    if (_timeline) _candidatesExpanded = false;
    _horizontal.addListener(_syncHeader);
    _header.addListener(_syncTimelineBody);
    _horizontal.addListener(_refreshWindow);
    _vertical.addListener(_refreshWindow);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _vertical.hasClients) {
        _vertical.jumpTo(
          ((_number('initialMinute', 480, 0, 1440) - _startMinute) * _scale)
              .clamp(0, _vertical.position.maxScrollExtent),
        );
        _refreshWindow();
      }
    });
  }

  void _refreshWindow() {
    if (!mounted) return;
    final size = _viewport?.size;
    if (size == null) return;
    final x = _horizontal.hasClients ? _horizontal.offset : 0.0;
    final y = _vertical.hasClients ? _vertical.offset : 0.0;
    // A cached overscan window changes only every 64px, keeping normal and
    // auto scrolling local while retaining rows entering the viewport.
    _window.value = Rect.fromLTWH(
      (x / 64).floor() * 64 - 64,
      (y / 64).floor() * 64 - 128,
      size.width + 192,
      size.height + 320,
    );
  }

  void _syncHeader() {
    if (_synchronizingTimeline ||
        !_header.hasClients ||
        !_horizontal.hasClients) {
      return;
    }
    final target = _horizontal.offset.clamp(
      0,
      _header.position.maxScrollExtent,
    );
    if ((_header.offset - target).abs() < .01) return;
    _synchronizingTimeline = true;
    try {
      _header.jumpTo(target.toDouble());
    } finally {
      _synchronizingTimeline = false;
    }
  }

  void _syncTimelineBody() {
    if (!_timeline ||
        _synchronizingTimeline ||
        !_header.hasClients ||
        !_horizontal.hasClients) {
      return;
    }
    final target = _header.offset.clamp(
      0,
      _horizontal.position.maxScrollExtent,
    );
    if ((_horizontal.offset - target).abs() < .01) return;
    _synchronizingTimeline = true;
    try {
      _horizontal.jumpTo(target.toDouble());
    } finally {
      _synchronizingTimeline = false;
    }
  }

  @override
  void didUpdateWidget(covariant PlannerBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.options['now'] != oldWidget.options['now']) {
      _clockElapsed.reset();
    }
    final retainedDate = _timeline && oldWidget.days.isNotEmpty
        ? _date(oldWidget.days.first['date'])?.add(
            Duration(
              days: _horizontal.hasClients
                  ? (_horizontal.offset / _columnWidth + .001).floor()
                  : 0,
            ),
          )
        : null;
    final retainedFraction = _horizontal.hasClients
        ? (_horizontal.offset / _columnWidth) % 1
        : 0.0;
    // Script trees are immutable snapshots. Chrome changes reuse their inputs;
    // only a new task snapshot invalidates parsed geometry and daily occupancy.
    if (!identical(widget.blocks, oldWidget.blocks) ||
        !identical(widget.pendingAdjustment, oldWidget.pendingAdjustment) ||
        widget.pendingAdjustment != null &&
            !identical(widget.candidates, oldWidget.candidates)) {
      _geometrySource = null;
      _geometry = null;
      _dailyOccupancy.clear();
    }
    final daysChanged =
        !identical(widget.days, oldWidget.days) &&
        jsonEncode(widget.days) != jsonEncode(oldWidget.days);
    if (daysChanged) {
      _daySource = _validatedDays = null;
    } else if (identical(oldWidget.days, _daySource)) {
      _daySource = widget.days;
    }
    if (_timeline) {
      final requested =
          widget.options['scrollRequest'] != oldWidget.options['scrollRequest'];
      if (requested || daysChanged) {
        final target = requested
            ? _date(widget.options['initialDate'])
            : retainedDate;
        if (target != null) {
          _positionTimeline(target, fraction: requested ? 0 : retainedFraction);
        }
      }
    }
    if (widget.options['startMinute'] != oldWidget.options['startMinute'] ||
        widget.options['endMinute'] != oldWidget.options['endMinute']) {
      final preserveMinute =
          _timeline &&
          '${widget.options['displayHoursLabel']}'.startsWith('自动') &&
          '${oldWidget.options['displayHoursLabel']}'.startsWith('自动');
      final oldScale = (oldWidget.options['pixelsPerMinute'] as num? ?? 1)
          .toDouble()
          .clamp(.5, 3.0);
      final minute = preserveMinute
          ? (oldWidget.options['startMinute'] as num? ?? 480) +
                (_vertical.hasClients ? _vertical.offset : 0) / oldScale
          : _number('initialMinute', _startMinute.toDouble(), 0, 1440);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _vertical.hasClients) {
          _vertical.jumpTo(
            ((minute - _startMinute) * _scale).clamp(
              0,
              _vertical.position.maxScrollExtent,
            ),
          );
          _refreshWindow();
        }
      });
    } else if (_focusScale == null &&
        widget.options['pixelsPerMinute'] !=
            oldWidget.options['pixelsPerMinute']) {
      // Keep the minute at the top of the viewport fixed when changing the
      // display scale. Tasks and horizontal position remain untouched.
      final oldScale = (oldWidget.options['pixelsPerMinute'] as num? ?? 1)
          .toDouble()
          .clamp(.5, 3.0);
      final minute =
          _startMinute +
          (_vertical.hasClients ? _vertical.offset : 0) / oldScale;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _vertical.hasClients) {
          _vertical.jumpTo(
            ((minute - _startMinute) * _scale).clamp(
              0,
              _vertical.position.maxScrollExtent,
            ),
          );
          _refreshWindow();
        }
      });
    }
    if (_selectedItem != null) {
      final id = _selectedItem!['id'];
      final matches = _blocks.where((item) => item['id'] == id);
      _selectedItem = matches.isEmpty ? null : matches.first;
    }
    if (!widget.enabled ||
        widget.previewIdentity != oldWidget.previewIdentity ||
        daysChanged ||
        widget.options['startMinute'] != oldWidget.options['startMinute'] ||
        widget.options['endMinute'] != oldWidget.options['endMinute'] ||
        widget.options['pixelsPerMinute'] !=
            oldWidget.options['pixelsPerMinute']) {
      _clearDrag();
      _viewGeneration++;
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _clockElapsed.stop();
    _fineTimer?.cancel();
    _intentTimer?.cancel();
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _previewTimer?.cancel();
    _dragSession++;
    _horizontal.dispose();
    _header.dispose();
    _candidatesScroll.dispose();
    _vertical.dispose();
    _proposal.dispose();
    if (_dragActive.value) widget.onDragActiveChanged?.call(false);
    _dragActive.dispose();
    _feedbackPointer.dispose();
    _validation.dispose();
    _window.dispose();
    super.dispose();
  }

  void _setDragActive(bool active) {
    if (_dragActive.value == active) return;
    void update() {
      if (!mounted || _dragActive.value == active) return;
      _dragActive.value = active;
      widget.onDragActiveChanged?.call(active);
      if (!active && _closeCandidatesAfterDrag) {
        _closeCandidatesAfterDrag = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _candidatesExpanded = false);
        });
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => update());
    } else {
      update();
    }
  }

  void _clearDrag({bool endGesture = true}) {
    if (endGesture) _setDragActive(false);
    _fineTimer?.cancel();
    _intentTimer?.cancel();
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _previewTimer?.cancel();
    _dragSession++;
    _previewRevision++;
    _previewSignature = null;
    void clearNotifiers() {
      _proposal.value = null;
      _validation.value = null;
      _window.value = _window.value.translate(.001, 0);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      final session = _dragSession;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && session == _dragSession) clearNotifiers();
      });
    } else {
      clearNotifiers();
    }
    _anchor = _lastPosition = null;
    _pointerPosition = null;
    _fineStart = null;
    _gestureTime = null;
    _gesturePointer = _horizontalIntentAnchor = null;
    _gestureDay = null;
    if (endGesture) _moveOrigin = _movePointerOrigin = null;
    _fine = false;
    _fineStep = 1;
    _intent = 'move';
    _targetId = null;
    _pendingIntent = null;
    _pendingTargetId = null;
    _activeItem = null;
    _pinnedSegment = null;
    _resizing = false;
    _resizeBasePoint = null;
    _resizeBaseEnd = null;
  }

  BoardItem _eventFor(_Proposal proposal) => {
    ...Map<String, Object?>.from(proposal.item['moveEvent'] as Map),
    'id': proposal.item['id'],
    'start': _stamp(proposal.start),
    'end': _stamp(proposal.end),
    'intent': proposal.intent,
    if (proposal.targetId != null) 'targetId': proposal.targetId,
    'snapMinutes': proposal.snap,
  };

  void _publish(_Proposal proposal) {
    _proposal.value = proposal;
    final preview = widget.onPreview;
    if (preview == null) return;
    final event = _eventFor(proposal);
    final signature = jsonEncode({...event}..remove('snapMinutes'));
    if (_previewSignature == signature) return;
    _previewSignature = signature;
    final revision = ++_previewRevision, session = _dragSession;
    _previewTimer?.cancel();
    _validation.value = null;
    _previewTimer = Timer(const Duration(milliseconds: 180), () async {
      try {
        final result = await preview(event);
        if (mounted &&
            session == _dragSession &&
            revision == _previewRevision &&
            _proposal.value != null) {
          _validation.value = result;
        }
      } catch (error) {
        if (mounted &&
            session == _dragSession &&
            revision == _previewRevision &&
            _proposal.value != null) {
          _validation.value = {'valid': false, 'previewLabel': '预览失败：$error'};
        }
      }
    });
  }

  Rect? get _viewport {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      origin.dx + 48,
      origin.dy,
      math.max(0, box.size.width - 48),
      box.size.height,
    );
  }

  void _ensureAutoScroll() {
    _scrollTimer ??= Timer.periodic(const Duration(milliseconds: 32), (_) {
      final position = _pointerPosition,
          viewport = _viewport,
          item = _activeItem;
      if (!mounted || position == null || viewport == null || item == null) {
        return;
      }
      double edge(double value, double min, double max) {
        const margin = 44.0;
        if (value < min + margin) {
          return -14 * ((min + margin - value) / margin).clamp(0, 1);
        }
        if (value > max - margin) {
          return 14 * ((value - max + margin) / margin).clamp(0, 1);
        }
        return 0;
      }

      bool scroll(ScrollController controller, double delta) {
        if (!controller.hasClients || delta == 0) return false;
        final next = (controller.offset + delta).clamp(
          0,
          controller.position.maxScrollExtent,
        );
        if ((next - controller.offset).abs() < .01) return false;
        controller.jumpTo(next.toDouble());
        return true;
      }

      final x = scroll(
        _horizontal,
        edge(position.dx, viewport.left, viewport.right),
      );
      final y = scroll(
        _vertical,
        edge(position.dy, viewport.top, viewport.bottom),
      );
      if (x || y) _hover(item, position, fromScroll: true);
    });
  }

  void _beginResize(BoardItem item, Offset global) {
    _clearDrag();
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_movable(item)) return;
    _setDragActive(true);
    _resizing = true;
    _resizeBasePoint = box.globalToLocal(global);
    _resizeBaseEnd = _date(item['end']);
    _hover(item, global);
  }

  int _fineDelta(Offset global) {
    final finger = (global.dy - _anchor!.dy) / _finePixels;
    final scroll =
        ((_vertical.hasClients ? _vertical.offset : 0) - _fineScrollAnchor) /
        _scale;
    return ((finger + scroll) / _fineStep).round() * _fineStep;
  }

  DateTime? _pointerInstant(Offset global) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _days.isEmpty) return null;
    final point = box.globalToLocal(global);
    final index = (point.dx / _columnWidth).floor().clamp(0, _days.length - 1);
    return _midnight(_date(_days[index]['date'])!).add(
      Duration(
        microseconds:
            ((_startMinute + point.dy / _scale) *
                    Duration.microsecondsPerMinute)
                .round(),
      ),
    );
  }

  void _enterFine(int step) {
    final value = _proposal.value;
    final position = _pointerPosition;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (!mounted || value == null || position == null || box == null) return;
    _fine = true;
    _fineStep = step;
    _anchor = position;
    _fineStart = _resizing ? value.end : value.start;
    _fineScrollAnchor = _vertical.hasClients ? _vertical.offset : 0;
    _fineDayAnchor = (box.globalToLocal(position).dx / _columnWidth)
        .floor()
        .clamp(0, _days.length - 1);
    _publish(
      _Proposal(
        value.item,
        value.start,
        value.end,
        step,
        intent: value.intent,
        targetId: value.targetId,
      ),
    );
  }

  /// Horizontal intent changes precision/date; vertical travel changes time.
  /// Rebase at each transition so neither changing mode nor changing day jumps
  /// to the pointer's absolute time, including when a card was grabbed midway.
  DateTime _dashboardTime(Offset global, int index) {
    final vertical = _vertical.hasClients ? _vertical.offset : 0.0;
    final horizontal = _horizontal.hasClients ? _horizontal.offset : 0.0;
    final instant = _pointerInstant(global)!;
    if (_gestureTime == null) {
      final origin = _resizing ? _resizeBaseEnd : _moveOrigin;
      final pointerOrigin = _resizing
          ? _pointerInstant(_resizeDown ?? global)
          : _movePointerOrigin;
      _gestureTime = origin != null && pointerOrigin != null
          ? origin.add(
              Duration(
                minutes:
                    (instant.difference(pointerOrigin).inMicroseconds /
                            Duration.microsecondsPerMinute /
                            5)
                        .round() *
                    5,
              ),
            )
          : _midnight(instant).add(
              Duration(
                minutes: ((instant.hour * 60 + instant.minute) / 5).round() * 5,
              ),
            );
      _gestureDay = index;
      _gesturePointer = _horizontalIntentAnchor = global;
      _gestureScroll = vertical;
      _horizontalIntentScroll = horizontal;
    }
    final delta =
        (global.dy - _gesturePointer!.dy) /
            (_fine ? math.max(4, _scale) : _scale) +
        (vertical - _gestureScroll) / _scale;
    final step = _fine ? 1 : 5;
    var time = _gestureTime!.add(
      Duration(minutes: (delta / step).round() * step),
    );
    final dx =
        global.dx -
        _horizontalIntentAnchor!.dx +
        horizontal -
        _horizontalIntentScroll;
    final dy = global.dy - _horizontalIntentAnchor!.dy;
    final point = (_gridKey.currentContext!.findRenderObject() as RenderBox)
        .globalToLocal(global);
    final depth = index > _gestureDay!
        ? point.dx - index * _columnWidth
        : (index + 1) * _columnWidth - point.dx;
    final changeDay =
        index != _gestureDay &&
        dx.abs() >= math.max(48, _columnWidth * .55) &&
        depth >= _columnWidth * .18;
    final fingerDx = (global.dx - _horizontalIntentAnchor!.dx).abs();
    final enterFine = !_fine && fingerDx >= 14 && fingerDx >= dy.abs() * .8;
    if (changeDay || enterFine) {
      if (changeDay) {
        final previous = _proposal.value;
        final held = previous == null
            ? time
            : (_resizing ? previous.end : previous.start);
        time = held.add(
          _midnight(_date(_days[index]['date'])!)
              .difference(_midnight(_date(_days[_gestureDay!]['date'])!)),
        );
        _gestureDay = index;
        _fine = false;
        _horizontalIntentAnchor = global;
        _horizontalIntentScroll = horizontal;
      } else {
        _fine = true;
        _fineStep = 1;
      }
      _gestureTime = time;
      _gesturePointer = global;
      _gestureScroll = vertical;
      HapticFeedback.selectionClick();
    } else if (!_fine && dx.abs() < 14 && dy.abs() > 10) {
      // Start measuring lateral intent afresh during ordinary vertical travel.
      _horizontalIntentAnchor = global;
      _horizontalIntentScroll = horizontal;
    }
    return time;
  }

  void _hover(BoardItem item, Offset global, {bool fromScroll = false}) {
    if (!_movable(item)) return;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    final days = _days;
    final duration = _duration(item);
    if (box == null || days.isEmpty || duration == null) return;
    _activeItem = item;
    _pointerPosition = global;
    _ensureAutoScroll();
    final point = box.globalToLocal(global);
    var index = (point.dx / _columnWidth).floor().clamp(0, days.length - 1);
    if (!_dashboard &&
        !fromScroll &&
        (_lastPosition == null || (global - _lastPosition!).distance > 8)) {
      _fineTimer?.cancel();
      if (_fine && (global - (_anchor ?? global)).distance > 48) {
        _fine = false;
        _fineStart = null;
      }
      _lastPosition = global;
      if (!_fine) {
        _fineTimer = Timer(
          const Duration(milliseconds: 650),
          () => _enterFine(1),
        );
      }
    }
    final dashboardTime = _dashboard ? _dashboardTime(global, index) : null;
    if (_dashboard) index = _gestureDay!;
    final day = _midnight(_date(days[index]['date'])!);
    final raw = _startMinute + point.dy / _scale;
    final minute = _fine && _fineStart != null
        ? _fineStart!.hour * 60 + _fineStart!.minute + _fineDelta(global)
        : (raw / 15).round() * 15;
    // Display bounds do not constrain the duration or move it back from midnight.
    var start =
        dashboardTime ??
        day.add(Duration(minutes: minute.clamp(0, _fine ? 1439 : 1425)));
    var end = start.add(duration);
    if (_resizing && _resizeBaseEnd != null && _resizeBasePoint != null) {
      start = _date(item['start'])!;
      final baseIndex = (_resizeBasePoint!.dx / _columnWidth).floor().clamp(
        0,
        days.length - 1,
      );
      final dayDelta = _midnight(_date(days[index]['date'])!)
          .difference(_midnight(_date(days[baseIndex]['date'])!));
      end =
          dashboardTime ??
          (_fine && _fineStart != null
              ? _fineStart!.add(
                  day.difference(
                        _midnight(_date(days[_fineDayAnchor]['date'])!),
                      ) +
                      Duration(minutes: _fineDelta(global)),
                )
              : _resizeBaseEnd!.add(
                  dayDelta +
                      Duration(
                        minutes: ((point.dy - _resizeBasePoint!.dy) / _scale)
                            .round(),
                      ),
                ));
      if (!_dashboard && !_fine) {
        end = _midnight(end).add(
          Duration(minutes: ((end.hour * 60 + end.minute) / 15).round() * 15),
        );
      }
      if (!end.isAfter(start)) end = start.add(const Duration(minutes: 1));
      _publish(_Proposal(item, start, end, _snap, intent: 'resize'));
      return;
    }
    BoardItem? target;
    final groups = _index(_blocks, _cardHeight).days[index];
    final position =
        start
            .difference(day.add(Duration(minutes: _startMinute)))
            .inMicroseconds /
        Duration.microsecondsPerMinute *
        _scale;
    var low = 0, high = groups.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (groups[middle].bottom <= position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low < groups.length && groups[low].top <= position) {
      for (final segment in groups[low].segments) {
        if (segment.item['id'] == item['id']) continue;
        if (!start.isBefore(segment.start) && start.isBefore(segment.end)) {
          target = segment.item;
          break;
        }
      }
    }
    var nextIntent = 'move';
    if (target != null) {
      final a = _date(target['start'])!, b = _date(target['end'])!;
      final fraction =
          start.difference(a).inMilliseconds / b.difference(a).inMilliseconds;
      nextIntent = fraction > .25 && fraction < .75 ? 'swap' : 'insert';
    }
    final nextId = target?['id'];
    if (nextId == _targetId && nextIntent == _intent) {
      _intentTimer?.cancel();
      _pendingIntent = null;
      _pendingTargetId = null;
    } else if (nextId != _pendingTargetId || nextIntent != _pendingIntent) {
      // Dwell keeps the target steady around an edge. This is an intent only;
      // scripts decide whether this target may be changed.
      _intentTimer?.cancel();
      _pendingIntent = nextIntent;
      _pendingTargetId = nextId;
      _intentTimer = Timer(const Duration(milliseconds: 280), () {
        if (!mounted || _proposal.value == null) return;
        _intent = nextIntent;
        _targetId = nextId;
        _pendingIntent = null;
        _pendingTargetId = null;
        final old = _proposal.value!;
        _publish(
          _Proposal(
            old.item,
            old.start,
            old.end,
            old.snap,
            intent: _intent,
            targetId: _targetId,
          ),
        );
      });
    }
    _publish(
      _Proposal(
        item,
        start,
        end,
        _snap,
        intent: _pendingIntent == null ? _intent : 'move',
        targetId: _pendingIntent == null ? _targetId : null,
      ),
    );
  }

  void _drop(BoardItem item, Offset position) {
    if (!_movable(item) || _activeItem == null) {
      _clearDrag();
      return;
    }
    _hover(item, position);
    final proposal = _proposal.value;
    if (proposal != null && item['moveEvent'] is Map) {
      widget.onEvent(_eventFor(proposal));
    }
    _clearDrag();
  }

  List<BoardItem> _localPreview(_Proposal value) {
    final sourceStart = _date(value.item['start']);
    final target = _index(_blocks, _cardHeight).byId[value.targetId];
    final targetStart = target == null ? null : _date(target['start']);
    final targetDuration = target == null ? null : _duration(target);
    if (value.intent == 'swap' &&
        sourceStart != null &&
        targetStart != null &&
        targetDuration != null) {
      return [
        {
          ...value.item,
          'start': _stamp(targetStart),
          'end': _stamp(targetStart.add(value.end.difference(value.start))),
        },
        {
          ...target!,
          'start': _stamp(sourceStart),
          'end': _stamp(sourceStart.add(targetDuration)),
        },
      ];
    }
    return [
      {...value.item, 'start': _stamp(value.start), 'end': _stamp(value.end)},
    ];
  }

  List<BoardItem> _servicePreview() {
    final blocks = _validation.value?['previewBlocks'];
    return blocks is List
        ? blocks
              .whereType<Map>()
              .map((item) => Map<String, Object?>.from(item))
              .toList()
        : [];
  }

  List<Widget> _status() => [
    if (_validation.value?['previewLabel'] != null)
      Text('${_validation.value!['previewLabel']}'),
    for (final conflict
        in _validation.value?['conflicts'] is List
            ? _validation.value!['conflicts'] as List
            : [])
      Text(
        '$conflict',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    if (_validation.value?['valid'] == false &&
        _validation.value?['previewLabel'] == null)
      Text(
        '此安排存在冲突，落下后仍须校验',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    if (_validation.value?['overdue'] == true ||
        (_validation.value?['overdue'] is List &&
            (_validation.value!['overdue'] as List).isNotEmpty))
      Text(
        '安排超过截止，落下后需明确确认',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
  ];

  Rect _feedbackBounds(BuildContext context) {
    final view = View.of(context);
    final size = view.physicalSize / view.devicePixelRatio;
    final media = MediaQuery.of(context);
    return Rect.fromLTRB(
      media.padding.left + 8,
      media.padding.top + 8,
      math.max(media.padding.left + 9, size.width - media.padding.right - 8),
      math.max(
        media.padding.top + 9,
        size.height -
            math.max(media.padding.bottom, media.viewInsets.bottom) -
            8,
      ),
    );
  }

  Rect _safeSourceRect(Size size, Offset grab) {
    final bounds = _feedbackBounds(context);
    final origin = _feedbackPointer.value - grab;
    return Rect.fromLTWH(
      origin.dx.clamp(
        bounds.left,
        math.max(bounds.left, bounds.right - size.width),
      ),
      origin.dy.clamp(
        bounds.top,
        math.max(bounds.top, bounds.bottom - size.height),
      ),
      size.width,
      size.height,
    );
  }

  Widget _dragHint(BuildContext context) {
    final value = _proposal.value;
    final scheme = Theme.of(context).colorScheme;
    return _ScreenClampedFeedback(
      pointer: _feedbackPointer.value,
      safeBounds: _feedbackBounds(context),
      abovePointer: true,
      child: Material(
        key: const ValueKey('planner-drag-hint'),
        elevation: 6,
        color: scheme.surfaceContainerHigh,
        shadowColor: scheme.shadow.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _fine ? Icons.tune_rounded : Icons.open_with_rounded,
                      size: 15,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      value == null ? '拖入时间表' : _snapLabel(value.snap),
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: scheme.primary),
                    ),
                    if (_activeItem != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${_activeItem!['title'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ],
                  ],
                ),
                if (value != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${value.start.month}/${value.start.day} ${_weekday(value.start)}  '
                    '${_time(value.start)}–${_time(value.end)}'
                    '${_midnight(value.end) != _midnight(value.start) ? '（${value.end.month}/${value.end.day}结束）' : ''}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  _fine ? '上下精调 · 大幅横移换日' : '横移精调 · 大幅横移换日',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                ..._status(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  (Rect, DateTime, DateTime)? _candidateTarget(_Proposal value) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    final viewport = _viewport;
    if (box == null || viewport == null) return null;
    final day = _midnight(value.start);
    final index = _days.indexWhere((d) => _midnight(_date(d['date'])!) == day);
    if (index < 0) return null;
    final from = day.add(Duration(minutes: _startMinute));
    final to = day.add(Duration(minutes: _endMinute));
    final start = value.start.isBefore(from) ? from : value.start;
    final end = value.end.isAfter(to) ? to : value.end;
    if (!end.isAfter(start)) return null;
    final origin = box.localToGlobal(
      Offset(
        index * _columnWidth + 6,
        start.difference(from).inMicroseconds /
            Duration.microsecondsPerMinute *
            _scale,
      ),
    );
    final rect = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      _columnWidth - 12,
      end.difference(start).inMicroseconds /
          Duration.microsecondsPerMinute *
          _scale,
    );
    final clipped = rect.intersect(viewport);
    if (clipped.isEmpty) return null;
    final visibleStart = clipped.top > rect.top
        ? start.add(
            Duration(
              microseconds:
                  ((clipped.top - rect.top) /
                          _scale *
                          Duration.microsecondsPerMinute)
                      .round(),
            ),
          )
        : start;
    final visibleEnd = clipped.bottom < rect.bottom
        ? end.subtract(
            Duration(
              microseconds:
                  ((rect.bottom - clipped.bottom) /
                          _scale *
                          Duration.microsecondsPerMinute)
                      .round(),
            ),
          )
        : end;
    return (clipped, visibleStart, visibleEnd);
  }

  List<Widget> _dragRuler(double gridHeight) {
    final value = _proposal.value;
    if (value == null) return const [];
    final scaler = MediaQuery.textScalerOf(context);
    final scheme = Theme.of(context).colorScheme;
    final labelHeight = scaler.scale(10) * 1.4 + 6;
    final top = _vertical.hasClients ? _vertical.offset : 0.0;
    final bottom = math.min(
      gridHeight,
      top + (_viewport?.height ?? gridHeight),
    );
    final from = _midnight(value.start).add(Duration(minutes: _startMinute));
    double y(DateTime instant) =>
        instant.difference(from).inMicroseconds /
        Duration.microsecondsPerMinute *
        _scale;
    final start = y(value.start), end = y(value.end);
    final last = math.max(top, bottom - labelHeight);
    var startTop = (start - labelHeight).clamp(top, last).toDouble();
    var endTop = end.clamp(top, last).toDouble();
    if (endTop < startTop + labelHeight + 2) {
      startTop = math.max(top, endTop - labelHeight - 2);
      endTop = math.min(last, math.max(endTop, startTop + labelHeight + 2));
    }
    return [
      for (final edge in [
        (true, start, startTop, value.start),
        (false, end, endTop, value.end),
      ]) ...[
        Positioned(
          left: 40,
          width: 8,
          height: 1,
          top: edge.$2.clamp(top, math.max(top, bottom - 1)),
          child: ColoredBox(color: scheme.primary),
        ),
        Positioned(
          key: ValueKey(edge.$1 ? 'planner-drag-start' : 'planner-drag-end'),
          left: 0,
          width: 47,
          height: labelHeight,
          top: edge.$3,
          child: Semantics(
            label: '拖动${edge.$1 ? '开始' : '结束'} ${_full(edge.$4)}',
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${edge.$2 < top
                    ? '↑'
                    : edge.$2 > bottom
                    ? '↓'
                    : ''}${_time(edge.$4)}',
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ),
      ],
    ];
  }

  Widget _card(
    BoardItem item,
    double height, {
    String? continuation,
    String? sourceSegment,
    double? segmentTop,
    bool draggable = true,
  }) {
    final generation = _viewGeneration;
    final scheme = Theme.of(context).colorScheme;
    final deadline = item['deadlineSummary'] as String?;
    final start = _date(item['start']), end = _date(item['end']);
    final scheduled = start != null && end != null;
    final compactCandidate =
        _timeline && !scheduled && item['_candidateList'] != true;
    final subtitle = _summary(item);
    final accent = _accent(item);
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final titleLines = item['_titleLines'] == 2 ? 2 : 1;
    double measuredHeight(TextStyle? style) {
      final direction = Directionality.of(context);
      if (_textHeights.length >= 64) _textHeights.clear();
      return _textHeights.putIfAbsent((style, scaler, direction), () {
        final painter = TextPainter(
          text: TextSpan(text: '时间任务', style: style),
          textScaler: scaler,
          textDirection: direction,
        )..layout();
        final result = painter.height;
        painter.dispose();
        return result;
      });
    }

    final timeHeight = measuredHeight(
      textTheme.labelSmall?.copyWith(fontSize: 10),
    );
    final titleHeight = math.max(
      12.0,
      measuredHeight(
        textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: titleLines > 1 ? 11 : null,
          height: titleLines > 1 ? 1.15 : null,
        ),
      ),
    );
    final full = scheduled && height >= timeHeight * 2 + titleHeight + 12;
    final two = scheduled && height >= titleHeight + timeHeight + 12;
    final icon = titleLines > 1
        ? null
        : item['readOnly'] == true
        ? Icons.school_outlined
        : item['fixed'] == true
        ? Icons.lock_rounded
        : null;
    final title = Row(
      children: [
        Expanded(
          child: Text(
            '${continuation ?? ''}${item['title'] ?? ''}',
            maxLines: full ? titleLines : 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: titleLines > 1
                  ? 11
                  : !scheduled && _timeline
                  ? 13
                  : null,
              height: titleLines > 1 ? 1.15 : null,
              color: ContentColors.foreground(
                accent,
                _surface(item),
                scheme.onSurface,
              ),
            ),
          ),
        ),
        if (icon != null) Icon(icon, size: 12, color: accent),
      ],
    );
    Widget card = Semantics(
      label:
          '${item['title'] ?? ''}，${scheduled ? '${_full(start)}至${_full(end)}' : subtitle}${item['readOnly'] == true ? '，来源只读' : ''}${item['fixed'] == true ? '，固定时间' : ''}',
      child: Material(
        elevation:
            scheduled &&
                _selectedItem?['id'] == item['id'] &&
                item['_resident'] != true
            ? 1
            : 0,
        shadowColor: scheme.primary.withValues(alpha: .2),
        color: item['_candidateList'] == true
            ? scheme.surface
            : item['_resident'] == true
            ? Colors.transparent
            : _selectedItem?['id'] == item['id']
            ? Color.lerp(_surface(item), scheme.surface, .2)
            : _surface(item),
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter:
              scheduled && item['readOnly'] == true && item['_resident'] != true
              ? _SourceHatching(accent)
              : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => _activate(item),
            child: Container(
              height: compactCandidate ? height - 10 : height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border:
                    _selectedItem?['id'] == item['id'] ||
                        item['selected'] == true ||
                        widget.selectedIds.contains(item['id'])
                    ? Border.all(
                        color: scheme.primary,
                        width: scheduled ? 2 : 1.5,
                      )
                    : item['_candidateList'] == true
                    ? Border.all(
                        color: scheme.outlineVariant.withValues(alpha: .6),
                      )
                    : null,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: scheduled ? (titleLines > 1 ? 2 : 7) : 10,
                vertical: item['_resident'] == true ? 2 : 4,
              ),
              child: scheduled
                  ? _dashboard && full
                        ? _PlannerBlockContents(
                            key: ValueKey(
                              'resident:${sourceSegment ?? item['id']}',
                            ),
                            item: item,
                            identity: sourceSegment ?? '${item['id']}',
                            continuation: continuation ?? '',
                            startLabel: _edgeTime(item, true),
                            endLabel: _edgeTime(item, false),
                            timeHeight: timeHeight,
                            accent: accent,
                            vertical: _vertical,
                            dragActive: _dragActive,
                            segmentTop: segmentTop,
                            bottomInset: widget.bottomInset,
                            viewportHeight: _viewport?.height ?? height,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (full)
                                Text(
                                  _edgeTime(item, true),
                                  maxLines: 1,
                                  style: textTheme.labelSmall?.copyWith(
                                    fontSize: 10,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              title,
                              if (full) const Spacer(),
                              if (two)
                                Text(
                                  full
                                      ? _edgeTime(item, false)
                                      : '${_time(start)}–${_time(end)}',
                                  maxLines: 1,
                                  style: textTheme.labelSmall?.copyWith(
                                    fontSize: 10,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          )
                  : _timeline
                  ? Row(
                      children: [
                        if (item['_candidateList'] == true) ...[
                          Icon(
                            Icons.drag_indicator,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 7),
                          Container(
                            width: 12,
                            height: 20,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .35),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(child: title),
                        if (item['overdue'] == true &&
                            item['_candidateList'] != true) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: scheme.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(width: 7),
                          Text(
                            '${item['_candidateList'] == true ? '' : '· '}${subtitle.replaceFirst('耗时', '')}',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              color: item['overdue'] == true
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            color: item['overdue'] == true
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
    if (compactCandidate) {
      card = SizedBox(
        height: height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _activate(item),
          child: Center(child: card),
        ),
      );
    }
    if (draggable && _movable(item)) {
      var sourceSize = Size(112, height);
      var sourceGrab = Offset.zero;
      card = LongPressDraggable<BoardItem>(
        data: {...item, '_boardGeneration': _viewGeneration},
        rootOverlay: true,
        dragAnchorStrategy: (draggable, context, position) {
          _feedbackPointer.value = position;
          final box = context.findRenderObject() as RenderBox;
          sourceSize = box.size;
          sourceGrab = box.globalToLocal(position);
          return Offset.zero;
        },
        onDragUpdate: (details) =>
            _feedbackPointer.value = details.globalPosition,
        onDragStarted: () {
          _clearDrag();
          _activeItem = item;
          if (_timeline && !scheduled) _closeCandidatesAfterDrag = true;
          if (_dashboard && scheduled) {
            _moveOrigin = start;
            _movePointerOrigin = _pointerInstant(_feedbackPointer.value);
          }
          _setDragActive(true);
          _pinnedSegment = sourceSegment;
        },
        onDragEnd: (_) => _clearDrag(),
        feedback: AnimatedBuilder(
          animation: Listenable.merge([
            _proposal,
            _validation,
            _feedbackPointer,
          ]),
          builder: (context, _) {
            if (!widget.enabled || generation != _viewGeneration) {
              return const SizedBox.shrink();
            }
            final value = _proposal.value;
            if (_dashboard) {
              final placement = value == null ? null : _candidateTarget(value);
              final target = placement?.$1;
              final feedbackItem = value == null
                  ? null
                  : <String, Object?>{
                      ...item,
                      'start': _stamp(value.start),
                      'end': _stamp(value.end),
                      if (placement != null)
                        '_visibleStart': _stamp(placement.$2),
                      if (placement != null)
                        '_visibleEnd': _stamp(placement.$3),
                    };
              final compactHeight = scheduled ? math.min(height, 96.0) : height;
              final compactSize = Size(sourceSize.width, compactHeight);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  _CandidateDragFeedback(
                    pointer: _feedbackPointer.value,
                    sourceRect: _safeSourceRect(compactSize, sourceGrab),
                    targetRect: target,
                    source: _card(item, compactHeight, draggable: false),
                    target: target == null || feedbackItem == null
                        ? null
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .085),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: target.height < scaler.scale(12) * 1.4 + 8
                                ? const SizedBox.expand()
                                : _card(
                                    feedbackItem,
                                    target.height,
                                    draggable: false,
                                  ),
                          ),
                  ),
                  _dragHint(context),
                ],
              );
            }
            return _ScreenClampedFeedback(
              pointer: _feedbackPointer.value,
              safeBounds: _feedbackBounds(context),
              child: Material(
                key: const ValueKey('planner-drag-feedback'),
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 250,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['title'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (value != null) ...[
                        Text('${_full(value.start)} → ${_full(value.end)}'),
                        Text(
                          '${value.end.difference(value.start).inMinutes}分钟 · ${_snapLabel(value.snap)}',
                        ),
                        Text(
                          '${switch (value.intent) {
                            'swap' => '交换',
                            'insert' => '插入',
                            'resize' => '调整时长',
                            _ => '移动',
                          }} · 待校验',
                        ),
                        for (final gap in _gaps({
                          ...value.item,
                          'start': _stamp(value.start),
                          'end': _stamp(value.end),
                        }, replacements: _servicePreview()))
                          Text(
                            '空闲${_elapsed(gap.$2.difference(gap.$1))}',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                      ] else
                        const Text('长按拖入日期表'),
                      if (deadline?.isNotEmpty == true)
                        Text(
                          '${item['deadlineText'] ?? deadline}',
                          style: TextStyle(
                            color: item['overdue'] == true
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      if (item['sourceLabel'] != null)
                        Text('${item['sourceLabel']}'),
                      ..._status(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        child: AnimatedBuilder(
          animation: Listenable.merge([_dragActive, _proposal]),
          child: card,
          builder: (context, child) => Opacity(
            opacity:
                _dashboard &&
                    _dragActive.value &&
                    _activeItem?['id'] == item['id']
                ? (scheduled ? 0 : .28)
                : 1,
            child: child,
          ),
        ),
      );
    }
    return card;
  }

  String _edgeTime(BoardItem item, bool beginning) {
    final boundary = _date(item[beginning ? '_visibleStart' : '_visibleEnd']);
    final real = _date(item[beginning ? 'start' : 'end'])!;
    return boundary != null && boundary != real
        ? (beginning ? '↳ 延续' : '延续 ↗')
        : _time(real);
  }

  void _showOutside(List<BoardItem> items, {String title = '显示范围外的安排'}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return ListTile(
                title: Text(title),
                trailing: items.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _zoom(items);
                        },
                        child: const Text('放大该时段'),
                      ),
              );
            }
            final item = items[index - 1];
            void prepareDrag() {
              Navigator.pop(context);
              setState(() => _selectedItem = item);
              _zoom([item]);
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('已放大该任务，请长按任务块拖动'),
                  duration: Duration(seconds: 3),
                ),
              );
            }

            return ListTile(
              onLongPress: _movable(item) ? prepareDrag : null,
              trailing: _movable(item)
                  ? IconButton(
                      onPressed: prepareDrag,
                      icon: const Icon(Icons.open_in_full),
                      tooltip: '放大后拖动',
                    )
                  : null,
              title: Text('${item['title'] ?? ''}'),
              subtitle: Text(
                '${_full(_date(item['start'])!)} → ${_full(_date(item['end'])!)}',
              ),
              onTap: !widget.enabled || item['event'] == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      _activate(item);
                    },
            );
          },
        ),
      ),
    );
  }

  _BoardGeometry _index(List<BoardItem> items, double cardHeight) {
    final settings = (_days, _startMinute, _endMinute, _scale, cardHeight);
    if (identical(items, _blocks) &&
        identical(items, _geometrySource) &&
        settings == _geometrySettings &&
        _geometry != null) {
      return _geometry!;
    }
    final days = _days;
    final segments = List.generate(days.length, (_) => <_BoardSegment>[]);
    final starts = [for (final day in days) _midnight(_date(day['date'])!)];
    final bounds = [
      for (final day in starts)
        (
          day.add(Duration(minutes: _startMinute)),
          day.add(Duration(minutes: _endMinute)),
        ),
    ];
    // Parse each item once per data/geometry revision, never per scroll frame.
    for (final item in items) {
      final start = _date(item['start']), end = _date(item['end']);
      if (start == null || end == null || !end.isAfter(start)) continue;
      for (var day = 0; day < days.length; day++) {
        final (from, to) = bounds[day];
        if (!start.isBefore(to) || !end.isAfter(from)) continue;
        final top = math.max(
          0.0,
          start.difference(from).inMilliseconds / 60000 * _scale,
        );
        final bottom = math.min(
          (_endMinute - _startMinute) * _scale,
          end.difference(from).inMilliseconds / 60000 * _scale,
        );
        segments[day].add(
          _BoardSegment(
            item,
            start,
            end,
            day,
            '${days[day]['date']}',
            from,
            to,
            top,
            bottom,
          ),
        );
      }
    }
    final byKey = <String, _BoardGroup>{};
    final groupsByDay = <List<_BoardGroup>>[];
    for (final day in segments) {
      day.sort((a, b) {
        final order = a.top.compareTo(b.top);
        return order != 0
            ? order
            : '${a.item['id']}'.compareTo('${b.item['id']}');
      });
      final groups = <_BoardGroup>[];
      var current = <_BoardSegment>[];
      var groupBottom = 0.0;
      void finish() {
        if (current.isEmpty) return;
        final ends = <double>[];
        for (final segment in current) {
          var lane = ends.indexWhere((end) => end <= segment.top);
          if (lane < 0) {
            lane = ends.length;
            ends.add(0);
          }
          ends[lane] = math.max(segment.bottom, segment.top + cardHeight);
          segment.lane = lane;
        }
        final group = _BoardGroup(
          current,
          current.first.top,
          groupBottom,
          ends.length,
        );
        groups.add(group);
        for (final segment in current) {
          byKey[segment.key] = group;
        }
        current = [];
      }

      for (final segment in day) {
        if (current.isNotEmpty && segment.top >= groupBottom) finish();
        current.add(segment);
        groupBottom = math.max(
          current.length == 1 ? 0 : groupBottom,
          math.max(segment.bottom, segment.top + cardHeight),
        );
      }
      finish();
      groupsByDay.add(groups);
    }
    final result = _BoardGeometry(groupsByDay, byKey, {
      for (final item in items) item['id']: item,
    });
    if (identical(items, _blocks)) {
      _geometrySource = items;
      _geometrySettings = settings;
      _geometry = result;
    }
    return result;
  }

  List<Widget> _segments(
    List<BoardItem> items,
    double cardHeight, {
    bool preview = false,
    String prefix = 'preview',
    bool outline = false,
  }) {
    final result = <Widget>[];
    var savingStatusAdded = false;
    final scheme = Theme.of(context).colorScheme;
    final index = _index(items, cardHeight);
    final window = _window.value;
    final firstDay = (window.left / _columnWidth)
        .floor()
        .clamp(0, math.max(0, index.days.length - 1))
        .toInt();
    final lastDay = (window.right / _columnWidth)
        .floor()
        .clamp(0, math.max(0, index.days.length - 1))
        .toInt();
    final groups = <_BoardGroup>{};
    for (var day = firstDay; day <= lastDay && day < index.days.length; day++) {
      final dayGroups = index.days[day];
      var low = 0, high = dayGroups.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (dayGroups[middle].bottom < window.top) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      for (
        var i = low;
        i < dayGroups.length && dayGroups[i].top <= window.bottom;
        i++
      ) {
        groups.add(dayGroups[i]);
      }
    }
    if (!preview &&
        _pinnedSegment != null &&
        index.byKey[_pinnedSegment] != null) {
      groups.add(index.byKey[_pinnedSegment]!);
    }
    for (final group in groups) {
      final laneWidth = (_columnWidth - 6) / group.lanes;
      final allShort = group.segments.every(
        (segment) => segment.bottom - segment.top < cardHeight,
      );
      // Two ordinary overlapping tasks remain separate, even on a phone.
      // Only genuinely dense or tiny bands need the grouped fallback.
      final dense = laneWidth < 72 && (group.lanes > 2 || allShort);
      final first = group.segments.first;
      final dayLeft = first.dayIndex * _columnWidth;
      if (!preview && !savingStatusAdded) {
        for (final segment in group.segments) {
          if (segment.item['_saving'] != true ||
              segment.bottom < window.top ||
              segment.top > window.bottom) {
            continue;
          }
          const statusWidth = 16.0, statusHeight = 12.0;
          final left = dayLeft + 3 + segment.lane * laneWidth;
          final badgeLeft = left + laneWidth - statusWidth - 2;
          final narrow = group.lanes == 2 && laneWidth < 72;
          final timePainter = TextPainter(
            text: TextSpan(
              text: segment.start.isBefore(segment.from)
                  ? '↳ 延续'
                  : _time(segment.start),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(fontSize: 10),
            ),
            textScaler: MediaQuery.textScalerOf(context),
            textDirection: Directionality.of(context),
          )..layout();
          final startGlyphRight =
              left + 3 + (narrow ? 2 : 7) + timePainter.width;
          timePainter.dispose();
          final compactHeight =
              MediaQuery.textScalerOf(context).scale(12) * 1.4 + 8;
          final visible =
              !dense &&
              segment.bottom - segment.top >=
                  math.max(compactHeight, statusHeight + 2) &&
              startGlyphRight + 2 <= badgeLeft;
          result.add(
            Positioned(
              key: ValueKey('saving-overlay:${segment.item['id']}'),
              left: badgeLeft,
              top: segment.top + 2,
              width: visible ? statusWidth : 0,
              height: visible ? statusHeight : 0,
              child: IgnorePointer(
                child: Semantics(
                  key: ValueKey('planner-saving:${segment.item['id']}'),
                  liveRegion: true,
                  label: '保存中',
                  child: visible
                      ? Tooltip(
                          message: '保存中',
                          child: const Icon(
                            Icons.cloud_upload_outlined,
                            size: 10,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          );
          savingStatusAdded = true;
          break;
        }
      }
      if (dense && !preview) {
        // Dense groups paint exact-duration stripes together; their widget count
        // does not grow with hundreds of coincident occupations.
        result.add(
          Positioned(
            key: ValueKey('dense-occupancy:${first.key}'),
            left: dayLeft + 3,
            top: group.top,
            width: allShort ? 24 : _columnWidth - 6,
            height: group.bottom - group.top,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DenseOccupancy(
                  group,
                  scheme.primary,
                  window.top,
                  window.bottom,
                  shortBands: allShort,
                ),
              ),
            ),
          ),
        );
        final labelTop = math.min(
          math.max(group.top, window.top + 160),
          math.max(group.top, group.bottom - cardHeight),
        );
        if (allShort) {
          final badgeWidth = math.min(88.0, _columnWidth - 36);
          final badgeHeight = math.max(
            32.0,
            MediaQuery.textScalerOf(context).scale(11) * 1.5 + 8,
          );
          final hitHeight = math.max(48.0, badgeHeight);
          final badgeLeft = dayLeft + _columnWidth - badgeWidth - 4;
          final badgeTop = labelTop.toDouble() - 8;
          final anchorY = first.top + (first.bottom - first.top) / 2;
          result.add(
            Positioned(
              key: ValueKey('short-leader:${first.key}'),
              left: dayLeft + 27,
              top: math.min(anchorY, badgeTop + hitHeight / 2),
              width: math.max(1, badgeLeft - dayLeft - 27),
              height: math.max(1, (badgeTop + hitHeight / 2 - anchorY).abs()),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ShortTaskLeader(
                    scheme.primary,
                    badgeTop + hitHeight / 2 >= anchorY,
                  ),
                ),
              ),
            ),
          );
          result.add(
            Positioned(
              key: ValueKey('dense:${first.key}'),
              left: badgeLeft,
              top: badgeTop,
              width: badgeWidth,
              height: hitHeight,
              child: Semantics(
                button: true,
                label: '${group.segments.length}项短任务，选择或放大',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: !widget.enabled
                        ? null
                        : () => _showOutside(
                            group.segments
                                .map((segment) => segment.item)
                                .toList(),
                            title:
                                '${_days[first.dayIndex]['label'] ?? first.day} · 选择安排',
                          ),
                    child: Center(
                      child: Container(
                        key: ValueKey('short-badge:${first.key}'),
                        height: badgeHeight,
                        width: badgeWidth,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: scheme.outlineVariant),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.shadow.withValues(alpha: .035),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          '${group.segments.length}项短任务',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.primary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          continue;
        }
        result.add(
          Positioned(
            key: ValueKey('dense:${first.key}'),
            left: dayLeft + 4,
            top: labelTop.toDouble(),
            width: _columnWidth - 8,
            height: cardHeight,
            child: Semantics(
              button: true,
              label: '${group.segments.length}项重叠安排，查看列表',
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: !widget.enabled
                      ? null
                      : () => _showOutside(
                          group.segments
                              .map((segment) => segment.item)
                              .toList(),
                          title:
                              '${_days[first.dayIndex]['label'] ?? first.day} · 选择安排',
                        ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 3,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final segment in group.segments.take(2))
                                Flexible(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 1,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _surface(segment.item),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '${segment.item['title'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.layers_outlined,
                              size: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                            Text(
                              '${group.segments.length}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        continue;
      }
      for (final segment in group.segments) {
        final active = _proposal.value;
        // The candidate feedback already paints this day's exact band. Keep
        // other dates (including cross-midnight continuations) in the grid.
        if (preview &&
            _dashboard &&
            active != null &&
            segment.item['id'] == active.item['id'] &&
            segment.day == _stamp(active.start).substring(0, 10) &&
            _candidateTarget(active) != null) {
          continue;
        }
        final pinned = !preview && segment.key == _pinnedSegment;
        final inWindow =
            segment.bottom >= window.top &&
            segment.top <= window.bottom &&
            dayLeft + _columnWidth >= window.left &&
            dayLeft <= window.right;
        if (!pinned && !inWindow) continue;
        final item = segment.item, start = segment.start, end = segment.end;
        final from = segment.from, to = segment.to;
        final left = dayLeft + 3 + segment.lane * laneWidth;
        if (inWindow) {
          result.add(
            Positioned(
              key: ValueKey('${preview ? prefix : 'occupancy'}:${segment.key}'),
              left: left,
              top: segment.top,
              width: math.max(.1, laneWidth - (dense ? 0 : 2)),
              height: segment.bottom - segment.top,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        !preview &&
                            segment.bottom - segment.top >=
                                MediaQuery.textScalerOf(context).scale(12) *
                                        1.4 +
                                    8
                        ? Colors.transparent
                        : outline
                        ? Colors.transparent
                        : preview
                        ? scheme.tertiary.withValues(alpha: .085)
                        : _surface(item),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        !preview &&
                            segment.bottom - segment.top >=
                                MediaQuery.textScalerOf(context).scale(12) *
                                        1.4 +
                                    8
                        ? null
                        : outline
                        ? Border.all(color: scheme.tertiary, width: 2)
                        : null,
                  ),
                  child: item['readOnly'] == true && !preview
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CustomPaint(
                            painter: _SourceHatching(_accent(item)),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          );
        }
        if (preview) continue;
        final actualHeight = segment.bottom - segment.top;
        final compactHeight =
            MediaQuery.textScalerOf(context).scale(12) * 1.4 + 8;
        final short = actualHeight < compactHeight;
        final naturalLabelTop = short
            ? math.min(
                segment.top,
                math.max(0, (_endMinute - _startMinute) * _scale - cardHeight),
              )
            : segment.top;
        // Text and hit regions may grow; the separate occupancy geometry never does.
        final labelTop = short ? naturalLabelTop : segment.top;
        final cardItem = <String, Object?>{
          ...item,
          if (group.lanes == 2 && laneWidth < 72) '_titleLines': 2,
          '_visibleStart': _stamp(start.isBefore(from) ? from : start),
          '_visibleEnd': _stamp(end.isAfter(to) ? to : end),
        };
        if (short) {
          result.add(
            Positioned(
              left: left + 5,
              top: segment.top + actualHeight / 2,
              width: 13,
              height: 1,
              child: ColoredBox(color: _accent(item)),
            ),
          );
        }
        result.add(
          Positioned(
            key: ValueKey('block:${segment.key}'),
            left: left + (short ? 17 : (cardItem['_titleLines'] == 2 ? 2 : 3)),
            top: labelTop.toDouble(),
            width: math.max(
              1,
              laneWidth - (short ? 20 : (cardItem['_titleLines'] == 2 ? 4 : 6)),
            ),
            child: _card(
              cardItem,
              short ? cardHeight : actualHeight,
              sourceSegment: segment.key,
              segmentTop: short ? null : segment.top,
              continuation:
                  '${start.isBefore(from) ? '↳ ' : ''}${_midnight(start) != _midnight(end) ? '跨天 ' : ''}${end.isAfter(to) ? '↗ ' : ''}',
            ),
          ),
        );
        if (!_dashboard && !short && actualHeight > compactHeight + 4) {
          final timePainter = TextPainter(
            text: TextSpan(
              text: '00:00',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(fontSize: 10),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final scaler = MediaQuery.textScalerOf(context);
          final hasStartLine =
              actualHeight >=
              scaler.scale(10) * 1.3 * 2 + scaler.scale(12) * 1.35 + 12;
          final titleStart =
              segment.top + 4 + (hasStartLine ? timePainter.height : 0);
          timePainter.dispose();
          result.add(
            Positioned(
              key: ValueKey('resident:${segment.key}'),
              left: left + 3,
              top: segment.top,
              width: math.max(1, laneWidth - 6),
              child: AnimatedBuilder(
                animation: _vertical,
                child: _card(
                  {...cardItem, '_resident': true},
                  MediaQuery.textScalerOf(context).scale(12) * 1.8 + 8,
                  sourceSegment: segment.key,
                  continuation: '↳ ',
                ),
                builder: (context, child) {
                  final offset = _vertical.hasClients ? _vertical.offset : 0.0;
                  final visible =
                      offset > titleStart && offset < segment.bottom;
                  final active =
                      _pinnedSegment == segment.key &&
                      _activeItem?['id'] == item['id'];
                  if (!visible && !active) return const SizedBox.shrink();
                  // Keep a live drag source hidden without forcing its title
                  // into view. Only a genuinely clipped title may be painted.
                  final delta = math.max(0.0, offset - segment.top);
                  return Transform.translate(
                    offset: Offset(0, delta),
                    child: Visibility(
                      visible: visible,
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: true,
                      child: child!,
                    ),
                  );
                },
              ),
            ),
          );
        }
        final handleTop = (segment.bottom - 12).clamp(
          0.0,
          math.max(0.0, (_endMinute - _startMinute) * _scale - 24),
        );
        if (_movable(item) &&
            (!_dashboard || _selectedItem?['id'] == item['id'] || pinned) &&
            (!short || _selectedItem?['id'] == item['id']) &&
            !end.isAfter(to) &&
            !end.isBefore(from) &&
            (pinned ||
                (handleTop + 48 >= window.top && handleTop <= window.bottom))) {
          result.add(
            Positioned(
              key: ValueKey('resize-position:${segment.key}'),
              left: left + math.max(0, laneWidth - 24),
              top: handleTop.toDouble(),
              width: math.min(24, laneWidth),
              height: 24,
              child: Tooltip(
                message: '拖动调整时长',
                child: Listener(
                  key: ValueKey('resize:${segment.key}'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (details) => _resizeDown = details.position,
                  child: Draggable<BoardItem>(
                    data: {...item, '_boardGeneration': _viewGeneration},
                    rootOverlay: true,
                    dragAnchorStrategy: (draggable, context, position) {
                      _feedbackPointer.value = position;
                      return Offset.zero;
                    },
                    onDragUpdate: (details) =>
                        _feedbackPointer.value = details.globalPosition,
                    onDragStarted: () {
                      if (_resizeDown != null) {
                        _beginResize(item, _resizeDown!);
                        _pinnedSegment = segment.key;
                      }
                    },
                    onDragEnd: (_) => _clearDrag(),
                    feedback: AnimatedBuilder(
                      animation: Listenable.merge([
                        _feedbackPointer,
                        _proposal,
                        _validation,
                      ]),
                      builder: (context, _) => _dashboard
                          ? _dragHint(context)
                          : _ScreenClampedFeedback(
                              pointer: _feedbackPointer.value,
                              safeBounds: _feedbackBounds(context),
                              child: Material(
                                elevation: 4,
                                borderRadius: BorderRadius.circular(8),
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Text('调整时长'),
                                ),
                              ),
                            ),
                    ),
                    child: Center(
                      child: Container(
                        width: 24,
                        height: 5,
                        decoration: BoxDecoration(
                          color: _selectedItem?['id'] == item['id']
                              ? scheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
    }
    if (savingStatusAdded) {
      final index = result.indexWhere(
        (child) =>
            child.key is ValueKey<String> &&
            (child.key as ValueKey<String>).value.startsWith('saving-overlay:'),
      );
      if (index >= 0) result.add(result.removeAt(index));
    }
    return result;
  }

  void _zoom(List<BoardItem> items) {
    if (items.isEmpty) return;
    final starts =
        items.map((item) => _date(item['start'])).whereType<DateTime>().toList()
          ..sort();
    final ends =
        items.map((item) => _date(item['end'])).whereType<DateTime>().toList()
          ..sort();
    if (starts.isEmpty || ends.isEmpty) return;
    if (_timeline) {
      _timelineRestoreDate = _leftDate;
      _timelineRestoreFraction = _horizontal.hasClients
          ? (_horizontal.offset / _columnWidth) % 1
          : 0;
      _timelineRestoreMinute =
          _startMinute + (_vertical.hasClients ? _vertical.offset : 0) / _scale;
    }
    _clearDrag();
    final day = _midnight(starts.first);
    final first = starts.first.difference(day).inMinutes;
    final last = ends.last.difference(day).inMinutes;
    setState(() {
      _focusItems = items;
      _focusDays = [
        {
          'date': _stamp(day).substring(0, 10),
          'label': '${day.month}月${day.day}日',
        },
      ];
      _focusStart = math.max(0, (first ~/ 5) * 5);
      _focusEnd = math.min(
        1440,
        math.max(_focusStart! + 15, ((last + 4) ~/ 5) * 5),
      );
      _focusScale = 28;
      _geometrySource = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_vertical.hasClients) _vertical.jumpTo(0);
      if (_horizontal.hasClients) _horizontal.jumpTo(0);
      _refreshWindow();
    });
  }

  void _leaveZoom() {
    _clearDrag();
    final minute = _timelineRestoreMinute;
    _timelineRestoreMinute = null;
    setState(() {
      _focusDays = null;
      _focusStart = null;
      _focusEnd = null;
      _focusScale = null;
      _geometrySource = null;
      if (widget.options['continuousDates'] == true) {
        _timelinePositioned = false;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_vertical.hasClients) {
        _vertical.jumpTo(
          (((minute ?? _number('initialMinute', 480, 0, 1440)) - _startMinute) *
                  _scale)
              .clamp(0, _vertical.position.maxScrollExtent),
        );
      }
      _refreshWindow();
    });
  }

  // Merge every actual occupation on the date before deriving neighbouring gaps.
  // Hidden candidates, courses and fixed blocks all remain part of this input.
  List<(DateTime, DateTime)> _gaps(
    BoardItem item, {
    List<BoardItem>? replacements,
  }) {
    final start = _date(item['start']), end = _date(item['end']);
    if (start == null || end == null) return [];
    final date = _midnight(start),
        next = _midnight(end).add(const Duration(days: 1));
    final changed = {
      for (final replacement in replacements ?? <BoardItem>[])
        replacement['id']: replacement,
    };
    final spans = <(DateTime, DateTime)>[];
    // Parse the full data source once for each relevant day and data revision.
    // Pointer frames only inspect that day's cached occupancy.
    final daily = _dailyOccupancy.putIfAbsent((date, next), () {
      final result = <(Object?, DateTime, DateTime)>[];
      for (final block in _blocks) {
        final a = _date(block['start']), b = _date(block['end']);
        if (a != null && b != null && a.isBefore(next) && b.isAfter(date)) {
          result.add((block['id'], a, b));
        }
      }
      return result;
    });
    for (final original in daily) {
      if (original.$1 == item['id'] || changed.containsKey(original.$1)) {
        continue;
      }
      spans.add((
        original.$2.isBefore(date) ? date : original.$2,
        original.$3.isAfter(next) ? next : original.$3,
      ));
    }
    for (final block in changed.values) {
      if (block['id'] == item['id']) continue;
      final a = _date(block['start']), b = _date(block['end']);
      if (a == null || b == null || !a.isBefore(next) || !b.isAfter(date)) {
        continue;
      }
      spans.add((a.isBefore(date) ? date : a, b.isAfter(next) ? next : b));
    }
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(DateTime, DateTime)>[];
    for (final span in spans) {
      if (merged.isEmpty || span.$1.isAfter(merged.last.$2)) {
        merged.add(span);
      } else if (span.$2.isAfter(merged.last.$2)) {
        merged[merged.length - 1] = (merged.last.$1, span.$2);
      }
    }
    if (merged.any((span) => span.$1.isBefore(end) && span.$2.isAfter(start))) {
      return [];
    }
    DateTime? previous, following;
    for (final span in merged) {
      if (!span.$2.isAfter(start)) previous = span.$2;
      if (!span.$1.isBefore(end)) {
        following = span.$1;
        break;
      }
    }
    return [
      if (previous != null && start.isAfter(previous)) (previous, start),
      if (following != null && following.isAfter(end)) (end, following),
    ];
  }

  bool _gapHasGridRoom((DateTime, DateTime) gap) {
    final day = _midnight(gap.$1);
    final endMinute =
        gap.$2.difference(day).inMicroseconds / Duration.microsecondsPerMinute;
    final minimum = MediaQuery.textScalerOf(context).scale(11) * 1.5 + 4;
    return _days.any((item) => _date(item['date']) == day) &&
        gap.$1.difference(day).inMicroseconds /
                Duration.microsecondsPerMinute >=
            _startMinute &&
        endMinute <= _endMinute &&
        gap.$2.difference(gap.$1).inMicroseconds /
                Duration.microsecondsPerMinute *
                _scale >=
            minimum;
  }

  bool _gapVisibleInGrid((DateTime, DateTime) gap) {
    if (!_gapHasGridRoom(gap)) return false;
    final viewport = _viewport;
    if (viewport == null) return false;
    final day = _midnight(gap.$1);
    final index = _days.indexWhere((item) => _date(item['date']) == day);
    final x =
        (index + .5) * _columnWidth -
        (_horizontal.hasClients ? _horizontal.offset : 0);
    final y =
        ((gap.$1.difference(day).inMicroseconds +
                        gap.$2.difference(day).inMicroseconds) /
                    2 /
                    Duration.microsecondsPerMinute -
                _startMinute) *
            _scale -
        (_vertical.hasClients ? _vertical.offset : 0);
    return x >= 0 && x <= viewport.width && y >= 0 && y <= viewport.height;
  }

  List<Widget> _gapLabels(BoardItem item, {List<BoardItem>? replacements}) {
    final start = _date(item['start']);
    if (start == null) return [];
    return [
      for (final gap in _gaps(item, replacements: replacements))
        for (final dayIndex in [
          _days.indexWhere((day) => _date(day['date']) == _midnight(gap.$1)),
        ])
          if (dayIndex >= 0 && _gapHasGridRoom(gap))
            Positioned(
              left: dayIndex * _columnWidth + 6,
              top:
                  (gap.$1
                          .difference(_date(_days[dayIndex]['date'])!)
                          .inMinutes -
                      _startMinute) *
                  _scale,
              width: _columnWidth - 12,
              height: gap.$2.difference(gap.$1).inMinutes * _scale,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    '空闲${_elapsed(gap.$2.difference(gap.$1))}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
    ];
  }

  Widget _selectionPanel() {
    final item = _selectedItem!;
    final start = _date(item['start'])!, end = _date(item['end'])!;
    final edit = item['editTimeEvent'] ?? widget.options['editTimeEvent'];
    final scheme = Theme.of(context).colorScheme;
    final fallbackGaps = _gaps(item)
        .where((gap) => !_gapVisibleInGrid(gap))
        .toList();
    final sourceLabel = item['sourceLabel']?.toString();
    final showSource =
        sourceLabel != null &&
        sourceLabel.isNotEmpty &&
        (item['readOnly'] == true || sourceLabel != '任务');
    return Material(
      key: const ValueKey('planner-selection-panel'),
      elevation: 2,
      shadowColor: scheme.shadow.withValues(alpha: .15),
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item['title'] ?? ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _selectedItem = null),
                  icon: const Icon(Icons.close),
                  tooltip: '关闭选中任务',
                ),
              ],
            ),
            Text(
              '${_full(start)} — ${_midnight(start) == _midnight(end) ? _time(end) : _full(end)} · ${_elapsed(_duration(item) ?? end.difference(start))}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            if ((item['deadlineText'] ?? item['deadlineSummary'])
                    ?.toString()
                    .isNotEmpty ==
                true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${item['deadlineText'] ?? _summary(item)}',
                  style: TextStyle(
                    color: item['overdue'] == true
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (showSource) Text(sourceLabel),
            if (fallbackGaps.isNotEmpty)
              Wrap(
                spacing: 12,
                children: [
                  for (final gap in fallbackGaps)
                    Text(
                      '空闲${_elapsed(gap.$2.difference(gap.$1))}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (edit is Map && _movable(item)) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => widget.onEvent({
                        ...Map<String, Object?>.from(edit),
                        'id': item['id'],
                      }),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('编辑时间'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: item['event'] == null
                        ? null
                        : () => widget.onEvent(item['event']),
                    child: const Text('查看详情'),
                  ),
                ),
                IconButton(
                  onPressed: () => _zoom([item]),
                  icon: const Icon(Icons.zoom_in),
                  tooltip: '放大该时段',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateToolbar(double viewportWidth) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('planner-date-toolbar'),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .35)),
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .35),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: widget.enabled ? () => _optionEvent('rangeEvent') : null,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '${widget.options['rangeLabel'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Text(
                          '${widget.options['periodLabel'] ?? '${_days.length}天'}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: AnimatedBuilder(
                              animation: _horizontal,
                              builder: (context, _) {
                                if (_days.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final left =
                                    (_horizontal.hasClients
                                        ? _horizontal.offset
                                        : 0) /
                                    _columnWidth;
                                final right =
                                    left + viewportWidth / _columnWidth;
                                final first = left.floor().clamp(
                                  0,
                                  _days.length - 1,
                                );
                                final last = (right.ceil() - 1).clamp(
                                  0,
                                  _days.length - 1,
                                );
                                return Semantics(
                                  key: const ValueKey('planner-range-rail'),
                                  label:
                                      '当前可见第${first + 1}至${last + 1}天，共${_days.length}天',
                                  child: ExcludeSemantics(
                                    child: Row(
                                      children: [
                                        for (
                                          var index = 0;
                                          index < _days.length;
                                          index++
                                        )
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                right: 3,
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                                child: SizedBox(
                                                  height: 5,
                                                  child: LayoutBuilder(
                                                    builder: (context, constraints) {
                                                      final start =
                                                          (left - index).clamp(
                                                            0.0,
                                                            1.0,
                                                          );
                                                      final end =
                                                          (right - index).clamp(
                                                            0.0,
                                                            1.0,
                                                          );
                                                      return Stack(
                                                        children: [
                                                          Positioned.fill(
                                                            child: ColoredBox(
                                                              color: scheme
                                                                  .outlineVariant
                                                                  .withValues(
                                                                    alpha: .45,
                                                                  ),
                                                            ),
                                                          ),
                                                          if (end > start)
                                                            Positioned(
                                                              key: ValueKey(
                                                                'planner-range-visible:$index',
                                                              ),
                                                              left:
                                                                  start *
                                                                  constraints
                                                                      .maxWidth,
                                                              width:
                                                                  (end -
                                                                      start) *
                                                                  constraints
                                                                      .maxWidth,
                                                              top: 0,
                                                              bottom: 0,
                                                              child: ColoredBox(
                                                                color: scheme
                                                                    .primary
                                                                    .withValues(
                                                                      alpha: .5,
                                                                    ),
                                                              ),
                                                            ),
                                                        ],
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: scheme.primary.withValues(alpha: .075),
              shape: const StadiumBorder(),
              minimumSize: const Size(44, 32),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => _optionEvent('todayEvent'),
            child: const Text('今天'),
          ),
          IconButton(
            onPressed: () => _optionEvent('previousEvent'),
            icon: const Icon(Icons.chevron_left),
            visualDensity: VisualDensity.compact,
            tooltip: '上一时段',
          ),
          IconButton(
            onPressed: () => _optionEvent('nextEvent'),
            icon: const Icon(Icons.chevron_right),
            visualDensity: VisualDensity.compact,
            tooltip: '下一时段',
          ),
        ],
      ),
    );
  }

  String _visibleRangeLabel(DateTime start, DateTime end) {
    if (start.year != end.year) {
      return '${start.year}/${start.month}/${start.day}–${end.year}/${end.month}/${end.day}';
    }
    if (start.month != end.month) {
      return '${start.month}月${start.day}日–${end.month}月${end.day}日';
    }
    return '${start.month}月${start.day}${start == end ? '' : '–${end.day}'}日';
  }

  Widget _timelineDateToolbar() {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _horizontal,
      builder: (context, _) {
        final start = _leftDate ?? _date(widget.options['initialDate']);
        final end = start?.add(Duration(days: _visibleDayCount - 1));
        final today = _date(widget.options['today']);
        final outside = start == null || end == null
            ? <BoardItem>[]
            : _outsideItems.where((item) {
                final from = _date(item['start']);
                final to = _date(item['end']);
                return from != null &&
                    to != null &&
                    from.isBefore(end.add(const Duration(days: 1))) &&
                    to.isAfter(start);
              }).toList();
        final showToday =
            start != null &&
            end != null &&
            today != null &&
            (today.isBefore(start) || today.isAfter(end));
        return Container(
          key: const ValueKey('planner-date-toolbar'),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .4),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const ValueKey('planner-date-picker'),
                    onPressed: widget.enabled
                        ? () => _optionEvent('rangeEvent')
                        : null,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      foregroundColor: scheme.onSurface,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            start != null && end != null
                                ? _visibleRangeLabel(start, end)
                                : '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              if (outside.isNotEmpty)
                IconButton(
                  key: const ValueKey('planner-outside-indicator'),
                  onPressed: () => _showOutside(outside),
                  tooltip: '显示时段外的安排（${outside.length}）',
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(44),
                    fixedSize: const Size.square(44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Badge(
                    label: Text('${outside.length}'),
                    child: const Icon(Icons.info_outline, size: 19),
                  ),
                ),
              if (showToday)
                TextButton(
                  key: const ValueKey('planner-return-today'),
                  onPressed: widget.enabled
                      ? () => _optionEvent('todayEvent')
                      : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('回到今天', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }

  double _candidateWidth(BoardItem item) {
    final subtitle = item['overdue'] == true
        ? ''
        : _summary(item).replaceFirst('耗时', '');
    final painter = TextPainter(
      text: TextSpan(
        text: '${item['title'] ?? ''}${subtitle.isEmpty ? '' : ' · $subtitle'}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = (painter.width + (item['overdue'] == true ? 38 : 24)).clamp(
      88.0,
      300.0,
    );
    painter.dispose();
    return width;
  }

  Widget _timelineCandidateRail(double height) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const ValueKey('planner-candidate-region'),
      height: height,
      child: TapRegion(
        groupId: _candidateTapGroup,
        child: Row(
          children: [
            CompositedTransformTarget(
              link: _candidateLink,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 8, end: 6),
                child: Semantics(
                  expanded: _candidatesExpanded,
                  child: TextButton(
                    key: const ValueKey('planner-toggle-candidates'),
                    onPressed: widget.enabled ? _toggleCandidates : null,
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      minimumSize: const Size(44, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      backgroundColor: scheme.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '待安排 ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          key: const ValueKey('planner-candidate-count'),
                          child: Text(
                            '$_candidateCount',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          _candidatesExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _candidates.isEmpty
                  ? Text(
                      '暂无待安排任务',
                      style: Theme.of(context).textTheme.labelSmall,
                    )
                  : ListView.separated(
                      key: const ValueKey('planner-candidates'),
                      controller: _candidatesScroll,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      itemCount: _candidates.length,
                      separatorBuilder: (_, index) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final item = _candidates[index];
                        return SizedBox(
                          width: _candidateWidth(item),
                          child: Center(child: _card(item, height)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timelineCandidatePopup(double width, double height) {
    final scheme = Theme.of(context).colorScheme;
    return CompositedTransformFollower(
      link: _candidateLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      child: TapRegion(
        groupId: _candidateTapGroup,
        onTapOutside: (_) {
          if (_candidatesExpanded && !_dragActive.value) {
            setState(() => _candidatesExpanded = false);
          }
        },
        child: Material(
          key: const ValueKey('planner-candidates-popup'),
          elevation: 5,
          shadowColor: scheme.shadow.withValues(alpha: .16),
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          '待安排 $_candidateCount',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleCandidates,
                        icon: const Icon(Icons.expand_less, size: 20),
                        tooltip: '收起待安排',
                      ),
                    ],
                  ),
                  Flexible(
                    child: _candidates.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('暂无待安排任务'),
                          )
                        : ListView.separated(
                            key: const ValueKey('planner-candidates-expanded'),
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            itemCount: _candidates.length,
                            separatorBuilder: (_, index) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final item = _candidates[index];
                              return SizedBox(
                                height: math.max(
                                  44,
                                  MediaQuery.textScalerOf(context).scale(14) *
                                          1.4 +
                                      12,
                                ),
                                child: _card(
                                  {...item, '_candidateList': true},
                                  math.max(
                                    44,
                                    MediaQuery.textScalerOf(context).scale(14) *
                                            1.4 +
                                        12,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('长按拖入时间表', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _timelineDayHeader(BoardItem day, double height) {
    final date = _date(day['date'])!;
    final today = _today(day);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label:
          '${date.year}年${date.month}月${date.day}日 ${today ? '今天' : _weekday(date)}',
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('planner-day:${day['date']}'),
          width: _columnWidth,
          height: height,
          decoration: BoxDecoration(
            color: today ? scheme.primary.withValues(alpha: .04) : null,
            border: Border(
              left: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .4),
              ),
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .4),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  today ? '今天' : _weekday(date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: today ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: today
                    ? BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: today ? FontWeight.w600 : FontWeight.w500,
                    color: today ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _currentTimeLine() {
    final now = _timelineNow;
    if (!_timeline || now == null) return const [];
    final index = _days.indexWhere(
      (day) => _date(day['date']) == _midnight(now),
    );
    final minute = now.hour * 60 + now.minute;
    if (index < 0 || minute < _startMinute || minute >= _endMinute) {
      return const [];
    }
    final scheme = Theme.of(context).colorScheme;
    return [
      Positioned(
        key: const ValueKey('planner-now-line'),
        left: index * _columnWidth,
        top: (minute - _startMinute) * _scale,
        width: _columnWidth,
        height: 1,
        child: IgnorePointer(child: ColoredBox(color: scheme.primary)),
      ),
      Positioned(
        left: index * _columnWidth,
        top: (minute - _startMinute) * _scale - 2,
        width: 5,
        height: 5,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _currentTimeLabel() {
    return AnimatedBuilder(
      animation: _horizontal,
      builder: (context, _) {
        final now = _timelineNow;
        final left = _leftDate;
        if (!_timeline ||
            now == null ||
            left == null ||
            _midnight(now).isBefore(left) ||
            !_midnight(now)
                .isBefore(left.add(Duration(days: _visibleDayCount)))) {
          return const SizedBox.shrink();
        }
        final minute = now.hour * 60 + now.minute;
        if (minute < _startMinute || minute >= _endMinute) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              key: const ValueKey('planner-now-label'),
              top: (minute - _startMinute) * _scale - 9,
              left: 2,
              right: 2,
              child: IgnorePointer(
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _time(now),
                    style: TextStyle(fontSize: 10, color: scheme.onPrimary),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final cardHeight = math.max(
      48.0,
      scaler.scale(12) * 1.5 + scaler.scale(11) * 1.5 + 8,
    );
    _cardHeight = cardHeight;
    final days = _days;
    final focusIds = _focusItems.map((item) => item['id']).toSet();
    final currentFocusItems = _blocks
        .where((item) => focusIds.contains(item['id']))
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _refreshWindow());
        final retainedDate = _leftDate;
        final retainedFraction = _horizontal.hasClients
            ? (_horizontal.offset / _columnWidth) % 1
            : 0.0;
        _columnWidth = _timeline
            ? math.max(1, (constraints.maxWidth - 48) / _visibleDayCount)
            : math.max(
                _number('minColumnWidth', 112, 96, 320),
                (constraints.maxWidth - 48) / math.max(1, days.length),
              );
        if (_timeline &&
            (!_timelinePositioned || _timelineColumnWidth != _columnWidth)) {
          final target = !_timelinePositioned
              ? _timelineRestoreDate ?? _date(widget.options['initialDate'])
              : retainedDate;
          if (target != null) {
            _positionTimeline(
              target,
              fraction: !_timelinePositioned
                  ? _timelineRestoreFraction
                  : retainedFraction,
            );
          }
          _timelinePositioned = true;
          _timelineColumnWidth = _columnWidth;
          _timelineRestoreDate = null;
          _timelineRestoreFraction = 0;
        }
        final railHeight = math.max(44.0, scaler.scale(13) * 1.5 + 20);
        final dayHeaderHeight = math.max(32.0, scaler.scale(13) * 1.4 + 8);
        final gridWidth = _columnWidth * days.length;
        final gridHeight = (_endMinute - _startMinute) * _scale;
        final outsideSettings = (days, _startMinute, _endMinute);
        if (!identical(_outsideSource, _blocks) ||
            _outsideSettings != outsideSettings) {
          _outsideSource = _blocks;
          _outsideSettings = outsideSettings;
          final visibleWindows = [
            for (final day in days)
              (
                _date(day['date'])!.add(Duration(minutes: _startMinute)),
                _date(day['date'])!.add(Duration(minutes: _endMinute)),
              ),
          ]..sort((a, b) => a.$1.compareTo(b.$1));
          _outsideItems = _blocks.where((item) {
            final start = _date(item['start']), end = _date(item['end']);
            if (start == null || end == null || !end.isAfter(start)) {
              return false;
            }
            // Report occupations belonging to the displayed dates, including a
            // fully hidden morning/evening. Adjacent visible day windows form one
            // continuous interval, so midnight itself never creates a warning.
            final belongs = days.any((day) {
              final date = _date(day['date'])!;
              return start.isBefore(date.add(const Duration(days: 1))) &&
                  end.isAfter(date);
            });
            if (!belongs) return false;
            var cursor = start;
            for (final window in visibleWindows) {
              if (!window.$2.isAfter(cursor)) continue;
              if (window.$1.isAfter(cursor)) return true;
              if (!window.$2.isBefore(end)) return false;
              cursor = window.$2;
            }
            return cursor.isBefore(end);
          }).toList();
        }
        final outside = _outsideItems;
        final board = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_timeline) ...[
              _timelineDateToolbar(),
              _timelineCandidateRail(railHeight),
            ],
            if (_focusDays == null && !_timeline)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                child: LayoutBuilder(
                  builder: (context, headerConstraints) {
                    final candidateLabel =
                        '${widget.options['candidateLabel'] ?? '待安排'}';
                    final candidateToggle = _dashboard
                        ? Semantics(
                            expanded: _candidatesExpanded,
                            child: TextButton.icon(
                              key: const ValueKey('planner-toggle-candidates'),
                              onPressed: _toggleCandidates,
                              icon: AnimatedRotation(
                                turns: _candidatesExpanded ? 0 : -.25,
                                duration: const Duration(milliseconds: 200),
                                child: const Icon(Icons.expand_more, size: 18),
                              ),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      candidateLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    key: const ValueKey(
                                      'planner-candidate-count',
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      '$_candidateCount',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    ),
                                  ),
                                ],
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.onSurface,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                              ),
                            ),
                          )
                        : Text(
                            '$candidateLabel  $_candidateCount',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          );
                    final quickToggle =
                        _dashboard && widget.onQuickAdjustChanged != null
                        ? Semantics(
                            key: const ValueKey(
                              'planner-quick-adjust-semantics',
                            ),
                            toggled: widget.quickAdjust,
                            enabled: widget.enabled,
                            child: Tooltip(
                              message: '拖动后自动保存，可撤销',
                              child: TextButton(
                                key: const ValueKey('planner-quick-adjust'),
                                onPressed: widget.enabled
                                    ? () => widget.onQuickAdjustChanged!(
                                        !widget.quickAdjust,
                                      )
                                    : null,
                                style: TextButton.styleFrom(
                                  backgroundColor: widget.quickAdjust
                                      ? scheme.primaryContainer
                                      : null,
                                  foregroundColor: widget.quickAdjust
                                      ? scheme.onPrimaryContainer
                                      : scheme.onSurfaceVariant,
                                  side: widget.quickAdjust
                                      ? BorderSide.none
                                      : BorderSide(
                                          color: scheme.outlineVariant,
                                        ),
                                  shape: const StadiumBorder(),
                                  minimumSize: const Size(0, 32),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                child: const Text('快速调整'),
                              ),
                            ),
                          )
                        : null;
                    final stacked =
                        quickToggle != null &&
                        headerConstraints.maxWidth < scaler.scale(260);
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: candidateToggle,
                          ),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 4,
                            children: [quickToggle],
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: candidateToggle,
                          ),
                        ),
                        if (quickToggle != null) ...[
                          quickToggle,
                          const SizedBox(width: 4),
                        ],
                      ],
                    );
                  },
                ),
              ),
            if (_dashboard &&
                _focusDays == null &&
                widget.options['onlyDeadline'] == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  '筛选：仅有截止',
                  key: const ValueKey('planner-active-filter'),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            if (_focusDays == null && !_timeline)
              AnimatedSize(
                key: const ValueKey('planner-candidate-region'),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                child: _dashboard && !_candidatesExpanded
                    ? const SizedBox(width: double.infinity)
                    : SizedBox(
                        height: cardHeight * 2 + 12,
                        child: _candidates.isEmpty
                            ? const Center(child: Text('暂无待安排任务'))
                            : GridView.builder(
                                key: const ValueKey('planner-candidates'),
                                controller: _candidatesScroll,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 3,
                                ),
                                scrollDirection: Axis.horizontal,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisExtent: _dashboard
                                          ? math.max(
                                              math.max(136, scaler.scale(90)),
                                              (constraints.maxWidth - 32) / 2,
                                            )
                                          : math.max(112, scaler.scale(112)) +
                                                (widget.selectEvent != null ||
                                                        _candidates.any(
                                                          (item) =>
                                                              item['selectEvent']
                                                                  is Map,
                                                        )
                                                    ? 48
                                                    : 0),
                                      crossAxisSpacing: 6,
                                      mainAxisSpacing: 8,
                                    ),
                                itemCount: _dashboard
                                    ? ((_candidates.length + 3) ~/ 4) * 4
                                    : _candidates.length,
                                itemBuilder: (context, index) {
                                  // The horizontal grid fills columns first;
                                  // present each two-column page in reading order.
                                  final displayIndex = _dashboard
                                      ? (index ~/ 4) * 4 +
                                            ((index % 4).isEven
                                                ? index % 4 ~/ 2
                                                : 2 + index % 4 ~/ 2)
                                      : index;
                                  if (displayIndex >= _candidates.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final item = _candidates[displayIndex];
                                  return Row(
                                    children: [
                                      if (!_dashboard &&
                                          (widget.selectEvent != null ||
                                              item['selectEvent'] is Map))
                                        SizedBox(
                                          width: 48,
                                          child: Checkbox(
                                            value:
                                                item['selected'] == true ||
                                                widget.selectedIds.contains(
                                                  item['id'],
                                                ),
                                            onChanged: !widget.enabled
                                                ? null
                                                : (selected) => widget.onEvent({
                                                    ...?widget.selectEvent,
                                                    if (item['selectEvent']
                                                        is Map)
                                                      ...Map<
                                                        String,
                                                        Object?
                                                      >.from(
                                                        item['selectEvent']
                                                            as Map,
                                                      ),
                                                    'id':
                                                        (item['selectEvent']
                                                                is Map
                                                            ? (item['selectEvent']
                                                                  as Map)['id']
                                                            : null) ??
                                                        widget
                                                            .selectEvent?['id'] ??
                                                        item['id'],
                                                    'selected': selected,
                                                    'value': selected,
                                                  }),
                                          ),
                                        ),
                                      Expanded(child: _card(item, cardHeight)),
                                    ],
                                  );
                                },
                              ),
                      ),
              ),
            if (_dashboard && _focusDays == null && !_timeline)
              _dateToolbar(math.max(0, constraints.maxWidth - 48)),
            if (_focusDays != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _leaveZoom,
                      icon: const Icon(Icons.chevron_left),
                      label: Text(
                        widget.options['continuousDates'] == true
                            ? '返回时间表'
                            : '返回${widget.options['periodLabel'] ?? '5天'}视图',
                      ),
                    ),
                    const Spacer(),
                    const Chip(label: Text('已放大')),
                  ],
                ),
              ),
            if (widget.options['errorText'] != null ||
                widget.options['noticeText'] != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.options['errorText'] ?? widget.options['noticeText']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.options['errorText'] == null
                              ? scheme.onSurfaceVariant
                              : scheme.error,
                        ),
                      ),
                    ),
                    if (widget.options['retryEvent'] is Map)
                      TextButton(
                        onPressed: () => _optionEvent('retryEvent'),
                        child: const Text('重试'),
                      ),
                    if (widget.options['dismissErrorEvent'] is Map)
                      IconButton(
                        onPressed: () => _optionEvent('dismissErrorEvent'),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                  ],
                ),
              ),
            if (widget.options['candidatePageLabel'] != null &&
                _focusDays == null)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () => _optionEvent('candidatePreviousEvent'),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${widget.options['candidatePageLabel']}'),
                  IconButton(
                    onPressed: () => _optionEvent('candidateNextEvent'),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            if (widget.previewLabel != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  widget.previewLabel!,
                  style: TextStyle(color: scheme.tertiary),
                ),
              ),
            if (outside.isNotEmpty && !_timeline)
              if (_focusDays != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _showOutside(outside),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 26),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 13),
                    label: Text(
                      '范围外 ${outside.length} 项 · 查看',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: () => _showOutside(outside),
                  child: Text('显示范围外有 ${outside.length} 项安排 · 查看'),
                ),
            Row(
              children: [
                SizedBox(
                  width: 48,
                  height: _timeline ? dayHeaderHeight : 38,
                  child: _timeline
                      ? Center(
                          child: Text(
                            '时间',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : null,
                ),
                Expanded(
                  child: NotificationListener<ScrollEndNotification>(
                    onNotification: (notification) {
                      if (notification.depth == 0 &&
                          notification.metrics.axis == Axis.horizontal) {
                        _reportTimelineViewport();
                      }
                      return false;
                    },
                    child: SingleChildScrollView(
                      key: const ValueKey('planner-date-header'),
                      controller: _header,
                      scrollDirection: Axis.horizontal,
                      physics: _timeline
                          ? _PlannerDayScrollPhysics(_columnWidth)
                          : const NeverScrollableScrollPhysics(),
                      child: Row(
                        children: [
                          for (final day in days)
                            if (_timeline)
                              _timelineDayHeader(day, dayHeaderHeight)
                            else
                              SizedBox(
                                width: _columnWidth,
                                height: _dashboard
                                    ? math.max(
                                        54,
                                        scaler.scale(11) * 1.5 +
                                            scaler.scale(14) * 1.5 +
                                            8,
                                      )
                                    : 38,
                                child: _dashboard && _focusDays != null
                                    ? Center(
                                        child: Text(
                                          '${_date(day['date'])!.month}月${_date(day['date'])!.day}日 ${_weekday(_date(day['date'])!)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      )
                                    : _dashboard
                                    ? Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            [
                                              '周一',
                                              '周二',
                                              '周三',
                                              '周四',
                                              '周五',
                                              '周六',
                                              '周日',
                                            ][_date(day['date'])!.weekday - 1],
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 2,
                                            ),
                                            decoration: _today(day)
                                                ? BoxDecoration(
                                                    color: scheme.primary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                  )
                                                : null,
                                            child: Text(
                                              '${_date(day['date'])!.day}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    color: _today(day)
                                                        ? scheme.onPrimary
                                                        : scheme
                                                              .onSurfaceVariant,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Center(
                                        child: Text(
                                          '${day['label'] ?? day['date']}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: SizedBox(
                key: _viewportKey,
                child: SingleChildScrollView(
                  key: const ValueKey('planner-vertical'),
                  controller: _vertical,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: widget.bottomInset),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 48,
                          height: gridHeight,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: _PlannerRulerOpacity(
                                  proposal: _proposal,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      for (
                                        var minute = _focusDays == null
                                            ? ((_startMinute + 59) ~/ 60) * 60
                                            : ((_startMinute + 4) ~/ 5) * 5;
                                        minute < _endMinute ||
                                            (_focusDays != null &&
                                                minute == _endMinute);
                                        minute += _focusDays == null ? 60 : 5
                                      )
                                        Positioned(
                                          key: ValueKey(
                                            'planner-ruler:$minute',
                                          ),
                                          top: minute == _endMinute
                                              ? math.max(
                                                  0,
                                                  gridHeight -
                                                      scaler.scale(11) * 1.5,
                                                )
                                              : (minute - _startMinute) *
                                                    _scale,
                                          left: 2,
                                          child: Text(
                                            '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: AnimatedBuilder(
                                  animation: Listenable.merge([
                                    _proposal,
                                    _vertical,
                                  ]),
                                  builder: (context, _) => Stack(
                                    clipBehavior: Clip.none,
                                    children: _dragRuler(gridHeight),
                                  ),
                                ),
                              ),
                              if (_timeline)
                                Positioned.fill(child: _currentTimeLabel()),
                            ],
                          ),
                        ),
                        Expanded(
                          child: NotificationListener<ScrollEndNotification>(
                            onNotification: (notification) {
                              if (notification.depth == 0 &&
                                  notification.metrics.axis ==
                                      Axis.horizontal) {
                                _reportTimelineViewport();
                              }
                              return false;
                            },
                            child: SingleChildScrollView(
                              key: const ValueKey('planner-horizontal'),
                              controller: _horizontal,
                              physics: _timeline
                                  ? _PlannerDayScrollPhysics(_columnWidth)
                                  : null,
                              scrollDirection: Axis.horizontal,
                              child: DragTarget<BoardItem>(
                                onWillAcceptWithDetails: (details) =>
                                    _movable(details.data),
                                onMove: (details) =>
                                    _hover(details.data, details.offset),
                                onLeave: (_) => _clearDrag(endGesture: false),
                                onAcceptWithDetails: (details) =>
                                    _drop(details.data, details.offset),
                                builder: (context, _, _) => SizedBox(
                                  key: _gridKey,
                                  width: gridWidth,
                                  height: gridHeight,
                                  child: AnimatedBuilder(
                                    animation: Listenable.merge([
                                      _proposal,
                                      _validation,
                                      _window,
                                    ]),
                                    child: AnimatedBuilder(
                                      animation: _window,
                                      child: RepaintBoundary(
                                        child: CustomPaint(
                                          painter: _BoardLines(
                                            _columnWidth,
                                            _scale,
                                            _startMinute,
                                            scheme.outlineVariant,
                                            interval: _focusDays == null
                                                ? 30
                                                : 5,
                                          ),
                                        ),
                                      ),
                                      builder: (context, lines) => Stack(
                                        children: [
                                          for (
                                            var dayIndex = 0;
                                            dayIndex < days.length;
                                            dayIndex++
                                          )
                                            if (_dashboard &&
                                                _today(days[dayIndex]))
                                              Positioned(
                                                left: dayIndex * _columnWidth,
                                                top: 0,
                                                bottom: 0,
                                                width: _columnWidth,
                                                child: ColoredBox(
                                                  color: scheme.primary
                                                      .withValues(alpha: .025),
                                                ),
                                              ),
                                          Positioned.fill(child: lines!),
                                          ..._segments(_blocks, cardHeight),
                                          if (_selectedItem != null)
                                            ..._gapLabels(_selectedItem!),
                                          ..._segments(
                                            widget.previewBlocks,
                                            cardHeight,
                                            preview: true,
                                          ),
                                          ..._currentTimeLine(),
                                        ],
                                      ),
                                    ),
                                    builder: (context, base) => Stack(
                                      clipBehavior: Clip.hardEdge,
                                      children: [
                                        Positioned.fill(child: base!),
                                        if (_proposal.value != null)
                                          ..._segments(
                                            _localPreview(_proposal.value!),
                                            cardHeight,
                                            preview: true,
                                            prefix: 'local',
                                          ),
                                        if (_proposal.value?.targetId != null)
                                          ..._segments(
                                            [
                                              ?_index(
                                                _blocks,
                                                cardHeight,
                                              ).byId[_proposal.value!.targetId],
                                            ],
                                            cardHeight,
                                            preview: true,
                                            prefix: 'target',
                                            outline: true,
                                          ),
                                        if (_proposal.value != null)
                                          ..._gapLabels({
                                            ..._proposal.value!.item,
                                            'start': _stamp(
                                              _proposal.value!.start,
                                            ),
                                            'end': _stamp(_proposal.value!.end),
                                          }, replacements: _servicePreview()),
                                        ..._segments(
                                          _servicePreview(),
                                          cardHeight,
                                          preview: true,
                                          prefix: 'service',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_focusDays != null)
              Container(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + widget.bottomInset),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: .4),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '${currentFocusItems.length}项任务 · 总耗时${_elapsed(currentFocusItems.fold(Duration.zero, (sum, item) => sum + (_duration(item) ?? Duration.zero)))}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '仅放大显示，任务时间不变',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () => setState(() {
                            _focusScale = (_scale / 1.4).clamp(8, 64);
                            _geometrySource = null;
                          }),
                          icon: const Icon(Icons.remove),
                          tooltip: '缩小时间轴',
                        ),
                        const Text('时间缩放'),
                        IconButton(
                          onPressed: () => setState(() {
                            _focusScale = (_scale * 1.4).clamp(8, 64);
                            _geometrySource = null;
                          }),
                          icon: const Icon(Icons.add),
                          tooltip: '放大时间轴',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
        final content = Stack(
          children: [
            Positioned.fill(child: board),
            if (_timeline && _candidatesExpanded)
              Positioned(
                top: 0,
                left: 0,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _dragActive,
                  builder: (context, dragging, child) =>
                      Offstage(offstage: dragging, child: child),
                  child: _timelineCandidatePopup(
                    math.min(340, constraints.maxWidth - 16),
                    math.min(
                      320,
                      math.max(
                        100,
                        constraints.maxHeight - widget.bottomInset - 105,
                      ),
                    ),
                  ),
                ),
              ),
            if (_selectedItem != null && _dashboard)
              Positioned(
                left: 0,
                right: 0,
                bottom: widget.bottomInset,
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _vertical,
                    _horizontal,
                    _dragActive,
                  ]),
                  builder: (context, _) => _dragActive.value
                      ? const SizedBox.shrink()
                      : _selectionPanel(),
                ),
              ),
            if (!_dashboard)
              Positioned(
                top: 4,
                right: 8,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_proposal, _validation]),
                    builder: (context, _) {
                      final value = _proposal.value;
                      if (value == null ||
                          _activeItem == null ||
                          (!_dashboard &&
                              value.intent != 'resize' &&
                              value.intent != 'swap' &&
                              _validation.value == null)) {
                        return const SizedBox.shrink();
                      }
                      return Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: math.min(300, constraints.maxWidth * .8),
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${value.intent == 'resize'
                                    ? '调整时长'
                                    : value.intent == 'swap'
                                    ? '交换几何预览'
                                    : value.intent == 'insert'
                                    ? '插入意图'
                                    : '移动预览'} · ${_snapLabel(value.snap)}',
                              ),
                              if (value.intent == 'resize')
                                Text(
                                  '${_full(value.start)} → ${_full(value.end)}',
                                ),
                              ..._status(),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
        return constraints.hasBoundedHeight
            ? content
            : SizedBox(height: 640, child: content);
      },
    );
  }
}

class _PlannerDayScrollPhysics extends ScrollPhysics {
  const _PlannerDayScrollPhysics(this.columnWidth, {super.parent});
  final double columnWidth;

  @override
  _PlannerDayScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _PlannerDayScrollPhysics(columnWidth, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final projected = position.pixels + velocity * .12;
    final target = ((projected / columnWidth).round() * columnWidth).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

/// Proposal moves preserve the same tick subtree; fading changes only when a
/// drag preview starts or ends, independently of normal scrolling.
class _PlannerRulerOpacity extends StatefulWidget {
  const _PlannerRulerOpacity({required this.proposal, required this.child});
  final ValueListenable<_Proposal?> proposal;
  final Widget child;
  @override
  State<_PlannerRulerOpacity> createState() => _PlannerRulerOpacityState();
}

class _PlannerRulerOpacityState extends State<_PlannerRulerOpacity> {
  late bool _dimmed;
  @override
  void initState() {
    super.initState();
    _dimmed = widget.proposal.value != null;
    widget.proposal.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant _PlannerRulerOpacity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.proposal, oldWidget.proposal)) {
      oldWidget.proposal.removeListener(_changed);
      widget.proposal.addListener(_changed);
    }
    _dimmed = widget.proposal.value != null;
  }

  void _changed() {
    final dimmed = widget.proposal.value != null;
    if (_dimmed != dimmed) setState(() => _dimmed = dimmed);
  }

  @override
  void dispose() {
    widget.proposal.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: _dimmed ? .25 : 1, child: widget.child);
}

/// Time labels remain at the real edges; this single information group can
/// move within the intersection of its card and the readable viewport.
class _PlannerBlockContents extends StatefulWidget {
  const _PlannerBlockContents({
    super.key,
    required this.item,
    required this.identity,
    required this.continuation,
    required this.startLabel,
    required this.endLabel,
    required this.timeHeight,
    required this.vertical,
    required this.dragActive,
    required this.segmentTop,
    required this.bottomInset,
    required this.viewportHeight,
    required this.accent,
  });

  final BoardItem item;
  final String identity, continuation, startLabel, endLabel;
  final double timeHeight, bottomInset;
  final ScrollController vertical;
  final ValueListenable<bool> dragActive;
  final double? segmentTop;
  final double viewportHeight;
  final Color accent;

  @override
  State<_PlannerBlockContents> createState() => _PlannerBlockContentsState();
}

class _PlannerBlockContentsState extends State<_PlannerBlockContents> {
  double? _contentHeight;
  double? _twoLineTitleHeight;
  bool? _mode;

  @override
  void initState() {
    super.initState();
    widget.vertical.addListener(_viewportChanged);
    widget.dragActive.addListener(_viewportChanged);
  }

  @override
  void didUpdateWidget(covariant _PlannerBlockContents oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.vertical, widget.vertical)) {
      oldWidget.vertical.removeListener(_viewportChanged);
      widget.vertical.addListener(_viewportChanged);
    }
    if (!identical(oldWidget.dragActive, widget.dragActive)) {
      oldWidget.dragActive.removeListener(_viewportChanged);
      widget.dragActive.addListener(_viewportChanged);
    }
  }

  @override
  void dispose() {
    widget.vertical.removeListener(_viewportChanged);
    widget.dragActive.removeListener(_viewportChanged);
    super.dispose();
  }

  ({double top, double available}) _geometry(double height) {
    final offset = widget.vertical.hasClients ? widget.vertical.offset : 0.0;
    final visibleTop = widget.segmentTop == null
        ? 0.0
        : offset - widget.segmentTop! - 4;
    final visibleBottom = widget.segmentTop == null
        ? height
        : offset +
              widget.viewportHeight -
              (widget.dragActive.value ? 0 : widget.bottomInset) -
              widget.segmentTop! -
              4;
    final gap = widget.item['_titleLines'] == 2 ? 1.0 : 2.0;
    final contentTop = widget.timeHeight + gap;
    final contentBottom = math.max(
      contentTop,
      height - widget.timeHeight - gap,
    );
    final top = math.max(contentTop, visibleTop + gap).clamp(0.0, height);
    final bottom = math.min(contentBottom, visibleBottom - gap);
    return (top: top, available: math.max(0.0, bottom - top));
  }

  bool _displayMode(double height) {
    final geometry = _geometry(height);
    return _twoLineTitleHeight != null &&
        geometry.available + .01 >= _twoLineTitleHeight!;
  }

  void _viewportChanged() {
    final height = _contentHeight;
    if (!mounted || height == null || _twoLineTitleHeight == null) return;
    final next = _displayMode(height);
    // Ordinary text stays laid out across every row boundary. Only compact
    // overlapping titles need a rebuild to choose one or two lines.
    if (_mode != next) setState(() => _mode = next);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item, identity = widget.identity;
    final continuation = widget.continuation, accent = widget.accent;
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final titleStyle = theme.textTheme.labelMedium!.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: item['_titleLines'] == 2 ? 11 : null,
      height: item['_titleLines'] == 2 ? 1.15 : null,
      color: ContentColors.foreground(
        accent,
        ContentColors.surface(accent, theme.colorScheme),
        theme.colorScheme.onSurface,
      ),
    );
    final detailStyle = theme.textTheme.labelSmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final timeStyle = detailStyle.copyWith(fontSize: 10);
    final icon = item['_titleLines'] == 2
        ? null
        : item['readOnly'] == true
        ? Icons.school_outlined
        : item['fixed'] == true
        ? Icons.lock_rounded
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        _contentHeight = constraints.maxHeight;
        final geometry = _geometry(constraints.maxHeight);
        _twoLineTitleHeight = item['_titleLines'] == 2
            ? scaler.scale(11) * 1.15 * 2
            : null;
        final rows = <({String key, String text, TextStyle style, int lines})>[
          (
            key: 'title',
            text: '$continuation${item['title'] ?? ''}',
            style: titleStyle,
            lines:
                _twoLineTitleHeight != null &&
                    geometry.available + .01 >= _twoLineTitleHeight!
                ? 2
                : 1,
          ),
          if ('${item['location'] ?? ''}'.trim().isNotEmpty)
            (
              key: 'location',
              text: '${item['location']}'.trim(),
              style: detailStyle,
              lines: 2,
            ),
          if ('${item['teacher'] ?? ''}'.trim().isNotEmpty)
            (
              key: 'teacher',
              text: '${item['teacher']}'.trim(),
              style: detailStyle,
              lines: 1,
            ),
          if ('${item['deadlineText'] ?? item['deadlineSummary'] ?? ''}'
              .trim()
              .isNotEmpty)
            (
              key: 'deadline',
              text: '${item['deadlineText'] ?? item['deadlineSummary']}'.trim(),
              style: detailStyle,
              lines: 1,
            ),
        ];
        final children = <Widget>[];
        for (final row in rows) {
          final isTitle = row.key == 'title';
          children.add(
            Padding(
              key: ValueKey('planner-info:$identity:${row.key}'),
              padding: EdgeInsets.only(top: isTitle ? 0 : 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      row.text,
                      maxLines: row.lines,
                      overflow: TextOverflow.ellipsis,
                      style: row.style,
                    ),
                  ),
                  if (isTitle && icon != null) ...[
                    const SizedBox(width: 4),
                    Icon(icon, size: 12, color: accent),
                  ],
                ],
              ),
            ),
          );
        }
        _mode = _displayMode(constraints.maxHeight);
        return ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Text(
                  widget.startLabel,
                  key: ValueKey('block-time-start:$identity'),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: timeStyle,
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Text(
                  widget.endLabel,
                  key: ValueKey('block-time-end:$identity'),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: timeStyle,
                ),
              ),
              Positioned.fill(
                child: _ScrollingBlockInfo(
                  vertical: widget.vertical,
                  dragActive: widget.dragActive,
                  geometry: (height) {
                    final value = _geometry(height);
                    return (value.top, value.available);
                  },
                  child: RepaintBoundary(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Scroll changes only the group's paint translation and clip. The metadata
/// column stays laid out; hiding is a direct function of the shared scroll
/// position, with no independent line animations or opacity layers.
class _ScrollingBlockInfo extends SingleChildRenderObjectWidget {
  const _ScrollingBlockInfo({
    required this.vertical,
    required this.dragActive,
    required this.geometry,
    required super.child,
  });
  final Listenable vertical, dragActive;
  final (double, double) Function(double height) geometry;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ScrollingBlockInfoRender(vertical, dragActive, geometry);
  @override
  void updateRenderObject(
    BuildContext context,
    _ScrollingBlockInfoRender renderObject,
  ) => renderObject.update(vertical, dragActive, geometry);
}

class _ScrollingBlockInfoRender extends RenderShiftedBox {
  _ScrollingBlockInfoRender(this.vertical, this.dragActive, this.geometry)
    : super(null);
  Listenable vertical, dragActive;
  (double, double) Function(double height) geometry;
  (double, double)? _cachedGeometry;
  void _changed() {
    final previous = _cachedGeometry;
    _cachedGeometry = null;
    if (hasSize && previous != null && _resolvedGeometry == previous) return;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void update(
    Listenable nextVertical,
    Listenable nextDrag,
    (double, double) Function(double) nextGeometry,
  ) {
    if (!identical(nextVertical, vertical)) {
      if (attached) vertical.removeListener(_changed);
      vertical = nextVertical;
      if (attached) vertical.addListener(_changed);
    }
    if (!identical(nextDrag, dragActive)) {
      if (attached) dragActive.removeListener(_changed);
      dragActive = nextDrag;
      if (attached) dragActive.addListener(_changed);
    }
    geometry = nextGeometry;
    _changed();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    vertical.addListener(_changed);
    dragActive.addListener(_changed);
  }

  @override
  void detach() {
    vertical.removeListener(_changed);
    dragActive.removeListener(_changed);
    super.detach();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    _cachedGeometry = null;
    child?.layout(
      BoxConstraints.tightFor(width: size.width),
      parentUsesSize: true,
    );
  }

  (double, double) get _resolvedGeometry =>
      _cachedGeometry ??= geometry(size.height);
  Offset get _translation => Offset(0, _resolvedGeometry.$1);
  Rect get _clip {
    final value = _resolvedGeometry;
    return Rect.fromLTWH(0, value.$1, size.width, value.$2);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _clip.isEmpty) return;
    context.pushClipRect(
      needsCompositing,
      offset,
      _clip,
      (context, offset) => context.paintChild(child, offset + _translation),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _clip.contains(position) &&
      child != null &&
      result.addWithPaintOffset(
        offset: _translation,
        position: position,
        hitTest: (result, transformed) =>
            child!.hitTest(result, position: transformed),
      );
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, _translation.dy, 0, 1);
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => _clip;
  @override
  Rect? describeSemanticsClip(RenderObject? child) => _clip;
}

class _BoardLines extends CustomPainter {
  _BoardLines(
    this.columnWidth,
    this.scale,
    this.startMinute,
    this.color, {
    this.interval = 30,
  });
  final int interval;
  final double columnWidth, scale;
  final int startMinute;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .6)
      ..strokeWidth = .5;
    for (double x = 0; x <= size.width; x += columnWidth) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (
      var minute = ((startMinute + interval - 1) ~/ interval) * interval;
      (minute - startMinute) * scale < size.height;
      minute += interval
    ) {
      final y = (minute - startMinute) * scale;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_BoardLines old) =>
      old.interval != interval ||
      old.columnWidth != columnWidth ||
      old.scale != scale ||
      old.startMinute != startMinute ||
      old.color != color;
}

class _DenseOccupancy extends CustomPainter {
  _DenseOccupancy(
    this.group,
    this.color,
    this.visibleTop,
    this.visibleBottom, {
    this.shortBands = false,
  });
  final bool shortBands;
  final _BoardGroup group;
  final Color color;
  final double visibleTop, visibleBottom;
  @override
  void paint(Canvas canvas, Size size) {
    final width = shortBands ? size.width : size.width / group.lanes;
    final fill = Paint()..color = color.withValues(alpha: .13);
    for (final segment in group.segments) {
      if (segment.top > visibleBottom) break;
      if (segment.bottom < visibleTop) continue;
      final rect = Rect.fromLTWH(
        shortBands ? 0 : segment.lane * width,
        segment.top - group.top,
        width,
        segment.bottom - segment.top,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_DenseOccupancy old) =>
      old.group != group ||
      old.shortBands != shortBands ||
      old.color != color ||
      old.visibleTop != visibleTop ||
      old.visibleBottom != visibleBottom;
}

/// Source texture is shared by the card and compact occupancy indicators.
class _SourceHatching extends CustomPainter {
  const _SourceHatching(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .14)
      ..strokeWidth = .6;
    for (double x = -size.height; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SourceHatching oldDelegate) => oldDelegate.color != color;
}

class _ShortTaskLeader extends CustomPainter {
  const _ShortTaskLeader(this.color, this.downward);
  final Color color;
  final bool downward;
  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(0, downward ? 0 : size.height);
    final end = Offset(size.width, downward ? size.height : 0);
    final paint = Paint()
      ..color = color.withValues(alpha: .75)
      ..strokeWidth = .8;
    canvas.drawLine(start, end, paint);
    canvas.drawCircle(start, 1.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ShortTaskLeader old) =>
      old.color != color || old.downward != downward;
}

/// Draggable positions this zero-size root at the pointer. Its child keeps its
/// real layout size and paints back inside the safe screen rectangle.
class _ScreenClampedFeedback extends SingleChildRenderObjectWidget {
  const _ScreenClampedFeedback({
    required this.pointer,
    required this.safeBounds,
    this.abovePointer = false,
    required super.child,
  });
  final Offset pointer;
  final Rect safeBounds;
  final bool abovePointer;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ClampedFeedbackRender(pointer, safeBounds, abovePointer);
  @override
  void updateRenderObject(
    BuildContext context,
    _ClampedFeedbackRender renderObject,
  ) => renderObject.update(pointer, safeBounds, abovePointer);
}

class _ClampedFeedbackRender extends RenderShiftedBox {
  _ClampedFeedbackRender(this.pointer, this.safeBounds, this.abovePointer)
    : super(null);
  Offset pointer;
  Rect safeBounds;
  bool abovePointer;
  void update(Offset value, Rect bounds, bool above) {
    if (pointer == value && safeBounds == bounds && abovePointer == above) {
      return;
    }
    pointer = value;
    safeBounds = bounds;
    abovePointer = above;
    markNeedsLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size.zero);
  @override
  void performLayout() {
    size = constraints.constrain(Size.zero);
    final child = this.child;
    if (child == null) return;
    child.layout(BoxConstraints.loose(safeBounds.size), parentUsesSize: true);
    final preferredX = abovePointer
        ? pointer.dx - child.size.width / 2
        : pointer.dx;
    var preferredY = abovePointer
        ? pointer.dy - child.size.height - 24
        : pointer.dy;
    if (abovePointer && preferredY < safeBounds.top) {
      preferredY = pointer.dy + 32;
    }
    final x = preferredX.clamp(
      safeBounds.left,
      math.max(safeBounds.left, safeBounds.right - child.size.width),
    );
    final y = preferredY.clamp(
      safeBounds.top,
      math.max(safeBounds.top, safeBounds.bottom - child.size.height),
    );
    (child.parentData! as BoxParentData).offset = Offset(
      x - pointer.dx,
      y - pointer.dy,
    );
  }

  @override
  Rect get paintBounds {
    final child = this.child;
    return child == null
        ? Rect.zero
        : (child.parentData! as BoxParentData).offset & child.size;
  }
}

/// The pointer still drives DragTarget hit testing. Only the feedback paint
/// geometry transitions from the original candidate to its exact visible band.
class _CandidateDragFeedback extends StatefulWidget {
  const _CandidateDragFeedback({
    required this.pointer,
    required this.sourceRect,
    required this.targetRect,
    required this.source,
    required this.target,
  });
  final Offset pointer;
  final Rect sourceRect;
  final Rect? targetRect;
  final Widget source;
  final Widget? target;
  @override
  State<_CandidateDragFeedback> createState() => _CandidateDragFeedbackState();
}

class _CandidateDragFeedbackState extends State<_CandidateDragFeedback> {
  Rect? _lastTarget;
  Widget? _lastTargetChild;
  @override
  Widget build(BuildContext context) {
    if (widget.targetRect != null) {
      _lastTarget = widget.targetRect;
      _lastTargetChild = widget.target;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: widget.targetRect == null ? 0 : 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      builder: (context, progress, _) {
        final rect = Rect.lerp(
          widget.sourceRect,
          _lastTarget ?? widget.sourceRect,
          progress,
        )!;
        return _GlobalRectFeedback(
          pointer: widget.pointer,
          rect: rect,
          child: Material(
            key: const ValueKey('planner-candidate-drag-feedback'),
            elevation: 4 * (1 - progress),
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (progress < 1)
                  Opacity(
                    opacity: 1 - progress,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: widget.sourceRect.width,
                      maxWidth: widget.sourceRect.width,
                      minHeight: widget.sourceRect.height,
                      maxHeight: widget.sourceRect.height,
                      child: widget.source,
                    ),
                  ),
                if (progress > 0 && _lastTargetChild != null)
                  Opacity(
                    opacity: progress,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: _lastTarget!.width,
                      maxWidth: _lastTarget!.width,
                      minHeight: _lastTarget!.height,
                      maxHeight: _lastTarget!.height,
                      child: _lastTargetChild,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GlobalRectFeedback extends SingleChildRenderObjectWidget {
  const _GlobalRectFeedback({
    required this.pointer,
    required this.rect,
    required super.child,
  });
  final Offset pointer;
  final Rect rect;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _GlobalRectFeedbackRender(pointer, rect);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _GlobalRectFeedbackRender renderObject,
  ) => renderObject.update(pointer, rect);
}

class _GlobalRectFeedbackRender extends RenderShiftedBox {
  _GlobalRectFeedbackRender(this.pointer, this.rect) : super(null);
  Offset pointer;
  Rect rect;
  void update(Offset nextPointer, Rect nextRect) {
    if (pointer == nextPointer && rect == nextRect) return;
    pointer = nextPointer;
    rect = nextRect;
    markNeedsLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size.zero);
  @override
  void performLayout() {
    size = constraints.constrain(Size.zero);
    child?.layout(BoxConstraints.tight(rect.size), parentUsesSize: true);
    if (child != null) {
      (child!.parentData! as BoxParentData).offset = rect.topLeft - pointer;
    }
  }

  @override
  Rect get paintBounds => child == null
      ? Rect.zero
      : (child!.parentData! as BoxParentData).offset & child!.size;
}
