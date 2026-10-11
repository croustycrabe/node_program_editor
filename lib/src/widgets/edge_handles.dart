import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/edge.dart';
import '../core/ids.dart';
import 'scope.dart';

/// Waypoint handles of the selected edge (draw.io style):
///
/// * drag a waypoint to move it (snapped when `snapEdgesToGrid` is on),
/// * double tap a waypoint to remove it,
/// * drag a segment's "+" handle to insert a waypoint. Curved / stepped
///   edges are converted to polyline / orthogonal routing on first insert.
class EdgeWaypointOverlay extends StatelessWidget {
  /// Creates the overlay.
  const EdgeWaypointOverlay({super.key, required this.controller});

  /// Controller.
  final NodeEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: Listenable.merge([
        c.selection,
        c.edgesListenable,
        c.viewport,
      ]),
      builder: (context, _) {
        final id = c.selection.value.singleEdge;
        final edge = id == null ? null : c.graph.edge(id);
        if (edge == null ||
            !c.config.edgesSelectable ||
            c.viewport.value.zoom < c.config.lodThreshold) {
          return const SizedBox.shrink();
        }
        final geometry = c.edgeGeometry(edge);
        if (geometry == null) return const SizedBox.shrink();
        final v = c.viewport.value;
        final theme = NodeEditorScope.of(context).theme;
        final children = <Widget>[];
        for (var i = 0; i < edge.waypoints.length; i++) {
          children.add(
            _Handle(
              key: ValueKey('wp$i'),
              controller: c,
              edgeId: edge.id,
              screen: v.toScreen(edge.waypoints[i]),
              color: theme.selectedEdgeColor,
              index: i,
              insert: false,
            ),
          );
        }
        // "+" handles: one per segment for angular routes, one at the
        // middle of curved routes.
        final pts = geometry.polyline;
        final curved =
            edge.style.pathType == EdgePathType.bezier ||
            edge.style.pathType == EdgePathType.custom;
        final mids = curved
            ? [geometry.midpoint]
            : [
                for (var s = 1; s < pts.length; s++)
                  if ((pts[s] - pts[s - 1]).distance * v.zoom >= 36)
                    (pts[s - 1] + pts[s]) / 2,
              ];
        for (var i = 0; i < mids.length; i++) {
          children.add(
            _Handle(
              key: ValueKey('ins$i'),
              controller: c,
              edgeId: edge.id,
              screen: v.toScreen(mids[i]),
              color: theme.selectedEdgeColor,
              index: _insertIndex(pts, edge.waypoints, mids[i]),
              insert: true,
            ),
          );
        }
        return Stack(children: children);
      },
    );
  }

  /// Index at which a waypoint inserted at [mid] belongs: the number of
  /// existing waypoints located before it along the route.
  static int _insertIndex(
    List<Offset> polyline,
    List<Offset> waypoints,
    Offset mid,
  ) {
    final at = _arc(polyline, mid);
    return waypoints.where((w) => _arc(polyline, w) < at).length;
  }

  /// Distance along [polyline] of the point closest to [p].
  static double _arc(List<Offset> polyline, Offset p) {
    var best = double.infinity, bestArc = 0.0, walked = 0.0;
    for (var i = 1; i < polyline.length; i++) {
      final a = polyline[i - 1], b = polyline[i];
      final ab = b - a;
      final len = ab.distance;
      final t = len == 0
          ? 0.0
          : (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / (len * len))
                .clamp(0.0, 1.0);
      final d = (p - (a + ab * t)).distance;
      if (d < best) {
        best = d;
        bestArc = walked + len * t;
      }
      walked += len;
    }
    return bestArc;
  }
}

class _Handle extends StatefulWidget {
  const _Handle({
    super.key,
    required this.controller,
    required this.edgeId,
    required this.screen,
    required this.color,
    required this.index,
    required this.insert,
  });

  final NodeEditorController controller;
  final EdgeId edgeId;
  final Offset screen;
  final Color color;
  final int index;
  final bool insert;

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  int? _dragIndex;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  NodeEditorController get c => widget.controller;

  Offset _snap(Offset p) {
    final s = c.canvasSettings.value;
    if (!s.snapEdgesToGrid) return p;
    return Offset(
      (p.dx / s.gridSpacing).roundToDouble() * s.gridSpacing,
      (p.dy / s.gridSpacing).roundToDouble() * s.gridSpacing,
    );
  }

  void _start(DragStartDetails d) {
    c.beginTransaction(widget.insert ? 'Add waypoint' : 'Move waypoint');
    final scope = NodeEditorScope.of(context);
    final p = _snap(scope.globalToCanvas(d.globalPosition));
    if (widget.insert) {
      c.updateEdge(widget.edgeId, (e) {
        final type = switch (e.style.pathType) {
          EdgePathType.orthogonal || EdgePathType.polyline => e.style.pathType,
          EdgePathType.step ||
          EdgePathType.smoothStep => EdgePathType.orthogonal,
          _ => EdgePathType.polyline,
        };
        final wps = [...e.waypoints]..insert(widget.index, p);
        return e.copyWith(
          waypoints: wps,
          style: e.style.copyWith(pathType: type),
        );
      });
    }
    _dragIndex = widget.index;
  }

  void _update(DragUpdateDetails d) {
    final i = _dragIndex;
    if (i == null) return;
    final scope = NodeEditorScope.of(context);
    final p = _snap(scope.globalToCanvas(d.globalPosition));
    c.updateEdge(widget.edgeId, (e) {
      if (i >= e.waypoints.length) return e;
      final wps = [...e.waypoints];
      wps[i] = p;
      return e.copyWith(waypoints: wps);
    });
  }

  void _end() {
    _dragIndex = null;
    c.commitTransaction();
  }

  void _tap() {
    final now = DateTime.now();
    if (!widget.insert && now.difference(_lastTap) < kDoubleTapTimeout) {
      c.updateEdge(
        widget.edgeId,
        (e) => e.copyWith(waypoints: [...e.waypoints]..removeAt(widget.index)),
      );
    }
    _lastTap = now;
  }

  @override
  Widget build(BuildContext context) {
    const size = 14.0;
    return Positioned(
      left: widget.screen.dx - size / 2,
      top: widget.screen.dy - size / 2,
      width: size,
      height: size,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: _tap,
          onPanStart: _start,
          onPanUpdate: _update,
          onPanEnd: (_) => _end(),
          onPanCancel: _end,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.insert ? Colors.white : widget.color,
              shape: widget.insert ? BoxShape.circle : BoxShape.rectangle,
              border: Border.all(color: widget.color, width: 2),
            ),
            child: widget.insert
                ? Icon(Icons.add, size: 9, color: widget.color)
                : null,
          ),
        ),
      ),
    );
  }
}
