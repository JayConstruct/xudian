part of 'planner_board.dart';

const _hoursRevealDistance = 72.0;

String _hoursLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

// A change to the first displayed hour moves the scroll origin. Apply that
// displacement during layout, preserving any active scroll or task gesture.
class _PlannerHoursScrollController extends ScrollController {
  double? anchoredOffset;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _PlannerHoursPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    controller: this,
  );
}

class _PlannerHoursPosition extends ScrollPositionWithSingleContext {
  _PlannerHoursPosition({
    required super.physics,
    required super.context,
    required super.oldPosition,
    required this.controller,
  });
  final _PlannerHoursScrollController controller;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final target = controller.anchoredOffset;
    if (target != null) {
      controller.anchoredOffset = null;
      correctPixels(target.clamp(minScrollExtent, maxScrollExtent));
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

class _HoursPullIndicator extends StatelessWidget {
  const _HoursPullIndicator({
    required this.pull,
    required this.dragging,
    required this.bottomInset,
  });
  final ValueListenable<double> pull;
  final ValueListenable<bool> dragging;
  final double bottomInset;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ValueListenableBuilder<double>(
      valueListenable: pull,
      builder: (context, value, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, children: [...previous, ?current]),
        child: value == 0
            ? const SizedBox.shrink()
            : Align(
                key: ValueKey(value.sign),
                alignment: value < 0
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 8, bottom: bottomInset + 8),
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 21,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Positioned.fill(
                                  child: CircularProgressIndicator(
                                    value: value.abs() / _hoursRevealDistance,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                    strokeWidth: 2,
                                  ),
                                ),
                                Icon(
                                  (value < 0) == dragging.value
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  size: 13,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            dragging.value
                                ? (value < 0 ? '继续向上拖，显示全天' : '继续向下拖，显示全天')
                                : (value < 0 ? '继续下拉，显示全天' : '继续上拉，显示全天'),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}
