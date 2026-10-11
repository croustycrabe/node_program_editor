import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'commands.dart';
import 'config.dart';
import 'edge.dart';
import 'edge_geometry.dart';
import 'graph.dart';
import 'ids.dart';
import 'io/design_document.dart';
import 'io/fragment.dart';
import 'io/graph_codec.dart';
import 'io/logic_document.dart';
import 'node.dart';
import 'port_geometry.dart';
import 'ports.dart';
import 'spatial_hash_grid.dart';
import 'supernode/super_node.dart';
import 'validation.dart';
import 'viewport.dart';

/// Alignment targets of [NodeEditorController.alignSelection].
enum NodeAlignment {
  /// Left edges.
  left,

  /// Horizontal centers.
  centerHorizontal,

  /// Right edges.
  right,

  /// Top edges.
  top,

  /// Vertical centers.
  centerVertical,

  /// Bottom edges.
  bottom,
}

/// Transient visual state of an edge, set by execution engines (not saved,
/// not undoable). See [NodeEditorController.setEdgeRuntime].
@immutable
class EdgeRuntimeState {
  /// Creates a runtime state.
  const EdgeRuntimeState({this.animated = false, this.color, this.label});

  /// Shows the flow animation.
  final bool animated;

  /// Overrides the stroke color.
  final Color? color;

  /// Overrides the label (e.g. "3 items").
  final String? label;
}

/// A link being dragged from a port.
@immutable
class ConnectionDraft {
  /// Creates a draft.
  const ConnectionDraft({
    required this.from,
    required this.fromPort,
    this.hoverTarget,
    this.hoverValid = false,
  });

  /// The port the drag started from.
  final PortRef from;

  /// Its spec.
  final PortSpec fromPort;

  /// The port currently snapped to, if any.
  final PortRef? hoverTarget;

  /// Whether connecting to [hoverTarget] is valid.
  final bool hoverValid;

  /// Returns a copy with another hover target.
  ConnectionDraft withHover(PortRef? target, bool valid) => ConnectionDraft(
    from: from,
    fromPort: fromPort,
    hoverTarget: target,
    hoverValid: valid,
  );
}

/// Details passed to [NodeEditorController.onConnectEnd] when a link drag is
/// released.
class ConnectEndDetails {
  /// Creates details.
  const ConnectEndDetails(
    this.from,
    this.fromPort,
    this.canvasPosition, {
    this.edge,
  });

  /// Port the drag started from.
  final PortRef from;

  /// Its spec.
  final PortSpec fromPort;

  /// Release position, canvas units.
  final Offset canvasPosition;

  /// The created edge, null when released on empty canvas.
  final Edge? edge;
}

/// One level of the super node navigation stack.
class EditorScope {
  /// Creates a scope.
  EditorScope({
    required this.graph,
    required this.label,
    this.superNode,
    this.instance,
    HistoryStack? history,
  }) : history = history ?? HistoryStack();

  /// The graph edited in this scope.
  final Graph graph;

  /// Breadcrumb label.
  final String label;

  /// The super node definition being edited (null for the root).
  final SuperNodeDefinition? superNode;

  /// The instance that was opened to enter this scope.
  final NodeId? instance;

  /// Undo history of this scope.
  final HistoryStack history;

  /// EditorViewport to restore when coming back to this scope.
  EditorViewport savedViewport = const EditorViewport();
}

class _Notifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// The single source of truth of a node editor.
///
/// Holds the graph, viewport, selection, undo history and interaction state,
/// and exposes fine grained [Listenable]s so widgets rebuild only what
/// changed:
///
/// * [structure]: nodes added / removed / reordered.
/// * [geometry]: any node moved or resized.
/// * [edgesListenable]: edges added / removed / restyled or their endpoints
///   moved.
/// * [nodeListenable]: one specific node changed (position, params,
///   selection, lock...).
/// * [viewport], [selection], [canvasSettings], [history].
///
/// Every user-level mutation is an undoable [GraphCommand].
class NodeEditorController extends ChangeNotifier implements GraphMutator {
  /// Creates a controller.
  NodeEditorController({
    NodeRegistry? registry,
    NodeEditorConfig config = const NodeEditorConfig(),
    this.validator = const ConnectionValidator(),
    CanvasSettings canvasSettings = const CanvasSettings(),
    EditorViewport viewport = const EditorViewport(),
  }) : registry = registry ?? NodeRegistry(),
       // ignore: prefer_initializing_formals
       _config = config,
       canvasSettings = ValueNotifier(canvasSettings),
       viewport = ValueNotifier(viewport) {
    _scopes.add(EditorScope(graph: Graph(), label: 'Root'));
    superNodes = SuperNodeLibrary(this.registry);
  }

  /// Node definitions and port types.
  @override
  final NodeRegistry registry;

  /// Reusable sub-graph definitions.
  late final SuperNodeLibrary superNodes;

  /// Connection rules.
  ConnectionValidator validator;

  NodeEditorConfig _config;

  /// Interaction options.
  NodeEditorConfig get config => _config;
  set config(NodeEditorConfig value) {
    _config = value;
    notifyListeners();
  }

  /// Grid and snapping settings.
  final ValueNotifier<CanvasSettings> canvasSettings;

  /// Pan / zoom state.
  final ValueNotifier<EditorViewport> viewport;

  final ValueNotifier<Size> _viewportSize = ValueNotifier(const Size(800, 600));
  bool _hasLayout = false;
  VoidCallback? _pendingFit;

  /// Size of the canvas widget (set by the canvas after layout).
  Size get viewportSize => _viewportSize.value;
  set viewportSize(Size value) {
    _hasLayout = true;
    _viewportSize.value = value;
    final fit = _pendingFit;
    _pendingFit = null;
    fit?.call();
  }

  /// Whether a canvas reported its size (view operations before that are
  /// deferred until the first layout).
  bool get hasLayout => _hasLayout;

  /// Fires when the canvas is resized.
  ValueListenable<Size> get viewportSizeListenable => _viewportSize;

  final ValueNotifier<GraphSelection> _selection = ValueNotifier(
    GraphSelection.empty,
  );

  /// Current selection.
  ValueListenable<GraphSelection> get selection => _selection;

  /// Link currently being dragged.
  final ValueNotifier<ConnectionDraft?> connectionDraft = ValueNotifier(null);

  /// Pointer position of the link being dragged, canvas units.
  final ValueNotifier<Offset?> connectionPointer = ValueNotifier(null);

  /// Selection box, canvas units.
  final ValueNotifier<Rect?> marquee = ValueNotifier(null);

  /// Node whose overlay menu is open (usually the single selected node).
  final ValueNotifier<NodeId?> menuNode = ValueNotifier(null);

  /// Edge whose overlay menu is open, and where (canvas units).
  final ValueNotifier<(EdgeId, Offset)?> menuEdge = ValueNotifier(null);

  /// Called after a link was created by the user.
  void Function(Edge edge)? onConnect;

  /// Called when a link drag ends, on a port or on empty canvas.
  void Function(ConnectEndDetails details)? onConnectEnd;

  /// Called when a node is tapped.
  void Function(NodeInstance node)? onNodeTap;

  /// Called when a node is double tapped. Return true to prevent the
  /// default behaviour (edit dialog / enter super node).
  bool Function(NodeInstance node)? onNodeDoubleTap;

  /// Called when an edge is tapped.
  void Function(Edge edge)? onEdgeTap;

  /// Called on a tap on empty canvas, canvas units.
  void Function(Offset canvasPosition)? onCanvasTap;

  /// Called on a secondary (right) click / long press on empty canvas.
  void Function(Offset canvasPosition, Offset globalPosition)?
  onCanvasContextMenu;

  /// Called after nodes were removed by a user action.
  void Function(List<NodeInstance> nodes)? onNodesDeleted;

  /// Opens the edit dialog for a node; installed by the canvas.
  void Function(NodeId id)? editNodeHandler;

  /// Opens the edit dialog for an edge; installed by the canvas.
  void Function(EdgeId id)? editEdgeHandler;

  /// Animates the viewport; installed by the canvas.
  void Function(EditorViewport target, Duration duration)? viewportAnimator;

  final List<EditorScope> _scopes = [];

  /// Super node navigation stack (root first).
  List<EditorScope> get scopes => List.unmodifiable(_scopes);

  /// The scope being edited.
  EditorScope get scope => _scopes.last;

  final _Notifier _scopeNotifier = _Notifier();

  /// Fires when entering / leaving a super node.
  Listenable get scopeListenable => _scopeNotifier;

  /// The graph being edited (current scope).
  @override
  Graph get graph => scope.graph;

  /// The root graph.
  Graph get rootGraph => _scopes.first.graph;

  /// Undo history of the current scope.
  HistoryStack get history => scope.history;

  /// Spatial index of node rects (current scope).
  final SpatialHashGrid<NodeId> nodeIndex = SpatialHashGrid();

  /// Spatial index of edge bounds (current scope).
  final SpatialHashGrid<EdgeId> edgeIndex = SpatialHashGrid();

  final Map<String, EdgePathBuilder> _edgePathBuilders = {};
  final Map<EdgeId, _EdgeGeometryEntry> _edgeGeometry = {};
  final Map<NodeId, _Notifier> _nodeNotifiers = {};
  final Map<NodeId, _Notifier> _nodePositionNotifiers = {};

  int _renderStamp = 0;
  int _animatedEdges = 0;

  final Map<EdgeId, EdgeRuntimeState> _edgeRuntime = {};
  int _runtimeStamp = 0;

  /// Changes whenever edge runtime states change.
  int get edgeRuntimeStamp => _runtimeStamp;

  /// Number of animated edges in the current graph (styles and runtime).
  int get animatedEdgeCount =>
      _animatedEdges + _edgeRuntime.values.where((r) => r.animated).length;

  /// Runtime state of edge [id], if any.
  EdgeRuntimeState? edgeRuntime(EdgeId id) => _edgeRuntime[id];

  /// Whether edge [edge] is currently animated (style or runtime).
  bool isEdgeAnimated(Edge edge) =>
      edge.style.animated || (_edgeRuntime[edge.id]?.animated ?? false);

  /// Sets (or clears with null) the transient state of edge [id]: use it to
  /// visualize execution (data flowing, errors) without touching the
  /// document or the undo history.
  void setEdgeRuntime(EdgeId id, EdgeRuntimeState? state) {
    if (state == null) {
      if (_edgeRuntime.remove(id) == null) return;
    } else {
      _edgeRuntime[id] = state;
    }
    _runtimeStamp++;
    _dirtyEdges = true;
    if (_batchDepth == 0) _flush();
  }

  /// Clears every edge and node runtime state.
  void clearRuntime() {
    batch(() {
      if (_edgeRuntime.isNotEmpty) {
        _edgeRuntime.clear();
        _runtimeStamp++;
        _dirtyEdges = true;
      }
      for (final n in graph.nodes) {
        if (n.runtime.isNotEmpty) {
          n.runtime.clear();
          _touchNode(n.id);
        }
      }
    });
  }

  /// Changes whenever something affecting the rendering of non-selected
  /// nodes changes (used by low-detail renderers to cache vertex buffers).
  int get renderStamp => _renderStamp;

  final _Notifier _structure = _Notifier();
  final _Notifier _geometry = _Notifier();
  final _Notifier _edges = _Notifier();
  final ValueNotifier<int> _revision = ValueNotifier(0);

  /// Nodes added / removed / reordered.
  Listenable get structure => _structure;

  /// Any node moved or resized.
  Listenable get geometry => _geometry;

  /// Edges changed (added, removed, restyled, or endpoints moved).
  Listenable get edgesListenable => _edges;

  /// Increments on every document change (use it for autosave / dirty
  /// flags).
  ValueListenable<int> get revision => _revision;

  /// A listenable for the content of one node (size, params, selection,
  /// lock, style). Position-only changes do not fire it.
  Listenable nodeListenable(NodeId id) =>
      _nodeNotifiers.putIfAbsent(id, _Notifier.new);

  /// A listenable firing when node [id] moves or is resized.
  Listenable nodePositionListenable(NodeId id) =>
      _nodePositionNotifiers.putIfAbsent(id, _Notifier.new);

  // ---------------------------------------------------------------------
  // Batching
  // ---------------------------------------------------------------------

  int _batchDepth = 0;
  bool _dirtyStructure = false;
  bool _dirtyGeometry = false;
  bool _dirtyEdges = false;
  bool _dirtyDocument = false;
  final Set<NodeId> _dirtyNodes = {};
  final Set<NodeId> _dirtyPositions = {};

  /// Runs [fn] and coalesces all notifications it triggers into one.
  T batch<T>(T Function() fn) {
    _batchDepth++;
    try {
      return fn();
    } finally {
      _batchDepth--;
      if (_batchDepth == 0) _flush();
    }
  }

  void _flush() {
    if (_dirtyPositions.isNotEmpty) {
      final nodes = List.of(_dirtyPositions);
      _dirtyPositions.clear();
      for (final id in nodes) {
        _nodePositionNotifiers[id]?.notify();
      }
    }
    if (_dirtyNodes.isNotEmpty) {
      final nodes = List.of(_dirtyNodes);
      _dirtyNodes.clear();
      for (final id in nodes) {
        _nodeNotifiers[id]?.notify();
      }
    }
    if (_dirtyStructure) {
      _dirtyStructure = false;
      _structure.notify();
    }
    if (_dirtyGeometry) {
      _dirtyGeometry = false;
      _geometry.notify();
    }
    if (_dirtyEdges) {
      _dirtyEdges = false;
      _edges.notify();
    }
    if (_dirtyDocument) {
      _dirtyDocument = false;
      _revision.value++;
    }
  }

  void _touchPosition(NodeId id) {
    _dirtyPositions.add(id);
    if (_batchDepth == 0) _flush();
  }

  void _touchNode(NodeId id) {
    _dirtyNodes.add(id);
    if (_batchDepth == 0) _flush();
  }

  void _markStructure() {
    _dirtyStructure = true;
    _dirtyDocument = true;
    if (_batchDepth == 0) _flush();
  }

  void _markGeometry() {
    _dirtyGeometry = true;
    _dirtyDocument = true;
    if (_batchDepth == 0) _flush();
  }

  void _markEdges() {
    _dirtyEdges = true;
    _dirtyDocument = true;
    if (_batchDepth == 0) _flush();
  }

  void _markDocument() {
    _dirtyDocument = true;
    if (_batchDepth == 0) _flush();
  }

  // ---------------------------------------------------------------------
  // GraphMutator (low level, used by commands)
  // ---------------------------------------------------------------------

  @override
  void insertNode(NodeInstance node, {int? index}) {
    _renderStamp++;
    assert(!graph.containsNode(node.id), 'Duplicate node id ${node.id}');
    graph.addNode(node, index: index);
    nodeIndex.insert(node.id, node.rect);
    _markStructure();
    _markGeometry();
  }

  @override
  void deleteNode(NodeId id) {
    _renderStamp++;
    for (final e in graph.removeNode(id)) {
      if (e.style.animated) _animatedEdges--;
      _forgetEdge(e.id);
      _touchNode(e.source.node == id ? e.target.node : e.source.node);
    }
    nodeIndex.remove(id);
    _nodeNotifiers.remove(id);
    _nodePositionNotifiers.remove(id);
    if (_selection.value.nodes.contains(id)) {
      _selection.value = GraphSelection(
        nodes: {..._selection.value.nodes}..remove(id),
        edges: _selection.value.edges,
      );
    }
    if (menuNode.value == id) menuNode.value = null;
    _markStructure();
    _markGeometry();
  }

  @override
  void insertEdge(Edge edge) {
    graph.addEdge(edge);
    _indexEdge(edge);
    if (edge.style.animated) _animatedEdges++;
    _touchNode(edge.source.node);
    _touchNode(edge.target.node);
    _markEdges();
  }

  @override
  void deleteEdge(EdgeId id) {
    final edge = graph.removeEdge(id);
    if (edge != null) {
      if (edge.style.animated) _animatedEdges--;
      _forgetEdge(id);
      _touchNode(edge.source.node);
      _touchNode(edge.target.node);
      _markEdges();
    }
  }

  void _forgetEdge(EdgeId id) {
    _edgeRuntime.remove(id);
    edgeIndex.remove(id);
    _edgeGeometry.remove(id);
    if (_selection.value.edges.contains(id)) {
      _selection.value = GraphSelection(
        nodes: _selection.value.nodes,
        edges: {..._selection.value.edges}..remove(id),
      );
    }
    if (menuEdge.value?.$1 == id) menuEdge.value = null;
  }

  @override
  void replaceEdge(Edge edge) {
    final old = graph.edge(edge.id);
    if (old != null && old.style.animated) _animatedEdges--;
    if (edge.style.animated) _animatedEdges++;
    graph.replaceEdge(edge);
    _indexEdge(edge);
    _markEdges();
  }

  @override
  void setNodeGeometry(NodeId id, {Offset? position, Size? size}) {
    final node = graph.node(id);
    if (node == null) return;
    if (!_selection.value.nodes.contains(id)) _renderStamp++;
    final resized = size != null && size != node.size;
    if (position != null) node.position = position;
    if (size != null) node.size = size;
    nodeIndex.insert(id, node.rect);
    for (final e in graph.edgesOfNode(id)) {
      _indexEdge(e);
    }
    _touchPosition(id);
    if (resized) _touchNode(id);
    _markGeometry();
    if (graph.edgeIdsOfNode(id).isNotEmpty) _markEdges();
  }

  @override
  void setNodeLocked(NodeId id, bool locked) {
    final node = graph.node(id);
    if (node == null) return;
    node.locked = locked;
    _touchNode(id);
    _markDocument();
  }

  @override
  void setNodeParams(NodeId id, Map<String, Object?> values) {
    final node = graph.node(id);
    if (node == null) return;
    node.params.addAll(values);
    _touchNode(id);
    _markDocument();
  }

  @override
  void setNodeAppearance(NodeId id, {NodeStyle? style, String? title}) {
    _renderStamp++;
    final node = graph.node(id);
    if (node == null) return;
    node
      ..style = style
      ..title = title;
    _touchNode(id);
    _markGeometry(); // low-LOD colors / titles
  }

  @override
  void setNodeCustomPorts(NodeId id, List<PortSpec> ports) {
    _renderStamp++;
    final node = graph.node(id);
    if (node == null) return;
    node
      ..customPorts = ports
      ..invalidatePorts();
    node.size = node.definition.clampSize(node.size, ports);
    _touchPosition(id);
    nodeIndex.insert(id, node.rect);
    for (final e in graph.edgesOfNode(id)) {
      _indexEdge(e);
    }
    _touchNode(id);
    _markGeometry();
    _markEdges();
  }

  @override
  void setNodeData(NodeId id, Map<String, Object?> data) {
    final node = graph.node(id);
    if (node == null) return;
    node.data
      ..clear()
      ..addAll(data);
    _touchNode(id);
    _markDocument();
  }

  // ---------------------------------------------------------------------
  // Commands, transactions, undo / redo
  // ---------------------------------------------------------------------

  List<GraphCommand>? _transaction;
  String _transactionLabel = '';

  /// Applies [command] and records it in the history.
  void execute(GraphCommand command) {
    batch(() => command.apply(this));
    final txn = _transaction;
    if (txn != null) {
      final merged = txn.isEmpty ? null : txn.last.mergeWith(command);
      if (merged != null) {
        txn[txn.length - 1] = merged;
      } else {
        txn.add(command);
      }
    } else {
      history.push(command);
    }
  }

  /// Starts grouping executed commands into a single undo step.
  void beginTransaction(String label) {
    if (_transaction != null) return;
    _transaction = [];
    _transactionLabel = label;
  }

  /// Ends the current transaction and records it.
  void commitTransaction() {
    final txn = _transaction;
    _transaction = null;
    if (txn == null || txn.isEmpty) return;
    history
      ..seal()
      ..push(
        txn.length == 1 ? txn.single : CompositeCommand(_transactionLabel, txn),
      )
      ..seal();
  }

  /// Reverts and discards the current transaction.
  void cancelTransaction() {
    final txn = _transaction;
    _transaction = null;
    if (txn == null) return;
    batch(() {
      for (final c in txn.reversed) {
        c.revert(this);
      }
    });
  }

  /// Runs [fn]; all commands it executes become one undo step.
  T transaction<T>(String label, T Function() fn) {
    final nested = _transaction != null;
    if (!nested) beginTransaction(label);
    try {
      return batch(fn);
    } finally {
      if (!nested) commitTransaction();
    }
  }

  /// Undoes the last step.
  void undo() {
    final c = history.takeUndo();
    if (c != null) batch(() => c.revert(this));
  }

  /// Redoes the last undone step.
  void redo() {
    final c = history.takeRedo();
    if (c != null) batch(() => c.apply(this));
  }

  // ---------------------------------------------------------------------
  // Edge geometry
  // ---------------------------------------------------------------------

  /// Registers a custom routing function, referenced by
  /// [EdgeStyle.customPath].
  void registerEdgePathBuilder(String name, EdgePathBuilder builder) {
    _edgePathBuilders[name] = builder;
    _edgeGeometry.clear();
    _markEdges();
  }

  /// Anchor of [ref] in canvas coordinates.
  Offset? portAnchor(PortRef ref) {
    final node = graph.node(ref.node);
    return node == null ? null : PortGeometry.anchor(node, ref.port);
  }

  /// Routing input for [edge] (null when an endpoint is missing).
  EdgePathInput? edgeInput(Edge edge) {
    final s = graph.node(edge.source.node), t = graph.node(edge.target.node);
    if (s == null || t == null) return null;
    final sp = s.port(edge.source.port), tp = t.port(edge.target.port);
    if (sp == null || tp == null) return null;
    final sa = PortGeometry.relativeAnchors(s)[sp.id]!;
    final ta = PortGeometry.relativeAnchors(t)[tp.id]!;
    return EdgePathInput(
      source: s.position + sa,
      sourceSide: sp.effectiveSide,
      target: t.position + ta,
      targetSide: tp.effectiveSide,
      style: edge.style,
      waypoints: edge.waypoints,
    );
  }

  /// Routed geometry of [edge], cached until an endpoint or the style
  /// changes.
  EdgeGeometry? edgeGeometry(Edge edge) {
    final input = edgeInput(edge);
    if (input == null) return null;
    final cached = _edgeGeometry[edge.id];
    if (cached != null &&
        cached.source == input.source &&
        cached.target == input.target &&
        identical(cached.style, edge.style) &&
        identical(cached.waypoints, edge.waypoints)) {
      return cached.geometry;
    }
    final geometry = EdgeRouter.route(input, custom: _edgePathBuilders);
    _edgeGeometry[edge.id] = _EdgeGeometryEntry(
      input.source,
      input.target,
      edge.style,
      edge.waypoints,
      geometry,
    );
    return geometry;
  }

  void _indexEdge(Edge edge) {
    final input = edgeInput(edge);
    if (input == null) {
      edgeIndex.remove(edge.id);
      return;
    }
    edgeIndex.insert(edge.id, EdgeRouter.estimateBounds(input));
  }

  void _rebuildIndexes() {
    nodeIndex.clear();
    edgeIndex.clear();
    _edgeGeometry.clear();
    for (final n in graph.nodes) {
      nodeIndex.insert(n.id, n.rect);
    }
    _animatedEdges = 0;
    for (final e in graph.edges) {
      _indexEdge(e);
      if (e.style.animated) _animatedEdges++;
    }
  }

  // ---------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------

  /// The topmost node containing [canvasPoint].
  NodeInstance? nodeAt(Offset canvasPoint) {
    NodeInstance? best;
    var bestZ = -1;
    for (final id in nodeIndex.queryPoint(canvasPoint)) {
      final z = graph.indexOfNode(id);
      if (z > bestZ) {
        bestZ = z;
        best = graph.node(id);
      }
    }
    return best;
  }

  /// Nodes overlapping (or inside, when [fullyInside]) [area].
  List<NodeId> nodesIn(Rect area, {bool fullyInside = false}) => [
    for (final id in nodeIndex.query(area))
      if (!fullyInside || _contains(area, nodeIndex.boundsOf(id)!)) id,
  ];

  static bool _contains(Rect outer, Rect inner) =>
      outer.left <= inner.left &&
      outer.top <= inner.top &&
      outer.right >= inner.right &&
      outer.bottom >= inner.bottom;

  /// The edge closest to [canvasPoint] within [tolerance] canvas units.
  Edge? edgeAt(Offset canvasPoint, {double? tolerance}) {
    final tol = tolerance ?? config.edgeHitTolerance / viewport.value.zoom;
    Edge? best;
    var bestD = tol;
    final area = Rect.fromCircle(center: canvasPoint, radius: tol);
    for (final id in edgeIndex.query(area)) {
      final edge = graph.edge(id);
      if (edge == null) continue;
      final g = edgeGeometry(edge);
      if (g == null || !g.bounds.inflate(tol).contains(canvasPoint)) continue;
      final d = g.distanceTo(canvasPoint);
      if (d <= bestD) {
        bestD = d;
        best = edge;
      }
    }
    return best;
  }

  /// The port closest to [canvasPoint] within [radius] canvas units,
  /// optionally filtered by [where].
  PortRef? portAt(
    Offset canvasPoint,
    double radius, {
    bool Function(PortRef ref, PortSpec spec)? where,
  }) {
    PortRef? best;
    var bestD = radius;
    final area = Rect.fromCircle(center: canvasPoint, radius: radius);
    for (final id in nodeIndex.query(area.inflate(1))) {
      final node = graph.node(id)!;
      final anchors = PortGeometry.relativeAnchors(node);
      for (final p in node.ports) {
        final d = (node.position + anchors[p.id]! - canvasPoint).distance;
        if (d > bestD) continue;
        final ref = PortRef(id, p.id);
        if (where != null && !where(ref, p)) continue;
        bestD = d;
        best = ref;
      }
    }
    return best;
  }

  /// Bounds of all nodes (or of [ids]), null when empty.
  Rect? boundsOf([Iterable<NodeId>? ids]) {
    if (ids == null) return nodeIndex.totalBounds;
    Rect? r;
    for (final id in ids) {
      final b = graph.node(id)?.rect;
      if (b == null) continue;
      r = r == null ? b : r.expandToInclude(b);
    }
    return r;
  }

  // ---------------------------------------------------------------------
  // Nodes and edges API
  // ---------------------------------------------------------------------

  /// Adds a node of [type] (or [definition]) with its top-left at
  /// [position] (snapped to the grid when enabled).
  NodeInstance addNode(
    String type, {
    required Offset position,
    Map<String, Object?>? params,
    NodeId? id,
    String? title,
    bool select = true,
  }) {
    final def = registry[type];
    if (def == null) throw ArgumentError('Unknown node type "$type"');
    final node = NodeInstance.create(
      def,
      position: canvasSettings.value.snapOffset(position),
      id: id,
      params: params,
      title: title,
    );
    execute(AddElementsCommand(nodes: [node], label: 'Add ${def.title}'));
    if (select) selectNodes([node.id]);
    return node;
  }

  /// Adds a node of [type] centered on canvas point [center].
  NodeInstance addNodeCentered(
    String type,
    Offset center, {
    Map<String, Object?>? params,
    bool select = true,
  }) {
    final def = registry[type];
    if (def == null) throw ArgumentError('Unknown node type "$type"');
    final size = def.resolvedDefaultSize();
    return addNode(
      type,
      position: center - Offset(size.width / 2, size.height / 2),
      params: params,
      select: select,
    );
  }

  /// Adds nodes and edges in one undo step.
  void addElements(
    List<NodeInstance> nodes,
    List<Edge> edges, {
    String label = 'Add',
  }) {
    execute(AddElementsCommand(nodes: nodes, edges: edges, label: label));
  }

  /// Removes nodes (and their edges) and edges.
  ///
  /// When [userAction] is true, locked and non-deletable nodes are kept.
  void remove({
    Iterable<NodeId> nodes = const [],
    Iterable<EdgeId> edges = const [],
    bool userAction = false,
  }) {
    var ids = nodes;
    if (userAction) {
      ids = nodes.where((id) {
        final n = graph.node(id);
        return n != null && !n.locked && n.definition.deletable;
      });
    }
    final cmd = RemoveElementsCommand.capture(
      graph,
      nodeIds: ids,
      edgeIds: edges,
    );
    if (cmd.isEmpty) return;
    execute(cmd);
    if (userAction && cmd.nodes.isNotEmpty) onNodesDeleted?.call(cmd.nodes);
  }

  /// Deletes the selected elements (respecting locks).
  void deleteSelection() {
    if (!config.deletable) return;
    final sel = _selection.value;
    remove(nodes: sel.nodes, edges: sel.edges, userAction: true);
  }

  /// Validates a link between two ports (in either order).
  ConnectionResult canConnect(PortRef a, PortRef b) =>
      validator.validate(graph, a, b);

  /// Links two ports (in either order). Returns the new edge, or null when
  /// the validator rejects it.
  Edge? connect(
    PortRef a,
    PortRef b, {
    EdgeStyle? style,
    String? label,
    bool userAction = false,
  }) {
    final result = validator.validate(graph, a, b);
    if (!result.isValid) return null;
    final req = result.request!;
    final edge = Edge(
      id: IdGenerator.edge(),
      source: req.source,
      target: req.target,
      style: style ?? canvasSettings.value.defaultEdgeStyle,
      label: label,
    );
    final commands = <GraphCommand>[];
    if (req.targetPort.maxLinks >= 0 &&
        graph.linkCount(req.target) >= req.targetPort.maxLinks) {
      commands.add(
        RemoveElementsCommand.capture(
          graph,
          edgeIds: graph.edgesOfPort(req.target).map((e) => e.id),
        ),
      );
    }
    commands.add(AddElementsCommand(edges: [edge], label: 'Connect'));
    execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand('Connect', commands),
    );
    if (userAction) onConnect?.call(edge);
    return edge;
  }

  /// Removes edges.
  void disconnect(Iterable<EdgeId> edges) => remove(edges: edges);

  /// Moves nodes to absolute positions.
  void moveNodes(Map<NodeId, Offset> positions) {
    final from = <NodeId, Offset>{};
    final to = <NodeId, Offset>{};
    positions.forEach((id, p) {
      final n = graph.node(id);
      if (n == null || n.position == p) return;
      from[id] = n.position;
      to[id] = p;
    });
    if (to.isNotEmpty) execute(MoveNodesCommand(from, to));
  }

  /// Moves the selected, unlocked nodes by [delta].
  void nudgeSelection(Offset delta) {
    if (!config.nodesDraggable) return;
    moveNodes({
      for (final id in _selection.value.nodes)
        if (graph.node(id) case final n? when !n.locked) id: n.position + delta,
    });
  }

  /// Arranges the nodes in layers from left to right following the links
  /// (undoable). With [selectionOnly], only the selected nodes move.
  void autoLayout({
    double columnGap = 80,
    double rowGap = 40,
    bool selectionOnly = false,
  }) {
    final copy = graph.copy();
    final only = selectionOnly ? _selection.value.nodes : null;
    final origin = boundsOf(only)?.topLeft ?? Offset.zero;
    GraphCodec.autoLayout(
      copy,
      columnGap: columnGap,
      rowGap: rowGap,
      origin: origin,
    );
    moveNodes({
      for (final n in copy.nodes)
        if ((only == null || only.contains(n.id)) &&
            !(graph.node(n.id)?.locked ?? true))
          n.id: canvasSettings.value.snapOffset(n.position),
    });
  }

  /// Aligns the selected, unlocked nodes.
  void alignSelection(NodeAlignment alignment) {
    final nodes = [
      for (final id in _selection.value.nodes)
        if (graph.node(id) case final n? when !n.locked) n,
    ];
    if (nodes.length < 2) return;
    final b = boundsOf(nodes.map((n) => n.id))!;
    moveNodes({
      for (final n in nodes)
        n.id: switch (alignment) {
          NodeAlignment.left => Offset(b.left, n.position.dy),
          NodeAlignment.centerHorizontal => Offset(
            b.center.dx - n.size.width / 2,
            n.position.dy,
          ),
          NodeAlignment.right => Offset(b.right - n.size.width, n.position.dy),
          NodeAlignment.top => Offset(n.position.dx, b.top),
          NodeAlignment.centerVertical => Offset(
            n.position.dx,
            b.center.dy - n.size.height / 2,
          ),
          NodeAlignment.bottom => Offset(
            n.position.dx,
            b.bottom - n.size.height,
          ),
        },
    });
  }

  /// Spreads the selected, unlocked nodes evenly along [horizontal] or
  /// vertical axis (equal gaps).
  void distributeSelection({bool horizontal = true}) {
    final nodes = [
      for (final id in _selection.value.nodes)
        if (graph.node(id) case final n? when !n.locked) n,
    ];
    if (nodes.length < 3) return;
    nodes.sort(
      (a, b) => horizontal
          ? a.position.dx.compareTo(b.position.dx)
          : a.position.dy.compareTo(b.position.dy),
    );
    final b = boundsOf(nodes.map((n) => n.id))!;
    final total = nodes.fold<double>(
      0,
      (s, n) => s + (horizontal ? n.size.width : n.size.height),
    );
    final gap =
        ((horizontal ? b.width : b.height) - total) / (nodes.length - 1);
    var cursor = horizontal ? b.left : b.top;
    final positions = <NodeId, Offset>{};
    for (final n in nodes) {
      positions[n.id] = horizontal
          ? Offset(cursor, n.position.dy)
          : Offset(n.position.dx, cursor);
      cursor += (horizontal ? n.size.width : n.size.height) + gap;
    }
    moveNodes(positions);
  }

  /// Sets the rect of node [id] (clamped to its definition limits).
  void setNodeRect(NodeId id, Rect rect) {
    final n = graph.node(id);
    if (n == null) return;
    final size = n.definition.clampSize(rect.size, n.customPorts);
    final to = rect.topLeft & size;
    if (to == n.rect) return;
    execute(SetNodeRectCommand(id, n.rect, to));
  }

  /// Sets parameter values of node [id].
  void setParams(NodeId id, Map<String, Object?> values) {
    final n = graph.node(id);
    if (n == null) return;
    final normalized = <String, Object?>{};
    values.forEach((k, v) {
      final spec = n.definition.param(k);
      normalized[k] = spec == null ? v : spec.type.normalizeAny(v);
    });
    final before = {for (final k in normalized.keys) k: n.params[k]};
    if (mapEquals(before, normalized)) return;
    execute(SetParamsCommand(id, before, normalized));
  }

  /// Sets one parameter of node [id].
  void setParam(NodeId id, String name, Object? value) =>
      setParams(id, {name: value});

  /// Locks or unlocks nodes.
  void setLocked(Iterable<NodeId> ids, bool locked) {
    final before = <NodeId, bool>{
      for (final id in ids)
        if (graph.node(id) case final n? when n.locked != locked) id: n.locked,
    };
    if (before.isNotEmpty) execute(SetLockedCommand(before, locked));
  }

  /// Toggles the lock of the selection.
  void toggleLockSelection() {
    final ids = _selection.value.nodes;
    if (ids.isEmpty) return;
    final allLocked = ids.every((id) => graph.node(id)?.locked ?? false);
    setLocked(ids, !allLocked);
  }

  /// Changes style / title of node [id].
  void setNodeAppearanceOf(NodeId id, {NodeStyle? style, String? title}) {
    final n = graph.node(id);
    if (n == null) return;
    execute(
      SetNodeAppearanceCommand(
        id,
        beforeStyle: n.style,
        afterStyle: style,
        beforeTitle: n.title,
        afterTitle: title,
      ),
    );
  }

  /// Replaces the custom ports of node [id], removing edges attached to
  /// ports that disappear.
  void setCustomPorts(NodeId id, List<PortSpec> ports) {
    final n = graph.node(id);
    if (n == null) return;
    final keep = {
      ...n.definition.ports.map((p) => p.id),
      ...ports.map((p) => p.id),
    };
    final orphan = [
      for (final e in graph.edgesOfNode(id))
        if ((e.source.node == id && !keep.contains(e.source.port)) ||
            (e.target.node == id && !keep.contains(e.target.port)))
          e.id,
    ];
    transaction('Edit ports', () {
      if (orphan.isNotEmpty) {
        execute(RemoveElementsCommand.capture(graph, edgeIds: orphan));
      }
      execute(SetCustomPortsCommand(id, n.customPorts, ports));
    });
  }

  /// Replaces the data payload of node [id] (undoable).
  void setNodeDataOf(NodeId id, Map<String, Object?> data) {
    final n = graph.node(id);
    if (n == null) return;
    execute(SetNodeDataCommand(id, Map.of(n.data), data));
  }

  /// Merges [values] into the transient runtime state of node [id]
  /// (`NodeInstance.runtime`): execution status, previews, results... Not
  /// saved and not recorded in the history. The built-in node body shows
  /// `status` (`running`, `success`, `warning`, `error`) and `statusText`.
  void setRuntimeData(NodeId id, Map<String, Object?> values) {
    final n = graph.node(id);
    if (n == null) return;
    n.runtime.addAll(values);
    _touchNode(id);
  }

  /// Updates edge [id].
  void updateEdge(EdgeId id, Edge Function(Edge edge) update) {
    final e = graph.edge(id);
    if (e == null) return;
    final next = update(e);
    if (identical(next, e)) return;
    execute(UpdateEdgeCommand(e, next));
  }

  /// Moves node [id] on top of the others (not recorded in history).
  void bringToFront(NodeId id) {
    _renderStamp++;
    if (!graph.containsNode(id)) return;
    if (graph.nodes.isNotEmpty && graph.nodes.last.id == id) return;
    graph.bringToFront(id);
    _markStructure();
  }

  // ---------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------

  /// Replaces the selection.
  void setSelection(GraphSelection value) {
    final old = _selection.value;
    if (setEquals(old.nodes, value.nodes) &&
        setEquals(old.edges, value.edges)) {
      return;
    }
    _renderStamp++;
    batch(() {
      for (final id in old.nodes.difference(value.nodes)) {
        _touchNode(id);
      }
      for (final id in value.nodes.difference(old.nodes)) {
        _touchNode(id);
      }
      _selection.value = value;
      _dirtyEdges = true;
    });
    final single = value.singleNode;
    menuNode.value = single;
    if (value.singleEdge == null) menuEdge.value = null;
  }

  /// Selects nodes; with [additive] they are added to the selection.
  void selectNodes(Iterable<NodeId> ids, {bool additive = false}) {
    if (!config.elementsSelectable) return;
    final sel = _selection.value;
    setSelection(
      GraphSelection(
        nodes: {if (additive) ...sel.nodes, ...ids},
        edges: additive ? sel.edges : const {},
      ),
    );
  }

  /// Selects edges; with [additive] they are added to the selection.
  void selectEdges(Iterable<EdgeId> ids, {bool additive = false}) {
    if (!config.edgesSelectable) return;
    final sel = _selection.value;
    setSelection(
      GraphSelection(
        nodes: additive ? sel.nodes : const {},
        edges: {if (additive) ...sel.edges, ...ids},
      ),
    );
  }

  /// Toggles node [id] in the selection.
  void toggleNodeSelection(NodeId id) {
    final sel = _selection.value;
    final nodes = {...sel.nodes};
    if (!nodes.remove(id)) nodes.add(id);
    setSelection(GraphSelection(nodes: nodes, edges: sel.edges));
  }

  /// Selects every node and edge.
  void selectAll() {
    if (!config.elementsSelectable) return;
    setSelection(
      GraphSelection(
        nodes: graph.nodeIds.toSet(),
        edges: {for (final e in graph.edges) e.id},
      ),
    );
  }

  /// Clears the selection.
  void clearSelection() => setSelection(GraphSelection.empty);

  /// Whether node [id] is selected.
  bool isNodeSelected(NodeId id) => _selection.value.nodes.contains(id);

  /// Whether edge [id] is selected.
  bool isEdgeSelected(EdgeId id) => _selection.value.edges.contains(id);

  // ---------------------------------------------------------------------
  // EditorViewport
  // ---------------------------------------------------------------------

  /// Sets the viewport (clamped to zoom limits and translate extent).
  void setViewport(EditorViewport v) {
    viewport.value = _clampViewport(v);
  }

  EditorViewport _clampViewport(EditorViewport v) {
    final zoom = v.zoom.clamp(config.minZoom, config.maxZoom);
    var offset = v.offset;
    final extent = config.translateExtent;
    if (extent != null) {
      final minX = viewportSize.width - extent.right * zoom;
      final maxX = -extent.left * zoom;
      final minY = viewportSize.height - extent.bottom * zoom;
      final maxY = -extent.top * zoom;
      offset = Offset(
        minX > maxX ? (minX + maxX) / 2 : offset.dx.clamp(minX, maxX),
        minY > maxY ? (minY + maxY) / 2 : offset.dy.clamp(minY, maxY),
      );
    }
    return EditorViewport(offset: offset, zoom: zoom);
  }

  /// Pans by [delta] screen pixels.
  void panBy(Offset delta) => setViewport(
    viewport.value.copyWith(offset: viewport.value.offset + delta),
  );

  /// Multiplies the zoom by [factor] around [focal] (screen; defaults to the
  /// viewport center).
  void zoomBy(double factor, {Offset? focal, bool animate = false}) {
    final v = viewport.value;
    final z = (v.zoom * factor).clamp(config.minZoom, config.maxZoom);
    _goTo(v.zoomAround(focal ?? viewportSize.center(Offset.zero), z), animate);
  }

  /// Sets the zoom around the viewport center.
  void zoomTo(double zoom, {bool animate = false}) =>
      zoomBy(zoom / viewport.value.zoom, animate: animate);

  /// Zooms in by [NodeEditorConfig.zoomStep].
  void zoomIn({bool animate = true}) =>
      zoomBy(config.zoomStep, animate: animate);

  /// Zooms out by [NodeEditorConfig.zoomStep].
  void zoomOut({bool animate = true}) =>
      zoomBy(1 / config.zoomStep, animate: animate);

  /// Centers the viewport on canvas point [point].
  void centerOn(Offset point, {double? zoom, bool animate = true}) {
    if (!_hasLayout) {
      _pendingFit = () => centerOn(point, zoom: zoom, animate: false);
      return;
    }
    final z = (zoom ?? viewport.value.zoom).clamp(
      config.minZoom,
      config.maxZoom,
    );
    _goTo(
      EditorViewport(
        offset: viewportSize.center(Offset.zero) - point * z,
        zoom: z,
      ),
      animate,
    );
  }

  /// Fits all nodes (or [ids]) in the viewport.
  void fitView({
    Iterable<NodeId>? ids,
    double padding = 48,
    double? maxZoom,
    bool animate = true,
  }) {
    if (!_hasLayout) {
      _pendingFit = () =>
          fitView(ids: ids, padding: padding, maxZoom: maxZoom, animate: false);
      return;
    }
    final b = boundsOf(ids);
    if (b == null || viewportSize.isEmpty) return;
    final zx = (viewportSize.width - padding * 2) / math.max(b.width, 1);
    final zy = (viewportSize.height - padding * 2) / math.max(b.height, 1);
    final z = math
        .min(zx, zy)
        .clamp(config.minZoom, math.min(maxZoom ?? 1.5, config.maxZoom))
        .toDouble();
    _goTo(
      EditorViewport(
        offset: viewportSize.center(Offset.zero) - b.center * z,
        zoom: z,
      ),
      animate,
    );
  }

  void _goTo(EditorViewport target, bool animate) {
    final t = _clampViewport(target);
    if (animate && viewportAnimator != null) {
      viewportAnimator!(t, const Duration(milliseconds: 260));
    } else {
      viewport.value = t;
    }
  }

  /// The canvas point at the center of the viewport.
  Offset get viewportCenter =>
      viewport.value.toCanvas(viewportSize.center(Offset.zero));

  // ---------------------------------------------------------------------
  // Interactions (called by the canvas widgets)
  // ---------------------------------------------------------------------

  Map<NodeId, Offset>? _dragStart;
  NodeId? _dragAnchor;

  /// Starts dragging [id] (and the rest of the selection when [id] is
  /// selected).
  void beginNodeDrag(NodeId id) {
    if (!config.nodesDraggable) return;
    if (!isNodeSelected(id)) selectNodes([id]);
    _dragAnchor = id;
    _dragStart = {
      for (final sid in _selection.value.nodes)
        if (graph.node(sid) case final n? when !n.locked) sid: n.position,
    };
    beginTransaction('Move');
  }

  /// Updates the drag with the total pointer displacement in canvas units.
  void updateNodeDrag(Offset totalDelta) {
    final start = _dragStart;
    if (start == null || start.isEmpty) return;
    var delta = totalDelta;
    final anchorStart = start[_dragAnchor] ?? start.values.first;
    final settings = canvasSettings.value;
    if (settings.snapToGrid) {
      delta = settings.snapOffset(anchorStart + totalDelta) - anchorStart;
    }
    moveNodes({for (final e in start.entries) e.key: e.value + delta});
  }

  /// Ends the node drag.
  void endNodeDrag() {
    _dragStart = null;
    _dragAnchor = null;
    commitTransaction();
  }

  /// Starts a link drag from port [from].
  void beginConnection(PortRef from) {
    if (!config.nodesConnectable) return;
    final spec = graph.port(from);
    if (spec == null) return;
    connectionDraft.value = ConnectionDraft(from: from, fromPort: spec);
    connectionPointer.value = portAnchor(from);
    menuNode.value = null;
    menuEdge.value = null;
  }

  /// Updates the link drag pointer (canvas units) and snaps to the nearest
  /// compatible port.
  void updateConnection(Offset canvasPosition) {
    final draft = connectionDraft.value;
    if (draft == null) return;
    connectionPointer.value = canvasPosition;
    final radius = config.connectionSnapRadius / viewport.value.zoom;
    final target = portAt(
      canvasPosition,
      radius,
      where: (ref, spec) =>
          ref != draft.from && validator.isCompatible(graph, draft.from, ref),
    );
    if (target == draft.hoverTarget) return;
    final valid =
        target != null && validator.validate(graph, draft.from, target).isValid;
    connectionDraft.value = draft.withHover(target, valid);
  }

  /// Ends the link drag, creating the edge when a valid port is hovered.
  Edge? endConnection() {
    final draft = connectionDraft.value;
    final pos = connectionPointer.value;
    connectionDraft.value = null;
    connectionPointer.value = null;
    if (draft == null) return null;
    Edge? edge;
    if (draft.hoverTarget != null && draft.hoverValid) {
      edge = connect(draft.from, draft.hoverTarget!, userAction: true);
    }
    onConnectEnd?.call(
      ConnectEndDetails(
        draft.from,
        draft.fromPort,
        pos ?? Offset.zero,
        edge: edge,
      ),
    );
    return edge;
  }

  /// Cancels the link drag.
  void cancelConnection() {
    connectionDraft.value = null;
    connectionPointer.value = null;
  }

  Offset? _marqueeOrigin;
  GraphSelection _marqueeBase = GraphSelection.empty;

  /// Starts a selection box at canvas point [origin].
  void beginMarquee(Offset origin, {bool additive = false}) {
    if (!config.elementsSelectable) return;
    _marqueeOrigin = origin;
    _marqueeBase = additive ? _selection.value : GraphSelection.empty;
    marquee.value = Rect.fromPoints(origin, origin);
    if (!additive) clearSelection();
  }

  /// Updates the selection box corner.
  void updateMarquee(Offset corner) {
    final origin = _marqueeOrigin;
    if (origin == null) return;
    final rect = Rect.fromPoints(origin, corner);
    marquee.value = rect;
    final nodes = nodesIn(
      rect,
      fullyInside: config.marqueeRequiresFullContainment,
    ).toSet();
    final edges = <EdgeId>{};
    if (config.selectEdgesOnMarquee) {
      for (final id in nodes) {
        for (final e in graph.edgesOfNode(id)) {
          if (nodes.contains(e.source.node) && nodes.contains(e.target.node)) {
            edges.add(e.id);
          }
        }
      }
    }
    setSelection(
      GraphSelection(
        nodes: {..._marqueeBase.nodes, ...nodes},
        edges: {..._marqueeBase.edges, ...edges},
      ),
    );
  }

  /// Ends the selection box.
  void endMarquee() {
    _marqueeOrigin = null;
    marquee.value = null;
  }

  // ---------------------------------------------------------------------
  // Clipboard
  // ---------------------------------------------------------------------

  GraphFragment? _clipboard;
  int _pasteCount = 0;

  /// The internal clipboard content.
  GraphFragment? get clipboard => _clipboard;

  /// Captures the selected nodes (and the edges between them).
  GraphFragment? copySelection() {
    final ids = [
      for (final id in _selection.value.nodes)
        if (graph.node(id)?.definition.copyable ?? false) id,
    ];
    if (ids.isEmpty) return null;
    final fragment = superNodes.attachDefinitions(
      GraphFragment.capture(graph, ids),
    );
    _clipboard = fragment;
    _pasteCount = 0;
    if (config.useSystemClipboard) {
      unawaited(
        Clipboard.setData(ClipboardData(text: fragment.toJsonString()))
            .catchError((Object _) {}),
      );
    }
    return fragment;
  }

  /// Copies then deletes the selection.
  void cutSelection() {
    if (copySelection() != null) deleteSelection();
  }

  /// Pastes [fragment] (default: clipboard). With [at], the fragment's
  /// top-left lands there; otherwise it is offset from the original.
  Future<List<NodeInstance>> paste({
    GraphFragment? fragment,
    Offset? at,
  }) async {
    var f = fragment;
    if (f == null && config.useSystemClipboard) {
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        f = GraphFragment.tryParse(data?.text);
      } catch (_) {}
    }
    f ??= _clipboard;
    if (f == null || f.isEmpty) return const [];
    return pasteFragment(f, at: at);
  }

  /// Synchronous paste of [fragment].
  List<NodeInstance> pasteFragment(GraphFragment fragment, {Offset? at}) {
    superNodes.registerFromFragment(fragment);
    final bounds = fragment.bounds ?? Rect.zero;
    final Offset delta;
    if (at != null) {
      delta = canvasSettings.value.snapOffset(at) - bounds.topLeft;
    } else {
      _pasteCount++;
      delta =
          Offset(config.pasteOffset, config.pasteOffset) *
          _pasteCount.toDouble();
    }
    final (nodes, edges) = fragment.instantiate(registry, delta: delta);
    execute(AddElementsCommand(nodes: nodes, edges: edges, label: 'Paste'));
    selectNodes(nodes.map((n) => n.id));
    return nodes;
  }

  /// Duplicates the selection.
  void duplicateSelection() {
    final f = GraphFragment.capture(graph, _selection.value.nodes);
    if (!f.isEmpty) {
      pasteFragment(
        f,
        at: f.bounds!.topLeft + Offset(config.pasteOffset, config.pasteOffset),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Super node scopes
  // ---------------------------------------------------------------------

  /// Enters the interior of super node instance [id].
  bool enterSuperNode(NodeId id) {
    final node = graph.node(id);
    final def = node == null ? null : superNodes.definitionOf(node.type);
    if (node == null || def == null) return false;
    scope.savedViewport = viewport.value;
    clearSelection();
    _scopes.add(
      EditorScope(
        graph: def.graph,
        label: def.name,
        superNode: def,
        instance: id,
      ),
    );
    _onScopeChanged();
    fitView(animate: false);
    return true;
  }

  /// Leaves the current super node (or goes back to [depth]).
  void exitSuperNode({int? depth}) {
    final target = depth ?? _scopes.length - 2;
    if (target < 0 || target >= _scopes.length - 1) return;
    clearSelection();
    final edited = <SuperNodeDefinition>[];
    while (_scopes.length > target + 1) {
      final left = _scopes.removeLast();
      if (left.superNode != null) edited.add(left.superNode!);
    }
    for (final def in edited) {
      superNodes.refresh(this, def);
    }
    _onScopeChanged();
    viewport.value = scope.savedViewport;
  }

  void _onScopeChanged() {
    _renderStamp++;
    cancelConnection();
    endMarquee();
    menuNode.value = null;
    menuEdge.value = null;
    _rebuildIndexes();
    batch(() {
      _dirtyStructure = true;
      _dirtyGeometry = true;
      _dirtyEdges = true;
    });
    _scopeNotifier.notify();
    notifyListeners();
  }

  /// Groups the selected nodes into a new super node. Returns the instance.
  NodeInstance? groupSelection({String? name}) {
    final ids = _selection.value.nodes;
    if (ids.isEmpty) return null;
    final result = superNodes.group(this, ids, name: name);
    if (result != null) selectNodes([result.id]);
    return result;
  }

  /// Replaces the selected super node instances by their content.
  void ungroupSelection() {
    final created = <NodeId>[];
    transaction('Ungroup', () {
      for (final id in List.of(_selection.value.nodes)) {
        created.addAll(superNodes.ungroup(this, id));
      }
    });
    if (created.isNotEmpty) selectNodes(created);
  }

  // ---------------------------------------------------------------------
  // Documents
  // ---------------------------------------------------------------------

  /// Exports the logic file of the root graph.
  LogicDocument exportLogic({Map<String, Object?> metadata = const {}}) {
    final (nodes, edges, _) = GraphCodec.encode(
      rootGraph.nodes,
      rootGraph.edges,
    );
    return LogicDocument(
      nodes: nodes,
      edges: edges,
      superNodes: superNodes.exportLogic(rootGraph),
      metadata: metadata,
    );
  }

  /// Exports the design file of the root graph.
  DesignDocument exportDesign() {
    final (_, _, design) = GraphCodec.encode(rootGraph.nodes, rootGraph.edges);
    return DesignDocument(
      viewport: _scopes.length == 1
          ? viewport.value
          : _scopes.first.savedViewport,
      canvas: canvasSettings.value,
      graph: design,
      superNodes: superNodes.exportDesign(rootGraph),
    );
  }

  /// Replaces the whole document. [design] is optional: without it nodes
  /// are laid out automatically.
  void load(LogicDocument logic, [DesignDocument? design]) {
    while (_scopes.length > 1) {
      _scopes.removeLast();
    }
    superNodes.importDefinitions(logic.superNodes, design?.superNodes ?? {});
    final graph = GraphCodec.decode(
      nodes: logic.nodes,
      edges: logic.edges,
      registry: registry,
      design: design?.graph,
    );
    _scopes[0] = EditorScope(graph: graph, label: 'Root');
    if (design != null) canvasSettings.value = design.canvas;
    _selection.value = GraphSelection.empty;
    _onScopeChanged();
    if (design != null) {
      viewport.value = design.viewport;
    } else {
      fitView(animate: false);
    }
  }

  /// Removes everything.
  void clear() {
    load(LogicDocument());
  }

  @override
  void dispose() {
    for (final n in [_structure, _geometry, _edges, _scopeNotifier]) {
      n.dispose();
    }
    _revision.dispose();
    _viewportSize.dispose();
    _selection.dispose();
    connectionDraft.dispose();
    connectionPointer.dispose();
    marquee.dispose();
    menuNode.dispose();
    menuEdge.dispose();
    canvasSettings.dispose();
    viewport.dispose();
    super.dispose();
  }
}

class _EdgeGeometryEntry {
  _EdgeGeometryEntry(
    this.source,
    this.target,
    this.style,
    this.waypoints,
    this.geometry,
  );
  final Offset source;
  final Offset target;
  final EdgeStyle style;
  final List<Offset> waypoints;
  final EdgeGeometry geometry;
}
