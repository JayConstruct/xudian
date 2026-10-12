import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Radial source sampling stays fixed at the wavefront and both band edges.
/// Its derivative is .96 at the front, giving approximately 1.04x local zoom.
double dateWaveLensSourceRadius({
  required double distance,
  required double radius,
  required double width,
  double strength = 1,
}) {
  if (width <= 0 || !width.isFinite) return distance;
  final delta = distance - radius;
  if (delta.abs() >= width / 2) return distance;
  final window = math.cos(math.pi * delta / width);
  return distance - delta * .04 * strength.clamp(0.0, 1.0) * window * window;
}

final _identity = Float64List.fromList([
  1,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  1,
]);

/// Refracts only a narrow moving band, using the already captured old and new
/// images. No custom shader asset, extra snapshot, or child repaint is needed.
/// Coordinates are local to the caller's canvas. Live navigation is excluded.
bool paintDateWaveLens(
  ui.Canvas canvas, {
  required ui.Image oldImage,
  required ui.Image newImage,
  required ui.Size oldSize,
  required ui.Size newSize,
  required ui.Offset origin,
  required double radius,
  required double width,
  required ui.Rect bounds,
  List<ui.Rect> navigation = const [],
  double strength = 1,
}) {
  if (!radius.isFinite ||
      !width.isFinite ||
      !strength.isFinite ||
      radius <= 0 ||
      width <= 0 ||
      strength <= 0 ||
      oldSize.isEmpty ||
      newSize.isEmpty ||
      !oldSize.width.isFinite ||
      !oldSize.height.isFinite ||
      !newSize.width.isFinite ||
      !newSize.height.isFinite ||
      bounds.isEmpty ||
      !origin.dx.isFinite ||
      !origin.dy.isFinite) {
    return false;
  }
  final inner = math.max(0.0, radius - width / 2);
  final outer = radius + width / 2;
  if (!ui.Rect.fromCircle(center: origin, radius: outer).overlaps(bounds)) {
    return false;
  }
  var allowed = ui.Path()..addRect(bounds);
  if (navigation.isNotEmpty) {
    final excluded = ui.Path();
    for (final rect in navigation) {
      excluded.addRect(rect);
    }
    allowed = ui.Path.combine(ui.PathOperation.difference, allowed, excluded);
  }
  // Keep arcs under 10 logical pixels where possible, with bounded mesh cost.
  final angularSteps = (2 * math.pi * outer / 10).ceil().clamp(96, 256);
  canvas.save();
  canvas.clipPath(allowed);
  _paintBand(
    canvas,
    image: newImage,
    imageSize: newSize,
    origin: origin,
    start: inner,
    end: radius,
    radius: radius,
    width: width,
    strength: strength,
    angularSteps: angularSteps,
  );
  _paintBand(
    canvas,
    image: oldImage,
    imageSize: oldSize,
    origin: origin,
    start: radius,
    end: outer,
    radius: radius,
    width: width,
    strength: strength,
    angularSteps: angularSteps,
  );
  canvas.restore();
  return true;
}

void _paintBand(
  ui.Canvas canvas, {
  required ui.Image image,
  required ui.Size imageSize,
  required ui.Offset origin,
  required double start,
  required double end,
  required double radius,
  required double width,
  required double strength,
  required int angularSteps,
}) {
  const radialSteps = 6;
  final columns = angularSteps + 1;
  final positions = Float32List((radialSteps + 1) * columns * 2);
  final texture = Float32List(positions.length);
  final indices = Uint16List(radialSteps * angularSteps * 6);
  final ratioX = image.width / imageSize.width;
  final ratioY = image.height / imageSize.height;
  final cosines = Float64List(columns), sines = Float64List(columns);
  for (var angle = 0; angle <= angularSteps; angle++) {
    final radians = 2 * math.pi * angle / angularSteps;
    cosines[angle] = math.cos(radians);
    sines[angle] = math.sin(radians);
  }
  for (var band = 0; band <= radialSteps; band++) {
    final distance = ui.lerpDouble(start, end, band / radialSteps)!;
    final sampled = dateWaveLensSourceRadius(
      distance: distance,
      radius: radius,
      width: width,
      strength: strength,
    );
    for (var angle = 0; angle <= angularSteps; angle++) {
      final dx = cosines[angle], dy = sines[angle];
      final index = (band * columns + angle) * 2;
      positions[index] = origin.dx + dx * distance;
      positions[index + 1] = origin.dy + dy * distance;
      texture[index] = (origin.dx + dx * sampled) * ratioX;
      texture[index + 1] = (origin.dy + dy * sampled) * ratioY;
    }
  }
  var index = 0;
  for (var band = 0; band < radialSteps; band++) {
    for (var angle = 0; angle < angularSteps; angle++) {
      final a = band * columns + angle;
      final b = a + 1;
      final c = a + columns;
      final d = c + 1;
      indices[index++] = a;
      indices[index++] = c;
      indices[index++] = b;
      indices[index++] = b;
      indices[index++] = c;
      indices[index++] = d;
    }
  }
  final vertices = ui.Vertices.raw(
    ui.VertexMode.triangles,
    positions,
    textureCoordinates: texture,
    indices: indices,
  );
  final shader = ui.ImageShader(
    image,
    ui.TileMode.decal,
    ui.TileMode.decal,
    _identity,
    filterQuality: ui.FilterQuality.low,
  );
  canvas.save();
  canvas.clipPath(
    ui.Path()
      ..fillType = ui.PathFillType.evenOdd
      ..addOval(ui.Rect.fromCircle(center: origin, radius: end))
      ..addOval(ui.Rect.fromCircle(center: origin, radius: start)),
  );
  canvas.drawVertices(vertices, ui.BlendMode.src, ui.Paint()..shader = shader);
  canvas.restore();
  shader.dispose();
  vertices.dispose();
}
