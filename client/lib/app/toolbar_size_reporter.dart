import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports actual chrome extent after layout, including custom UI recipes.
/// A render object avoids a second layout pass and only publishes size changes.
class ToolbarSizeReporter extends SingleChildRenderObjectWidget {
  const ToolbarSizeReporter({
    super.key,
    required super.child,
    this.onSizeChanged,
  });

  final ValueChanged<Size>? onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ToolbarSizeRenderObject(onSizeChanged);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _ToolbarSizeRenderObject).onSizeChanged = onSizeChanged;
  }
}

class _ToolbarSizeRenderObject extends RenderProxyBox {
  _ToolbarSizeRenderObject(this.onSizeChanged);

  ValueChanged<Size>? onSizeChanged;
  Size? _reported;
  Size? _pending;

  @override
  void performLayout() {
    super.performLayout();
    if (onSizeChanged == null || size == _reported || size == _pending) return;
    _pending = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final measured = _pending;
      _pending = null;
      if (!attached || measured == null || measured == _reported) return;
      _reported = measured;
      onSizeChanged?.call(measured);
    });
  }
}
