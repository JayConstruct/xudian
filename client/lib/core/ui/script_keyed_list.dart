import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_motion.dart';

class ScriptListItem {
  const ScriptListItem({required this.id, required this.builder});

  final String id;
  final WidgetBuilder builder;
}

/// Keeps rows by identity. Only explicit, fresh command feedback animates a
/// removal or highlights a new row; query refreshes never replay entrances.
class ScriptKeyedList extends StatefulWidget {
  const ScriptKeyedList({
    super.key,
    required this.items,
    required this.scope,
    this.feedbackKey,
    this.removeKeys = const {},
    this.highlightKeys = const {},
    this.duration = const Duration(milliseconds: 220),
    this.spacing = 12,
    this.scrollController,
    this.padding = EdgeInsets.zero,
  });

  final List<ScriptListItem> items;
  final String scope;
  final Object? feedbackKey;
  final Set<String> removeKeys, highlightKeys;
  final Duration duration;
  final double spacing;
  final ScrollController? scrollController;
  final EdgeInsets padding;

  @override
  State<ScriptKeyedList> createState() => _ScriptKeyedListState();
}

class _Entry {
  _Entry(this.item, {this.removing = false, this.highlightKey});
  final ScriptListItem item;
  final bool removing;
  final Object? highlightKey;
}

class _ScriptKeyedListState extends State<ScriptKeyedList> {
  late List<_Entry> entries;
  Object? consumedFeedback;
  final removalTimers = <String, Timer>{};
  final highlightTimers = <String, Timer>{};
  bool reduceMotion = false;

  @override
  void initState() {
    super.initState();
    entries = widget.items.map(_Entry.new).toList();
    consumedFeedback = widget.feedbackKey;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion = AppMotion.reduced(context);
    if (reduceMotion) {
      _cancelTimers();
      entries = [
        for (final entry in entries)
          if (!entry.removing) _Entry(entry.item),
      ];
    }
  }

  void _cancelTimers() {
    for (final timer in [...removalTimers.values, ...highlightTimers.values]) {
      timer.cancel();
    }
    removalTimers.clear();
    highlightTimers.clear();
  }

  @override
  void didUpdateWidget(ScriptKeyedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      _cancelTimers();
      consumedFeedback = widget.feedbackKey;
      entries = widget.items.map(_Entry.new).toList();
      return;
    }
    final fresh =
        widget.feedbackKey != null && widget.feedbackKey != consumedFeedback;
    if (widget.feedbackKey != null) consumedFeedback = widget.feedbackKey;
    final previous = {for (final entry in entries) entry.item.id: entry};
    final next = <_Entry>[];
    for (final item in widget.items) {
      final old = previous[item.id];
      removalTimers.remove(item.id)?.cancel();
      final highlight =
          !reduceMotion &&
          fresh &&
          old == null &&
          widget.highlightKeys.contains(item.id);
      next.add(
        _Entry(
          item,
          highlightKey: highlight ? widget.feedbackKey : old?.highlightKey,
        ),
      );
      if (highlight) {
        highlightTimers.remove(item.id)?.cancel();
        highlightTimers[item.id] = Timer(const Duration(milliseconds: 900), () {
          highlightTimers.remove(item.id);
          if (!mounted) return;
          setState(() {
            entries = [
              for (final entry in entries)
                if (entry.item.id == item.id)
                  _Entry(entry.item, removing: entry.removing)
                else
                  entry,
            ];
          });
        });
      }
    }
    final present = widget.items.map((item) => item.id).toSet();
    for (var i = 0; i < entries.length; i++) {
      final old = entries[i];
      final id = old.item.id;
      if (present.contains(id)) continue;
      highlightTimers.remove(id)?.cancel();
      if (!reduceMotion &&
          (old.removing || fresh && widget.removeKeys.contains(id))) {
        next.insert(i.clamp(0, next.length), _Entry(old.item, removing: true));
        // The parent timer also retires offscreen lazy rows. Refreshes and
        // subsequent commits preserve the original removal deadline.
        removalTimers.putIfAbsent(
          id,
          () => Timer(widget.duration, () {
            removalTimers.remove(id);
            if (!mounted) return;
            setState(() => entries.removeWhere((entry) => entry.item.id == id));
          }),
        );
      } else {
        removalTimers.remove(id)?.cancel();
      }
    }
    entries = next;
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  Widget _row(_Entry entry) => _ScriptListRow(
    key: ValueKey((widget.scope, entry.item.id)),
    removing: entry.removing,
    highlightKey: entry.highlightKey,
    duration: widget.duration,
    spacing: widget.spacing,
    child: Builder(builder: entry.item.builder),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.scrollController != null) {
      final indices = {
        for (var i = 0; i < entries.length; i++)
          ValueKey((widget.scope, entries[i].item.id)): i,
      };
      return ListView.builder(
        controller: widget.scrollController,
        padding: widget.padding,
        itemCount: entries.length,
        findChildIndexCallback: (key) => indices[key],
        itemBuilder: (_, index) => _row(entries[index]),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: entries.map(_row).toList(),
    );
  }
}

class _ScriptListRow extends StatefulWidget {
  const _ScriptListRow({
    super.key,
    required this.child,
    required this.removing,
    required this.highlightKey,
    required this.duration,
    required this.spacing,
  });

  final Widget child;
  final bool removing;
  final Object? highlightKey;
  final Duration duration;
  final double spacing;

  @override
  State<_ScriptListRow> createState() => _ScriptListRowState();
}

class _ScriptListRowState extends State<_ScriptListRow>
    with TickerProviderStateMixin {
  late final exit = AnimationController(
    vsync: this,
    value: 1,
    duration: widget.duration,
  );
  late final highlight = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 900),
  );
  late final exitCurve = CurvedAnimation(parent: exit, curve: AppMotion.leave);
  bool initialized = false;
  bool reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = AppMotion.reduced(context);
    if (reduced) {
      exit.value = widget.removing ? 0 : 1;
      highlight.value = 1;
    } else if (!initialized) {
      if (widget.removing) exit.reverse();
      if (widget.highlightKey != null) highlight.forward(from: 0);
    }
    initialized = true;
  }

  @override
  void didUpdateWidget(_ScriptListRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    exit.duration = widget.duration;
    if (widget.removing != oldWidget.removing) {
      if (reduced) {
        exit.value = widget.removing ? 0 : 1;
      } else if (widget.removing) {
        exit.reverse();
      } else {
        exit.forward();
      }
    }
    if (widget.highlightKey != oldWidget.highlightKey) {
      if (reduced || widget.highlightKey == null) {
        highlight.value = 1;
      } else {
        highlight.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    exitCurve.dispose();
    exit.dispose();
    highlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: exitCurve,
    alignment: Alignment.topCenter,
    child: FadeTransition(
      opacity: exitCurve,
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.spacing),
        child: IgnorePointer(
          ignoring: widget.removing,
          child: ExcludeFocus(
            excluding: widget.removing,
            child: ExcludeSemantics(
              excluding: widget.removing,
              child: AnimatedBuilder(
                animation: highlight,
                child: widget.child,
                builder: (context, child) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer
                        .withValues(alpha: .45 * (1 - highlight.value)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
