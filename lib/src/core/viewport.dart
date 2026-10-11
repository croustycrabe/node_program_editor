import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show Matrix4;

import 'edge.dart';
import 'ids.dart';
import 'json.dart';

/// Pan / zoom state: `screen = canvas * zoom + offset`.
@immutable
class Viewport {
  /// Creates a viewport.
  const Viewport({this.offset = Offset.zero, this.zoom = 1});

  /// Screen position of the canvas origin, logical pixels.
  final Offset offset;

  /// Scale factor.
  final double zoom;

  /// Converts a screen point to canvas coordinates.
  Offset toCanvas(Offset screen) => (screen - offset) / zoom;

  /// Converts a canvas point to screen coordinates.
  Offset toScreen(Offset canvas) => canvas * zoom + offset;

  /// Converts a canvas rect to screen coordinates.
  Rect rectToScreen(Rect r) =>
      Rect.fromPoints(toScreen(r.topLeft), toScreen(r.bottomRight));

  /// The canvas area visible in a widget of [size].
  Rect visibleRect(Size size) => Rect.fromPoints(
    toCanvas(Offset.zero),
    toCanvas(size.bottomRight(Offset.zero)),
  );

  /// Canvas → screen transform.
  Matrix4 get matrix => Matrix4.identity()
    ..translateByDouble(offset.dx, offset.dy, 0, 1)
    ..scaleByDouble(zoom, zoom, 1, 1);

  /// Returns a copy with the given fields replaced.
  Viewport copyWith({Offset? offset, double? zoom}) =>
      Viewport(offset: offset ?? this.offset, zoom: zoom ?? this.zoom);

  /// Zooms to [newZoom] keeping the canvas point under [focal] (screen)
  /// fixed.
  Viewport zoomAround(Offset focal, double newZoom) {
    final c = toCanvas(focal);
    return Viewport(offset: focal - c * newZoom, zoom: newZoom);
  }

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
    'x': offset.dx,
    'y': offset.dy,
    'zoom': zoom,
  };

  /// Parses JSON produced by [toJson].
  factory Viewport.fromJson(Map<String, Object?> json) => Viewport(
    offset: Offset(readDouble(json['x']) ?? 0, readDouble(json['y']) ?? 0),
    zoom: readDouble(json['zoom']) ?? 1,
  );

  @override
  bool operator ==(Object other) =>
      other is Viewport && other.offset == offset && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(offset, zoom);

  @override
  String toString() => 'Viewport($offset, x$zoom)';
}

/// The current selection. Immutable; the controller publishes a new instance
/// on every change.
@immutable
class GraphSelection {
  /// Creates a selection.
  const GraphSelection({this.nodes = const {}, this.edges = const {}});

  /// The empty selection.
  static const empty = GraphSelection();

  /// Selected nodes.
  final Set<NodeId> nodes;

  /// Selected edges.
  final Set<EdgeId> edges;

  /// Whether nothing is selected.
  bool get isEmpty => nodes.isEmpty && edges.isEmpty;

  /// Whether something is selected.
  bool get isNotEmpty => !isEmpty;

  /// The single selected node, or null.
  NodeId? get singleNode =>
      nodes.length == 1 && edges.isEmpty ? nodes.first : null;

  /// The single selected edge, or null.
  EdgeId? get singleEdge =>
      edges.length == 1 && nodes.isEmpty ? edges.first : null;
}

/// Visual style of the background grid.
enum GridStyle {
  /// No grid.
  none,

  /// Dots at intersections.
  dots,

  /// Full lines.
  lines,

  /// Small crosses at intersections.
  cross,
}

/// Canvas level settings persisted in the design file.
@immutable
class CanvasSettings {
  /// Creates canvas settings.
  const CanvasSettings({
    this.gridStyle = GridStyle.dots,
    this.gridSpacing = 20,
    this.majorEvery = 5,
    this.snapToGrid = false,
    this.snapEdgesToGrid = false,
    this.defaultEdgeStyle = const EdgeStyle(),
    this.gridColor,
    this.majorGridColor,
    this.backgroundColor,
  });

  /// Grid style.
  final GridStyle gridStyle;

  /// Minor grid spacing in canvas units; also the snapping step.
  final double gridSpacing;

  /// A major line every N minor lines (0 or 1 disables).
  final int majorEvery;

  /// Whether node moves and resizes snap to the grid.
  final bool snapToGrid;

  /// Whether edge waypoints snap to the grid.
  final bool snapEdgesToGrid;

  /// Style of newly created edges.
  final EdgeStyle defaultEdgeStyle;

  /// Grid color override.
  final Color? gridColor;

  /// Major grid color override.
  final Color? majorGridColor;

  /// Background color override.
  final Color? backgroundColor;

  /// Whether the grid is drawn.
  bool get showGrid => gridStyle != GridStyle.none;

  /// Snaps [v] to the grid when [snapToGrid] is on.
  double snap(double v) =>
      snapToGrid ? (v / gridSpacing).roundToDouble() * gridSpacing : v;

  /// Snaps an offset to the grid when [snapToGrid] is on.
  Offset snapOffset(Offset o) => Offset(snap(o.dx), snap(o.dy));

  /// Returns a copy with the given fields replaced.
  CanvasSettings copyWith({
    GridStyle? gridStyle,
    double? gridSpacing,
    int? majorEvery,
    bool? snapToGrid,
    bool? snapEdgesToGrid,
    EdgeStyle? defaultEdgeStyle,
    Color? gridColor,
    Color? majorGridColor,
    Color? backgroundColor,
  }) => CanvasSettings(
    gridStyle: gridStyle ?? this.gridStyle,
    gridSpacing: gridSpacing ?? this.gridSpacing,
    majorEvery: majorEvery ?? this.majorEvery,
    snapToGrid: snapToGrid ?? this.snapToGrid,
    snapEdgesToGrid: snapEdgesToGrid ?? this.snapEdgesToGrid,
    defaultEdgeStyle: defaultEdgeStyle ?? this.defaultEdgeStyle,
    gridColor: gridColor ?? this.gridColor,
    majorGridColor: majorGridColor ?? this.majorGridColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
  );

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'gridStyle': gridStyle.name,
    'gridSpacing': gridSpacing,
    'majorEvery': majorEvery,
    'snapToGrid': snapToGrid,
    'snapEdgesToGrid': snapEdgesToGrid,
    'defaultEdgeStyle': defaultEdgeStyle.toJson(),
    'gridColor': colorToJson(gridColor),
    'majorGridColor': colorToJson(majorGridColor),
    'backgroundColor': colorToJson(backgroundColor),
  });

  /// Parses JSON produced by [toJson].
  factory CanvasSettings.fromJson(Map<String, Object?> json) => CanvasSettings(
    gridStyle:
        enumByName(GridStyle.values, json['gridStyle']) ?? GridStyle.dots,
    gridSpacing: readDouble(json['gridSpacing']) ?? 20,
    majorEvery: readInt(json['majorEvery']) ?? 5,
    snapToGrid: json['snapToGrid'] == true,
    snapEdgesToGrid: json['snapEdgesToGrid'] == true,
    defaultEdgeStyle: json['defaultEdgeStyle'] == null
        ? const EdgeStyle()
        : EdgeStyle.fromJson(asJsonMap(json['defaultEdgeStyle'])),
    gridColor: colorFromJson(json['gridColor']),
    majorGridColor: colorFromJson(json['majorGridColor']),
    backgroundColor: colorFromJson(json['backgroundColor']),
  );
}
