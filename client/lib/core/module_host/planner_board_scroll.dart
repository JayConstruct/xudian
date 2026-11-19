part of 'planner_board.dart';

class _PlannerLinkedScrollController extends ScrollController {
  _PlannerLinkedScrollController? peer;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _PlannerLinkedScrollPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    stopPeer: () => peer?.stop(),
  );

  void follow(double value) =>
      (position as _PlannerLinkedScrollPosition).follow(value);

  void stop() {
    if (hasClients && position.isScrollingNotifier.value) {
      (position as _PlannerLinkedScrollPosition).goIdle();
    }
  }
}

class _PlannerLinkedScrollPosition extends ScrollPositionWithSingleContext {
  _PlannerLinkedScrollPosition({
    required super.physics,
    required super.context,
    required super.initialPixels,
    required super.keepScrollOffset,
    super.oldPosition,
    required this.stopPeer,
  });

  final VoidCallback stopPeer;

  void follow(double value) {
    goIdle();
    if (pixels == value) return;
    final previous = pixels;
    forcePixels(value);
    didUpdateScrollPositionBy(value - previous);
  }

  @override
  ScrollHoldController hold(VoidCallback holdCancelCallback) {
    stopPeer();
    return super.hold(holdCancelCallback);
  }
}

class _PlannerDayScrollPhysics extends ScrollPhysics {
  const _PlannerDayScrollPhysics(
    this.columnWidth, {
    this.dragOrigin,
    super.parent,
  });
  final double columnWidth;
  final double? Function()? dragOrigin;

  @override
  double get minFlingDistance => 12;

  @override
  _PlannerDayScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _PlannerDayScrollPhysics(
        columnWidth,
        dragOrigin: dragOrigin,
        parent: buildParent(ancestor),
      );

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final projected = position.pixels + velocity * .18;
    var column = (projected / columnWidth).round();
    if (velocity.abs() >= minFlingVelocity) {
      column = velocity > 0
          ? math.max(column, (position.pixels / columnWidth).ceil())
          : math.min(column, (position.pixels / columnWidth).floor());
    } else {
      final origin = dragOrigin?.call();
      if (origin != null &&
          (position.pixels - origin).abs() >= columnWidth * .25) {
        column = position.pixels > origin
            ? math.max(column, (origin / columnWidth).floor() + 1)
            : math.min(column, (origin / columnWidth).ceil() - 1);
      }
    }
    final target = (column * columnWidth).clamp(
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
