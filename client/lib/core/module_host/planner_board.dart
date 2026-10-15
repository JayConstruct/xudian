import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
  final _vertical = ScrollController();
  final _gridKey = GlobalKey();
  final _viewportKey = GlobalKey();
  final _proposal = ValueNotifier<_Proposal?>(null);
  final _validation = ValueNotifier<BoardItem?>(null);
  final _window = ValueNotifier<Rect>(const Rect.fromLTWH(0, 0, 800, 600));
  List<BoardItem>? _geometrySource;
  Object? _geometrySettings;
  _BoardGeometry? _geometry;
  String? _pinnedSegment;
  Timer? _fineTimer, _intentTimer, _scrollTimer, _previewTimer;
  Offset? _anchor, _lastPosition, _pointerPosition;
  DateTime? _fineStart;
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

  double _number(String key, double fallback, double min, double max) =>
      (widget.options[key] as num? ?? fallback).toDouble().clamp(min, max);
  int get _startMinute => _number('startMinute', 0, 0, 1439).round();
  int get _endMinute {
    final value = _number('endMinute', 1440, 1, 1440).round();
    return value > _startMinute ? value : 1440;
  }

  double get _scale => _number('pixelsPerMinute', 1, .5, 3);
  // The script supplies floating wall-clock ISO values in its planning zone.
  // UTC is only an arithmetic container here, so the device timezone and its
  // DST rules cannot alter geometry; scripts resolve actual instants.
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
            parsed.millisecond,
            parsed.microsecond,
          );
  }

  DateTime _midnight(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);
  List<BoardItem> get _days {
    if (widget.days.isNotEmpty) {
      return widget.days.where((day) => _date(day['date']) != null).toList();
    }
    final today = _midnight(DateTime.now());
    return List.generate(5, (i) {
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
    _horizontal.addListener(_syncHeader);
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
    if (_header.hasClients && _horizontal.hasClients) {
      _header.jumpTo(
        _horizontal.offset.clamp(0, _header.position.maxScrollExtent),
      );
    }
  }

  @override
  void didUpdateWidget(covariant PlannerBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A script render is a data revision; viewport notifications do not enter
    // this lifecycle and therefore reuse the parsed, sorted geometry index.
    _geometrySource = null;
    _geometry = null;
    if (!widget.enabled ||
        widget.previewIdentity != oldWidget.previewIdentity ||
        jsonEncode(widget.days) != jsonEncode(oldWidget.days) ||
        _startMinute != (oldWidget.options['startMinute'] as num? ?? 0) ||
        _endMinute != (oldWidget.options['endMinute'] as num? ?? 1440) ||
        _scale != (oldWidget.options['pixelsPerMinute'] as num? ?? 1)) {
      _clearDrag();
      _viewGeneration++;
    }
  }

  @override
  void dispose() {
    _fineTimer?.cancel();
    _intentTimer?.cancel();
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _previewTimer?.cancel();
    _dragSession++;
    _horizontal.dispose();
    _header.dispose();
    _vertical.dispose();
    _proposal.dispose();
    _validation.dispose();
    _window.dispose();
    super.dispose();
  }

  void _clearDrag() {
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
    _fine = false;
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
    _resizing = true;
    _resizeBasePoint = box.globalToLocal(global);
    _resizeBaseEnd = _date(item['end']);
    _hover(item, global);
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
    final index = (point.dx / _columnWidth).floor().clamp(0, days.length - 1);
    final day = _midnight(_date(days[index]['date'])!);
    if (!fromScroll &&
        (_lastPosition == null || (global - _lastPosition!).distance > 8)) {
      _fineTimer?.cancel();
      // Resume coarse snapping only after a deliberate, larger movement.
      if (_fine && (global - (_anchor ?? global)).distance > 48) {
        _fine = false;
        _fineStart = null;
      }
      _lastPosition = global;
      if (!_fine) {
        _fineTimer = Timer(const Duration(milliseconds: 650), () {
          if (!mounted || _proposal.value == null) return;
          _fine = true;
          _anchor = _pointerPosition ?? global;
          _fineStart = _resizing
              ? _proposal.value!.end
              : _proposal.value!.start;
          _fineScrollAnchor = _vertical.hasClients ? _vertical.offset : 0;
          _fineDayAnchor =
              ((_gridKey.currentContext!.findRenderObject() as RenderBox)
                          .globalToLocal(_anchor!)
                          .dx /
                      _columnWidth)
                  .floor()
                  .clamp(0, days.length - 1);
          final old = _proposal.value!;
          _publish(
            _Proposal(
              old.item,
              old.start,
              old.end,
              1,
              intent: old.intent,
              targetId: old.targetId,
            ),
          );
        });
      }
    }
    final raw = _startMinute + point.dy / _scale;
    final minute = _fine && _fineStart != null
        ? _fineStart!.hour * 60 +
              _fineStart!.minute +
              ((global.dy -
                          _anchor!.dy +
                          (_vertical.hasClients ? _vertical.offset : 0) -
                          _fineScrollAnchor) /
                      _scale)
                  .round()
        : (raw / 15).round() * 15;
    // Display bounds do not constrain the duration or move it back from midnight.
    var start = day.add(
      Duration(minutes: minute.clamp(0, _fine ? 1439 : 1425)),
    );
    var end = start.add(duration);
    if (_resizing && _resizeBaseEnd != null && _resizeBasePoint != null) {
      start = _date(item['start'])!;
      final baseIndex = (_resizeBasePoint!.dx / _columnWidth).floor().clamp(
        0,
        days.length - 1,
      );
      final dayDelta = _midnight(_date(days[index]['date'])!)
          .difference(_midnight(_date(days[baseIndex]['date'])!));
      end = _fine && _fineStart != null
          ? _fineStart!.add(
              day.difference(_midnight(_date(days[_fineDayAnchor]['date'])!)) +
                  Duration(
                    minutes:
                        ((global.dy -
                                    _anchor!.dy +
                                    (_vertical.hasClients
                                        ? _vertical.offset
                                        : 0) -
                                    _fineScrollAnchor) /
                                _scale)
                            .round(),
                  ),
            )
          : _resizeBaseEnd!.add(
              dayDelta +
                  Duration(
                    minutes: ((point.dy - _resizeBasePoint!.dy) / _scale)
                        .round(),
                  ),
            );
      if (!_fine) {
        end = _midnight(end).add(
          Duration(minutes: ((end.hour * 60 + end.minute) / 15).round() * 15),
        );
      }
      if (!end.isAfter(start)) end = start.add(const Duration(minutes: 1));
      _publish(_Proposal(item, start, end, _fine ? 1 : 15, intent: 'resize'));
      return;
    }
    BoardItem? target;
    final groups = _index(widget.blocks, _cardHeight).days[index];
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
        _fine ? 1 : 15,
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
    final target = _index(widget.blocks, _cardHeight).byId[value.targetId];
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

  Widget _card(
    BoardItem item,
    double height, {
    String? continuation,
    String? sourceSegment,
  }) {
    final generation = _viewGeneration;
    final scheme = Theme.of(context).colorScheme;
    final deadline = item['deadlineSummary'] as String?;
    final start = _date(item['start']);
    final subtitle = deadline?.isNotEmpty == true
        ? '${item['overdue'] == true ? '逾期 · ' : ''}$deadline'
        : start != null
        ? _time(start)
        : '待安排';
    final icon = item['readOnly'] == true
        ? Icons.link
        : item['fixed'] == true
        ? Icons.lock_outline
        : null;
    Widget card = Semantics(
      label:
          '${item['title'] ?? ''}，$subtitle${item['readOnly'] == true ? '，来源只读' : ''}${item['fixed'] == true ? '，固定时间' : ''}',
      child: Material(
        color: item['readOnly'] == true
            ? scheme.surfaceContainerHighest
            : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: !widget.enabled || item['event'] == null
              ? null
              : () => widget.onEvent(item['event']),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border:
                  item['selected'] == true ||
                      widget.selectedIds.contains(item['id'])
                  ? Border.all(color: scheme.primary, width: 2)
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Icon(icon, size: 12),
                      ),
                    Expanded(
                      child: Text(
                        '${continuation ?? ''}${item['title'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: deadline?.isNotEmpty == true
                        ? scheme.error
                        : scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (_movable(item)) {
      card = LongPressDraggable<BoardItem>(
        data: {...item, '_boardGeneration': _viewGeneration},
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: () {
          _clearDrag();
          _pinnedSegment = sourceSegment;
        },
        onDragEnd: (_) => _clearDrag(),
        feedback: AnimatedBuilder(
          animation: Listenable.merge([_proposal, _validation]),
          builder: (context, _) {
            if (!widget.enabled || generation != _viewGeneration) {
              return const SizedBox.shrink();
            }
            final value = _proposal.value;
            return Material(
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
                        '${value.end.difference(value.start).inMinutes}分钟 · ${value.snap == 1 ? '1分钟细调' : '15分钟吸附'}',
                      ),
                      Text(
                        '${switch (value.intent) {
                          'swap' => '交换',
                          'insert' => '插入',
                          'resize' => '调整时长',
                          _ => '移动',
                        }} · 待校验',
                      ),
                    ] else
                      const Text('长按拖入日期表'),
                    if (deadline?.isNotEmpty == true)
                      Text(
                        '${item['deadlineText'] ?? deadline}',
                        style: TextStyle(color: scheme.error),
                      ),
                    if (item['sourceLabel'] != null)
                      Text('${item['sourceLabel']}'),
                    ..._status(),
                  ],
                ),
              ),
            );
          },
        ),
        child: card,
      );
    }
    return card;
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
            if (index == 0) return ListTile(title: Text(title));
            final item = items[index - 1];
            return ListTile(
              title: Text('${item['title'] ?? ''}'),
              subtitle: Text(
                '${_full(_date(item['start'])!)} → ${_full(_date(item['end'])!)}',
              ),
              onTap: !widget.enabled || item['event'] == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      widget.onEvent(item['event']);
                    },
            );
          },
        ),
      ),
    );
  }

  _BoardGeometry _index(List<BoardItem> items, double cardHeight) {
    final settings = (
      jsonEncode(_days),
      _startMinute,
      _endMinute,
      _scale,
      cardHeight,
    );
    if (identical(items, widget.blocks) &&
        identical(items, _geometrySource) &&
        settings == _geometrySettings &&
        _geometry != null) {
      return _geometry!;
    }
    final days = _days;
    final segments = List.generate(days.length, (_) => <_BoardSegment>[]);
    final starts = [for (final day in days) _midnight(_date(day['date'])!)];
    // Parse each item once per data/geometry revision, never per scroll frame.
    for (final item in items) {
      final start = _date(item['start']), end = _date(item['end']);
      if (start == null || end == null || !end.isAfter(start)) continue;
      for (var day = 0; day < days.length; day++) {
        final from = starts[day].add(Duration(minutes: _startMinute));
        final to = starts[day].add(Duration(minutes: _endMinute));
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
    if (identical(items, widget.blocks)) {
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
      final dense = laneWidth < 72;
      final first = group.segments.first;
      final dayLeft = first.dayIndex * _columnWidth;
      if (dense && !preview) {
        // Dense groups paint exact-duration stripes together; their widget count
        // does not grow with hundreds of coincident occupations.
        result.add(
          Positioned(
            key: ValueKey('dense-occupancy:${first.key}'),
            left: dayLeft + 3,
            top: group.top,
            width: _columnWidth - 6,
            height: group.bottom - group.top,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DenseOccupancy(
                  group,
                  scheme.primary,
                  window.top,
                  window.bottom,
                ),
              ),
            ),
          ),
        );
        final labelTop = math.min(
          math.max(group.top, window.top + 160),
          math.max(group.top, group.bottom - cardHeight),
        );
        result.add(
          Positioned(
            key: ValueKey('dense:${first.key}'),
            left: dayLeft + 4,
            top: labelTop.toDouble(),
            width: _columnWidth - 8,
            height: cardHeight,
            child: Material(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: !widget.enabled
                    ? null
                    : () => _showOutside(
                        group.segments.map((segment) => segment.item).toList(),
                        title:
                            '${_days[first.dayIndex]['label'] ?? first.day} · 选择安排',
                      ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      '${group.segments.length}项安排 · 选择',
                      textAlign: TextAlign.center,
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
                    color: outline
                        ? Colors.transparent
                        : (preview
                                  ? scheme.tertiary
                                  : item['readOnly'] == true
                                  ? scheme.outline
                                  : scheme.primary)
                              .withValues(alpha: .13),
                    border: outline
                        ? Border.all(color: scheme.tertiary, width: 2)
                        : Border(
                            left: BorderSide(
                              color: preview ? scheme.tertiary : scheme.primary,
                              width: math.min(laneWidth, preview ? 3 : 2),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          );
        }
        if (preview) continue;
        final naturalLabelTop = math.min(
          segment.top,
          math.max(0, (_endMinute - _startMinute) * _scale - cardHeight),
        );
        // A long occupation remains identifiable when its original label is far
        // above the viewport. The true occupancy stripe never changes length.
        final labelTop = pinned
            ? naturalLabelTop
            : math.min(
                math.max(naturalLabelTop, window.top + 160),
                math.max(naturalLabelTop, segment.bottom - cardHeight),
              );
        result.add(
          Positioned(
            key: ValueKey('block:${segment.key}'),
            left: left + 3,
            top: labelTop.toDouble(),
            width: math.max(1, laneWidth - 6),
            child: _card(
              item,
              cardHeight,
              sourceSegment: segment.key,
              continuation:
                  '${start.isBefore(from) ? '↳ ' : ''}${_midnight(start) != _midnight(end) ? '跨天 ' : ''}${end.isAfter(to) ? '↗ ' : ''}',
            ),
          ),
        );
        final handleTop = (segment.bottom - 24).clamp(
          0.0,
          math.max(0.0, (_endMinute - _startMinute) * _scale - 48),
        );
        if (_movable(item) &&
            !end.isAfter(to) &&
            !end.isBefore(from) &&
            (pinned ||
                (handleTop + 48 >= window.top && handleTop <= window.bottom))) {
          result.add(
            Positioned(
              key: ValueKey('resize-position:${segment.key}'),
              left: left + math.max(0, laneWidth - 48),
              top: handleTop.toDouble(),
              width: math.min(48, laneWidth),
              height: 48,
              child: Tooltip(
                message: '拖动调整时长',
                child: Listener(
                  key: ValueKey('resize:${segment.key}'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (details) => _resizeDown = details.position,
                  child: Draggable<BoardItem>(
                    data: {...item, '_boardGeneration': _viewGeneration},
                    dragAnchorStrategy: pointerDragAnchorStrategy,
                    onDragStarted: () {
                      if (_resizeDown != null) {
                        _beginResize(item, _resizeDown!);
                        _pinnedSegment = segment.key;
                      }
                    },
                    onDragEnd: (_) => _clearDrag(),
                    feedback: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('调整时长'),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 24,
                        height: 5,
                        decoration: BoxDecoration(
                          color: scheme.primary,
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
    return result;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _refreshWindow());
        _columnWidth = math.max(
          _number('minColumnWidth', 112, 96, 320),
          (constraints.maxWidth - 48) / math.max(1, days.length),
        );
        final gridWidth = _columnWidth * days.length;
        final gridHeight = (_endMinute - _startMinute) * _scale;
        final outside = widget.blocks.where((item) {
          final start = _date(item['start']), end = _date(item['end']);
          if (start == null || end == null) return false;
          return days.any((day) {
            final date = _midnight(_date(day['date'])!);
            final next = DateTime.utc(date.year, date.month, date.day + 1);
            if (!start.isBefore(next) || !end.isAfter(date)) return false;
            return start.isBefore(date.add(Duration(minutes: _startMinute))) ||
                end.isAfter(date.add(Duration(minutes: _endMinute)));
          });
        }).toList();
        final board = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                '${widget.options['candidateLabel'] ?? '待安排'} · ${widget.candidates.length}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            SizedBox(
              height: cardHeight * 2 + 12,
              child: widget.candidates.isEmpty
                  ? const Center(child: Text('暂无待安排任务'))
                  : GridView.builder(
                      key: const ValueKey('planner-candidates'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      scrollDirection: Axis.horizontal,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisExtent:
                            math.max(112, scaler.scale(112)) +
                            (widget.selectEvent != null ||
                                    widget.candidates.any(
                                      (item) => item['selectEvent'] is Map,
                                    )
                                ? 48
                                : 0),
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      itemCount: widget.candidates.length,
                      itemBuilder: (context, index) {
                        final item = widget.candidates[index];
                        return Row(
                          children: [
                            if (widget.selectEvent != null ||
                                item['selectEvent'] is Map)
                              SizedBox(
                                width: 48,
                                child: Checkbox(
                                  value:
                                      item['selected'] == true ||
                                      widget.selectedIds.contains(item['id']),
                                  onChanged: !widget.enabled
                                      ? null
                                      : (selected) => widget.onEvent({
                                          ...?widget.selectEvent,
                                          if (item['selectEvent'] is Map)
                                            ...Map<String, Object?>.from(
                                              item['selectEvent'] as Map,
                                            ),
                                          'id':
                                              (item['selectEvent'] is Map
                                                  ? (item['selectEvent']
                                                        as Map)['id']
                                                  : null) ??
                                              widget.selectEvent?['id'] ??
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
            if (widget.previewLabel != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  widget.previewLabel!,
                  style: TextStyle(color: scheme.tertiary),
                ),
              ),
            if (outside.isNotEmpty)
              TextButton(
                onPressed: () => _showOutside(outside),
                child: Text('显示范围外有 ${outside.length} 项安排 · 查看'),
              ),
            Row(
              children: [
                const SizedBox(
                  width: 48,
                  height: 38,
                  child: Center(child: Text('时间')),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _header,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Row(
                      children: [
                        for (final day in days)
                          SizedBox(
                            width: _columnWidth,
                            height: 38,
                            child: Center(
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
              ],
            ),
            Expanded(
              child: SizedBox(
                key: _viewportKey,
                child: SingleChildScrollView(
                  key: const ValueKey('planner-vertical'),
                  controller: _vertical,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 48,
                        height: gridHeight,
                        child: Stack(
                          children: [
                            for (
                              var minute = ((_startMinute + 59) ~/ 60) * 60;
                              minute < _endMinute;
                              minute += 60
                            )
                              Positioned(
                                top: (minute - _startMinute) * _scale,
                                left: 2,
                                child: Text(
                                  '${(minute ~/ 60).toString().padLeft(2, '0')}:00',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          key: const ValueKey('planner-horizontal'),
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          child: DragTarget<BoardItem>(
                            onWillAcceptWithDetails: (details) =>
                                _movable(details.data),
                            onMove: (details) =>
                                _hover(details.data, details.offset),
                            onLeave: (_) => _clearDrag(),
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
                                  builder: (context, _) => Stack(
                                    children: [
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: _BoardLines(
                                            _columnWidth,
                                            _scale,
                                            _startMinute,
                                            scheme.outlineVariant,
                                          ),
                                        ),
                                      ),
                                      ..._segments(widget.blocks, cardHeight),
                                      ..._segments(
                                        widget.previewBlocks,
                                        cardHeight,
                                        preview: true,
                                      ),
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
                                            widget.blocks,
                                            cardHeight,
                                          ).byId[_proposal.value!.targetId],
                                        ],
                                        cardHeight,
                                        preview: true,
                                        prefix: 'target',
                                        outline: true,
                                      ),
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
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
        final content = Stack(
          children: [
            Positioned.fill(child: board),
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
                        (value.intent != 'resize' &&
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
                                  : '移动预览'} · ${value.snap == 1 ? '1分钟细调' : '15分钟吸附'}',
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

class _BoardLines extends CustomPainter {
  _BoardLines(this.columnWidth, this.scale, this.startMinute, this.color);
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
      var minute = ((startMinute + 29) ~/ 30) * 30;
      (minute - startMinute) * scale < size.height;
      minute += 30
    ) {
      final y = (minute - startMinute) * scale;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_BoardLines old) =>
      old.columnWidth != columnWidth ||
      old.scale != scale ||
      old.startMinute != startMinute ||
      old.color != color;
}

class _DenseOccupancy extends CustomPainter {
  _DenseOccupancy(this.group, this.color, this.visibleTop, this.visibleBottom);
  final _BoardGroup group;
  final Color color;
  final double visibleTop, visibleBottom;
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width / group.lanes;
    final fill = Paint()..color = color.withValues(alpha: .13);
    final edge = Paint()..color = color;
    for (final segment in group.segments) {
      if (segment.top > visibleBottom) break;
      if (segment.bottom < visibleTop) continue;
      final rect = Rect.fromLTWH(
        segment.lane * width,
        segment.top - group.top,
        width,
        segment.bottom - segment.top,
      );
      canvas.drawRect(rect, fill);
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, math.min(2, width), rect.height),
        edge,
      );
    }
  }

  @override
  bool shouldRepaint(_DenseOccupancy old) =>
      old.group != group ||
      old.color != color ||
      old.visibleTop != visibleTop ||
      old.visibleBottom != visibleBottom;
}
