import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'ui_motion.dart';

/// Coordinates immediate background feedback and the latest ready date fade.
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
  void cancel() => _state?._finish(clearWaves: true);
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

/// Marks live navigation paint excluded from date fading and background waves.
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
/// second script runtime. Background waves start immediately; the latest
/// complete content fades in after [ready], independently of those waves.
class DateReveal extends StatefulWidget {
  const DateReveal({
    super.key,
    required this.controller,
    required this.revision,
    required this.ready,
    required this.child,
    this.duration = AppMotion.dateReveal,
    this.fadeDuration = AppMotion.dateContentFade,
    this.blockInteraction = true,
  });

  final DateRevealController controller;
  final Object revision;
  final bool ready;
  final Widget child;
  final Duration duration;
  final Duration fadeDuration;
  final bool blockInteraction;

  @override
  State<DateReveal> createState() => _DateRevealState();
}

class _BackgroundWave {
  const _BackgroundWave(this.started, this.originGlobal, this.initialRadius);

  final Duration started;
  final Offset? originGlobal;
  final double initialRadius;
}

class _DateRevealState extends State<DateReveal> with TickerProviderStateMixin {
  // Capture only the actual content, so decorative waves never enter an image.
  final contentBoundaryKey = GlobalKey();
  late final AnimationController animation =
      AnimationController(vsync: this, duration: widget.fadeDuration, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _finish();
        });
  late final Ticker waveTicker = createTicker(_tickWaves);
  final waves = <_BackgroundWave>[];
  Duration clock = Duration.zero;
  Duration tickerBase = Duration.zero;
  Duration? oldFadeStarted;
  Duration? lastWaveStarted;
  ui.Image? snapshot;
  Size? snapshotSize;
  List<Rect> snapshotNavigation = const [];
  bool prepared = false;
  bool revealScheduled = false;
  bool armed = false;
  int request = 0;

  bool get reduced =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.highContrastOf(context);

  double get oldOpacity {
    if (!prepared || snapshot == null) return 0;
    if (reduced) return 1;
    final elapsed = clock - (oldFadeStarted ?? clock);
    return 1 -
        Curves.easeOut.transform(
          (elapsed.inMicroseconds / AppMotion.dateContentLeave.inMicroseconds)
              .clamp(0.0, 1.0),
        );
  }

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  void _startWaves() {
    if (waveTicker.isActive) return;
    tickerBase = clock;
    waveTicker.start();
  }

  void _tickWaves(Duration elapsed) {
    clock = tickerBase + elapsed;
    waves.removeWhere((wave) => clock - wave.started >= widget.duration);
    if (waves.isEmpty && oldOpacity == 0) waveTicker.stop();
    setState(() {});
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
    // One old image for the entire burst. It fades out independently; clicks
    // during preparation or fading do not allocate another page-sized image.
    if (!prepared) {
      final boundary = contentBoundaryKey.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary &&
          boundary.hasSize &&
          !boundary.debugNeedsPaint &&
          !boundary.size.isEmpty) {
        final area = boundary.size.width * boundary.size.height;
        final ratio = math.min(2.0, math.sqrt(4000000 / math.max(1, area)));
        snapshot = boundary.toImageSync(pixelRatio: ratio);
        snapshotSize = boundary.size;
        snapshotNavigation = _navigationRects(widget.controller, boundary);
      }
      oldFadeStarted = clock;
    }
    if (!reduced) {
      // Coalesce decorative feedback under 80ms, never date intents. Every
      // wave shares this ticker and expires after 480ms, with at most 3 alive.
      if (!swipe &&
          (lastWaveStarted == null ||
              clock - lastWaveStarted! >= AppMotion.dateWaveSpacing)) {
        if (waves.length == 3) waves.removeAt(0);
        waves.add(
          _BackgroundWave(clock, originGlobal, math.max(0, initialRadius)),
        );
        lastWaveStarted = clock;
      }
      _startWaves();
    }
    prepared = true;
    animation.value = 0;
    widget.controller._status(transitioning: true, preparing: true);
    setState(() {});
  }

  void _finish({bool clearWaves = false}) {
    if (!mounted) return;
    request++;
    revealScheduled = false;
    animation.stop();
    final old = snapshot;
    snapshot = null;
    snapshotSize = null;
    snapshotNavigation = const [];
    oldFadeStarted = null;
    prepared = false;
    armed = false;
    widget.controller._status(transitioning: false, preparing: false);
    if (clearWaves) {
      waves.clear();
      lastWaveStarted = null;
    }
    if (waves.isEmpty) waveTicker.stop();
    // A render configuration scheduled earlier this frame can still use old.
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    setState(() {});
  }

  void _revealAfterPaint() {
    if (!prepared ||
        !widget.ready ||
        animation.isAnimating ||
        revealScheduled) {
      return;
    }
    revealScheduled = true;
    final expected = request;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || expected != request) return;
      revealScheduled = false;
      if (!widget.ready) return;
      if (reduced) {
        _finish();
      } else {
        // Readiness, not wave completion, starts the single latest-page fade.
        widget.controller._status(transitioning: true, preparing: false);
        animation.duration = widget.fadeDuration;
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
        preparing: prepared && !animation.isAnimating,
      );
    }
    animation.duration = widget.fadeDuration;
    if (oldWidget.revision != widget.revision) {
      if (!armed && (oldWidget.ready || prepared)) _prepare();
      armed = false;
    }
    if (!widget.ready &&
        oldWidget.ready &&
        !explicitlyPrepared &&
        oldWidget.revision == widget.revision) {
      _prepare(swipe: true);
      armed = false;
    }
    _revealAfterPaint();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduced) {
      waves.clear();
      waveTicker.stop();
      if (prepared && widget.ready) _finish();
    } else if (prepared || waves.isNotEmpty) {
      _startWaves();
    }
  }

  @override
  void dispose() {
    widget.controller._detach(this);
    animation.dispose();
    waveTicker.dispose();
    snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _revealAfterPaint();
    return AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(
        key: contentBoundaryKey,
        child: IgnorePointer(
          ignoring: prepared && widget.blockInteraction,
          child: ExcludeFocus(
            excluding: prepared && widget.blockInteraction,
            child: ExcludeSemantics(
              excluding: prepared && widget.blockInteraction,
              child: widget.child,
            ),
          ),
        ),
      ),
      builder: (context, child) => _DateRevealPaint(
        image: snapshot,
        imageSize: snapshotSize,
        snapshotNavigation: snapshotNavigation,
        controller: widget.controller,
        contentOpacity: prepared
            ? Curves.easeOut.transform(animation.value)
            : 1,
        oldOpacity: oldOpacity,
        waves: [
          for (final wave in waves)
            (
              originGlobal: wave.originGlobal,
              initialRadius: wave.initialRadius,
              progress:
                  ((clock - wave.started).inMicroseconds /
                          math.max(1, widget.duration.inMicroseconds))
                      .clamp(0.0, 1.0),
            ),
        ],
        background: Theme.of(context).scaffoldBackgroundColor,
        tint: Theme.of(context).colorScheme.primary,
        child: child!,
      ),
    );
  }
}

typedef _WavePaint = ({
  Offset? originGlobal,
  double initialRadius,
  double progress,
});

class _DateRevealPaint extends SingleChildRenderObjectWidget {
  const _DateRevealPaint({
    required this.image,
    required this.imageSize,
    required this.snapshotNavigation,
    required this.controller,
    required this.contentOpacity,
    required this.oldOpacity,
    required this.waves,
    required this.background,
    required this.tint,
    required super.child,
  });
  final ui.Image? image;
  final Size? imageSize;
  final List<Rect> snapshotNavigation;
  final DateRevealController controller;
  final double contentOpacity, oldOpacity;
  final List<_WavePaint> waves;
  final Color background, tint;

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
    // Paint exactly one mounted subtree. A translucent background cover fades
    // it in without an offscreen opacity layer, a texture mesh or refraction.
    context.canvas.drawRect(offset & size, Paint()..color = config.background);
    if (config.contentOpacity >= 1 && config.waves.isEmpty) {
      super.paint(context, offset);
      return;
    }
    final navigation = _navigationRects(config.controller, this);
    final live = Path();
    for (final rect in navigation) {
      live.addRect(rect);
    }
    final allowed = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      live,
    );
    context.canvas.save();
    context.canvas.clipPath(allowed.shift(offset));
    _paintWaves(context.canvas, offset);
    context.canvas.restore();
    super.paint(context, offset);
    if (config.contentOpacity >= 1) return;
    context.pushClipPath(
      needsCompositing,
      offset,
      Offset.zero & size,
      allowed,
      (paintContext, paintOffset) {
        final canvas = paintContext.canvas;
        final cover = 1 - config.contentOpacity;
        if (cover > 0) {
          canvas.drawRect(
            paintOffset & size,
            Paint()..color = config.background.withValues(alpha: cover),
          );
        }
        if (config.image case final ui.Image image when config.oldOpacity > 0) {
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            paintOffset & config.imageSize!,
            Paint()
              ..color = Colors.white.withValues(
                alpha: config.oldOpacity * cover,
              )
              ..filterQuality = FilterQuality.low,
          );
          for (final rect in config.snapshotNavigation) {
            canvas.drawRect(
              rect.shift(paintOffset),
              Paint()..color = config.background,
            );
          }
        }
        // Restore the same tinted background through the fading cover. Once
        // content is opaque, waves are painted only underneath it.
        _paintWaves(canvas, paintOffset, strength: cover);
      },
    );
  }

  void _paintWaves(Canvas canvas, Offset paintOffset, {double strength = 1}) {
    final config = _configuration;
    for (final wave in config.waves) {
      final origin = wave.originGlobal == null
          ? size.center(Offset.zero)
          : globalToLocal(wave.originGlobal!);
      final maximum = [
        Offset.zero,
        Offset(size.width, 0),
        Offset(0, size.height),
        Offset(size.width, size.height),
      ].map((corner) => (corner - origin).distance).reduce(math.max);
      final radius = ui.lerpDouble(
        wave.initialRadius,
        math.max(maximum, wave.initialRadius) + 2,
        Curves.easeOutQuad.transform(wave.progress),
      )!;
      if (radius <= 0) continue;
      // A softly coloured surface, not a bright rim; its centre and edge
      // gradually disappear. Three waves still have a bounded tint.
      final alpha =
          .045 *
          strength *
          (1 - wave.progress) *
          math.min(1.0, wave.progress / .08);
      final center = paintOffset + origin;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            radius,
            [
              config.tint.withValues(alpha: alpha * .35),
              config.tint.withValues(alpha: alpha),
              config.tint.withValues(alpha: 0),
            ],
            [0, .8, 1],
          ),
      );
    }
  }
}
