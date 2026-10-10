import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final uiAnnotationProvider = NotifierProvider<UiAnnotationController, bool>(
  UiAnnotationController.new,
);

class UiAnnotationController extends Notifier<bool> {
  final _changes = ValueNotifier<int>(0);
  final _records = <_AnnotationRecord>[];
  _RenderAnnotationAnchor? _controls;
  bool _hidden = false;
  bool _inspecting = false;
  bool _queued = false;
  bool _disposed = false;
  int _nextNumber = 0;
  NavigatorState? _inspectionNavigator;
  ModalRoute<dynamic>? _inspectionRoute;

  bool get isHidden => _hidden;

  @override
  bool build() {
    ref.onDispose(() {
      _disposed = true;
      _changes.dispose();
    });
    return false;
  }

  void setEnabled(bool enabled) {
    if (state == enabled) return;
    _hidden = false;
    if (enabled) {
      _nextNumber = 0;
      for (final record in _records) {
        record.number = null;
      }
    }
    state = enabled;
    if (!enabled) {
      final route = _inspectionRoute;
      final navigator = _inspectionNavigator;
      if (route != null &&
          route.isActive &&
          navigator != null &&
          navigator.mounted) {
        navigator.removeRoute(route);
      }
    }
    _scheduleRefresh(force: true);
  }

  void setHidden(bool hidden) {
    if (!state || _hidden == hidden) return;
    _hidden = hidden;
    _scheduleRefresh(force: true);
  }

  void toggleHidden() => setHidden(!_hidden);

  bool get _visible => !_disposed && state && !_hidden && !_inspecting;

  void _scheduleRefresh({bool force = false}) {
    if (_disposed || _queued || (!force && !_visible)) return;
    _queued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!_disposed) _refresh();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _refresh() {
    final geometries = <_AnnotationRecord, _AnnotationGeometry>{};
    if (_visible) {
      for (final record in _records) {
        if (!record.active || !record.context.mounted) continue;
        final geometry = record.anchor?.geometry(record.context);
        if (geometry != null) {
          record.number ??= 'U${(++_nextNumber).toString().padLeft(2, '0')}';
          geometries[record] = geometry;
        }
      }
    }
    final ordered = geometries.keys.toList()
      ..sort((first, second) {
        final firstGeometry = geometries[first]!;
        final secondGeometry = geometries[second]!;
        final depth = secondGeometry.depth.compareTo(firstGeometry.depth);
        if (depth != 0) return depth;
        return (firstGeometry.bounds.width * firstGeometry.bounds.height)
            .compareTo(
              secondGeometry.bounds.width * secondGeometry.bounds.height,
            );
      });
    final occupied = <Rect>[];
    final controls = _controls;
    if (controls != null && controls.attached && controls.hasSize) {
      occupied.add(
        MatrixUtils.transformRect(
          controls.getTransformTo(null),
          controls.paintBounds,
        ).inflate(4),
      );
    }
    for (final record in ordered) {
      final geometry = geometries[record]!;
      final style = Theme.of(record.context).textTheme.labelSmall!;
      final scaler = MediaQuery.textScalerOf(record.context);
      final maxWidth = math.min(240.0, geometry.clip.width);
      final painter = TextPainter(
        text: TextSpan(text: record.label, style: style),
        textDirection: Directionality.of(record.context),
        textScaler: scaler,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, maxWidth - 12));
      final labelSize = Size(
        math.min(maxWidth, painter.width + 12),
        math.max(32, painter.height + 8),
      );
      painter.dispose();
      record.placement = _placeLabel(
        geometry,
        labelSize,
        occupied,
        geometries.values.map((value) => value.bounds.center),
      );
      if (record.placement != null) occupied.add(record.placement!.inflate(2));
    }
    for (final record in _records) {
      if (!geometries.containsKey(record)) record.placement = null;
      final show = record.placement != null;
      if (show && !record.portal.isShowing) record.portal.show();
      if (!show && record.portal.isShowing) record.portal.hide();
    }
    _changes.value++;
  }

  Rect? _placeLabel(
    _AnnotationGeometry geometry,
    Size size,
    List<Rect> occupied,
    Iterable<Offset> targetCenters,
  ) {
    final clip = geometry.clip;
    if (size.width <= 0 || size.height > clip.height) return null;
    final bounds = geometry.bounds.intersect(clip);
    final candidates = <Offset>[
      Offset(bounds.left + 3, bounds.top + 3),
      Offset(bounds.left + 3, bounds.bottom - size.height - 3),
      Offset(bounds.right - size.width - 3, bounds.top + 3),
      Offset(bounds.left, bounds.top - size.height - 3),
      Offset(bounds.right - size.width, bounds.bottom + 3),
      Offset(bounds.right + 3, bounds.top),
      Offset(bounds.left - size.width - 3, bounds.bottom - size.height),
      Offset(bounds.left + 3, bounds.top + 3),
      Offset(bounds.right - size.width - 3, bounds.top + 3),
      Offset(bounds.left + 3, bounds.bottom - size.height - 3),
    ];
    for (var row = 1; row <= 3; row++) {
      candidates.add(
        Offset(bounds.left + 3, bounds.top + 3 + row * (size.height + 3)),
      );
      candidates.add(
        Offset(
          bounds.right - size.width - 3,
          bounds.top + 3 + row * (size.height + 3),
        ),
      );
    }
    for (final candidate in candidates) {
      final offset = Offset(
        candidate.dx.clamp(clip.left, clip.right - size.width),
        candidate.dy.clamp(clip.top, clip.bottom - size.height),
      );
      final rectangle = offset & size;
      if (occupied.any((other) => rectangle.overlaps(other))) continue;
      if (targetCenters.any(rectangle.contains)) continue;
      return rectangle;
    }
    return null;
  }
}

class UiAnnotation extends ConsumerStatefulWidget {
  const UiAnnotation({
    super.key,
    required this.id,
    required this.name,
    required this.child,
    this.moduleId = 'app.core.system',
    this.pagePath = '',
    this.slot = '',
    this.purpose = '',
  });

  final String id;
  final String name;
  final String moduleId;
  final String pagePath;
  final String slot;
  final String purpose;
  final Widget child;

  @override
  ConsumerState<UiAnnotation> createState() => _UiAnnotationState();
}

class _UiAnnotationState extends ConsumerState<UiAnnotation> {
  late final UiAnnotationController _controller;
  late final _AnnotationRecord _record;
  final _positions = <ScrollPosition>{};
  bool _tracking = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(uiAnnotationProvider.notifier);
    _record = _AnnotationRecord(context, widget);
    _controller._records.add(_record);
    _controller._changes.addListener(_visibilityChanged);
  }

  @override
  void didUpdateWidget(UiAnnotation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _record.metadata = widget;
    _controller._scheduleRefresh();
  }

  void _visibilityChanged() {
    if (!mounted) return;
    if (_tracking != (_controller._visible && _record.active)) {
      setState(() {});
    }
  }

  void _trackScroll(bool track) {
    _tracking = track;
    final next = <ScrollPosition>{};
    if (track) {
      context.visitAncestorElements((element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          next.add((element.state as ScrollableState).position);
        }
        return true;
      });
    }
    for (final position in _positions.difference(next)) {
      position.removeListener(_scrolled);
    }
    for (final position in next.difference(_positions)) {
      position.addListener(_scrolled);
    }
    _positions
      ..clear()
      ..addAll(next);
  }

  void _scrolled() => _controller._scheduleRefresh();

  @override
  void dispose() {
    for (final position in _positions) {
      position.removeListener(_scrolled);
    }
    if (!_controller._disposed) {
      _controller._changes.removeListener(_visibilityChanged);
    }
    _controller._records.remove(_record);
    _controller._scheduleRefresh();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(uiAnnotationProvider);
    _record.active = enabled && (ModalRoute.of(context)?.isCurrent ?? true);
    _trackScroll(_controller._visible && _record.active);
    _controller._scheduleRefresh();
    return OverlayPortal(
      controller: _record.portal,
      overlayChildBuilder: (overlayContext) => ValueListenableBuilder<int>(
        valueListenable: _controller._changes,
        builder: (context, revision, child) {
          final placement = _record.placement;
          if (!_controller._visible || placement == null) {
            return const SizedBox.shrink();
          }
          final overlay = Overlay.of(overlayContext).context.findRenderObject();
          final origin = overlay is RenderBox
              ? overlay.localToGlobal(Offset.zero)
              : Offset.zero;
          return Positioned(
            left: placement.left - origin.dx,
            top: placement.top - origin.dy,
            width: placement.width,
            height: placement.height,
            child: _AnnotationBadge(record: _record, onPressed: _inspect),
          );
        },
      ),
      child: _AnnotationAnchor(
        controller: _controller,
        record: _record,
        tracking: _tracking,
        child: widget.child,
      ),
    );
  }

  Future<void> _inspect() async {
    if (!_controller._visible) return;
    _controller._inspecting = true;
    _controller._scheduleRefresh(force: true);
    final description = _record.description;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          _controller._inspectionNavigator = Navigator.of(dialogContext);
          _controller._inspectionRoute = ModalRoute.of(dialogContext);
          return AlertDialog(
            title: const Text('界面标识'),
            content: SingleChildScrollView(child: SelectableText(description)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await Clipboard.setData(ClipboardData(text: description));
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (_) {
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.maybeOf(
                      dialogContext,
                    )?.showSnackBar(const SnackBar(content: Text('复制失败，请重试')));
                  }
                },
                child: const Text('复制标识'),
              ),
            ],
          );
        },
      );
    } finally {
      _controller._inspectionNavigator = null;
      _controller._inspectionRoute = null;
      _controller._inspecting = false;
      _controller._scheduleRefresh(force: true);
    }
  }
}

class AnnotationControls extends ConsumerStatefulWidget {
  const AnnotationControls({super.key, this.child});

  final Widget? child;

  @override
  ConsumerState<AnnotationControls> createState() => _AnnotationControlsState();
}

class _AnnotationControlsState extends ConsumerState<AnnotationControls> {
  Offset? _position;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(uiAnnotationProvider);
    final controller = ref.read(uiAnnotationProvider.notifier);
    return Overlay.wrap(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          const toolbarSize = Size(128, 48);
          final left = math.min(8.0, constraints.maxWidth - toolbarSize.width);
          final right = math.max(
            left,
            constraints.maxWidth - toolbarSize.width - 8,
          );
          final top = media.padding.top + 8;
          final bottom = math.max(
            top,
            constraints.maxHeight -
                math.max(media.viewInsets.bottom, media.padding.bottom) -
                toolbarSize.height -
                8,
          );
          final position = Offset(
            (_position?.dx ?? right).clamp(left, right),
            (_position?.dy ?? bottom).clamp(top, bottom),
          );
          return Stack(
            fit: StackFit.passthrough,
            children: [
              widget.child ?? const SizedBox.expand(),
              if (enabled)
                Positioned(
                  left: position.dx,
                  top: position.dy,
                  width: toolbarSize.width,
                  height: toolbarSize.height,
                  child: _AnnotationAnchor(
                    controller: controller,
                    tracking: true,
                    child: Material(
                      elevation: 4,
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: ValueListenableBuilder<int>(
                        valueListenable: controller._changes,
                        builder: (context, revision, child) => Row(
                          children: [
                            Semantics(
                              label: '拖动标注控制条，避开界面内容',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanUpdate: (details) => setState(() {
                                  _position = position + details.delta;
                                }),
                                child: const SizedBox(
                                  width: 32,
                                  height: 48,
                                  child: Icon(Icons.drag_indicator, size: 20),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: controller.isHidden ? '显示标注' : '暂时隐藏标注',
                              onPressed: controller.toggleHidden,
                              icon: Icon(
                                controller.isHidden
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                            IconButton(
                              tooltip: '退出界面标注',
                              onPressed: () => controller.setEnabled(false),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AnnotationRecord {
  _AnnotationRecord(this.context, this.metadata);

  final BuildContext context;
  final portal = OverlayPortalController();
  UiAnnotation metadata;
  _RenderAnnotationAnchor? anchor;
  bool active = false;
  String? number;
  Rect? placement;

  String get label => '$number · ${_clean(metadata.name)}';

  String get description =>
      '会话编号：$number\n名称：${_clean(metadata.name)}\n'
      'UI ID：${_clean(metadata.id)}\n模块：${_clean(metadata.moduleId)}\n'
      '页面路径：${_clean(metadata.pagePath)}\n槽位：${_clean(metadata.slot)}\n'
      '作用：${_clean(metadata.purpose)}';

  String _clean(String value) =>
      value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
}

class _AnnotationBadge extends StatelessWidget {
  const _AnnotationBadge({required this.record, required this.onPressed});

  final _AnnotationRecord record;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '标注：${record.label}',
    child: Material(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        key: ValueKey('ui-annotation-badge-${record.number}'),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            record.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ),
    ),
  );
}

class _AnnotationGeometry {
  const _AnnotationGeometry(this.bounds, this.clip, this.depth);

  final Rect bounds;
  final Rect clip;
  final int depth;
}

class _AnnotationAnchor extends SingleChildRenderObjectWidget {
  const _AnnotationAnchor({
    required this.controller,
    required this.tracking,
    required super.child,
    this.record,
  });

  final UiAnnotationController controller;
  final _AnnotationRecord? record;
  final bool tracking;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnnotationAnchor(controller, record, tracking);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderAnnotationAnchor renderObject,
  ) {
    renderObject.tracking = tracking;
  }
}

class _RenderAnnotationAnchor extends RenderProxyBox {
  _RenderAnnotationAnchor(this.controller, this.record, this.tracking);

  final UiAnnotationController controller;
  final _AnnotationRecord? record;
  bool tracking;
  Rect? _lastBounds;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (record == null) {
      controller._controls = this;
    } else {
      record!.anchor = this;
    }
    controller._scheduleRefresh();
  }

  @override
  void detach() {
    if (record == null) {
      if (identical(controller._controls, this)) controller._controls = null;
    } else {
      record!.anchor = null;
    }
    controller._scheduleRefresh();
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!tracking || !controller._visible) return;
    final bounds = MatrixUtils.transformRect(getTransformTo(null), paintBounds);
    if (_lastBounds != bounds) {
      _lastBounds = bounds;
      controller._scheduleRefresh();
    }
  }

  _AnnotationGeometry? geometry(BuildContext context) {
    if (!attached || !hasSize || size.isEmpty) return null;
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlay is! RenderBox || !overlay.hasSize) return null;
    final bounds = MatrixUtils.transformRect(getTransformTo(null), paintBounds);
    if (!bounds.isFinite || bounds.isEmpty) return null;
    var clip = MatrixUtils.transformRect(
      overlay.getTransformTo(null),
      Offset.zero & overlay.size,
    );
    final media = MediaQuery.of(context);
    final view = View.of(context);
    final deviceRatio = view.devicePixelRatio;
    clip = clip.intersect(
      Rect.fromLTRB(
        math.max(media.viewPadding.left, view.viewPadding.left / deviceRatio),
        math.max(media.viewPadding.top, view.viewPadding.top / deviceRatio),
        media.size.width -
            math.max(
              media.viewPadding.right,
              view.viewPadding.right / deviceRatio,
            ),
        media.size.height -
            math.max(
              media.viewInsets.bottom,
              math.max(
                media.viewPadding.bottom,
                view.viewPadding.bottom / deviceRatio,
              ),
            ),
      ),
    );
    var depth = 0;
    RenderObject descendant = this;
    RenderObject? ancestor = parent;
    while (ancestor != null) {
      if (ancestor is RenderOffstage && ancestor.offstage) return null;
      if (ancestor is _RenderAnnotationAnchor) depth++;
      final ancestorClip = ancestor.describeApproximatePaintClip(descendant);
      if (ancestorClip != null) {
        clip = clip.intersect(
          MatrixUtils.transformRect(
            ancestor.getTransformTo(null),
            ancestorClip,
          ),
        );
      }
      descendant = ancestor;
      ancestor = ancestor.parent;
    }
    if (!clip.isFinite || clip.isEmpty || !clip.overlaps(bounds)) return null;
    return _AnnotationGeometry(bounds, clip, depth);
  }
}
