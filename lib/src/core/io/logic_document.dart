import 'dart:convert';

import '../ids.dart';
import '../json.dart';
import '../ports.dart';

/// Summary of a port in the logic file.
class LogicPort {
  /// Creates a port summary.
  const LogicPort({
    required this.id,
    required this.type,
    this.label = '',
    this.maxLinks = -1,
  });

  /// Port id.
  final String id;

  /// Port type name.
  final String type;

  /// Label.
  final String label;

  /// Max links (-1 unlimited).
  final int maxLinks;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'id': id,
    'type': type,
    'label': label.isEmpty ? null : label,
    'maxLinks': maxLinks == -1 ? null : maxLinks,
  });

  /// Parses JSON produced by [toJson].
  factory LogicPort.fromJson(Map<String, Object?> json) => LogicPort(
    id: json['id']! as String,
    type: json['type'] as String? ?? 'any',
    label: json['label'] as String? ?? '',
    maxLinks: readInt(json['maxLinks']) ?? -1,
  );
}

/// A node in the logic file.
class LogicNode {
  /// Creates a logic node.
  LogicNode({
    required this.id,
    required this.type,
    this.title,
    Map<String, Object?>? params,
    this.inputs = const [],
    this.outputs = const [],
    this.customPorts = const [],
    Map<String, Object?>? data,
  }) : params = params ?? {},
       data = data ?? {};

  /// Node id.
  final NodeId id;

  /// Node type (definition id). Super node instances use `super:<id>`.
  final String type;

  /// Title override.
  final String? title;

  /// Parameter values, JSON encoded by their `ParamType`.
  final Map<String, Object?> params;

  /// Input ports (informational: lets an executor work without the
  /// registry).
  final List<LogicPort> inputs;

  /// Output ports.
  final List<LogicPort> outputs;

  /// Full specs of instance specific ports (`NodeInstance.customPorts`).
  final List<Map<String, Object?>> customPorts;

  /// Free payload.
  final Map<String, Object?> data;

  /// Returns a copy with the given fields replaced.
  LogicNode copyWith({NodeId? id, Map<String, Object?>? params}) => LogicNode(
    id: id ?? this.id,
    type: type,
    title: title,
    params: params ?? Map.of(this.params),
    inputs: inputs,
    outputs: outputs,
    customPorts: customPorts,
    data: Map.of(data),
  );

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'id': id.value,
    'type': type,
    'title': title,
    'params': params,
    'inputs': [for (final p in inputs) p.toJson()],
    'outputs': [for (final p in outputs) p.toJson()],
    'customPorts': customPorts.isEmpty ? null : customPorts,
    'data': data.isEmpty ? null : data,
  });

  /// Parses JSON produced by [toJson].
  factory LogicNode.fromJson(Map<String, Object?> json) => LogicNode(
    id: NodeId(json['id']! as String),
    type: json['type']! as String,
    title: json['title'] as String?,
    params: json['params'] == null ? {} : Map.of(asJsonMap(json['params'])),
    inputs: [
      for (final p in asJsonList(json['inputs']))
        LogicPort.fromJson(asJsonMap(p)),
    ],
    outputs: [
      for (final p in asJsonList(json['outputs']))
        LogicPort.fromJson(asJsonMap(p)),
    ],
    customPorts: [
      for (final p in asJsonList(json['customPorts'])) asJsonMap(p),
    ],
    data: json['data'] == null ? {} : Map.of(asJsonMap(json['data'])),
  );
}

/// A link in the logic file.
class LogicEdge {
  /// Creates a logic edge.
  LogicEdge({
    required this.id,
    required this.source,
    required this.target,
    Map<String, Object?>? data,
  }) : data = data ?? {};

  /// Edge id.
  final EdgeId id;

  /// Output port.
  final PortRef source;

  /// Input port.
  final PortRef target;

  /// Free payload.
  final Map<String, Object?> data;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'id': id.value,
    'source': source.toJson(),
    'target': target.toJson(),
    'data': data.isEmpty ? null : data,
  });

  /// Parses JSON produced by [toJson].
  factory LogicEdge.fromJson(Map<String, Object?> json) => LogicEdge(
    id: EdgeId(json['id']! as String),
    source: PortRef.fromJson(asJsonMap(json['source'])),
    target: PortRef.fromJson(asJsonMap(json['target'])),
    data: json['data'] == null ? {} : Map.of(asJsonMap(json['data'])),
  );
}

/// Maps a super node parameter to a parameter of an inner node.
class LogicParamBinding {
  /// Creates a binding.
  const LogicParamBinding({
    required this.name,
    required this.label,
    required this.node,
    required this.param,
  });

  /// Parameter name on the super node.
  final String name;

  /// Displayed label.
  final String label;

  /// Inner node.
  final NodeId node;

  /// Parameter name on the inner node.
  final String param;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
    'name': name,
    'label': label,
    'node': node.value,
    'param': param,
  };

  /// Parses JSON produced by [toJson].
  factory LogicParamBinding.fromJson(Map<String, Object?> json) =>
      LogicParamBinding(
        name: json['name']! as String,
        label: json['label'] as String? ?? json['name']! as String,
        node: NodeId(json['node']! as String),
        param: json['param']! as String,
      );
}

/// A reusable sub-graph ("function") in the logic file.
///
/// Its inner graph contains two proxy nodes: [inputProxy] (whose output
/// ports are the super node inputs) and [outputProxy] (whose input ports are
/// the super node outputs).
class LogicSuperNode {
  /// Creates a super node definition.
  LogicSuperNode({
    required this.id,
    required this.name,
    this.category = 'Functions',
    this.description,
    required this.inputProxy,
    required this.outputProxy,
    this.inputs = const [],
    this.outputs = const [],
    this.params = const [],
    this.nodes = const [],
    this.edges = const [],
  });

  /// Definition id; instances have type `super:<id>`.
  final String id;

  /// Display name.
  final String name;

  /// Palette category.
  final String category;

  /// Description.
  final String? description;

  /// Inner node exposing the super node inputs.
  final NodeId inputProxy;

  /// Inner node collecting the super node outputs.
  final NodeId outputProxy;

  /// Exposed inputs.
  final List<LogicPort> inputs;

  /// Exposed outputs.
  final List<LogicPort> outputs;

  /// Exposed parameters.
  final List<LogicParamBinding> params;

  /// Inner nodes (including the two proxies).
  final List<LogicNode> nodes;

  /// Inner edges.
  final List<LogicEdge> edges;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'id': id,
    'name': name,
    'category': category,
    'description': description,
    'inputProxy': inputProxy.value,
    'outputProxy': outputProxy.value,
    'inputs': [for (final p in inputs) p.toJson()],
    'outputs': [for (final p in outputs) p.toJson()],
    'params': [for (final p in params) p.toJson()],
    'nodes': [for (final n in nodes) n.toJson()],
    'edges': [for (final e in edges) e.toJson()],
  });

  /// Parses JSON produced by [toJson].
  factory LogicSuperNode.fromJson(Map<String, Object?> json) => LogicSuperNode(
    id: json['id']! as String,
    name: json['name'] as String? ?? 'Function',
    category: json['category'] as String? ?? 'Functions',
    description: json['description'] as String?,
    inputProxy: NodeId(json['inputProxy']! as String),
    outputProxy: NodeId(json['outputProxy']! as String),
    inputs: [
      for (final p in asJsonList(json['inputs']))
        LogicPort.fromJson(asJsonMap(p)),
    ],
    outputs: [
      for (final p in asJsonList(json['outputs']))
        LogicPort.fromJson(asJsonMap(p)),
    ],
    params: [
      for (final p in asJsonList(json['params']))
        LogicParamBinding.fromJson(asJsonMap(p)),
    ],
    nodes: [
      for (final n in asJsonList(json['nodes']))
        LogicNode.fromJson(asJsonMap(n)),
    ],
    edges: [
      for (final e in asJsonList(json['edges']))
        LogicEdge.fromJson(asJsonMap(e)),
    ],
  );
}

/// The logic file: which nodes exist, their parameters and how they are
/// connected. It contains no UI data and is meant to be sent to an
/// execution engine.
///
/// ```json
/// {
///   "format": "node_program_editor/logic",
///   "schemaVersion": 1,
///   "nodes": [{"id": "n1", "type": "math.add", "params": {"bias": 0}, ...}],
///   "edges": [{"id": "e1", "source": {"node": "n1", "port": "out"},
///              "target": {"node": "n2", "port": "a"}}],
///   "superNodes": {"sn1": {...}}
/// }
/// ```
class LogicDocument {
  /// Creates a logic document.
  LogicDocument({
    this.nodes = const [],
    this.edges = const [],
    this.superNodes = const {},
    this.metadata = const {},
    this.schemaVersion = currentSchemaVersion,
  });

  /// Format identifier written in files.
  static const format = 'node_program_editor/logic';

  /// Schema version written by this package.
  static const currentSchemaVersion = 1;

  /// Prefix of super node instance types.
  static const superNodeTypePrefix = 'super:';

  /// Version of the loaded file.
  final int schemaVersion;

  /// Top level nodes.
  final List<LogicNode> nodes;

  /// Top level edges.
  final List<LogicEdge> edges;

  /// Super node definitions referenced by `super:<id>` nodes.
  final Map<String, LogicSuperNode> superNodes;

  /// Free metadata (name, author, app version...).
  final Map<String, Object?> metadata;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'format': format,
    'schemaVersion': schemaVersion,
    'metadata': metadata.isEmpty ? null : metadata,
    'nodes': [for (final n in nodes) n.toJson()],
    'edges': [for (final e in edges) e.toJson()],
    'superNodes': superNodes.isEmpty
        ? null
        : {for (final s in superNodes.entries) s.key: s.value.toJson()},
  });

  /// Pretty printed JSON.
  String toJsonString({bool pretty = true}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toJson());

  /// Parses JSON produced by [toJson].
  factory LogicDocument.fromJson(Map<String, Object?> json) => LogicDocument(
    schemaVersion: readInt(json['schemaVersion']) ?? 1,
    metadata: json['metadata'] == null
        ? const {}
        : Map.of(asJsonMap(json['metadata'])),
    nodes: [
      for (final n in asJsonList(json['nodes']))
        LogicNode.fromJson(asJsonMap(n)),
    ],
    edges: [
      for (final e in asJsonList(json['edges']))
        LogicEdge.fromJson(asJsonMap(e)),
    ],
    superNodes: {
      for (final e in asJsonMap(json['superNodes'] ?? const {}).entries)
        e.key: LogicSuperNode.fromJson(asJsonMap(e.value)),
    },
  );

  /// Parses a JSON string.
  factory LogicDocument.fromJsonString(String source) =>
      LogicDocument.fromJson(asJsonMap(jsonDecode(source)));

  /// Returns an equivalent document without super nodes: every super node
  /// instance is replaced (recursively) by its inner nodes.
  ///
  /// Inner node ids become `<instanceId>/<innerId>` so results can be traced
  /// back to the instance. Exposed parameter values of the instance are
  /// written into the bound inner parameters. This is what most execution
  /// engines want to consume.
  LogicDocument flatten() {
    final outNodes = <LogicNode>[];
    final outEdges = <LogicEdge>[];
    // Edge endpoints that point into a super node are redirected here:
    // (instance, exposed port) -> inner port refs.
    final inputRedirect = <PortRef, List<PortRef>>{};
    final outputRedirect = <PortRef, PortRef>{};

    void expand(
      List<LogicNode> nodes,
      List<LogicEdge> edges,
      String prefix,
      Map<PortRef, List<PortRef>> inRedir,
      Map<PortRef, PortRef> outRedir,
    ) {
      NodeId pid(NodeId id) => NodeId('$prefix${id.value}');
      final localIn = <PortRef, List<PortRef>>{};
      final localOut = <PortRef, PortRef>{};
      final pending = <LogicEdge>[];

      for (final node in nodes) {
        if (node.type.startsWith(superNodeTypePrefix)) {
          final def =
              superNodes[node.type.substring(superNodeTypePrefix.length)];
          if (def == null) {
            outNodes.add(node.copyWith(id: pid(node.id)));
            continue;
          }
          final innerPrefix = '${pid(node.id).value}/';
          // Apply exposed parameter values to inner nodes.
          final overrides = <NodeId, Map<String, Object?>>{};
          for (final b in def.params) {
            if (node.params.containsKey(b.name)) {
              (overrides[b.node] ??= {})[b.param] = node.params[b.name];
            }
          }
          final innerNodes = [
            for (final n in def.nodes)
              if (n.id != def.inputProxy && n.id != def.outputProxy)
                overrides[n.id] == null
                    ? n
                    : n.copyWith(params: {...n.params, ...overrides[n.id]!}),
          ];
          final innerEdges = <LogicEdge>[];
          final instance = pid(node.id);
          final innerIn = <PortRef, List<PortRef>>{};
          final innerOut = <PortRef, PortRef>{};
          for (final e in def.edges) {
            if (e.source.node == def.inputProxy) {
              // Exposed input -> inner target.
              (localIn[PortRef(instance, e.source.port)] ??= []).add(
                PortRef(
                  NodeId('$innerPrefix${e.target.node.value}'),
                  e.target.port,
                ),
              );
            } else if (e.target.node == def.outputProxy) {
              localOut[PortRef(instance, e.target.port)] = PortRef(
                NodeId('$innerPrefix${e.source.node.value}'),
                e.source.port,
              );
            } else {
              innerEdges.add(e);
            }
          }
          expand(innerNodes, innerEdges, innerPrefix, innerIn, innerOut);
          // Resolve redirects produced by nested super nodes.
          for (final entry in localIn.entries.toList()) {
            localIn[entry.key] = [
              for (final r in entry.value) ...(innerIn[r] ?? [r]),
            ];
          }
          for (final entry in localOut.entries.toList()) {
            localOut[entry.key] = innerOut[entry.value] ?? entry.value;
          }
        } else {
          outNodes.add(node.copyWith(id: pid(node.id)));
        }
      }
      for (final e in edges) {
        pending.add(e);
      }
      for (final e in pending) {
        var src = PortRef(pid(e.source.node), e.source.port);
        src = localOut[src] ?? src;
        final dst = PortRef(pid(e.target.node), e.target.port);
        final targets = localIn[dst] ?? [dst];
        for (var i = 0; i < targets.length; i++) {
          outEdges.add(
            LogicEdge(
              id: EdgeId(
                targets.length == 1
                    ? '$prefix${e.id.value}'
                    : '$prefix${e.id.value}#$i',
              ),
              source: src,
              target: targets[i],
              data: e.data,
            ),
          );
        }
      }
      inRedir.addAll(localIn);
      outRedir.addAll(localOut);
    }

    expand(nodes, edges, '', inputRedirect, outputRedirect);
    return LogicDocument(nodes: outNodes, edges: outEdges, metadata: metadata);
  }
}
