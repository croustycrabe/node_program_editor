import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'edge.dart';
import 'graph.dart';
import 'ids.dart';
import 'node.dart';
import 'ports.dart';

/// Low level, notification-aware mutations used by [GraphCommand]s.
///
/// Implemented by the `NodeEditorController`. Commands must only change the
/// graph through this interface so indexes, caches and listeners stay in
/// sync.
abstract interface class GraphMutator {
  /// The graph being edited (the current super-node scope).
  Graph get graph;

  /// The node registry.
  NodeRegistry get registry;

  /// Inserts [node] at z-[index] (top when null).
  void insertNode(NodeInstance node, {int? index});

  /// Deletes node [id]. Its edges must already be removed.
  void deleteNode(NodeId id);

  /// Inserts [edge].
  void insertEdge(Edge edge);

  /// Deletes edge [id].
  void deleteEdge(EdgeId id);

  /// Replaces an edge keeping its id.
  void replaceEdge(Edge edge);

  /// Moves / resizes node [id].
  void setNodeGeometry(NodeId id, {Offset? position, Size? size});

  /// Locks or unlocks node [id].
  void setNodeLocked(NodeId id, bool locked);

  /// Writes parameter values of node [id] (other keys are kept).
  void setNodeParams(NodeId id, Map<String, Object?> values);

  /// Sets style and title overrides of node [id].
  void setNodeAppearance(NodeId id, {NodeStyle? style, String? title});

  /// Replaces the custom ports of node [id].
  void setNodeCustomPorts(NodeId id, List<PortSpec> ports);

  /// Replaces the free data payload of node [id].
  void setNodeData(NodeId id, Map<String, Object?> data);
}

/// An undoable edit.
abstract class GraphCommand {
  /// Const constructor for subclasses.
  const GraphCommand();

  /// Human readable label (shown in undo tooltips).
  String get label;

  /// Performs the edit.
  void apply(GraphMutator m);

  /// Reverts the edit.
  void revert(GraphMutator m);

  /// Returns a single command equivalent to `this` followed by [next], or
  /// null when they cannot be merged.
  GraphCommand? mergeWith(GraphCommand next) => null;
}

/// Several commands applied as one undo step.
class CompositeCommand extends GraphCommand {
  /// Creates a composite.
  CompositeCommand(this.label, this.commands);

  @override
  final String label;

  /// The children, applied in order and reverted in reverse order.
  final List<GraphCommand> commands;

  @override
  void apply(GraphMutator m) {
    for (final c in commands) {
      c.apply(m);
    }
  }

  @override
  void revert(GraphMutator m) {
    for (final c in commands.reversed) {
      c.revert(m);
    }
  }
}

/// Adds nodes and edges.
class AddElementsCommand extends GraphCommand {
  /// Creates the command.
  AddElementsCommand({
    this.nodes = const [],
    this.edges = const [],
    this.label = 'Add',
  });

  /// Nodes to add.
  final List<NodeInstance> nodes;

  /// Edges to add (after the nodes).
  final List<Edge> edges;

  @override
  final String label;

  @override
  void apply(GraphMutator m) {
    for (final n in nodes) {
      m.insertNode(n);
    }
    for (final e in edges) {
      m.insertEdge(e);
    }
  }

  @override
  void revert(GraphMutator m) {
    for (final e in edges.reversed) {
      m.deleteEdge(e.id);
    }
    for (final n in nodes.reversed) {
      m.deleteNode(n.id);
    }
  }
}

/// Removes nodes (with all their edges) and edges.
class RemoveElementsCommand extends GraphCommand {
  /// Captures what to remove from [graph]: [nodeIds], every edge touching
  /// them, and [edgeIds].
  factory RemoveElementsCommand.capture(
    Graph graph, {
    Iterable<NodeId> nodeIds = const [],
    Iterable<EdgeId> edgeIds = const [],
    String label = 'Delete',
  }) {
    final nodeSet = nodeIds.where(graph.containsNode).toSet();
    final edges = <EdgeId, Edge>{};
    for (final id in edgeIds) {
      final e = graph.edge(id);
      if (e != null) edges[id] = e;
    }
    for (final n in nodeSet) {
      for (final e in graph.edgesOfNode(n)) {
        edges[e.id] = e;
      }
    }
    final nodes = <(int, NodeInstance)>[];
    var i = 0;
    for (final n in graph.nodes) {
      if (nodeSet.contains(n.id)) nodes.add((i, n));
      i++;
    }
    return RemoveElementsCommand._(nodes, edges.values.toList(), label);
  }

  RemoveElementsCommand._(this._nodes, this.edges, this.label);

  final List<(int, NodeInstance)> _nodes;

  /// Removed edges.
  final List<Edge> edges;

  @override
  final String label;

  /// Removed nodes.
  List<NodeInstance> get nodes => [for (final n in _nodes) n.$2];

  /// Whether nothing would be removed.
  bool get isEmpty => _nodes.isEmpty && edges.isEmpty;

  @override
  void apply(GraphMutator m) {
    for (final e in edges) {
      m.deleteEdge(e.id);
    }
    for (final n in _nodes.reversed) {
      m.deleteNode(n.$2.id);
    }
  }

  @override
  void revert(GraphMutator m) {
    for (final n in _nodes) {
      m.insertNode(n.$2, index: n.$1);
    }
    for (final e in edges) {
      m.insertEdge(e);
    }
  }
}

/// Moves nodes. Consecutive moves of the same node set merge into one step.
class MoveNodesCommand extends GraphCommand {
  /// Creates the command from start and end positions.
  MoveNodesCommand(this.from, this.to);

  /// Positions before.
  final Map<NodeId, Offset> from;

  /// Positions after.
  final Map<NodeId, Offset> to;

  @override
  String get label => from.length == 1 ? 'Move node' : 'Move nodes';

  @override
  void apply(GraphMutator m) =>
      to.forEach((id, p) => m.setNodeGeometry(id, position: p));

  @override
  void revert(GraphMutator m) =>
      from.forEach((id, p) => m.setNodeGeometry(id, position: p));

  @override
  GraphCommand? mergeWith(GraphCommand next) {
    if (next is! MoveNodesCommand ||
        !setEquals(next.from.keys.toSet(), to.keys.toSet())) {
      return null;
    }
    return MoveNodesCommand(from, next.to);
  }
}

/// Moves and / or resizes one node.
class SetNodeRectCommand extends GraphCommand {
  /// Creates the command.
  SetNodeRectCommand(this.id, this.from, this.to);

  /// Node.
  final NodeId id;

  /// Rect before.
  final Rect from;

  /// Rect after.
  final Rect to;

  @override
  String get label => 'Resize node';

  @override
  void apply(GraphMutator m) =>
      m.setNodeGeometry(id, position: to.topLeft, size: to.size);

  @override
  void revert(GraphMutator m) =>
      m.setNodeGeometry(id, position: from.topLeft, size: from.size);

  @override
  GraphCommand? mergeWith(GraphCommand next) =>
      next is SetNodeRectCommand && next.id == id
      ? SetNodeRectCommand(id, from, next.to)
      : null;
}

/// Changes parameter values of one node.
class SetParamsCommand extends GraphCommand {
  /// Creates the command; [before] holds the previous values of the keys in
  /// [after].
  SetParamsCommand(this.id, this.before, this.after);

  /// Node.
  final NodeId id;

  /// Previous values.
  final Map<String, Object?> before;

  /// New values.
  final Map<String, Object?> after;

  @override
  String get label => 'Edit parameters';

  @override
  void apply(GraphMutator m) => m.setNodeParams(id, after);

  @override
  void revert(GraphMutator m) => m.setNodeParams(id, before);

  @override
  GraphCommand? mergeWith(GraphCommand next) {
    if (next is! SetParamsCommand ||
        next.id != id ||
        !setEquals(next.after.keys.toSet(), after.keys.toSet())) {
      return null;
    }
    return SetParamsCommand(id, before, next.after);
  }
}

/// Locks / unlocks nodes.
class SetLockedCommand extends GraphCommand {
  /// Creates the command.
  SetLockedCommand(this.before, this.locked);

  /// Previous lock state per node.
  final Map<NodeId, bool> before;

  /// New lock state.
  final bool locked;

  @override
  String get label => locked ? 'Lock' : 'Unlock';

  @override
  void apply(GraphMutator m) {
    for (final id in before.keys) {
      m.setNodeLocked(id, locked);
    }
  }

  @override
  void revert(GraphMutator m) => before.forEach(m.setNodeLocked);
}

/// Changes the style / title of one node.
class SetNodeAppearanceCommand extends GraphCommand {
  /// Creates the command.
  SetNodeAppearanceCommand(
    this.id, {
    required this.beforeStyle,
    required this.afterStyle,
    required this.beforeTitle,
    required this.afterTitle,
  });

  /// Node.
  final NodeId id;

  /// Style before.
  final NodeStyle? beforeStyle;

  /// Style after.
  final NodeStyle? afterStyle;

  /// Title before.
  final String? beforeTitle;

  /// Title after.
  final String? afterTitle;

  @override
  String get label => 'Edit node';

  @override
  void apply(GraphMutator m) =>
      m.setNodeAppearance(id, style: afterStyle, title: afterTitle);

  @override
  void revert(GraphMutator m) =>
      m.setNodeAppearance(id, style: beforeStyle, title: beforeTitle);
}

/// Replaces the custom ports of a node.
class SetCustomPortsCommand extends GraphCommand {
  /// Creates the command.
  SetCustomPortsCommand(this.id, this.before, this.after);

  /// Node.
  final NodeId id;

  /// Ports before.
  final List<PortSpec> before;

  /// Ports after.
  final List<PortSpec> after;

  @override
  String get label => 'Edit ports';

  @override
  void apply(GraphMutator m) => m.setNodeCustomPorts(id, after);

  @override
  void revert(GraphMutator m) => m.setNodeCustomPorts(id, before);
}

/// Replaces the data payload of a node.
class SetNodeDataCommand extends GraphCommand {
  /// Creates the command.
  SetNodeDataCommand(this.id, this.before, this.after);

  /// Node.
  final NodeId id;

  /// Data before.
  final Map<String, Object?> before;

  /// Data after.
  final Map<String, Object?> after;

  @override
  String get label => 'Edit data';

  @override
  void apply(GraphMutator m) => m.setNodeData(id, after);

  @override
  void revert(GraphMutator m) => m.setNodeData(id, before);
}

/// Replaces an edge (style, label, waypoints) keeping its id.
class UpdateEdgeCommand extends GraphCommand {
  /// Creates the command.
  UpdateEdgeCommand(this.before, this.after) : assert(before.id == after.id);

  /// Edge before.
  final Edge before;

  /// Edge after.
  final Edge after;

  @override
  String get label => 'Edit link';

  @override
  void apply(GraphMutator m) => m.replaceEdge(after);

  @override
  void revert(GraphMutator m) => m.replaceEdge(before);

  @override
  GraphCommand? mergeWith(GraphCommand next) =>
      next is UpdateEdgeCommand && next.after.id == after.id
      ? UpdateEdgeCommand(before, next.after)
      : null;
}

/// Undo / redo stack.
///
/// Commands pushed within [mergeWindow] of each other are merged when they
/// support it (e.g. typing in a parameter field, arrow-key nudges), so one
/// user gesture is one undo step.
class HistoryStack extends ChangeNotifier {
  /// Creates a history stack.
  HistoryStack({
    this.maxDepth = 200,
    this.mergeWindow = const Duration(milliseconds: 800),
  });

  /// Maximum number of undo steps kept.
  final int maxDepth;

  /// Maximum delay between two mergeable commands.
  final Duration mergeWindow;

  final List<GraphCommand> _undo = [];
  final List<GraphCommand> _redo = [];
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  bool _sealed = true;

  /// Whether [undo] is possible.
  bool get canUndo => _undo.isNotEmpty;

  /// Whether [redo] is possible.
  bool get canRedo => _redo.isNotEmpty;

  /// Label of the next undo step.
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;

  /// Label of the next redo step.
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;

  /// Number of undo steps.
  int get undoDepth => _undo.length;

  /// Records an already applied command.
  void push(GraphCommand command) {
    final now = DateTime.now();
    if (!_sealed &&
        _undo.isNotEmpty &&
        now.difference(_lastPush) <= mergeWindow) {
      final merged = _undo.last.mergeWith(command);
      if (merged != null) {
        _undo[_undo.length - 1] = merged;
        _lastPush = now;
        _redo.clear();
        notifyListeners();
        return;
      }
    }
    _undo.add(command);
    if (_undo.length > maxDepth) _undo.removeAt(0);
    _redo.clear();
    _lastPush = now;
    _sealed = false;
    notifyListeners();
  }

  /// Prevents the next push from merging into the last step.
  void seal() => _sealed = true;

  /// Pops the command to undo (caller reverts it).
  GraphCommand? takeUndo() {
    if (_undo.isEmpty) return null;
    final c = _undo.removeLast();
    _redo.add(c);
    _sealed = true;
    notifyListeners();
    return c;
  }

  /// Pops the command to redo (caller re-applies it).
  GraphCommand? takeRedo() {
    if (_redo.isEmpty) return null;
    final c = _redo.removeLast();
    _undo.add(c);
    _sealed = true;
    notifyListeners();
    return c;
  }

  /// Clears both stacks.
  void clear() {
    _undo.clear();
    _redo.clear();
    _sealed = true;
    notifyListeners();
  }
}
