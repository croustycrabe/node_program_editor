import 'dart:convert';
import 'dart:ui';

import '../edge.dart';
import '../graph.dart';
import '../ids.dart';
import '../json.dart';
import '../node.dart';
import '../ports.dart';
import 'design_document.dart';
import 'graph_codec.dart';
import 'logic_document.dart';

/// A self-contained piece of a graph: what copy / paste and super node
/// libraries exchange. Serialized as JSON so it can travel through the
/// system clipboard between editor instances or applications.
class GraphFragment {
  /// Creates a fragment.
  GraphFragment({
    this.nodes = const [],
    this.edges = const [],
    GraphDesign? design,
    this.superNodes = const {},
    this.superNodeDesigns = const {},
  }) : design = design ?? GraphDesign();

  /// Captures [nodeIds] from [graph] together with the edges between them.
  factory GraphFragment.capture(Graph graph, Iterable<NodeId> nodeIds) {
    final ids = nodeIds.toSet();
    final nodes = [
      for (final n in graph.nodes)
        if (ids.contains(n.id)) n,
    ];
    final edges = [
      for (final e in graph.edges)
        if (ids.contains(e.source.node) && ids.contains(e.target.node)) e,
    ];
    final (ln, le, d) = GraphCodec.encode(nodes, edges);
    return GraphFragment(nodes: ln, edges: le, design: d);
  }

  /// Format identifier.
  static const format = 'node_program_editor/fragment';

  /// Nodes.
  final List<LogicNode> nodes;

  /// Edges.
  final List<LogicEdge> edges;

  /// Geometry and styles.
  final GraphDesign design;

  /// Super node definitions used by [nodes].
  final Map<String, LogicSuperNode> superNodes;

  /// Interior designs of [superNodes].
  final Map<String, GraphDesign> superNodeDesigns;

  /// Whether the fragment has no nodes.
  bool get isEmpty => nodes.isEmpty;

  /// Bounds of the fragment nodes (null when empty).
  Rect? get bounds {
    Rect? r;
    for (final d in design.nodes.values) {
      final rect = d.position & (d.size ?? const Size(160, 80));
      r = r == null ? rect : r.expandToInclude(rect);
    }
    return r;
  }

  /// Creates fresh instances with new ids, translated by [delta].
  (List<NodeInstance>, List<Edge>) instantiate(
    NodeRegistry registry, {
    Offset delta = Offset.zero,
  }) {
    final idMap = <NodeId, NodeId>{};
    final nodesOut = <NodeInstance>[];
    for (final ln in nodes) {
      final newId = IdGenerator.node();
      idMap[ln.id] = newId;
      final d = design.nodes[ln.id];
      final node = GraphCodec.decodeNode(ln.copyWith(id: newId), d, registry);
      node.position += delta;
      nodesOut.add(node);
    }
    final edgesOut = <Edge>[];
    for (final le in edges) {
      final s = idMap[le.source.node], t = idMap[le.target.node];
      if (s == null || t == null) continue;
      final d = design.edges[le.id];
      edgesOut.add(
        Edge(
          id: IdGenerator.edge(),
          source: PortRef(s, le.source.port),
          target: PortRef(t, le.target.port),
          style: d?.style ?? const EdgeStyle(),
          label: d?.label,
          waypoints: [
            for (final w in d?.waypoints ?? const <Offset>[]) w + delta,
          ],
          data: Map.of(le.data),
        ),
      );
    }
    return (nodesOut, edgesOut);
  }

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'format': format,
    'nodes': [for (final n in nodes) n.toJson()],
    'edges': [for (final e in edges) e.toJson()],
    'design': design.toJson(),
    'superNodes': superNodes.isEmpty
        ? null
        : {for (final e in superNodes.entries) e.key: e.value.toJson()},
    'superNodeDesigns': superNodeDesigns.isEmpty
        ? null
        : {for (final e in superNodeDesigns.entries) e.key: e.value.toJson()},
  });

  /// JSON string.
  String toJsonString() => jsonEncode(toJson());

  /// Parses JSON produced by [toJson].
  factory GraphFragment.fromJson(Map<String, Object?> json) => GraphFragment(
    nodes: [
      for (final n in asJsonList(json['nodes']))
        LogicNode.fromJson(asJsonMap(n)),
    ],
    edges: [
      for (final e in asJsonList(json['edges']))
        LogicEdge.fromJson(asJsonMap(e)),
    ],
    design: json['design'] == null
        ? null
        : GraphDesign.fromJson(asJsonMap(json['design'])),
    superNodes: {
      for (final e in asJsonMap(json['superNodes'] ?? const {}).entries)
        e.key: LogicSuperNode.fromJson(asJsonMap(e.value)),
    },
    superNodeDesigns: {
      for (final e in asJsonMap(json['superNodeDesigns'] ?? const {}).entries)
        e.key: GraphDesign.fromJson(asJsonMap(e.value)),
    },
  );

  /// Parses [text] when it is a fragment, otherwise returns null.
  static GraphFragment? tryParse(String? text) {
    if (text == null || !text.contains(format)) return null;
    try {
      final json = asJsonMap(jsonDecode(text));
      if (json['format'] != format) return null;
      return GraphFragment.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
