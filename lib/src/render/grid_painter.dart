import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../core/viewport.dart';
import '../widgets/theme.dart';
import 'shaders.dart';

/// Paints the canvas background and grid.
///
/// Uses `shaders/grid.frag` (one draw call for the whole screen, cost
/// independent of the grid density); falls back to batched
/// `drawRawPoints` calls when the shader is unavailable.
class GridPainter extends CustomPainter {
  /// Creates a grid painter.
  GridPainter({
    required this.viewport,
    required this.settings,
    required this.theme,
  }) : super(
         repaint: Listenable.merge([viewport, settings, EditorShaders.loaded]),
       );

  /// EditorViewport.
  final ValueListenable<EditorViewport> viewport;

  /// Canvas settings.
  final ValueListenable<CanvasSettings> settings;

  /// Theme.
  final NodeEditorThemeData theme;

  static ui.FragmentShader? _shader;

  @override
  void paint(Canvas canvas, Size size) {
    final s = settings.value;
    final v = viewport.value;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = s.backgroundColor ?? theme.backgroundColor,
    );
    if (!s.showGrid || s.gridSpacing <= 0) return;
    final minor = s.gridColor ?? theme.gridColor;
    final major = s.majorGridColor ?? theme.majorGridColor;
    final program = EditorShaders.grid;
    if (program != null) {
      final shader = _shader ??= program.fragmentShader();
      var i = 0;
      shader
        ..setFloat(i++, size.width)
        ..setFloat(i++, size.height)
        ..setFloat(i++, v.offset.dx)
        ..setFloat(i++, v.offset.dy)
        ..setFloat(i++, v.zoom)
        ..setFloat(i++, s.gridSpacing)
        ..setFloat(i++, s.majorEvery.toDouble())
        ..setFloat(i++, switch (s.gridStyle) {
          GridStyle.dots => 0,
          GridStyle.lines => 1,
          _ => 2,
        })
        ..setFloat(i++, theme.gridThickness);
      i = setColorUniform(shader, i, minor);
      setColorUniform(shader, i, major);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      return;
    }
    _paintFallback(canvas, size, s, v, minor, major);
  }

  void _paintFallback(
    Canvas canvas,
    Size size,
    CanvasSettings s,
    EditorViewport v,
    Color minor,
    Color major,
  ) {
    var step = s.gridSpacing;
    while (step * v.zoom < 8) {
      step *= 2;
    }
    final screenStep = step * v.zoom;
    // Fade dense minor grids like the shader does.
    final fade = ((screenStep - 8) / 8).clamp(0.0, 1.0) * 0.6 + 0.4;
    minor = minor.withValues(alpha: minor.a * fade);
    final x0 = (v.offset.dx % screenStep) - screenStep;
    final y0 = (v.offset.dy % screenStep) - screenStep;
    final cols = (size.width / screenStep).ceil() + 2;
    final rows = (size.height / screenStep).ceil() + 2;
    final majorStep = s.majorEvery > 1 ? step * s.majorEvery : 0.0;
    bool isMajor(double screen, double offset) {
      if (majorStep == 0) return false;
      final c = (screen - offset) / v.zoom;
      final r = (c / majorStep).roundToDouble() * majorStep;
      return (c - r).abs() < step / 2;
    }

    final minorPaint = Paint()
      ..color = minor
      ..strokeWidth = theme.gridThickness
      ..strokeCap = StrokeCap.round;
    final majorPaint = Paint()
      ..color = major
      ..strokeWidth = theme.gridThickness * 1.5
      ..strokeCap = StrokeCap.round;

    if (s.gridStyle == GridStyle.dots) {
      if (cols * rows > 200000) return;
      final pts = Float32List(cols * rows * 2);
      var i = 0;
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          pts[i++] = x0 + c * screenStep;
          pts[i++] = y0 + r * screenStep;
        }
      }
      canvas.drawRawPoints(
        ui.PointMode.points,
        pts,
        minorPaint..strokeWidth = theme.gridThickness * 2,
      );
      return;
    }
    final minorLines = <double>[];
    final majorLines = <double>[];
    final arm = s.gridStyle == GridStyle.cross
        ? math.max(3.0, theme.gridThickness * 4)
        : null;
    for (var c = 0; c < cols; c++) {
      final x = x0 + c * screenStep;
      final list = isMajor(x, v.offset.dx) ? majorLines : minorLines;
      if (arm == null) {
        list.addAll([x, 0, x, size.height]);
      } else {
        for (var r = 0; r < rows; r++) {
          final y = y0 + r * screenStep;
          list.addAll([x, y - arm, x, y + arm, x - arm, y, x + arm, y]);
        }
      }
    }
    if (arm == null) {
      for (var r = 0; r < rows; r++) {
        final y = y0 + r * screenStep;
        final list = isMajor(y, v.offset.dy) ? majorLines : minorLines;
        list.addAll([0, y, size.width, y]);
      }
    }
    canvas.drawRawPoints(
      ui.PointMode.lines,
      Float32List.fromList(minorLines),
      minorPaint,
    );
    if (majorLines.isNotEmpty) {
      canvas.drawRawPoints(
        ui.PointMode.lines,
        Float32List.fromList(majorLines),
        majorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      old.theme != theme ||
      old.viewport != viewport ||
      old.settings != settings;
}
