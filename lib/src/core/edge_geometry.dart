import 'dart:math' as math;
import 'dart:ui';

import 'edge.dart';
import 'ports.dart';

/// Input of an edge routing function.
class EdgePathInput {
  /// Creates a routing input.
  const EdgePathInput({
    required this.source,
    required this.sourceSide,
    required this.target,
    required this.targetSide,
    this.style = const EdgeStyle(),
    this.waypoints = const [],
  });

  /// Source anchor, canvas coordinates.
  final Offset source;

  /// Side of the source port.
  final PortSide sourceSide;

  /// Target anchor, canvas coordinates.
  final Offset target;

  /// Side of the target port.
  final PortSide targetSide;

  /// Edge style.
  final EdgeStyle style;

  /// User waypoints.
  final List<Offset> waypoints;
}

/// A custom routing function; register it with
/// `NodeEditorController.registerEdgePathBuilder` and reference it with
/// [EdgeStyle.customPath].
typedef EdgePathBuilder = EdgeGeometry Function(EdgePathInput input);

/// A routed edge: a drawable [path] plus a [polyline] approximation used for
/// hit testing, label placement and markers.
class EdgeGeometry {
  /// Creates an edge geometry.
  EdgeGeometry(this.path, this.polyline) : assert(polyline.length >= 2);

  /// Creates a geometry whose path is the [polyline] itself.
  factory EdgeGeometry.fromPolyline(
    List<Offset> polyline, {
    double cornerRadius = 0,
  }) {
    return EdgeGeometry(
      EdgeRouter.roundedPolylinePath(polyline, cornerRadius),
      polyline,
    );
  }

  /// The drawable path.
  final Path path;

  /// Polyline approximation of [path].
  final List<Offset> polyline;

  Rect? _bounds;
  double? _length;

  /// Bounds of the polyline.
  Rect get bounds => _bounds ??= _computeBounds();

  Rect _computeBounds() {
    var l = polyline.first.dx, r = l, t = polyline.first.dy, b = t;
    for (final p in polyline) {
      if (p.dx < l) l = p.dx;
      if (p.dx > r) r = p.dx;
      if (p.dy < t) t = p.dy;
      if (p.dy > b) b = p.dy;
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  /// Total polyline length.
  double get length {
    if (_length != null) return _length!;
    var len = 0.0;
    for (var i = 1; i < polyline.length; i++) {
      len += (polyline[i] - polyline[i - 1]).distance;
    }
    return _length = len;
  }

  /// The point at fraction [t] of the length.
  Offset pointAt(double t) {
    var remaining = length * t.clamp(0.0, 1.0);
    for (var i = 1; i < polyline.length; i++) {
      final a = polyline[i - 1], b = polyline[i];
      final seg = (b - a).distance;
      if (remaining <= seg && seg > 0) {
        return Offset.lerp(a, b, remaining / seg)!;
      }
      remaining -= seg;
    }
    return polyline.last;
  }

  /// Middle point (label anchor).
  Offset get midpoint => pointAt(0.5);

  /// Unit direction at the target end.
  Offset get endDirection => _dir(polyline[polyline.length - 2], polyline.last);

  /// Unit direction at the source end (pointing away from the edge).
  Offset get startDirection => _dir(polyline[1], polyline.first);

  static Offset _dir(Offset a, Offset b) {
    final d = b - a;
    final len = d.distance;
    return len == 0 ? const Offset(1, 0) : d / len;
  }

  /// Distance from [p] to the polyline.
  double distanceTo(Offset p) {
    var best = double.infinity;
    for (var i = 1; i < polyline.length; i++) {
      final d = EdgeRouter.distanceToSegment(p, polyline[i - 1], polyline[i]);
      if (d < best) best = d;
    }
    return best;
  }
}

/// Built-in edge routing algorithms.
abstract final class EdgeRouter {
  /// Distance an orthogonal route travels out of a port before turning.
  static const double portOffset = 20;

  /// Routes an edge.
  static EdgeGeometry route(
    EdgePathInput input, {
    Map<String, EdgePathBuilder> custom = const {},
  }) {
    final style = input.style;
    switch (style.pathType) {
      case EdgePathType.straight:
        return EdgeGeometry.fromPolyline([input.source, input.target]);
      case EdgePathType.bezier:
        return bezier(input);
      case EdgePathType.step:
        return EdgeGeometry.fromPolyline(stepPoints(input));
      case EdgePathType.smoothStep:
        return EdgeGeometry.fromPolyline(
          stepPoints(input),
          cornerRadius: style.cornerRadius,
        );
      case EdgePathType.orthogonal:
        if (input.waypoints.isEmpty) {
          return EdgeGeometry.fromPolyline(
            stepPoints(input),
            cornerRadius: style.cornerRadius,
          );
        }
        return EdgeGeometry.fromPolyline(
          orthogonalPoints(input),
          cornerRadius: style.cornerRadius,
        );
      case EdgePathType.polyline:
        return EdgeGeometry.fromPolyline([
          input.source,
          ...input.waypoints,
          input.target,
        ]);
      case EdgePathType.custom:
        final builder = custom[style.customPath];
        return builder != null ? builder(input) : bezier(input);
    }
  }

  /// Cubic bezier leaving and entering along the port side normals.
  static EdgeGeometry bezier(EdgePathInput input) {
    final s = input.source, t = input.target;
    final dist = (t - s).distance;
    final k = input.style.curvature;
    // Distance of the control point from `from`, which leaves through `side`
    // heading towards `to`.
    double controlDistance(PortSide side, Offset from, Offset to) {
      final along = side.isHorizontal ? (to.dx - from.dx) : (to.dy - from.dy);
      final forward = side == PortSide.right || side == PortSide.bottom
          ? along >= 0
          : along <= 0;
      final base = forward ? along.abs() * k : 25 * k * math.sqrt(dist);
      return math.max(base, 24.0);
    }

    final c1 =
        s + input.sourceSide.normal * controlDistance(input.sourceSide, s, t);
    final c2 =
        t + input.targetSide.normal * controlDistance(input.targetSide, t, s);
    final path = Path()
      ..moveTo(s.dx, s.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, t.dx, t.dy);
    const n = 24;
    final pts = <Offset>[
      for (var i = 0; i <= n; i++) cubicPoint(s, c1, c2, t, i / n),
    ];
    return EdgeGeometry(path, pts);
  }

  /// Point at parameter [t] of a cubic bezier.
  static Offset cubicPoint(
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
    double t,
  ) {
    final mt = 1 - t;
    final a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t;
    final d = t * t * t;
    return Offset(
      a * p0.dx + b * p1.dx + c * p2.dx + d * p3.dx,
      a * p0.dy + b * p1.dy + c * p2.dy + d * p3.dy,
    );
  }

  /// Orthogonal route between two ports (no waypoints).
  static List<Offset> stepPoints(EdgePathInput input) {
    final s = input.source, t = input.target;
    final ns = input.sourceSide, nt = input.targetSide;
    final s1 = s + ns.normal * portOffset;
    final t1 = t + nt.normal * portOffset;
    List<Offset> pts;
    if (ns.isHorizontal && nt.isHorizontal) {
      final forward =
          (ns == PortSide.right && t1.dx >= s1.dx) ||
          (ns == PortSide.left && t1.dx <= s1.dx);
      if (ns != nt && forward) {
        final midX = (s.dx + t.dx) / 2;
        pts = [s, Offset(midX, s.dy), Offset(midX, t.dy), t];
      } else if (ns == nt) {
        final x = ns == PortSide.right
            ? math.max(s1.dx, t1.dx)
            : math.min(s1.dx, t1.dx);
        pts = [s, Offset(x, s.dy), Offset(x, t.dy), t];
      } else {
        final midY = (s.dy + t.dy) / 2;
        pts = [s, s1, Offset(s1.dx, midY), Offset(t1.dx, midY), t1, t];
      }
    } else if (!ns.isHorizontal && !nt.isHorizontal) {
      final forward =
          (ns == PortSide.bottom && t1.dy >= s1.dy) ||
          (ns == PortSide.top && t1.dy <= s1.dy);
      if (ns != nt && forward) {
        final midY = (s.dy + t.dy) / 2;
        pts = [s, Offset(s.dx, midY), Offset(t.dx, midY), t];
      } else if (ns == nt) {
        final y = ns == PortSide.bottom
            ? math.max(s1.dy, t1.dy)
            : math.min(s1.dy, t1.dy);
        pts = [s, Offset(s.dx, y), Offset(t.dx, y), t];
      } else {
        final midX = (s.dx + t.dx) / 2;
        pts = [s, s1, Offset(midX, s1.dy), Offset(midX, t1.dy), t1, t];
      }
    } else if (ns.isHorizontal) {
      pts = [s, s1, Offset(t1.dx, s1.dy), t1, t];
    } else {
      pts = [s, s1, Offset(s1.dx, t1.dy), t1, t];
    }
    return simplify(pts);
  }

  /// Orthogonal route through user waypoints.
  static List<Offset> orthogonalPoints(EdgePathInput input) {
    final s = input.source, t = input.target;
    final s1 = s + input.sourceSide.normal * portOffset;
    final t1 = t + input.targetSide.normal * portOffset;
    final raw = [s, s1, ...input.waypoints, t1, t];
    final pts = <Offset>[raw.first];
    for (var i = 1; i < raw.length; i++) {
      final a = pts.last, b = raw[i];
      if (a.dx != b.dx && a.dy != b.dy) {
        // Insert an elbow; prefer continuing the previous segment direction.
        final prevHorizontal =
            pts.length >= 2 && pts[pts.length - 2].dy == a.dy;
        pts.add(prevHorizontal ? Offset(a.dx, b.dy) : Offset(b.dx, a.dy));
      }
      pts.add(b);
    }
    return simplify(pts);
  }

  /// Removes duplicate and collinear interior points.
  static List<Offset> simplify(List<Offset> pts) {
    final out = <Offset>[];
    for (final p in pts) {
      if (out.isNotEmpty && (out.last - p).distanceSquared < 1e-6) continue;
      if (out.length >= 2) {
        final a = out[out.length - 2], b = out.last;
        final cross =
            (b.dx - a.dx) * (p.dy - b.dy) - (b.dy - a.dy) * (p.dx - b.dx);
        if (cross.abs() < 1e-6) {
          out[out.length - 1] = p;
          continue;
        }
      }
      out.add(p);
    }
    if (out.length < 2) out.add(out.first);
    return out;
  }

  /// A path through [pts] with corners rounded by [radius].
  static Path roundedPolylinePath(List<Offset> pts, double radius) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (radius <= 0 || pts.length < 3) {
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      return path;
    }
    for (var i = 1; i < pts.length - 1; i++) {
      final a = pts[i - 1], p = pts[i], b = pts[i + 1];
      final da = a - p, db = b - p;
      final r = math.min(radius, math.min(da.distance, db.distance) / 2);
      final start = p + da / da.distance * r;
      final end = p + db / db.distance * r;
      path
        ..lineTo(start.dx, start.dy)
        ..quadraticBezierTo(p.dx, p.dy, end.dx, end.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }

  /// Distance from [p] to segment [a]-[b].
  static double distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    if (len2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }

  /// Cheap conservative bounds used by the spatial index before the exact
  /// route is computed.
  static Rect estimateBounds(EdgePathInput input) {
    var r = Rect.fromPoints(input.source, input.target);
    for (final w in input.waypoints) {
      r = r.expandToInclude(Rect.fromCenter(center: w, width: 1, height: 1));
    }
    final margin = switch (input.style.pathType) {
      EdgePathType.bezier || EdgePathType.custom => math.max(
        40.0,
        (input.target - input.source).distance * 0.5,
      ),
      _ => portOffset + 4,
    };
    return r.inflate(margin);
  }
}
