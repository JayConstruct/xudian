part of 'planner_board.dart';

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
    final edgeStatus = item['statusIndicator'] == 'edgeToCorner';
    final appearance = PlannerCardAppearance.of(item);
    final titleStyle = theme.textTheme.labelMedium!.copyWith(
      decoration:
          appearance.lineThrough || item['completed'] == true && !edgeStatus
          ? TextDecoration.lineThrough
          : null,
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
    final icon = edgeStatus
        ? null
        : item['completed'] == true
        ? Icons.check_circle_outline
        : item['_titleLines'] != 2 &&
              item['readOnly'] != true &&
              item['fixed'] == true
        ? Icons.lock_rounded
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        _contentHeight = constraints.maxHeight;
        final geometry = _geometry(constraints.maxHeight);
        _twoLineTitleHeight =
            item['_titleLines'] == 2 && item['readOnly'] != true
            ? scaler.scale(11) * 1.15 * 2
            : null;
        final rows = <({String key, String text, TextStyle style, int? lines})>[
          (
            key: 'title',
            text: '$continuation${item['title'] ?? ''}',
            style: titleStyle,
            lines:
                _twoLineTitleHeight != null &&
                    geometry.available + .01 >= _twoLineTitleHeight!
                ? 2
                : item['readOnly'] == true
                ? null
                : 1,
          ),
          if (item['showLocation'] != false &&
              '${item['location'] ?? ''}'.trim().isNotEmpty)
            (
              key: 'location',
              text: '${item['location']}'.trim(),
              style: detailStyle,
              lines: 2,
            ),
          if (item['showTeacher'] != false &&
              '${item['teacher'] ?? ''}'.trim().isNotEmpty)
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
                      softWrap: true,
                      maxLines: row.lines,
                      overflow: row.lines == null
                          ? TextOverflow.clip
                          : TextOverflow.ellipsis,
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
