import 'dart:collection';

import 'edge.dart';
import 'ids.dart';
import 'node.dart';
import 'ports.dart';

/// In-memory graph store: nodes, edges and adjacency indexes.
///
/// * Nodes are kept in insertion order, which is also their z-order (last is
///   on top).
/// * Lookups by id, port link counts and node neighbourhoods are O(1).
///
/// The graph performs no validation and fires no notifications; use the
/// `NodeEditorController` to edit a displayed graph.
class Graph {
  /// Creates an empty graph.
  Graph();

  final LinkedHashMap<NodeId, NodeInstance> _nodes = LinkedHashMap();
  final LinkedHashMap<EdgeId, Edge> _edges = LinkedHashMap();
  final Map<NodeId, Set<EdgeId>> _nodeEdges = {};
  final Map<PortRef, Set<EdgeId>> _portEdges = {};
  Map<NodeId, int>? _zIndex;

  /// Nodes in z-order (bottom first).
  Iterable<NodeInstance> get nodes => _nodes.values;

  /// Edges in insertion order.
  Iterable<Edge> get edges => _edges.values;

  /// Node ids in z-order.
  Iterable<NodeId> get nodeIds => _nodes.keys;

  /// Number of nodes.
  int get nodeCount => _nodes.length;

  /// Number of edges.
  int get edgeCount => _edges.length;

  /// Whether the graph has no nodes.
  bool get isEmpty => _nodes.isEmpty;

  /// The node with [id], or null.
  NodeInstance? node(NodeId id) => _nodes[id];

  /// The edge with [id], or null.
  Edge? edge(EdgeId id) => _edges[id];

  /// Whether a node with [id] exists.
  bool containsNode(NodeId id) => _nodes.containsKey(id);

  /// Whether an edge with [id] exists.
  bool containsEdge(EdgeId id) => _edges.containsKey(id);

  /// The port spec referenced by [ref], or null.
  PortSpec? port(PortRef ref) => _nodes[ref.node]?.port(ref.port);

  /// Ids of edges touching node [id].
  Iterable<EdgeId> edgeIdsOfNode(NodeId id) => _nodeEdges[id] ?? const {};

  /// Edges touching node [id].
  Iterable<Edge> edgesOfNode(NodeId id) =>
      edgeIdsOfNode(id).map((e) => _edges[e]!);

  /// Edges attached to port [ref].
  Iterable<Edge> edgesOfPort(PortRef ref) =>
      (_portEdges[ref] ?? const {}).map((e) => _edges[e]!);

  /// Number of edges attached to port [ref].
  int linkCount(PortRef ref) => _portEdges[ref]?.length ?? 0;

  /// Edges whose target is node [id].
  Iterable<Edge> incoming(NodeId id) =>
      edgesOfNode(id).where((e) => e.target.node == id);

  /// Edges whose source is node [id].
  Iterable<Edge> outgoing(NodeId id) =>
      edgesOfNode(id).where((e) => e.source.node == id);

  /// The z-index of node [id] (0 = bottom), -1 if absent.
  int indexOfNode(NodeId id) {
    final z = _zIndex ??= {for (final (i, k) in _nodes.keys.indexed) k: i};
    return z[id] ?? -1;
  }

  /// Adds [node]. When [index] is given the node is inserted at that
  /// z-index (used by undo to restore order).
  void addNode(NodeInstance node, {int? index}) {
    _zIndex = null;
    if (index == null || index >= _nodes.length) {
      _nodes[node.id] = node;
    } else {
      final entries = _nodes.entries.toList();
      _nodes.clear();
      for (var i = 0; i < entries.length; i++) {
        if (i == index) _nodes[node.id] = node;
        _nodes[entries[i].key] = entries[i].value;
      }
    }
    _nodeEdges.putIfAbsent(node.id, () => {});
  }

  /// Removes node [id] and every edge touching it. Returns the removed edges.
  List<Edge> removeNode(NodeId id) {
    final removed = <Edge>[];
    for (final e in List.of(edgeIdsOfNode(id))) {
      final edge = removeEdge(e);
      if (edge != null) removed.add(edge);
    }
    _nodes.remove(id);
    _zIndex = null;
    _nodeEdges.remove(id);
    return removed;
  }

  /// Adds [edge]. Both endpoint nodes must exist.
  void addEdge(Edge edge) {
    assert(_nodes.containsKey(edge.source.node), 'Missing ${edge.source}');
    assert(_nodes.containsKey(edge.target.node), 'Missing ${edge.target}');
    _edges[edge.id] = edge;
    _nodeEdges.putIfAbsent(edge.source.node, () => {}).add(edge.id);
    _nodeEdges.putIfAbsent(edge.target.node, () => {}).add(edge.id);
    _portEdges.putIfAbsent(edge.source, () => {}).add(edge.id);
    _portEdges.putIfAbsent(edge.target, () => {}).add(edge.id);
  }

  /// Replaces an existing edge with the same id (style / waypoint edits).
  void replaceEdge(Edge edge) {
    final old = _edges[edge.id];
    if (old == null) return;
    if (old.source != edge.source || old.target != edge.target) {
      removeEdge(edge.id);
      addEdge(edge);
    } else {
      _edges[edge.id] = edge;
    }
  }

  /// Removes edge [id] and returns it.
  Edge? removeEdge(EdgeId id) {
    final edge = _edges.remove(id);
    if (edge == null) return null;
    _nodeEdges[edge.source.node]?.remove(id);
    _nodeEdges[edge.target.node]?.remove(id);
    _removePortEdge(edge.source, id);
    _removePortEdge(edge.target, id);
    return edge;
  }

  void _removePortEdge(PortRef ref, EdgeId id) {
    final set = _portEdges[ref];
    if (set == null) return;
    set.remove(id);
    if (set.isEmpty) _portEdges.remove(ref);
  }

  /// Moves node [id] to the top of the z-order.
  void bringToFront(NodeId id) {
    _zIndex = null;
    final node = _nodes.remove(id);
    if (node != null) _nodes[id] = node;
  }

  /// Whether a path exists from node [from] to node [to] following edge
  /// direction (used for cycle detection).
  bool hasPath(NodeId from, NodeId to) {
    if (from == to) return true;
    final visited = <NodeId>{from};
    final stack = [from];
    while (stack.isNotEmpty) {
      final n = stack.removeLast();
      for (final e in outgoing(n)) {
        final next = e.target.node;
        if (next == to) return true;
        if (visited.add(next)) stack.add(next);
      }
    }
    return false;
  }

  /// Nodes ordered so that every edge goes from an earlier to a later node.
  /// Nodes on cycles are appended at the end in z-order.
  List<NodeInstance> topologicalOrder() {
    final inDegree = <NodeId, int>{for (final n in _nodes.keys) n: 0};
    for (final e in _edges.values) {
      inDegree[e.target.node] = (inDegree[e.target.node] ?? 0) + 1;
    }
    final queue = Queue<NodeId>.of(
      inDegree.entries.where((e) => e.value == 0).map((e) => e.key),
    );
    final result = <NodeInstance>[];
    while (queue.isNotEmpty) {
      final id = queue.removeFirst();
      result.add(_nodes[id]!);
      for (final e in outgoing(id)) {
        final t = e.target.node;
        final d = inDegree[t]! - 1;
        inDegree[t] = d;
        if (d == 0) queue.add(t);
      }
    }
    if (result.length < _nodes.length) {
      final seen = result.map((n) => n.id).toSet();
      result.addAll(_nodes.values.where((n) => !seen.contains(n.id)));
    }
    return result;
  }

  /// Removes everything.
  void clear() {
    _zIndex = null;
    _nodes.clear();
    _edges.clear();
    _nodeEdges.clear();
    _portEdges.clear();
  }

  /// A deep copy of the graph.
  Graph copy() {
    final g = Graph();
    for (final n in _nodes.values) {
      g.addNode(n.copy());
    }
    for (final e in _edges.values) {
      g.addEdge(e);
    }
    return g;
  }
}
