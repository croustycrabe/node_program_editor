import 'dart:ui';

import '../core/controller.dart';
import '../core/node.dart';
import '../core/ports.dart';

/// Everything a custom node builder needs to render a node body.
///
/// The body is laid out with the node size; ports, selection outline and
/// resize handles are drawn around it by the editor, at the anchors computed
/// by `PortGeometry`, so custom bodies never break link positions.
class NodeRenderContext {
  /// Creates a render context.
  const NodeRenderContext({
    required this.controller,
    required this.node,
    required this.selected,
    required this.zoom,
  });

  /// The editor controller.
  final NodeEditorController controller;

  /// The node instance.
  final NodeInstance node;

  /// Whether the node is selected.
  final bool selected;

  /// Current zoom (useful to hide details when zoomed out).
  final double zoom;

  /// The node definition.
  NodeDefinition get definition => node.definition;

  /// The node size, canvas units.
  Size get size => node.size;

  /// Current value of parameter [name].
  Object? param(String name) => node.params[name];

  /// Sets parameter [name] (undoable).
  void setParam(String name, Object? value) =>
      controller.setParam(node.id, name, value);

  /// Ports of the node.
  List<PortSpec> get ports => node.ports;

  /// Whether the node is locked.
  bool get locked => node.locked;
}
