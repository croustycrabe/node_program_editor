import 'dart:convert';
import 'dart:ui';

import '../edge.dart';
import '../ids.dart';
import '../json.dart';
import '../node.dart';
import '../viewport.dart';

/// Graphical state of one node.
class NodeDesign {
  /// Creates a node design.
  const NodeDesign({
    required this.position,
    this.size,
    this.locked = false,
    this.style,
  });

  /// Top-left corner, canvas units.
  final Offset position;

  /// Size (null = definition default).
  final Size? size;

  /// Whether the node is locked.
  final bool locked;

  /// Style overrides.
  final NodeStyle? style;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'x': position.dx,
    'y': position.dy,
    'w': size?.width,
    'h': size?.height,
    'locked': locked ? true : null,
    'style': style?.toJson(),
  });

  /// Parses JSON produced by [toJson].
  factory NodeDesign.fromJson(Map<String, Object?> json) {
    final w = readDouble(json['w']), h = readDouble(json['h']);
    return NodeDesign(
      position: Offset(readDouble(json['x']) ?? 0, readDouble(json['y']) ?? 0),
      size: w != null && h != null ? Size(w, h) : null,
      locked: json['locked'] == true,
      style: json['style'] == null
          ? null
          : NodeStyle.fromJson(asJsonMap(json['style'])),
    );
  }
}

/// Graphical state of one edge.
class EdgeDesign {
  /// Creates an edge design.
  const EdgeDesign({
    this.style = const EdgeStyle(),
    this.label,
    this.waypoints = const [],
  });

  /// Style.
  final EdgeStyle style;

  /// Label.
  final String? label;

  /// Waypoints, canvas units.
  final List<Offset> waypoints;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'style': style.toJson(),
    'label': label,
    'waypoints': waypoints.isEmpty
        ? null
        : [for (final w in waypoints) offsetToJson(w)],
  });

  /// Parses JSON produced by [toJson].
  factory EdgeDesign.fromJson(Map<String, Object?> json) => EdgeDesign(
    style: json['style'] == null
        ? const EdgeStyle()
        : EdgeStyle.fromJson(asJsonMap(json['style'])),
    label: json['label'] as String?,
    waypoints: [
      for (final w in asJsonList(json['waypoints'])) offsetFromJson(w),
    ],
  );
}

/// Graphical state of a graph (top level or super node interior).
class GraphDesign {
  /// Creates a graph design.
  GraphDesign({Map<NodeId, NodeDesign>? nodes, Map<EdgeId, EdgeDesign>? edges})
    : nodes = nodes ?? {},
      edges = edges ?? {};

  /// Node designs by id.
  final Map<NodeId, NodeDesign> nodes;

  /// Edge designs by id.
  final Map<EdgeId, EdgeDesign> edges;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
    'nodes': {for (final e in nodes.entries) e.key.value: e.value.toJson()},
    'edges': {for (final e in edges.entries) e.key.value: e.value.toJson()},
  };

  /// Parses JSON produced by [toJson].
  factory GraphDesign.fromJson(Map<String, Object?> json) => GraphDesign(
    nodes: {
      for (final e in asJsonMap(json['nodes'] ?? const {}).entries)
        NodeId(e.key): NodeDesign.fromJson(asJsonMap(e.value)),
    },
    edges: {
      for (final e in asJsonMap(json['edges'] ?? const {}).entries)
        EdgeId(e.key): EdgeDesign.fromJson(asJsonMap(e.value)),
    },
  );
}

/// The design file: everything about how the graph looks (positions, sizes,
/// styles, viewport, grid) but nothing about what it does. Joined with the
/// [LogicDocument] by node and edge ids.
class DesignDocument {
  /// Creates a design document.
  DesignDocument({
    this.viewport = const EditorViewport(),
    this.canvas = const CanvasSettings(),
    GraphDesign? graph,
    Map<String, GraphDesign>? superNodes,
    this.schemaVersion = currentSchemaVersion,
  }) : graph = graph ?? GraphDesign(),
       superNodes = superNodes ?? {};

  /// Format identifier written in files.
  static const format = 'node_program_editor/design';

  /// Schema version written by this package.
  static const currentSchemaVersion = 1;

  /// Version of the loaded file.
  final int schemaVersion;

  /// Saved viewport.
  final EditorViewport viewport;

  /// Grid and snapping settings.
  final CanvasSettings canvas;

  /// Top level graph design.
  final GraphDesign graph;

  /// Interior designs of super node definitions, by definition id.
  final Map<String, GraphDesign> superNodes;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'format': format,
    'schemaVersion': schemaVersion,
    'viewport': viewport.toJson(),
    'canvas': canvas.toJson(),
    ...graph.toJson(),
    'superNodes': superNodes.isEmpty
        ? null
        : {for (final e in superNodes.entries) e.key: e.value.toJson()},
  });

  /// Pretty printed JSON.
  String toJsonString({bool pretty = true}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toJson());

  /// Parses JSON produced by [toJson].
  factory DesignDocument.fromJson(Map<String, Object?> json) => DesignDocument(
    schemaVersion: readInt(json['schemaVersion']) ?? 1,
    viewport: json['viewport'] == null
        ? const EditorViewport()
        : EditorViewport.fromJson(asJsonMap(json['viewport'])),
    canvas: json['canvas'] == null
        ? const CanvasSettings()
        : CanvasSettings.fromJson(asJsonMap(json['canvas'])),
    graph: GraphDesign.fromJson(json),
    superNodes: {
      for (final e in asJsonMap(json['superNodes'] ?? const {}).entries)
        e.key: GraphDesign.fromJson(asJsonMap(e.value)),
    },
  );

  /// Parses a JSON string.
  factory DesignDocument.fromJsonString(String source) =>
      DesignDocument.fromJson(asJsonMap(jsonDecode(source)));
}
