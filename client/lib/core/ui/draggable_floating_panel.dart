import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design_system.dart';

/// A small page-local panel; only its header drags, so content remains usable.
class DraggableFloatingPanel extends StatefulWidget {
  const DraggableFloatingPanel({
    super.key,
    required this.viewport,
    required this.child,
    required this.title,
    required this.onClose,
    this.closeLabel = '关闭面板',
    this.bottomInset = 0,
    this.initialTop = 16,
  });

  final Size viewport;
  final Widget child;
  final String title, closeLabel;
  final VoidCallback? onClose;
  final double bottomInset, initialTop;

  @override
  State<DraggableFloatingPanel> createState() => _DraggableFloatingPanelState();
}

class _DraggableFloatingPanelState extends State<DraggableFloatingPanel> {
  final surfaceKey = GlobalKey();
  Offset? position;

  double get margin => math.min(12, widget.viewport.width / 4);
  double get width =>
      math.min(300, math.max(0, widget.viewport.width - margin * 2));
  double get availableHeight =>
      math.max(0, widget.viewport.height - widget.bottomInset);
  double get maxHeight => math.min(
    availableHeight - math.min(24, availableHeight),
    math.max(120, availableHeight * .55),
  );

  Offset bounded(Offset offset) {
    final box = surfaceKey.currentContext?.findRenderObject();
    final height = box is RenderBox && box.hasSize
        ? box.size.height
        : maxHeight;
    final maxX = math.max(margin, widget.viewport.width - width - margin);
    final maxY = math.max(0, availableHeight - height - 12);
    return Offset(
      offset.dx.clamp(margin, maxX).toDouble(),
      offset.dy.clamp(0, maxY).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offset = bounded(
      position ??
          Offset(widget.viewport.width - width - margin, widget.initialTop),
    );
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      width: width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: math.max(0, maxHeight)),
        child: FloatingSurface(
          key: surfaceKey,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: (maxHeight - 18).clamp(0, 48),
                child: ClipRect(
                  child: GestureDetector(
                    key: const ValueKey('script-floating-panel-drag-handle'),
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) => setState(() {
                      position = bounded((position ?? offset) + details.delta);
                    }),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              widget.title,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: widget.closeLabel,
                          onPressed: widget.onClose,
                          iconSize: 20,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Flexible(child: SingleChildScrollView(child: widget.child)),
            ],
          ),
        ),
      ),
    );
  }
}
