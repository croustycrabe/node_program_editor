import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart' show Icons;

import '../../params/param_types.dart';
import '../commands.dart';
import '../controller.dart';
import '../edge.dart';
import '../graph.dart';
import '../ids.dart';
import '../io/design_document.dart';
import '../io/fragment.dart';
import '../io/graph_codec.dart';
import '../io/logic_document.dart';
import '../json.dart';
import '../node.dart';
import '../ports.dart';

/// Exposes a parameter of an inner node as a parameter of the super node.
class ParamBinding {
  /// Creates a binding.
  const ParamBinding({
    required this.name,
    required this.label,
    required this.node,
    required this.param,
  });

  /// Name on the super node.
  final String name;

  /// Label on the super node.
  final String label;

  /// Inner node.
  final NodeId node;

  /// Inner parameter name.
  final String param;
}

/// A reusable sub-graph ("function"). Instances are nodes of type
/// `super:<id>`; editing the definition (by entering an instance) updates
/// every instance.
class SuperNodeDefinition {
  /// Creates a definition.
  SuperNodeDefinition({
    required this.id,
    required this.name,
    required this.graph,
    required this.inputProxy,
    required this.outputProxy,
    this.category = 'Functions',
    this.description,
    List<ParamBinding> params = const [],
  }) : params = List.of(params);

  /// Unique id.
  final String id;

  /// Display name.
  String name;

  /// Palette category.
  String category;

  /// Description.
  String? description;

  /// Interior graph (contains the two proxy nodes).
  final Graph graph;

  /// Interior node whose outputs are the super node inputs.
  final NodeId inputProxy;

  /// Interior node whose inputs are the super node outputs.
  final NodeId outputProxy;

  /// Exposed parameters. Interior parameters that are not exposed keep their
  /// interior value (fixed parameters).
  final List<ParamBinding> params;

  /// Node type of instances.
  String get type => '${LogicDocument.superNodeTypePrefix}$id';

  /// Exposed input ports.
  List<PortSpec> get inputs => [
    for (final p in graph.node(inputProxy)?.customPorts ?? <PortSpec>[])
      PortSpec(
        id: p.id,
        direction: PortDirection.input,
        label: p.label,
        type: p.type,
        maxLinks: p.maxLinks < 0 ? 1 : p.maxLinks,
      ),
  ];

  /// Exposed output ports.
  List<PortSpec> get outputs => [
    for (final p in graph.node(outputProxy)?.customPorts ?? <PortSpec>[])
      PortSpec(
        id: p.id,
        direction: PortDirection.output,
        label: p.label,
        type: p.type,
        maxLinks: -1,
      ),
  ];

  /// Parameter specs of instances, derived from the bound interior specs.
  List<ParamSpec> get paramSpecs => [
    for (final b in params)
      if (graph.node(b.node) case final n?)
        if (n.definition.param(b.param) case final spec?)
          spec.copyWith(
            name: b.name,
            label: b.label,
            showInNode: true,
            defaultValue: n.params[b.param],
          ),
  ];

  /// The node definition registered for instances.
  SuperNodeNodeDefinition toNodeDefinition() => SuperNodeNodeDefinition(this);

  /// Encodes to the logic format.
  LogicSuperNode toLogic() {
    final (nodes, edges, _) = GraphCodec.encode(graph.nodes, graph.edges);
    LogicPort port(PortSpec p) => LogicPort(
      id: p.id,
      type: p.type.name,
      label: p.label,
      maxLinks: p.maxLinks,
    );
    return LogicSuperNode(
      id: id,
      name: name,
      category: category,
      description: description,
      inputProxy: inputProxy,
      outputProxy: outputProxy,
      inputs: inputs.map(port).toList(),
      outputs: outputs.map(port).toList(),
      params: [
        for (final b in params)
          LogicParamBinding(
            name: b.name,
            label: b.label,
            node: b.node,
            param: b.param,
          ),
      ],
      nodes: nodes,
      edges: edges,
    );
  }

  /// Encodes the interior design.
  GraphDesign toDesign() => GraphCodec.encode(graph.nodes, graph.edges).$3;
}

/// Node definition of super node instances.
class SuperNodeNodeDefinition extends NodeDefinition {
  /// Creates the node definition of [superNode].
  SuperNodeNodeDefinition(this.superNode)
    : super(
        type: superNode.type,
        title: superNode.name,
        category: superNode.category,
        description: superNode.description ?? 'Reusable function',
        icon: Icons.account_tree,
        ports: [...superNode.inputs, ...superNode.outputs],
        params: superNode.paramSpecs,
        variant: superNode.params.isEmpty
            ? NodeVariant.static
            : NodeVariant.dynamic,
        tags: const ['super', 'function', 'group'],
        style: const NodeStyle(headerColor: Color(0xFF5C6BC0)),
      );

  /// The definition behind this node type.
  final SuperNodeDefinition superNode;
}

/// Records the registration of a super node definition (undoable).
class RegisterSuperNodeCommand extends GraphCommand {
  /// Creates the command.
  RegisterSuperNodeCommand(this.library, this.definition);

  /// Library.
  final SuperNodeLibrary library;

  /// Definition.
  final SuperNodeDefinition definition;

  @override
  String get label => 'Create function';

  @override
  void apply(GraphMutator m) => library.register(definition);

  @override
  void revert(GraphMutator m) => library.unregister(definition.id);
}

/// Manages super node definitions: registration in the [NodeRegistry],
/// grouping / ungrouping, (de)serialization and reusable libraries.
class SuperNodeLibrary {
  /// Creates a library bound to [registry] and registers the proxy node
  /// types.
  SuperNodeLibrary(this.registry) {
    registry.registerAll(const [inputProxyDefinition, outputProxyDefinition]);
  }

  /// The registry definitions are registered into.
  final NodeRegistry registry;

  final Map<String, SuperNodeDefinition> _definitions = {};

  int _counter = 0;

  /// Type of the interior input proxy node.
  static const inputProxyType = '__super_input__';

  /// Type of the interior output proxy node.
  static const outputProxyType = '__super_output__';

  /// Definition of the interior input proxy node.
  static const inputProxyDefinition = NodeDefinition(
    type: inputProxyType,
    title: 'Inputs',
    category: '__internal__',
    deletable: false,
    copyable: false,
    resizable: false,
    description: 'Edit to add, rename or remove the function ports.',
    style: NodeStyle(headerColor: Color(0xFF455A64)),
  );

  /// Definition of the interior output proxy node.
  static const outputProxyDefinition = NodeDefinition(
    type: outputProxyType,
    title: 'Outputs',
    category: '__internal__',
    deletable: false,
    copyable: false,
    resizable: false,
    description: 'Edit to add, rename or remove the function ports.',
    style: NodeStyle(headerColor: Color(0xFF455A64)),
  );

  /// All definitions.
  Iterable<SuperNodeDefinition> get definitions => _definitions.values;

  /// The definition with [id].
  SuperNodeDefinition? operator [](String id) => _definitions[id];

  /// The definition behind node [type] (`super:<id>`), or null.
  SuperNodeDefinition? definitionOf(String type) =>
      type.startsWith(LogicDocument.superNodeTypePrefix)
      ? _definitions[type.substring(LogicDocument.superNodeTypePrefix.length)]
      : null;

  /// Whether [node] is a proxy node.
  static bool isProxy(NodeInstance node) =>
      node.type == inputProxyType || node.type == outputProxyType;

  /// Registers (or replaces) [definition].
  void register(SuperNodeDefinition definition) {
    _definitions[definition.id] = definition;
    registry.register(definition.toNodeDefinition());
  }

  /// Unregisters definition [id].
  void unregister(String id) {
    final def = _definitions.remove(id);
    if (def != null) registry.unregister(def.type);
  }

  /// Re-registers [definition] after its interior or bindings changed and
  /// rebinds instances in [graphs].
  void notifyEdited(
    SuperNodeDefinition definition, [
    Iterable<Graph> graphs = const [],
  ]) {
    definition.params.removeWhere(
      (b) => definition.graph.node(b.node)?.definition.param(b.param) == null,
    );
    final nodeDef = definition.toNodeDefinition();
    registry.register(nodeDef);
    for (final g in graphs) {
      for (final n in g.nodes) {
        if (n.type == definition.type) {
          n
            ..definition = nodeDef
            ..invalidatePorts();
        }
      }
    }
  }

  /// Whether an instance of node [type] placed inside [outer] would make
  /// [outer] contain itself (directly or through nested functions).
  bool wouldRecurse(String type, SuperNodeDefinition outer) {
    final def = definitionOf(type);
    if (def == null) return false;
    return identical(def, outer) || usedBy(def.graph.nodes).contains(outer);
  }

  /// Replaces the exposed ports of [definition].
  ///
  /// [inputs] / [outputs] are the function ports as seen from outside
  /// (keep existing ids to keep their links). Links attached to removed
  /// ports are deleted, inside the function and on every instance.
  void setInterface(
    NodeEditorController controller,
    SuperNodeDefinition definition, {
    required List<PortSpec> inputs,
    required List<PortSpec> outputs,
  }) {
    final proxyIn = [
      for (final p in inputs)
        PortSpec(
          id: p.id,
          direction: PortDirection.output,
          label: p.label,
          type: p.type,
          side: PortSide.right,
        ),
    ];
    final proxyOut = [
      for (final p in outputs)
        PortSpec(
          id: p.id,
          direction: PortDirection.input,
          label: p.label,
          type: p.type,
          maxLinks: 1,
          side: PortSide.left,
        ),
    ];
    final g = definition.graph;
    if (identical(controller.graph, g)) {
      controller.transaction('Edit function ports', () {
        controller.setCustomPorts(definition.inputProxy, proxyIn);
        controller.setCustomPorts(definition.outputProxy, proxyOut);
      });
    } else {
      for (final (id, ports) in [
        (definition.inputProxy, proxyIn),
        (definition.outputProxy, proxyOut),
      ]) {
        final proxy = g.node(id);
        if (proxy == null) continue;
        final keep = {for (final p in ports) p.id};
        for (final e in g.edgesOfNode(id).toList()) {
          final port = e.source.node == id ? e.source.port : e.target.port;
          if (!keep.contains(port)) g.removeEdge(e.id);
        }
        proxy
          ..customPorts = ports
          ..invalidatePorts()
          ..size = proxy.definition.clampSize(proxy.size, ports);
      }
    }
    refresh(controller, definition);
  }

  /// Rebinds every instance of [definition] reachable from
  /// [controller]'s scopes (call after changing [SuperNodeDefinition.params]
  /// or its name).
  void refresh(
    NodeEditorController controller,
    SuperNodeDefinition definition,
  ) {
    final graphs = {
      for (final s in controller.scopes) s.graph,
      for (final d in _definitions.values) d.graph,
    };
    notifyEdited(definition, graphs);
    for (final g in graphs) {
      for (final n in g.nodes) {
        if (n.type == definition.type) {
          for (final spec in n.definition.params) {
            n.params.putIfAbsent(spec.name, () => spec.initialValue);
          }
          n.params.removeWhere((k, _) => n.definition.param(k) == null);
          n.size = n.definition.clampSize(n.size);
        }
      }
    }
    controller.batch(() {
      for (final g in graphs) {
        for (final n in g.nodes.toList()) {
          if (n.type != definition.type) continue;
          // Drop links attached to ports the function no longer exposes.
          for (final e in g.edgesOfNode(n.id).toList()) {
            final port = e.source.node == n.id ? e.source.port : e.target.port;
            if (n.port(port) != null) continue;
            if (identical(g, controller.graph)) {
              controller.deleteEdge(e.id);
            } else {
              g.removeEdge(e.id);
            }
          }
          if (identical(g, controller.graph)) {
            controller.setNodeGeometry(n.id, size: n.size);
          }
        }
      }
    });
  }

  /// Replaces the exposed parameters of [definition].
  void setExposedParams(
    NodeEditorController controller,
    SuperNodeDefinition definition,
    List<ParamBinding> bindings,
  ) {
    definition.params
      ..clear()
      ..addAll(bindings);
    refresh(controller, definition);
  }

  /// Groups [ids] of the controller's current graph into a new super node
  /// instance (one undo step). Edges crossing the selection boundary become
  /// exposed ports.
  NodeInstance? group(
    NodeEditorController controller,
    Set<NodeId> ids, {
    String? name,
  }) {
    final g = controller.graph;
    final selected = {
      for (final id in ids)
        if (g.node(id) case final n? when !isProxy(n)) id,
    };
    if (selected.isEmpty) return null;
    final bounds = controller.boundsOf(selected)!;
    final inner = Graph();
    for (final n in g.nodes) {
      if (selected.contains(n.id)) inner.addNode(n.copy());
    }

    final inputs = <PortRef, PortSpec>{};
    final outputs = <PortRef, PortSpec>{};
    final incoming = <Edge>[];
    final outgoing = <Edge>[];
    final usedLabels = <String>{};
    String uniqueLabel(PortSpec p, NodeInstance n) {
      var label = p.label.isEmpty ? p.id : p.label;
      if (!usedLabels.add(label)) {
        label = '${n.displayTitle} $label';
        usedLabels.add(label);
      }
      return label;
    }

    for (final e in g.edges) {
      final sIn = selected.contains(e.source.node);
      final tIn = selected.contains(e.target.node);
      if (sIn && tIn) {
        inner.addEdge(e);
      } else if (tIn) {
        incoming.add(e);
        inputs.putIfAbsent(e.target, () {
          final n = g.node(e.target.node)!;
          final p = n.port(e.target.port)!;
          return PortSpec.output(
            'in${inputs.length + 1}',
            label: uniqueLabel(p, n),
            type: p.type,
            maxLinks: p.maxLinks,
          );
        });
      } else if (sIn) {
        outgoing.add(e);
        outputs.putIfAbsent(e.source, () {
          final n = g.node(e.source.node)!;
          final p = n.port(e.source.port)!;
          return PortSpec.input(
            'out${outputs.length + 1}',
            label: uniqueLabel(p, n),
            type: p.type,
            maxLinks: 1,
          );
        });
      }
    }

    final inProxy = NodeInstance.create(
      inputProxyDefinition,
      position: Offset.zero,
      customPorts: [
        for (final p in inputs.values) p.copyWith(side: PortSide.right),
      ],
    );
    inProxy.position = Offset(
      bounds.left - inProxy.size.width - 120,
      bounds.center.dy - inProxy.size.height / 2,
    );
    final outProxy = NodeInstance.create(
      outputProxyDefinition,
      position: Offset.zero,
      customPorts: [
        for (final p in outputs.values) p.copyWith(side: PortSide.left),
      ],
    );
    outProxy.position = Offset(
      bounds.right + 120,
      bounds.center.dy - outProxy.size.height / 2,
    );
    inner
      ..addNode(inProxy)
      ..addNode(outProxy);
    final style = controller.canvasSettings.value.defaultEdgeStyle;
    inputs.forEach(
      (target, spec) => inner.addEdge(
        Edge(
          id: IdGenerator.edge(),
          source: PortRef(inProxy.id, spec.id),
          target: target,
          style: style,
        ),
      ),
    );
    outputs.forEach(
      (source, spec) => inner.addEdge(
        Edge(
          id: IdGenerator.edge(),
          source: source,
          target: PortRef(outProxy.id, spec.id),
          style: style,
        ),
      ),
    );

    _counter++;
    final def = SuperNodeDefinition(
      id: IdGenerator.next('sn'),
      name: name ?? 'Function ${_definitions.length + _counter}',
      graph: inner,
      inputProxy: inProxy.id,
      outputProxy: outProxy.id,
    );
    final nodeDef = def.toNodeDefinition();
    final size = nodeDef.resolvedDefaultSize();
    final instance = NodeInstance.create(
      nodeDef,
      position: controller.canvasSettings.value.snapOffset(
        bounds.center - Offset(size.width / 2, size.height / 2),
      ),
    );
    final newEdges = <Edge>[
      for (final e in incoming)
        Edge(
          id: IdGenerator.edge(),
          source: e.source,
          target: PortRef(instance.id, inputs[e.target]!.id),
          style: e.style,
          label: e.label,
          data: e.data,
        ),
      for (final e in outgoing)
        Edge(
          id: IdGenerator.edge(),
          source: PortRef(instance.id, outputs[e.source]!.id),
          target: e.target,
          style: e.style,
          label: e.label,
          data: e.data,
        ),
    ];
    controller.execute(
      CompositeCommand('Group into function', [
        RemoveElementsCommand.capture(g, nodeIds: selected),
        RegisterSuperNodeCommand(this, def),
        _AddWithDefinition(instance, newEdges, this, def),
      ]),
    );
    return instance;
  }

  /// Replaces super node instance [id] by a copy of its interior. Returns the
  /// created node ids (empty when [id] is not a super node).
  List<NodeId> ungroup(NodeEditorController controller, NodeId id) {
    final g = controller.graph;
    final node = g.node(id);
    final def = node == null ? null : definitionOf(node.type);
    if (node == null || def == null) return const [];
    final interior = [
      for (final n in def.graph.nodes)
        if (n.id != def.inputProxy && n.id != def.outputProxy) n,
    ];
    if (interior.isEmpty) return const [];
    Rect? b;
    for (final n in interior) {
      b = b == null ? n.rect : b.expandToInclude(n.rect);
    }
    final delta = node.rect.center - b!.center;
    final idMap = <NodeId, NodeId>{};
    final clones = <NodeInstance>[];
    for (final n in interior) {
      final c = n.copy(id: IdGenerator.node(), position: n.position + delta);
      idMap[n.id] = c.id;
      clones.add(c);
    }
    for (final binding in def.params) {
      final newId = idMap[binding.node];
      if (newId == null || !node.params.containsKey(binding.name)) continue;
      clones.firstWhere((c) => c.id == newId).params[binding.param] =
          node.params[binding.name];
    }
    final edges = <Edge>[];
    for (final e in def.graph.edges) {
      final s = idMap[e.source.node], t = idMap[e.target.node];
      if (s != null && t != null) {
        edges.add(
          e.copyWith(
            id: IdGenerator.edge(),
            source: PortRef(s, e.source.port),
            target: PortRef(t, e.target.port),
          ),
        );
      }
    }
    for (final outer in g.edgesOfNode(id)) {
      if (outer.target.node == id) {
        for (final ie in def.graph.edgesOfPort(
          PortRef(def.inputProxy, outer.target.port),
        )) {
          final t = idMap[ie.target.node];
          if (t == null) continue;
          edges.add(
            outer.copyWith(
              id: IdGenerator.edge(),
              target: PortRef(t, ie.target.port),
            ),
          );
        }
      } else {
        for (final ie in def.graph.edgesOfPort(
          PortRef(def.outputProxy, outer.source.port),
        )) {
          final s = idMap[ie.source.node];
          if (s == null) continue;
          edges.add(
            outer.copyWith(
              id: IdGenerator.edge(),
              source: PortRef(s, ie.source.port),
            ),
          );
        }
      }
    }
    controller.execute(
      CompositeCommand('Ungroup', [
        RemoveElementsCommand.capture(g, nodeIds: [id]),
        AddElementsCommand(nodes: clones, edges: edges),
      ]),
    );
    return idMap.values.toList();
  }

  /// Makes instance [id] use a private copy of its definition, so editing it
  /// no longer affects other instances.
  SuperNodeDefinition? detach(NodeEditorController controller, NodeId id) {
    final g = controller.graph;
    final node = g.node(id);
    final def = node == null ? null : definitionOf(node.type);
    if (node == null || def == null) return null;
    final copy = SuperNodeDefinition(
      id: IdGenerator.next('sn'),
      name: '${def.name} (copy)',
      category: def.category,
      description: def.description,
      graph: def.graph.copy(),
      inputProxy: def.inputProxy,
      outputProxy: def.outputProxy,
      params: def.params,
    );
    final instance = node.copy()..definition = copy.toNodeDefinition();
    final edges = g.edgesOfNode(id).toList();
    controller.execute(
      CompositeCommand('Detach function', [
        RemoveElementsCommand.capture(g, nodeIds: [id]),
        RegisterSuperNodeCommand(this, copy),
        _AddWithDefinition(instance, edges, this, copy),
      ]),
    );
    return copy;
  }

  /// Definitions used by [graph], including nested ones.
  Set<SuperNodeDefinition> usedBy(Iterable<NodeInstance> nodes) {
    final result = <SuperNodeDefinition>{};
    void visit(Iterable<NodeInstance> ns) {
      for (final n in ns) {
        final d = definitionOf(n.type);
        if (d != null && result.add(d)) visit(d.graph.nodes);
      }
    }

    visit(nodes);
    return result;
  }

  /// Logic encoding of the definitions used by [root].
  Map<String, LogicSuperNode> exportLogic(Graph root) => {
    for (final d in usedBy(root.nodes)) d.id: d.toLogic(),
  };

  /// Interior designs of the definitions used by [root].
  Map<String, GraphDesign> exportDesign(Graph root) => {
    for (final d in usedBy(root.nodes)) d.id: d.toDesign(),
  };

  /// Imports definitions from documents (replacing same-id definitions).
  void importDefinitions(
    Map<String, LogicSuperNode> logic,
    Map<String, GraphDesign> design, {
    bool replaceExisting = true,
  }) {
    final todo = {
      for (final e in logic.entries)
        if (replaceExisting || !_definitions.containsKey(e.key)) e.key: e.value,
    };
    if (todo.isEmpty) return;
    // Pass 1: provisional node definitions so nested instances resolve.
    for (final s in todo.values) {
      registry.register(
        NodeDefinition(
          type: '${LogicDocument.superNodeTypePrefix}${s.id}',
          title: s.name,
          category: s.category,
          ports: [
            for (final p in s.inputs)
              PortSpec.input(
                p.id,
                label: p.label,
                type: registry.portType(p.type),
                maxLinks: p.maxLinks,
              ),
            for (final p in s.outputs)
              PortSpec.output(
                p.id,
                label: p.label,
                type: registry.portType(p.type),
                maxLinks: p.maxLinks,
              ),
          ],
        ),
      );
    }
    // Pass 2: interiors.
    final created = <SuperNodeDefinition>[];
    for (final s in todo.values) {
      final graph = GraphCodec.decode(
        nodes: s.nodes,
        edges: s.edges,
        registry: registry,
        design: design[s.id],
      );
      final def = SuperNodeDefinition(
        id: s.id,
        name: s.name,
        category: s.category,
        description: s.description,
        graph: graph,
        inputProxy: s.inputProxy,
        outputProxy: s.outputProxy,
        params: [
          for (final b in s.params)
            ParamBinding(
              name: b.name,
              label: b.label,
              node: b.node,
              param: b.param,
            ),
        ],
      );
      _definitions[def.id] = def;
      created.add(def);
    }
    // Pass 3: final node definitions, then rebind nested instances.
    for (final def in created) {
      registry.register(def.toNodeDefinition());
    }
    for (final def in _definitions.values) {
      for (final n in def.graph.nodes) {
        final d = registry[n.type];
        if (d != null && !identical(d, n.definition)) {
          n
            ..definition = d
            ..invalidatePorts();
        }
      }
    }
  }

  /// Adds the definitions used by [fragment]'s nodes to it.
  GraphFragment attachDefinitions(GraphFragment fragment) {
    final used = <SuperNodeDefinition>{};
    for (final n in fragment.nodes) {
      final d = definitionOf(n.type);
      if (d != null) {
        used
          ..add(d)
          ..addAll(usedBy(d.graph.nodes));
      }
    }
    if (used.isEmpty) return fragment;
    return GraphFragment(
      nodes: fragment.nodes,
      edges: fragment.edges,
      design: fragment.design,
      superNodes: {for (final d in used) d.id: d.toLogic()},
      superNodeDesigns: {for (final d in used) d.id: d.toDesign()},
    );
  }

  /// Registers definitions carried by [fragment] that are not known yet.
  void registerFromFragment(GraphFragment fragment) {
    if (fragment.superNodes.isEmpty) return;
    importDefinitions(
      fragment.superNodes,
      fragment.superNodeDesigns,
      replaceExisting: false,
    );
  }

  /// Serializes definitions (default: all) as a reusable library file.
  String exportLibrary([Iterable<SuperNodeDefinition>? definitions]) {
    final defs = <SuperNodeDefinition>{};
    for (final d in definitions ?? _definitions.values) {
      defs
        ..add(d)
        ..addAll(usedBy(d.graph.nodes));
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'node_program_editor/library',
      'superNodes': {for (final d in defs) d.id: d.toLogic().toJson()},
      'designs': {for (final d in defs) d.id: d.toDesign().toJson()},
    });
  }

  /// Loads a library produced by [exportLibrary]; returns the imported ids.
  List<String> importLibrary(String source) {
    final json = asJsonMap(jsonDecode(source));
    final logic = {
      for (final e in asJsonMap(json['superNodes'] ?? const {}).entries)
        e.key: LogicSuperNode.fromJson(asJsonMap(e.value)),
    };
    final design = {
      for (final e in asJsonMap(json['designs'] ?? const {}).entries)
        e.key: GraphDesign.fromJson(asJsonMap(e.value)),
    };
    importDefinitions(logic, design, replaceExisting: false);
    return logic.keys.toList();
  }
}

/// Adds an instance whose definition must be (re)bound at apply time,
/// because undo / redo unregisters and re-registers the definition.
class _AddWithDefinition extends AddElementsCommand {
  _AddWithDefinition(
    NodeInstance instance,
    List<Edge> edges,
    this.library,
    this.definition,
  ) : super(nodes: [instance], edges: edges, label: 'Add function');

  final SuperNodeLibrary library;
  final SuperNodeDefinition definition;

  @override
  void apply(GraphMutator m) {
    final def = m.registry[definition.type];
    if (def != null) {
      for (final n in nodes) {
        n
          ..definition = def
          ..invalidatePorts();
      }
    }
    super.apply(m);
  }
}
