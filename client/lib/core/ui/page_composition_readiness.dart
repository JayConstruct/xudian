import 'dart:async';

import 'package:flutter/material.dart';

/// Inline pages stay mounted while their initial asynchronous content arrives.
/// The composition appears together, and retains its content during refreshes.
class PageCompositionReadiness extends ChangeNotifier {
  final pending = <String, Set<Object>>{};
  final ready = <String>{};
  final contextControllers = <String>{};
  int generation = 0;
  bool hasDisplayed = false;
  bool _scheduled = false, _disposed = false;

  bool get waiting =>
      ready.length != pending.length ||
      pending.values.any((owners) => owners.isNotEmpty);

  void configure(Iterable<String> ids) {
    generation++;
    pending
      ..clear()
      ..addEntries(ids.map((id) => MapEntry(id, <Object>{})));
    ready.clear();
    contextControllers.removeWhere((id) => !pending.containsKey(id));
  }

  void allowContextChanges(String id, int version) {
    if (version != generation || !pending.containsKey(id)) return;
    contextControllers.add(id);
  }

  void begin(String id, Object owner, int version) {
    if (version != generation || !pending.containsKey(id)) return;
    pending[id]!.add(owner);
    ready.remove(id);
    _notifyLater();
  }

  void complete(String id, Object owner, int version) {
    if (version != generation || !pending.containsKey(id)) return;
    pending[id]!.remove(owner);
    if (pending[id]!.isEmpty) ready.add(id);
    if (!waiting) hasDisplayed = true;
    _notifyLater();
  }

  void _notifyLater() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class PageCompositionReadinessScope extends InheritedWidget {
  const PageCompositionReadinessScope({
    super.key,
    required this.controller,
    required this.memberId,
    required this.generation,
    required super.child,
  });
  final PageCompositionReadiness controller;
  final String memberId;
  final int generation;

  void begin(Object owner) => controller.begin(memberId, owner, generation);
  void complete(Object owner) =>
      controller.complete(memberId, owner, generation);
  void allowContextChanges() =>
      controller.allowContextChanges(memberId, generation);
  static PageCompositionReadinessScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PageCompositionReadinessScope>();

  @override
  bool updateShouldNotify(PageCompositionReadinessScope oldWidget) =>
      generation != oldWidget.generation || memberId != oldWidget.memberId;
}

class PageCompositionReadyGroup extends StatefulWidget {
  const PageCompositionReadyGroup({
    super.key,
    required this.identity,
    required this.memberIds,
    required this.children,
  });
  final String identity;
  final List<String> memberIds;
  final List<Widget> children;

  @override
  State<PageCompositionReadyGroup> createState() =>
      _PageCompositionReadyGroupState();
}

class _PageCompositionReadyGroupState extends State<PageCompositionReadyGroup> {
  final readiness = PageCompositionReadiness();
  Timer? progressTimer;
  bool showProgress = false;

  void readinessChanged() {
    progressTimer?.cancel();
    if (!readiness.waiting) {
      if (showProgress) setState(() => showProgress = false);
    } else if (readiness.hasDisplayed) {
      if (!showProgress) setState(() => showProgress = true);
    } else {
      progressTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted && readiness.waiting) setState(() => showProgress = true);
      });
    }
  }

  void configure() {
    readiness.configure(widget.memberIds);
    final generation = readiness.generation;
    // Native pages and mount diagnostics have no asynchronous renderer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final id in widget.memberIds) {
        if (readiness.pending[id]?.isEmpty == true) {
          readiness.complete(id, this, generation);
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    readiness.addListener(readinessChanged);
    configure();
    readinessChanged();
  }

  @override
  void didUpdateWidget(PageCompositionReadyGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.identity != oldWidget.identity ||
        widget.memberIds.join('|') != oldWidget.memberIds.join('|')) {
      configure();
      readinessChanged();
    }
  }

  @override
  void dispose() {
    progressTimer?.cancel();
    readiness.removeListener(readinessChanged);
    readiness.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: readiness,
    builder: (context, _) => Stack(
      children: [
        Opacity(
          opacity: readiness.hasDisplayed || !readiness.waiting ? 1 : 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.memberIds.length; i++)
                IgnorePointer(
                  key: ValueKey(widget.memberIds[i]),
                  ignoring:
                      readiness.waiting &&
                      (!readiness.hasDisplayed ||
                          !readiness.contextControllers.contains(
                            widget.memberIds[i],
                          )),
                  child: ExcludeSemantics(
                    excluding:
                        readiness.waiting &&
                        (!readiness.hasDisplayed ||
                            !readiness.contextControllers.contains(
                              widget.memberIds[i],
                            )),
                    child: PageCompositionReadinessScope(
                      controller: readiness,
                      memberId: widget.memberIds[i],
                      generation: readiness.generation,
                      child: widget.children[i],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (showProgress && readiness.waiting)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    ),
  );
}
