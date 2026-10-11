import 'dart:math' as math;
import 'dart:ui';

import '../edge.dart';
import '../graph.dart';
import '../ids.dart';
import '../node.dart';
import '../ports.dart';
import 'design_document.dart';
import 'logic_document.dart';

/// Converts between live [Graph]s and the logic / design documents.
abstract final class GraphCodec {
  /// Encodes the logic part of [node].
  static LogicNode encodeNode(NodeInstance node) {
    final def = node.definition;
    LogicPort port(PortSpec p) => LogicPort(
      id: p.id,
      type: p.type.name,
      label: p.label,
      maxLinks: p.maxLinks,
    );
    return LogicNode(
      id: node.id,
      type: node.type,
      title: node.title,
      params: {
        for (final e in node.params.entries)
          e.key: def.param(e.key)?.type.encodeAny(e.value) ?? e.value,
      },
      inputs: [
        for (final p in node.ports)
          if (p.isInput) port(p),
      ],
      outputs: [
        for (final p in node.ports)
          if (p.isOutput) port(p),
      ],
      customPorts: [for (final p in node.customPorts) p.toJson()],
      data: Map.of(node.data),
    );
  }

  /// Encodes the logic part of [edge].
  static LogicEdge encodeEdge(Edge edge) => LogicEdge(
    id: edge.id,
    source: edge.source,
    target: edge.target,
    data: Map.of(edge.data),
  );

  /// Encodes the design part of [node].
  static NodeDesign encodeNodeDesign(NodeInstance node) => NodeDesign(
    position: node.position,
    size: node.size,
    locked: node.locked,
    style: node.style,
  );

  /// Encodes the design part of [edge].
  static EdgeDesign encodeEdgeDesign(Edge edge) => EdgeDesign(
    style: edge.style,
    label: edge.label,
    waypoints: edge.waypoints,
  );

  /// Encodes a set of nodes and edges.
  static (List<LogicNode>, List<LogicEdge>, GraphDesign) encode(
    Iterable<NodeInstance> nodes,
    Iterable<Edge> edges,
  ) {
    final design = GraphDesign();
    final logicNodes = <LogicNode>[];
    for (final n in nodes) {
      logicNodes.add(encodeNode(n));
      design.nodes[n.id] = encodeNodeDesign(n);
    }
    final logicEdges = <LogicEdge>[];
    for (final e in edges) {
      logicEdges.add(encodeEdge(e));
      design.edges[e.id] = encodeEdgeDesign(e);
    }
    return (logicNodes, logicEdges, design);
  }

  /// Decodes one node.
  static NodeInstance decodeNode(
    LogicNode logic,
    NodeDesign? design,
    NodeRegistry registry, {
    Offset fallbackPosition = Offset.zero,
  }) {
    PortSpec fromLogic(LogicPort p, PortDirection d) => PortSpec(
      id: p.id,
      direction: d,
      label: p.label,
      type: registry.portType(p.type),
      maxLinks: p.maxLinks,
    );
    final customPorts = [
      for (final p in logic.customPorts)
        PortSpec.fromJson(p, registry.portType),
    ];
    final customIds = customPorts.map((p) => p.id).toSet();
    final def = registry.resolve(
      logic.type,
      ports: [
        for (final p in logic.inputs)
          if (!customIds.contains(p.id)) fromLogic(p, PortDirection.input),
        for (final p in logic.outputs)
          if (!customIds.contains(p.id)) fromLogic(p, PortDirection.output),
      ],
    );
    final params = def.initialParams();
    for (final e in logic.params.entries) {
      final spec = def.param(e.key);
      params[e.key] = spec == null
          ? e.value
          : spec.type.normalizeAny(spec.type.decodeAny(e.value));
    }
    return NodeInstance(
      id: logic.id,
      definition: def,
      position: design?.position ?? fallbackPosition,
      size: def.clampSize(
        design?.size ?? def.resolvedDefaultSize(customPorts),
        customPorts,
      ),
      locked: design?.locked ?? false,
      style: design?.style,
      title: logic.title,
      params: params,
      data: Map.of(logic.data),
      customPorts: customPorts,
    );
  }

  /// Builds a graph from documents. Edges referencing missing nodes or
  /// ports are dropped. Nodes without design get an automatic layered
  /// layout.
  static Graph decode({
    required List<LogicNode> nodes,
    required List<LogicEdge> edges,
    required NodeRegistry registry,
    GraphDesign? design,
  }) {
    final graph = Graph();
    final missing = <NodeId>[];
    for (final n in nodes) {
      final d = design?.nodes[n.id];
      if (d == null) missing.add(n.id);
      graph.addNode(decodeNode(n, d, registry));
    }
    for (final e in edges) {
      final s = graph.node(e.source.node), t = graph.node(e.target.node);
      if (s == null || t == null) continue;
      if (s.port(e.source.port) == null || t.port(e.target.port) == null) {
        continue;
      }
      final d = design?.edges[e.id];
      graph.addEdge(
        Edge(
          id: e.id,
          source: e.source,
          target: e.target,
          data: Map.of(e.data),
          style: d?.style ?? const EdgeStyle(),
          label: d?.label,
          waypoints: d?.waypoints ?? const [],
        ),
      );
    }
    if (missing.isNotEmpty) autoLayout(graph, only: missing.toSet());
    return graph;
  }

  /// Layered left-to-right layout: column = longest path from a source,
  /// row = order within the column. When [only] is given, other nodes keep
  /// their position and the laid out nodes are placed below them.
  static void autoLayout(
    Graph graph, {
    Set<NodeId>? only,
    double columnGap = 80,
    double rowGap = 40,
    Offset origin = Offset.zero,
  }) {
    final order = graph.topologicalOrder();
    final depth = <NodeId, int>{};
    for (final n in order) {
      var d = 0;
      for (final e in graph.incoming(n.id)) {
        final pd = depth[e.source.node];
        if (pd != null) d = math.max(d, pd + 1);
      }
      depth[n.id] = d;
    }
    var start = origin;
    if (only != null) {
      double? bottom;
      for (final n in graph.nodes) {
        if (only.contains(n.id)) continue;
        bottom = math.max(bottom ?? n.rect.bottom, n.rect.bottom);
      }
      if (bottom != null) start = Offset(origin.dx, bottom + rowGap * 2);
    }
    final columns = <int, List<NodeInstance>>{};
    for (final n in order) {
      if (only != null && !only.contains(n.id)) continue;
      (columns[depth[n.id]!] ??= []).add(n);
    }
    var x = start.dx;
    final keys = columns.keys.toList()..sort();
    for (final c in keys) {
      var y = start.dy;
      var width = 0.0;
      for (final n in columns[c]!) {
        n.position = Offset(x, y);
        y += n.size.height + rowGap;
        width = math.max(width, n.size.width);
      }
      x += width + columnGap;
    }
  }
}
