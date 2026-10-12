import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'ui_motion.dart';
import 'date_wave_lens.dart';

/// Captures the currently painted date before its asynchronous content changes.
/// Navigation controls can be outside [DateReveal] or marked with
/// [DateRevealNavigation] while the host blocks business interactions.
class DateRevealController extends ChangeNotifier {
  _DateRevealState? _state;
  final _navigation = <_RenderDateRevealNavigation>{};
  bool _isTransitioning = false, _isPreparing = false;
  bool _notificationScheduled = false, _disposed = false;

  bool get isTransitioning => _isTransitioning;
  bool get isPreparing => _isPreparing;

  void _status({required bool transitioning, required bool preparing}) {
    if (_isTransitioning == transitioning && _isPreparing == preparing) return;
    _isTransitioning = transitioning;
    _isPreparing = preparing;
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_notificationScheduled) return;
      _notificationScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notificationScheduled = false;
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _state = null;
    _isTransitioning = false;
    _isPreparing = false;
    _navigation.clear();
    super.dispose();
  }

  void _detach(_DateRevealState state) {
    if (_state != state) return;
    _state = null;
    _status(transitioning: false, preparing: false);
  }

  void prepare({
    Offset? originGlobal,
    double initialRadius = 0,
    bool swipe = false,
    int direction = 1,
  }) => _state?._prepare(
    originGlobal: originGlobal,
    initialRadius: initialRadius,
    swipe: swipe,
    direction: direction,
  );

  /// Restores the live content when an interaction did not change the date.
  void cancel() => _state?._finish();
}

class DateRevealScope extends InheritedNotifier<DateRevealController> {
  const DateRevealScope({
    super.key,
    required DateRevealController controller,
    required super.child,
  }) : super(notifier: controller);

  static DateRevealController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DateRevealScope>()?.notifier;

  static DateRevealController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DateRevealScope>()?.notifier;
}

/// Marks live navigation paint that must stay visible over the frozen image.
/// The host uses `blockInteraction: false` and independently excludes its
/// business controls from interaction and semantics during a transition.
class DateRevealNavigation extends StatelessWidget {
  const DateRevealNavigation({super.key, this.controller, required this.child});

  final DateRevealController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => _DateRevealNavigationMarker(
    controller: controller ?? DateRevealScope.of(context),
    child: child,
  );
}

class _DateRevealNavigationMarker extends SingleChildRenderObjectWidget {
  const _DateRevealNavigationMarker({
    required this.controller,
    required super.child,
  });

  final DateRevealController? controller;

  @override
  _RenderDateRevealNavigation createRenderObject(BuildContext context) =>
      _RenderDateRevealNavigation(controller);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDateRevealNavigation renderObject,
  ) => renderObject.controller = controller;
}

class _RenderDateRevealNavigation extends RenderProxyBox {
  _RenderDateRevealNavigation(this._controller);
  DateRevealController? _controller;

  set controller(DateRevealController? controller) {
    if (_controller == controller) return;
    _controller?._navigation.remove(this);
    _controller = controller;
    if (attached) _controller?._navigation.add(this);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller?._navigation.add(this);
  }

  @override
  void detach() {
    _controller?._navigation.remove(this);
    super.detach();
  }
}

List<Rect> _navigationRects(
  DateRevealController controller,
  RenderBox target,
) => [
  for (final navigation in controller._navigation)
    if (navigation.attached && navigation.hasSize)
      Rect.fromPoints(
        target.globalToLocal(navigation.localToGlobal(Offset.zero)),
        target.globalToLocal(
          navigation.localToGlobal(navigation.size.bottomRight(Offset.zero)),
        ),
      ),
];

/// Keeps one actual subtree mounted. The old view is an inert image, never a
/// second script runtime. A new complete paint is revealed after [ready].
class DateReveal extends StatefulWidget {
  const DateReveal({
    super.key,
    required this.controller,
    required this.revision,
    required this.ready,
    required this.child,
    this.duration = AppMotion.dateReveal,
    this.swipeDuration = AppMotion.dateRevealSwipe,
    this.blockInteraction = true,
  });

  final DateRevealController controller;
  final Object revision;
  final bool ready;
  final Widget child;
  final Duration duration;
  final Duration swipeDuration;
  final bool blockInteraction;

  @override
  State<DateReveal> createState() => _DateRevealState();
}

class _DateRevealState extends State<DateReveal>
    with SingleTickerProviderStateMixin {
  final boundaryKey = GlobalKey();
  final targetBoundaryKey = GlobalKey();
  late final AnimationController animation =
      AnimationController(vsync: this, duration: widget.duration, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _finish();
        });
  ui.Image? snapshot;
  ui.Image? targetSnapshot;
  Size? targetSnapshotSize;
  Size? snapshotSize;
  List<Rect> snapshotNavigation = const [];
  Offset? originGlobal;
  double initialRadius = 0;
  bool swipe = false;
  int direction = 1;
  bool prepared = false;
  bool revealScheduled = false;
  bool armed = false;
  int request = 0;

  bool get reduced =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.highContrastOf(context);

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  void _prepare({
    Offset? originGlobal,
    double initialRadius = 0,
    bool swipe = false,
    int direction = 1,
  }) {
    if (!mounted) return;
    request++;
    armed = true;
    revealScheduled = false;
    animation.stop();
    _clearTargetSnapshot();
    final boundary = boundaryKey.currentContext?.findRenderObject();
    // A second selection while waiting keeps the last complete frozen image.
    // During a reveal, capture its current composite for visual continuity.
    if ((!prepared || animation.value > 0) &&
        boundary is RenderRepaintBoundary &&
        boundary.hasSize &&
        !boundary.debugNeedsPaint &&
        !boundary.size.isEmpty) {
      final area = boundary.size.width * boundary.size.height;
      // The old view and the optional lens texture share an 8 MP upper budget.
      final ratio = math.min(2.0, math.sqrt(4000000 / math.max(1, area)));
      final image = boundary.toImageSync(pixelRatio: ratio);
      final old = snapshot;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      snapshot = image;
      snapshotSize = boundary.size;
      snapshotNavigation = _navigationRects(widget.controller, boundary);
    }
    this.originGlobal = originGlobal;
    this.initialRadius = math.max(0, initialRadius);
    this.swipe = swipe;
    this.direction = direction < 0 ? -1 : 1;
    prepared = true;
    animation.value = 0;
    widget.controller._status(transitioning: true, preparing: true);
    setState(() {});
  }

  void _finish() {
    if (!mounted) return;
    request++;
    revealScheduled = false;
    animation.stop();
    _clearTargetSnapshot();
    final old = snapshot;
    snapshot = null;
    snapshotSize = null;
    snapshotNavigation = const [];
    prepared = false;
    armed = false;
    widget.controller._status(transitioning: false, preparing: false);
    // Keep a paint already scheduled with the old image valid until this frame.
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    setState(() {});
  }

  void _clearTargetSnapshot() {
    final old = targetSnapshot;
    targetSnapshot = null;
    targetSnapshotSize = null;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  void _captureTargetSnapshot() {
    if (swipe || reduced || targetSnapshot != null) return;
    final boundary = targetBoundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary ||
        !boundary.hasSize ||
        boundary.debugNeedsPaint ||
        boundary.size.isEmpty) {
      return;
    }
    final area = boundary.size.width * boundary.size.height;
    final ratio = math.min(2.0, math.sqrt(4000000 / math.max(1, area)));
    try {
      targetSnapshot = boundary.toImageSync(pixelRatio: ratio);
      targetSnapshotSize = boundary.size;
    } on Exception {
      // A missing texture only omits the decorative lens. Content and the
      // original reveal still use the actual mounted subtree.
    }
  }

  void _revealAfterPaint() {
    if (!prepared || !widget.ready || revealScheduled) return;
    revealScheduled = true;
    final expected = request;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || expected != request || !widget.ready) return;
      revealScheduled = false;
      if (reduced || snapshot == null) {
        _finish();
      } else {
        _captureTargetSnapshot();
        widget.controller._status(transitioning: true, preparing: false);
        animation.duration = swipe ? widget.swipeDuration : widget.duration;
        animation.forward(from: 0);
      }
    });
  }

  @override
  void didUpdateWidget(DateReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    final explicitlyPrepared = armed;
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._detach(this);
      widget.controller._state = this;
      widget.controller._status(
        transitioning: prepared,
        preparing: prepared && animation.value == 0,
      );
    }
    animation.duration = swipe ? widget.swipeDuration : widget.duration;
    if (oldWidget.revision != widget.revision) {
      if (!armed && (oldWidget.ready || prepared)) _prepare();
      armed = false;
    }
    if (!widget.ready &&
        oldWidget.ready &&
        !explicitlyPrepared &&
        oldWidget.revision == widget.revision) {
      _prepare(
        originGlobal: prepared ? originGlobal : null,
        initialRadius: prepared ? initialRadius : 0,
        swipe: prepared && swipe,
        direction: direction,
      );
      armed = false;
    }
    _revealAfterPaint();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (prepared && reduced && widget.ready) _finish();
  }

  @override
  void dispose() {
    widget.controller._detach(this);
    animation.dispose();
    snapshot?.dispose();
    targetSnapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _revealAfterPaint();
    return RepaintBoundary(
      key: boundaryKey,
      child: AnimatedBuilder(
        animation: animation,
        child: RepaintBoundary(
          key: targetBoundaryKey,
          child: IgnorePointer(
            ignoring: prepared && widget.blockInteraction,
            child: ExcludeSemantics(
              excluding: prepared && widget.blockInteraction,
              child: widget.child,
            ),
          ),
        ),
        builder: (context, child) => _DateRevealPaint(
          image: snapshot,
          imageSize: snapshotSize,
          targetImage: targetSnapshot,
          targetImageSize: targetSnapshotSize,
          snapshotNavigation: snapshotNavigation,
          controller: widget.controller,
          progress: prepared
              ? (swipe ? Curves.easeOutCubic : Curves.easeOutQuad).transform(
                  animation.value,
                )
              : 1,
          originGlobal: originGlobal,
          initialRadius: initialRadius,
          swipe: swipe,
          direction: direction,
          background: Theme.of(context).scaffoldBackgroundColor,
          rim: Theme.of(context).colorScheme.primary,
          child: child!,
        ),
      ),
    );
  }
}

class _DateRevealPaint extends SingleChildRenderObjectWidget {
  const _DateRevealPaint({
    required this.image,
    required this.imageSize,
    required this.targetImage,
    required this.targetImageSize,
    required this.snapshotNavigation,
    required this.controller,
    required this.progress,
    required this.originGlobal,
    required this.initialRadius,
    required this.swipe,
    required this.direction,
    required this.background,
    required this.rim,
    required super.child,
  });
  final ui.Image? image;
  final ui.Image? targetImage;
  final Size? imageSize;
  final Size? targetImageSize;
  final List<Rect> snapshotNavigation;
  final DateRevealController controller;
  final double progress, initialRadius;
  final Offset? originGlobal;
  final bool swipe;
  final int direction;
  final Color background, rim;

  @override
  _RenderDateReveal createRenderObject(BuildContext context) =>
      _RenderDateReveal(this);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDateReveal renderObject,
  ) {
    renderObject.configuration = this;
  }
}

class _RenderDateReveal extends RenderProxyBox {
  _RenderDateReveal(this._configuration);
  _DateRevealPaint _configuration;
  set configuration(_DateRevealPaint value) {
    _configuration = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final config = _configuration;
    final image = config.image;
    if (image == null || config.progress >= 1) {
      super.paint(context, offset);
      return;
    }
    final bounds = offset & size;
    final navigation = _navigationRects(config.controller, this);
    // Paint the real subtree once, unmasked, into its retained boundary. The
    // previous image covers the unrevealed area; the ready frame can therefore
    // be sampled once for the lens without running another page or waiting an
    // extra frame. A composited child layer must never be painted twice.
    context.canvas.drawRect(bounds, Paint()..color = config.background);
    super.paint(context, offset);
    final origin = config.originGlobal == null
        ? size.center(Offset.zero)
        : globalToLocal(config.originGlobal!);
    final maxRadius = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((corner) => (corner - origin).distance).reduce(math.max);
    final radius = ui.lerpDouble(
      config.initialRadius,
      math.max(maxRadius, config.initialRadius) + 2,
      config.progress,
    )!;
    final reveal = Path();
    for (final rect in navigation) {
      reveal.addRect(rect);
    }
    if (config.progress > 0) {
      if (config.swipe) {
        reveal.addRect(
          Rect.fromLTWH(
            config.direction > 0 ? size.width * (1 - config.progress) : 0,
            0,
            size.width * config.progress,
            size.height,
          ),
        );
      } else {
        reveal.addOval(Rect.fromCircle(center: origin, radius: radius));
      }
    }
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (
      clippedContext,
      clippedOffset,
    ) {
      clippedContext.pushClipPath(
        needsCompositing,
        clippedOffset,
        Offset.zero & size,
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          reveal,
        ),
        (paintContext, paintOffset) {
          final canvas = paintContext.canvas;
          canvas.drawRect(
            paintOffset & size,
            Paint()..color = config.background,
          );
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            paintOffset & config.imageSize!,
            Paint()..filterQuality = FilterQuality.low,
          );
          for (final rect in [...config.snapshotNavigation, ...navigation]) {
            canvas.drawRect(
              rect.shift(paintOffset),
              Paint()..color = config.background,
            );
          }
        },
      );
      if (!config.swipe && config.progress > 0) {
        final canvas = clippedContext.canvas;
        // A broad gradient makes the front visible without distorting content
        // or using a blur/saveLayer. Live navigation keeps its exact colours.
        canvas.save();
        if (navigation.isNotEmpty) {
          final live = Path();
          for (final rect in navigation) {
            live.addRect(rect.shift(clippedOffset));
          }
          canvas.clipPath(
            Path.combine(
              PathOperation.difference,
              Path()..addRect(clippedOffset & size),
              live,
            ),
          );
        }
        final width = (size.shortestSide * .14).clamp(32.0, 56.0);
        final outer = radius + width / 2;
        final inner = math.max(0.0, radius - width / 2);
        final visibility =
            math.min(1.0, config.progress / .08) *
            math.min(1.0, (1 - config.progress) / .18);
        final center = clippedOffset + origin;
        if (config.targetImage case final ui.Image target) {
          canvas.save();
          canvas.translate(clippedOffset.dx, clippedOffset.dy);
          paintDateWaveLens(
            canvas,
            oldImage: image,
            newImage: target,
            oldSize: config.imageSize!,
            newSize: config.targetImageSize!,
            origin: origin,
            radius: radius,
            width: width,
            strength: visibility,
            bounds: Offset.zero & size,
            navigation: [...navigation, ...config.snapshotNavigation],
          );
          canvas.restore();
        }
        final transparent = config.rim.withValues(alpha: 0);
        canvas.drawCircle(
          center,
          outer,
          Paint()
            ..shader = ui.Gradient.radial(
              center,
              outer,
              [
                transparent,
                transparent,
                config.rim.withValues(alpha: .14 * visibility),
                transparent,
              ],
              [0, inner / outer, radius / outer, 1],
            ),
        );
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = config.rim.withValues(alpha: .18 * visibility)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        // Thin bright/dark shoulders give the lens a rounded water surface;
        // neither survives after the normal content has been fully revealed.
        for (final shoulder in [
          (
            radius - width * .20,
            Colors.white.withValues(alpha: .16 * visibility),
          ),
          (
            radius + width * .20,
            Colors.black.withValues(alpha: .045 * visibility),
          ),
        ]) {
          canvas.drawCircle(
            center,
            math.max(0, shoulder.$1),
            Paint()
              ..color = shoulder.$2
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
        canvas.restore();
      }
    });
  }
}
