import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'ui_motion.dart';

/// Crossfades the visible part of a tab while keeping exactly one live set of
/// form fields, focus nodes, scroll positions and accessibility actions.
class TabContentTransition extends StatefulWidget {
  const TabContentTransition({
    super.key,
    required this.index,
    required this.child,
  }) : sliver = false;
  const TabContentTransition.sliver({
    super.key,
    required this.index,
    required this.child,
  }) : sliver = true;
  final int index;
  final Widget child;
  final bool sliver;

  @override
  State<TabContentTransition> createState() => _TabContentTransitionState();
}

class _TabContentTransitionState extends State<TabContentTransition>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: AppMotion.tabChange,
    value: 1,
  );

  @override
  void didUpdateWidget(TabContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index && !AppMotion.reduced(context)) {
      controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) controller.value = 1;
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final direction = Directionality.of(context);
    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (_, child) => _TabPaintRegion(
        index: widget.index,
        progress: Curves.easeInOut.transform(controller.value),
        view: view,
        direction: direction,
        sliver: widget.sliver,
        child: child!,
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class _TabPaintRegion extends SingleChildRenderObjectWidget {
  const _TabPaintRegion({
    required this.index,
    required this.progress,
    required this.view,
    required this.direction,
    required this.sliver,
    required super.child,
  });
  final int index;
  final double progress;
  final ui.FlutterView view;
  final TextDirection direction;
  final bool sliver;

  @override
  _TabPaint createRenderObject(BuildContext context) {
    final _TabPaint region = sliver ? _TabSliver() : _TabBox();
    return region..update(this);
  }

  @override
  void updateRenderObject(BuildContext context, _TabPaint renderObject) =>
      renderObject.update(this);
}

mixin _TabPaint on RenderObject {
  ui.Image? _outgoing;
  Rect _captured = Rect.zero;
  int? _index;
  double _progress = 1;
  double _distance = 0;

  Offset get _incomingOffset =>
      _outgoing == null ? Offset.zero : Offset(_distance * (1 - _progress), 0);

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    transform.translateByDouble(_incomingOffset.dx, 0, 0, 1);
  }

  @override
  bool get isRepaintBoundary => true;

  void update(_TabPaintRegion config) {
    if (config.index != _index && _index != null && config.progress < 1) {
      _outgoing?.dispose();
      _outgoing = null;
      final previous = layer;
      if (previous is OffsetLayer &&
          previous.attached &&
          previous.supportsRasterization()) {
        final ratio = config.view.devicePixelRatio;
        final screen = Offset.zero & (config.view.physicalSize / ratio);
        _captured = paintBounds.intersect(
          MatrixUtils.inverseTransformRect(getTransformTo(null), screen),
        );
        if (!_captured.isEmpty && _captured.isFinite) {
          // The previous frame is visible for only 220 ms. Bound the transient
          // texture for large desktop windows and high-density devices.
          final pixels = _captured.width * _captured.height;
          final scale = math.min(
            ratio,
            math.min(2.0, math.sqrt(4000000 / pixels)),
          );
          _outgoing = previous.toImageSync(_captured, pixelRatio: scale);
        }
      }
      final forward = config.index > _index!;
      _distance = forward == (config.direction == TextDirection.ltr) ? 10 : -10;
    }
    _index = config.index;
    if (_progress == config.progress) return;
    _progress = config.progress;
    if (_progress == 1) {
      _outgoing?.dispose();
      _outgoing = null;
    }
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final image = _outgoing;
    if (image == null || _progress == 1) {
      super.paint(context, offset);
      return;
    }
    context.pushClipRect(true, offset, paintBounds, (context, offset) {
      context.canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        _captured.shift(offset + Offset(-_distance * _progress, 0)),
        Paint()
          ..color = const Color(0xffffffff).withValues(alpha: 1 - _progress),
      );
      context.pushOpacity(
        offset + _incomingOffset,
        (255 * _progress).round(),
        super.paint,
      );
    });
  }

  @override
  void dispose() {
    _outgoing?.dispose();
    super.dispose();
  }
}

class _TabBox extends RenderProxyBox with _TabPaint {
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _incomingOffset,
        position: position,
        hitTest: (result, local) =>
            super.hitTestChildren(result, position: local),
      );
}

class _TabSliver extends RenderProxySliver with _TabPaint {
  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    final offset = _incomingOffset;
    final main = applyGrowthDirectionToAxisDirection(
      constraints.axisDirection,
      constraints.growthDirection,
    );
    double along(AxisDirection axis) => switch (axis) {
      AxisDirection.right => offset.dx,
      AxisDirection.left => -offset.dx,
      _ => 0,
    };
    return result.addWithAxisOffset(
      paintOffset: offset,
      mainAxisOffset: along(main),
      crossAxisOffset: along(constraints.crossAxisDirection),
      mainAxisPosition: mainAxisPosition,
      crossAxisPosition: crossAxisPosition,
      hitTest: super.hitTestChildren,
    );
  }
}
