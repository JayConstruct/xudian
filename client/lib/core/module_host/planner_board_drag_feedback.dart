part of 'planner_board.dart';

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
