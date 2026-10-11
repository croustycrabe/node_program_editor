import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/node.dart';
import 'theme.dart';

/// Overview of the whole graph with the visible area. Tap or drag to
/// navigate, scroll to zoom.
///
/// Nodes are drawn as colored rectangles in one `drawVertices` call from a
/// cached buffer (rebuilt only when non-selected nodes change), so the
/// minimap stays cheap with very large graphs.
class NodeMiniMap extends StatefulWidget {
  /// Creates a minimap.
  const NodeMiniMap({
    super.key,
    required this.controller,
    this.width = 200,
    this.height = 140,
    this.nodeColor,
    this.interactive = true,
    this.zoomable = true,
    this.theme,
    this.borderRadius = 8,
  });

  /// Controller.
  final NodeEditorController controller;

  /// Width.
  final double width;

  /// Height.
  final double height;

  /// Node color (default: node header color).
  final Color Function(NodeInstance node)? nodeColor;

  /// Whether tap / drag navigates.
  final bool interactive;

  /// Whether scrolling over the minimap zooms the canvas.
  final bool zoomable;

  /// Theme override.
  final NodeEditorThemeData? theme;

  /// Corner radius.
  final double borderRadius;

  @override
  State<NodeMiniMap> createState() => _NodeMiniMapState();
}

class _NodeMiniMapState extends State<NodeMiniMap> {
  final _MiniMapCache _cache = _MiniMapCache();

  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }

  void _navigate(Offset local, {bool animate = false}) {
    final t = _MiniMapPainter.transform(
      widget.controller,
      Size(widget.width, widget.height),
    );
    widget.controller.centerOn((local - t.$2) / t.$1, animate: animate);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? NodeEditorThemeData.of(context);
    Widget map = CustomPaint(
      size: Size(widget.width, widget.height),
      painter: _MiniMapPainter(
        controller: widget.controller,
        theme: theme,
        cache: _cache,
        nodeColor: widget.nodeColor,
      ),
    );
    if (widget.interactive) {
      map = Listener(
        onPointerSignal: widget.zoomable
            ? (e) {
                if (e is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(e, (
                    e,
                  ) {
                    final s = e as PointerScrollEvent;
                    widget.controller.zoomBy(
                      math.pow(2, -s.scrollDelta.dy / 300).toDouble(),
                    );
                  });
                }
              }
            : null,
        child: GestureDetector(
          onTapUp: (d) => _navigate(d.localPosition, animate: true),
          onPanUpdate: (d) => _navigate(d.localPosition),
          child: map,
        ),
      );
    }
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: theme.minimapBackground,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: theme.panelBorderColor),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 8)],
      ),
      clipBehavior: Clip.antiAlias,
      child: RepaintBoundary(child: map),
    );
  }
}

class _MiniMapCache {
  Object? key;
  ui.Vertices? vertices;

  void dispose() => vertices?.dispose();
}

class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter({
    required this.controller,
    required this.theme,
    required this.cache,
    this.nodeColor,
  }) : super(
         repaint: Listenable.merge([
           controller.viewport,
           controller.geometry,
           controller.structure,
           controller.selection,
           controller.viewportSizeListenable,
         ]),
       );

  final NodeEditorController controller;
  final NodeEditorThemeData theme;
  final _MiniMapCache cache;
  final Color Function(NodeInstance node)? nodeColor;

  /// (scale, offset) mapping canvas to minimap coordinates.
  static (double, Offset) transform(NodeEditorController c, Size size) {
    final visible = c.viewport.value.visibleRect(c.viewportSize);
    var world = c.boundsOf() ?? visible;
    world = world.expandToInclude(visible);
    world = world.inflate(math.max(world.width, world.height) * 0.05);
    final s = math.min(size.width / world.width, size.height / world.height);
    final offset = Offset(
      (size.width - world.width * s) / 2 - world.left * s,
      (size.height - world.height * s) / 2 - world.top * s,
    );
    return (s, offset);
  }

  Color _color(NodeInstance n) =>
      nodeColor?.call(n) ?? resolveNodeColors(n, theme).header;

  ui.Vertices _build(Iterable<NodeInstance> nodes, int count) {
    final pos = Float32List(count * 12);
    final col = Int32List(count * 6);
    var i = 0;
    for (final n in nodes) {
      final r = n.rect;
      final p = i * 12, c = i * 6;
      pos
        ..[p] = r.left
        ..[p + 1] = r.top
        ..[p + 2] = r.right
        ..[p + 3] = r.top
        ..[p + 4] = r.right
        ..[p + 5] = r.bottom
        ..[p + 6] = r.left
        ..[p + 7] = r.top
        ..[p + 8] = r.right
        ..[p + 9] = r.bottom
        ..[p + 10] = r.left
        ..[p + 11] = r.bottom;
      final argb = _color(n).toARGB32();
      for (var k = 0; k < 6; k++) {
        col[c + k] = argb;
      }
      i++;
    }
    return ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(pos, 0, i * 12),
      colors: Int32List.sublistView(col, 0, i * 6),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final graph = controller.graph;
    final sel = controller.selection.value;
    final (s, offset) = transform(controller, size);
    final key = (graph, controller.renderStamp, theme);
    if (cache.key != key) {
      cache.vertices?.dispose();
      cache.vertices = _build(
        graph.nodes.where((n) => !sel.nodes.contains(n.id)),
        graph.nodeCount,
      );
      cache.key = key;
    }
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(s);
    canvas.drawVertices(cache.vertices!, BlendMode.dst, Paint());
    if (sel.nodes.isNotEmpty) {
      final selected = [for (final id in sel.nodes) ?graph.node(id)];
      final p = Paint()..color = theme.selectedBorderColor;
      for (final n in selected) {
        canvas.drawRect(n.rect, p);
      }
    }
    canvas.restore();

    final visible = controller.viewport.value.visibleRect(
      controller.viewportSize,
    );
    final vr = Rect.fromLTRB(
      visible.left * s + offset.dx,
      visible.top * s + offset.dy,
      visible.right * s + offset.dx,
      visible.bottom * s + offset.dy,
    );
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(vr);
    canvas
      ..drawPath(mask, Paint()..color = theme.minimapMaskColor)
      ..drawRect(
        vr,
        Paint()
          ..color = theme.minimapViewportColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
  }

  @override
  bool shouldRepaint(_MiniMapPainter old) =>
      old.controller != controller ||
      old.theme != theme ||
      old.nodeColor != nodeColor;
}
