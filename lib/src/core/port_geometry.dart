import 'dart:ui';

import 'node.dart';
import 'ports.dart';

/// Computes port anchor positions from the node model.
///
/// Anchors depend only on the node size, its port list and its
/// [PortLayout]: never on measured widgets. Edges, hit testing, the low-LOD
/// renderer and the node widgets therefore always agree, with no
/// post-frame measurement pass.
abstract final class PortGeometry {
  static final Expando<_AnchorCache> _cache = Expando('portAnchors');

  /// Anchors of every port of [node], relative to the node's top-left.
  static Map<String, Offset> relativeAnchors(NodeInstance node) {
    final ports = node.ports;
    final cached = _cache[node];
    if (cached != null &&
        cached.size == node.size &&
        identical(cached.ports, ports)) {
      return cached.anchors;
    }
    final anchors = compute(node.size, ports, node.definition.portLayout);
    _cache[node] = _AnchorCache(node.size, ports, anchors);
    return anchors;
  }

  /// Anchor of [portId] in canvas coordinates (null for unknown ports).
  static Offset? anchor(NodeInstance node, String portId) {
    final rel = relativeAnchors(node)[portId];
    return rel == null ? null : node.position + rel;
  }

  /// Computes relative anchors for [ports] on a node of [size].
  static Map<String, Offset> compute(
    Size size,
    List<PortSpec> ports,
    PortLayout layout,
  ) {
    final bySide = <PortSide, List<PortSpec>>{};
    for (final p in ports) {
      if (p.alignment == null) {
        (bySide[p.effectiveSide] ??= []).add(p);
      }
    }
    final result = <String, Offset>{};
    for (final p in ports) {
      final side = p.effectiveSide;
      final double along;
      if (p.alignment != null) {
        along = (side.isHorizontal ? size.height : size.width) * p.alignment!;
      } else {
        final list = bySide[side]!;
        final i = list.indexOf(p);
        along = side.isHorizontal
            ? _stacked(size.height, i, list.length, layout)
            : size.width * (i + 1) / (list.length + 1);
      }
      result[p.id] = switch (side) {
        PortSide.left => Offset(0, along),
        PortSide.right => Offset(size.width, along),
        PortSide.top => Offset(along, 0),
        PortSide.bottom => Offset(along, size.height),
      };
    }
    return result;
  }

  static double _stacked(double height, int i, int n, PortLayout l) {
    final y = l.headerHeight + l.padding + l.rowHeight * (i + 0.5);
    final lastY = l.headerHeight + l.padding + l.rowHeight * (n - 0.5);
    if (lastY <= height - l.padding / 2) return y;
    // Not enough room: distribute evenly below the header instead.
    final top = l.headerHeight.clamp(0.0, height * 0.4);
    return top + (height - top) * (i + 1) / (n + 1);
  }
}

class _AnchorCache {
  _AnchorCache(this.size, this.ports, this.anchors);
  final Size size;
  final List<PortSpec> ports;
  final Map<String, Offset> anchors;
}
