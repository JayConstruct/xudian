import 'package:flutter/material.dart';

/// Moves pages past their edges without stretching the content itself.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      _PageScrollPhysics(parent: super.getScrollPhysics(context));
}

/// Horizontal surfaces retain their platform physics, including synchronized
/// date headers. Short vertical pages can still reveal space at either edge.
class _PageScrollPhysics extends ScrollPhysics {
  const _PageScrollPhysics({super.parent});

  static const _vertical = BouncingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );

  @override
  _PageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _PageScrollPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      position.axis == Axis.vertical
      ? _vertical.shouldAcceptUserOffset(position)
      : super.shouldAcceptUserOffset(position);

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      position.axis == Axis.vertical
      ? _vertical.applyPhysicsToUserOffset(position, offset)
      : super.applyPhysicsToUserOffset(position, offset);

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) =>
      position.axis == Axis.vertical
      ? _vertical.applyBoundaryConditions(position, value)
      : super.applyBoundaryConditions(position, value);

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => position.axis == Axis.vertical
      ? _vertical.createBallisticSimulation(position, velocity)
      : super.createBallisticSimulation(position, velocity);
}
