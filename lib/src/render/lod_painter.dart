import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../core/controller.dart';
import '../core/node.dart';
import '../widgets/theme.dart';

/// Caches the low-detail vertex buffers of one canvas.
class LodRenderCache {
  Object? _key;
  ui.Vertices? _static;
  final Map<String, ui.Paragraph> _titles = {};

  /// Drops cached buffers.
  void clear() {
    _static?.dispose();
    _static = null;
    _key = null;
    _titles.clear();
  }
}

/// Builds batched quads for many nodes: positions + per-vertex colors.
class _QuadBuilder {
  _QuadBuilder(int quads)
    : positions = Float32List(quads * 12),
      colors = Int32List(quads * 6);

  final Float32List positions;
  final Int32List colors;
  int _q = 0;

  void add(Rect r, Color color) {
    final p = _q * 12, c = _q * 6;
    final l = r.left, t = r.top, rt = r.right, b = r.bottom;
    positions
      ..[p] = l
      ..[p + 1] = t
      ..[p + 2] = rt
      ..[p + 3] = t
      ..[p + 4] = rt
      ..[p + 5] = b
      ..[p + 6] = l
      ..[p + 7] = t
      ..[p + 8] = rt
      ..[p + 9] = b
      ..[p + 10] = l
      ..[p + 11] = b;
    final argb = color.toARGB32();
    for (var i = 0; i < 6; i++) {
      colors[c + i] = argb;
    }
    _q++;
  }

  ui.Vertices build() => ui.Vertices.raw(
    ui.VertexMode.triangles,
    Float32List.sublistView(positions, 0, _q * 12),
    colors: Int32List.sublistView(colors, 0, _q * 6),
  );
}

/// Renders nodes when zoomed out below `NodeEditorConfig.lodThreshold`.
///
/// No widget is built: every node becomes two colored quads (body + header)
/// and the whole graph is drawn with a single `drawVertices` call from a
/// buffer that is rebuilt only when non-selected nodes change. Selected
/// nodes (usually the ones being dragged) go in a small per-frame buffer,
/// so dragging stays cheap even with tens of thousands of nodes.
class LodNodePainter extends CustomPainter {
  /// Creates the painter.
  LodNodePainter({
    required this.controller,
    required this.theme,
    required this.cache,
  }) : super(
         repaint: Listenable.merge([
           controller.viewport,
           controller.geometry,
           controller.structure,
           controller.selection,
         ]),
       );

  /// Controller.
  final NodeEditorController controller;

  /// Theme.
  final NodeEditorThemeData theme;

  /// Shared caches.
  final LodRenderCache cache;

  static void _addNode(
    _QuadBuilder q,
    NodeInstance n,
    NodeEditorThemeData theme, {
    Color? outline,
    double outlineWidth = 0,
  }) {
    final colors = resolveNodeColors(n, theme);
    final r = n.rect;
    if (outline != null) q.add(r.inflate(outlineWidth), outline);
    q.add(r, colors.body);
    final header = math.min(
      n.definition.portLayout.headerHeight,
      r.height * 0.5,
    );
    q.add(Rect.fromLTWH(r.left, r.top, r.width, header), colors.header);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = controller.viewport.value;
    final config = controller.config;
    if (v.zoom >= config.lodThreshold) return;
    final graph = controller.graph;
    final sel = controller.selection.value;

    final key = (graph, controller.renderStamp, theme);
    if (cache._key != key) {
      cache._static?.dispose();
      final q = _QuadBuilder(graph.nodeCount * 2);
      for (final n in graph.nodes) {
        if (!sel.nodes.contains(n.id)) _addNode(q, n, theme);
      }
      cache
        .._static = q.build()
        .._key = key;
    }

    canvas
      ..save()
      ..transform(v.matrix.storage);
    final paint = Paint();
    canvas.drawVertices(cache._static!, BlendMode.dst, paint);

    if (sel.nodes.isNotEmpty) {
      final q = _QuadBuilder(sel.nodes.length * 3);
      for (final id in sel.nodes) {
        final n = graph.node(id);
        if (n != null) {
          _addNode(
            q,
            n,
            theme,
            outline: theme.selectedBorderColor,
            outlineWidth: 3 / v.zoom,
          );
        }
      }
      final vertices = q.build();
      canvas.drawVertices(vertices, BlendMode.dst, paint);
      vertices.dispose();
    }

    if (v.zoom >= config.lodTextThreshold) {
      final visible = v.visibleRect(size);
      final fontSize = 14.0;
      for (final id in controller.nodeIndex.query(visible)) {
        final n = graph.node(id)!;
        final header = math.min(
          n.definition.portLayout.headerHeight,
          n.size.height * 0.5,
        );
        final width = n.size.width - 12;
        if (width <= 0) continue;
        final colors = resolveNodeColors(n, theme);
        final titleKey =
            '${n.displayTitle}|${width.round()}|${colors.text.toARGB32()}';
        final paragraph = cache._titles[titleKey] ??= _buildTitle(
          n.displayTitle,
          width,
          fontSize,
          colors.text,
        );
        canvas.drawParagraph(
          paragraph,
          Offset(
            n.position.dx + 6,
            n.position.dy + (header - paragraph.height) / 2,
          ),
        );
      }
      if (cache._titles.length > 4000) cache._titles.clear();
    }
    canvas.restore();
  }

  static ui.Paragraph _buildTitle(
    String text,
    double width,
    double fontSize,
    Color color,
  ) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              maxLines: 1,
              ellipsis: '…',
            ),
          )
          ..pushStyle(ui.TextStyle(color: color))
          ..addText(text);
    return builder.build()..layout(ui.ParagraphConstraints(width: width));
  }

  @override
  bool shouldRepaint(LodNodePainter old) =>
      old.controller != controller || old.theme != theme;
}
