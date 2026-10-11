import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../core/controller.dart';
import '../core/edge.dart';
import '../core/edge_geometry.dart';
import '../core/ports.dart';
import '../core/viewport.dart';
import '../widgets/theme.dart';
import 'shaders.dart';

/// Caches shared by the edge painters of one canvas (labels, dashed paths,
/// low-detail line batches). Owned by the canvas state.
class EdgeRenderCache {
  final Map<String, TextPainter> _labels = {};
  final Expando<_DashCache> _dashes = Expando('dashes');
  Object? _lodKey;
  List<(Color, Float32List)> _lodBatches = const [];

  /// Drops every cached object.
  void clear() {
    for (final l in _labels.values) {
      l.dispose();
    }
    _labels.clear();
    _lodKey = null;
    _lodBatches = const [];
  }

  /// A laid out label painter.
  TextPainter label(String text, TextStyle style) {
    final key = '${style.hashCode}|$text';
    final cached = _labels[key];
    if (cached != null) return cached;
    if (_labels.length > 800) clear();
    return _labels[key] = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }

  /// The dashed version of [geometry]'s path.
  Path dashed(EdgeGeometry geometry, List<double> pattern, [double phase = 0]) {
    if (phase == 0) {
      final c = _dashes[geometry];
      if (c != null && identical(c.pattern, pattern)) return c.path;
    }
    final path = dashPath(geometry.path, pattern, phase);
    if (phase == 0) _dashes[geometry] = _DashCache(pattern, path);
    return path;
  }

  /// Splits [source] into dashes.
  static Path dashPath(Path source, List<double> pattern, double phase) {
    final out = Path();
    if (pattern.isEmpty || pattern.every((d) => d <= 0)) return source;
    final total = pattern.fold<double>(0, (a, b) => a + b);
    for (final metric in source.computeMetrics()) {
      var d = -(phase % total);
      var i = 0;
      while (d < metric.length) {
        final len = pattern[i % pattern.length];
        if (i.isEven && d + len > 0) {
          out.addPath(
            metric.extractPath(
              math.max(d, 0),
              math.min(d + len, metric.length),
            ),
            Offset.zero,
          );
        }
        d += len;
        i++;
      }
    }
    return out;
  }
}

class _DashCache {
  _DashCache(this.pattern, this.path);
  final List<double> pattern;
  final Path path;
}

/// Resolves edge colors and widths from style, port type and theme.
class EdgeStyleResolver {
  /// Creates a resolver.
  const EdgeStyleResolver(this.controller, this.theme);

  /// Controller.
  final NodeEditorController controller;

  /// Theme.
  final NodeEditorThemeData theme;

  /// Stroke color of [edge].
  Color color(Edge edge, {bool selected = false}) {
    if (selected) return theme.selectedEdgeColor;
    final c = edge.style.color;
    if (c != null) return c;
    if (!theme.colorEdgesByType) return theme.edgeColor;
    final type = controller.graph.port(edge.source)?.type;
    return type == null || type.isAny ? theme.edgeColor : type.color;
  }

  /// Stroke width of [edge], canvas units.
  double width(Edge edge, {bool selected = false}) =>
      (edge.style.width ?? theme.edgeWidth) + (selected ? 1.5 : 0);
}

/// Draws one edge end marker.
void paintEdgeMarker(
  Canvas canvas,
  EdgeMarker marker,
  Offset tip,
  Offset direction,
  Color color,
  double width,
) {
  if (marker == EdgeMarker.none) return;
  final size = 7 + width * 1.5;
  final back = tip - direction * size;
  final normal = Offset(-direction.dy, direction.dx) * (size * 0.55);
  final paint = Paint()
    ..color = color
    ..isAntiAlias = true;
  switch (marker) {
    case EdgeMarker.none:
      return;
    case EdgeMarker.arrow:
      canvas.drawPath(
        Path()
          ..moveTo((back + normal).dx, (back + normal).dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo((back - normal).dx, (back - normal).dy),
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    case EdgeMarker.arrowClosed:
      canvas.drawPath(
        Path()
          ..moveTo((back + normal).dx, (back + normal).dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo((back - normal).dx, (back - normal).dy)
          ..close(),
        paint,
      );
    case EdgeMarker.circle:
      canvas.drawCircle(tip - direction * (size / 2), size / 2.4, paint);
    case EdgeMarker.diamond:
      final mid = tip - direction * (size / 2);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo((mid + normal).dx, (mid + normal).dy)
          ..lineTo(back.dx, back.dy)
          ..lineTo((mid - normal).dx, (mid - normal).dy)
          ..close(),
        paint,
      );
  }
}

/// Paints all non-animated edges.
///
/// Full detail: culled through the edge spatial index, cached routed paths,
/// markers and labels. Low detail (zoomed out): every edge is a straight
/// segment, batched per color into a single `drawRawPoints` call from a
/// cached buffer, so panning a 50k-edge graph re-uses the same buffers.
class EdgePainter extends CustomPainter {
  /// Creates an edge painter.
  EdgePainter({
    required this.controller,
    required this.theme,
    required this.cache,
    this.skipAnimated = true,
  }) : super(
         repaint: Listenable.merge([
           controller.viewport,
           controller.edgesListenable,
           controller.selection,
         ]),
       );

  /// Controller.
  final NodeEditorController controller;

  /// Theme.
  final NodeEditorThemeData theme;

  /// Shared caches.
  final EdgeRenderCache cache;

  /// Whether animated edges are left to [AnimatedEdgePainter].
  final bool skipAnimated;

  @override
  void paint(Canvas canvas, Size size) {
    final v = controller.viewport.value;
    final config = controller.config;
    canvas
      ..save()
      ..transform(v.matrix.storage);
    if (v.zoom < config.lodThreshold) {
      _paintLowDetail(canvas, v);
    } else {
      _paintFull(canvas, size, v);
    }
    canvas.restore();
  }

  void _paintLowDetail(Canvas canvas, EditorViewport v) {
    final graph = controller.graph;
    final sel = controller.selection.value;
    final key = (graph, controller.revision.value, sel, theme);
    if (cache._lodKey != key) {
      final resolver = EdgeStyleResolver(controller, theme);
      final groups = <Color, List<double>>{};
      for (final e in graph.edges) {
        final s = controller.portAnchor(e.source);
        final t = controller.portAnchor(e.target);
        if (s == null || t == null) continue;
        final color = resolver.color(e, selected: sel.edges.contains(e.id));
        (groups[color] ??= []).addAll([s.dx, s.dy, t.dx, t.dy]);
      }
      cache
        .._lodKey = key
        .._lodBatches = [
          for (final g in groups.entries)
            (g.key, Float32List.fromList(g.value)),
        ];
    }
    final paint = Paint()
      ..strokeWidth = math.max(1.0 / v.zoom, theme.edgeWidth)
      ..strokeCap = StrokeCap.butt;
    for (final (color, pts) in cache._lodBatches) {
      canvas.drawRawPoints(ui.PointMode.lines, pts, paint..color = color);
    }
  }

  void _paintFull(Canvas canvas, Size size, EditorViewport v) {
    final graph = controller.graph;
    final sel = controller.selection.value;
    final resolver = EdgeStyleResolver(controller, theme);
    final visible = v.visibleRect(size).inflate(40 / v.zoom);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final showLabels = v.zoom >= controller.config.lodTextThreshold * 2;
    final selected = <Edge>[];

    void draw(Edge e, bool isSelected) {
      final g = controller.edgeGeometry(e);
      if (g == null) return;
      final color = resolver.color(e, selected: isSelected);
      final width = resolver.width(e, selected: isSelected);
      paint
        ..color = color
        ..strokeWidth = width;
      final dash = e.style.dashPattern;
      canvas.drawPath(dash == null ? g.path : cache.dashed(g, dash), paint);
      _paintDecorations(canvas, e, g, color, width, showLabels);
    }

    for (final id in controller.edgeIndex.query(visible)) {
      final e = graph.edge(id);
      if (e == null) continue;
      if (sel.edges.contains(id)) {
        selected.add(e);
        continue;
      }
      if (skipAnimated && e.style.animated) {
        continue;
      }
      draw(e, false);
    }
    for (final e in selected) {
      draw(e, true);
    }
  }

  void _paintDecorations(
    Canvas canvas,
    Edge e,
    EdgeGeometry g,
    Color color,
    double width,
    bool showLabels,
  ) {
    final inset = theme.portSize / 2;
    if (e.style.endMarker != EdgeMarker.none) {
      paintEdgeMarker(
        canvas,
        e.style.endMarker,
        g.polyline.last - g.endDirection * inset,
        g.endDirection,
        color,
        width,
      );
    }
    if (e.style.startMarker != EdgeMarker.none) {
      paintEdgeMarker(
        canvas,
        e.style.startMarker,
        g.polyline.first - g.startDirection * inset,
        g.startDirection,
        color,
        width,
      );
    }
    final label = e.label;
    if (showLabels && label != null && label.isNotEmpty) {
      final style = theme.edgeLabelStyle.copyWith(
        color: e.style.labelColor,
        fontSize: e.style.labelFontSize,
      );
      final tp = cache.label(label, style);
      final mid = g.midpoint;
      final box = Rect.fromCenter(
        center: mid,
        width: tp.width + 10,
        height: tp.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(4)),
        Paint()..color = e.style.labelBackground ?? theme.edgeLabelBackground,
      );
      tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(EdgePainter old) =>
      old.controller != controller ||
      old.theme != theme ||
      old.skipAnimated != skipAnimated;
}

/// Paints animated edges with the `edge_flow.frag` shader (or a marching
/// dash fallback). Lives on its own layer and is the only edge layer that
/// repaints every frame, and only while animated edges are visible.
class AnimatedEdgePainter extends CustomPainter {
  /// Creates the painter.
  AnimatedEdgePainter({
    required this.controller,
    required this.theme,
    required this.cache,
    required this.time,
  }) : super(
         repaint: Listenable.merge([
           controller.viewport,
           controller.edgesListenable,
           time,
         ]),
       );

  /// Controller.
  final NodeEditorController controller;

  /// Theme.
  final NodeEditorThemeData theme;

  /// Shared caches.
  final EdgeRenderCache cache;

  /// Animation clock, seconds.
  final ValueListenable<double> time;

  static final List<ui.FragmentShader> _pool = [];

  @override
  void paint(Canvas canvas, Size size) {
    final v = controller.viewport.value;
    if (v.zoom < controller.config.lodThreshold) return;
    final graph = controller.graph;
    final sel = controller.selection.value;
    final resolver = EdgeStyleResolver(controller, theme);
    final visible = v.visibleRect(size).inflate(40 / v.zoom);
    final program = EditorShaders.edgeFlow;
    final t = time.value;
    canvas
      ..save()
      ..transform(v.matrix.storage);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    var used = 0;
    final showLabels = v.zoom >= controller.config.lodTextThreshold * 2;
    for (final id in controller.edgeIndex.query(visible)) {
      final e = graph.edge(id);
      if (e == null || !e.style.animated || sel.edges.contains(id)) continue;
      final g = controller.edgeGeometry(e);
      if (g == null) continue;
      final color = resolver.color(e);
      final width = resolver.width(e);
      paint
        ..strokeWidth = width + 0.5
        ..color = color
        ..shader = null;
      if (program != null) {
        if (_pool.length <= used) _pool.add(program.fragmentShader());
        final shader = _pool[used++];
        final dir = g.polyline.last - g.polyline.first;
        final len = dir.distance;
        final d = len == 0 ? const Offset(1, 0) : dir / len;
        var i = 0;
        shader
          ..setFloat(i++, t)
          ..setFloat(i++, d.dx)
          ..setFloat(i++, d.dy)
          ..setFloat(i++, 28)
          ..setFloat(i++, 60);
        i = setColorUniform(shader, i, color.withValues(alpha: color.a * 0.55));
        setColorUniform(
          shader,
          i,
          Color.lerp(color, const Color(0xFFFFFFFF), 0.35)!,
        );
        paint.shader = shader;
        canvas.drawPath(g.path, paint);
      } else {
        canvas.drawPath(cache.dashed(g, const [8, 6], -t * 40), paint);
      }
      paint.shader = null;
      _paintEnds(canvas, e, g, color, width, showLabels);
    }
    canvas.restore();
  }

  void _paintEnds(
    Canvas canvas,
    Edge e,
    EdgeGeometry g,
    Color color,
    double width,
    bool showLabels,
  ) {
    final inset = theme.portSize / 2;
    if (e.style.endMarker != EdgeMarker.none) {
      paintEdgeMarker(
        canvas,
        e.style.endMarker,
        g.polyline.last - g.endDirection * inset,
        g.endDirection,
        color,
        width,
      );
    }
    final label = e.label;
    if (showLabels && label != null && label.isNotEmpty) {
      final tp = cache.label(label, theme.edgeLabelStyle);
      final mid = g.midpoint;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: mid,
            width: tp.width + 10,
            height: tp.height + 4,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = theme.edgeLabelBackground,
      );
      tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(AnimatedEdgePainter old) =>
      old.controller != controller || old.theme != theme;
}

/// Paints the link being dragged and the selection box.
class InteractionPainter extends CustomPainter {
  /// Creates the painter.
  InteractionPainter({required this.controller, required this.theme})
    : super(
        repaint: Listenable.merge([
          controller.viewport,
          controller.connectionDraft,
          controller.connectionPointer,
          controller.marquee,
        ]),
      );

  /// Controller.
  final NodeEditorController controller;

  /// Theme.
  final NodeEditorThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final v = controller.viewport.value;
    canvas
      ..save()
      ..transform(v.matrix.storage);
    final draft = controller.connectionDraft.value;
    final pointer = controller.connectionPointer.value;
    if (draft != null && pointer != null) {
      final from = controller.portAnchor(draft.from);
      if (from != null) {
        final hover = draft.hoverTarget;
        final to = hover == null ? pointer : controller.portAnchor(hover)!;
        final toSide = hover == null
            ? draft.fromPort.effectiveSide.opposite
            : controller.graph.port(hover)!.effectiveSide;
        final out = draft.fromPort.isOutput;
        final input = EdgePathInput(
          source: out ? from : to,
          sourceSide: out ? draft.fromPort.effectiveSide : toSide,
          target: out ? to : from,
          targetSide: out ? toSide : draft.fromPort.effectiveSide,
          style: controller.canvasSettings.value.defaultEdgeStyle,
        );
        final g = EdgeRouter.route(input);
        final color = hover == null
            ? theme.connectionColor
            : (draft.hoverValid
                  ? theme.validTargetColor
                  : theme.invalidTargetColor);
        canvas.drawPath(
          EdgeRenderCache.dashPath(g.path, const [6, 4], 0),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = theme.edgeWidth
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(to, 4, Paint()..color = color);
      }
    }
    final m = controller.marquee.value;
    if (m != null) {
      canvas
        ..drawRect(m, Paint()..color = theme.marqueeFill)
        ..drawRect(
          m,
          Paint()
            ..color = theme.marqueeBorder
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 / v.zoom,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(InteractionPainter old) =>
      old.controller != controller || old.theme != theme;
}

extension on PortSide {
  PortSide get opposite => switch (this) {
    PortSide.left => PortSide.right,
    PortSide.right => PortSide.left,
    PortSide.top => PortSide.bottom,
    PortSide.bottom => PortSide.top,
  };
}
