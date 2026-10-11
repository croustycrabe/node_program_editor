import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../params/param_types.dart';
import '../widgets/node_render_context.dart';
import 'ids.dart';
import 'json.dart';
import 'ports.dart';

/// Builds the complete visual of a node. See [NodeRenderContext].
typedef NodeWidgetBuilder = Widget Function(
  BuildContext context,
  NodeRenderContext node,
);

/// The two flavours of the built-in node widget.
enum NodeVariant {
  /// Header + description text. Parameters are only editable in the edit
  /// dialog.
  static,

  /// Header + inline editors for parameters marked `showInNode`.
  dynamic,
}

/// Controls where the built-in layout places ports that have no explicit
/// [PortSpec.alignment].
@immutable
class PortLayout {
  /// Creates a port layout.
  const PortLayout({
    this.headerHeight = 36,
    this.rowHeight = 24,
    this.padding = 8,
    this.paramRowHeight = 40,
  });

  /// Height reserved for the header; side ports start below it.
  final double headerHeight;

  /// Vertical distance between stacked side ports.
  final double rowHeight;

  /// Inner padding of the node body.
  final double padding;

  /// Height of one inline parameter editor in [NodeVariant.dynamic] nodes.
  final double paramRowHeight;
}

/// Visual overrides for one node instance (persisted in the design file).
@immutable
class NodeStyle {
  /// Creates a node style.
  const NodeStyle({
    this.color,
    this.headerColor,
    this.borderColor,
    this.textColor,
    this.borderWidth,
    this.borderRadius,
  });

  /// Body color.
  final Color? color;

  /// Header color; also used as the node color at low zoom levels.
  final Color? headerColor;

  /// Border color.
  final Color? borderColor;

  /// Text color.
  final Color? textColor;

  /// Border width.
  final double? borderWidth;

  /// Corner radius.
  final double? borderRadius;

  /// Returns a copy where non-null fields of [other] win.
  NodeStyle merge(NodeStyle? other) => other == null
      ? this
      : NodeStyle(
          color: other.color ?? color,
          headerColor: other.headerColor ?? headerColor,
          borderColor: other.borderColor ?? borderColor,
          textColor: other.textColor ?? textColor,
          borderWidth: other.borderWidth ?? borderWidth,
          borderRadius: other.borderRadius ?? borderRadius,
        );

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'color': colorToJson(color),
    'headerColor': colorToJson(headerColor),
    'borderColor': colorToJson(borderColor),
    'textColor': colorToJson(textColor),
    'borderWidth': borderWidth,
    'borderRadius': borderRadius,
  });

  /// Parses JSON produced by [toJson].
  factory NodeStyle.fromJson(Map<String, Object?> json) => NodeStyle(
    color: colorFromJson(json['color']),
    headerColor: colorFromJson(json['headerColor']),
    borderColor: colorFromJson(json['borderColor']),
    textColor: colorFromJson(json['textColor']),
    borderWidth: readDouble(json['borderWidth']),
    borderRadius: readDouble(json['borderRadius']),
  );

  @override
  bool operator ==(Object other) =>
      other is NodeStyle &&
      other.color == color &&
      other.headerColor == headerColor &&
      other.borderColor == borderColor &&
      other.textColor == textColor &&
      other.borderWidth == borderWidth &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(
    color,
    headerColor,
    borderColor,
    textColor,
    borderWidth,
    borderRadius,
  );
}

/// Declares a kind of node: its ports, parameters, sizing rules and look.
///
/// Definitions are registered once in a [NodeRegistry]; the graph only stores
/// lightweight [NodeInstance]s that reference a definition by [type].
class NodeDefinition {
  /// Creates a node definition.
  const NodeDefinition({
    required this.type,
    required this.title,
    this.category = 'General',
    this.description,
    this.icon,
    this.tags = const [],
    this.ports = const [],
    this.params = const [],
    this.variant = NodeVariant.static,
    this.defaultSize,
    this.minSize = const Size(120, 60),
    this.maxSize = const Size(2000, 2000),
    this.resizable = true,
    this.deletable = true,
    this.copyable = true,
    this.showMenu,
    this.style,
    this.portLayout = const PortLayout(),
    this.builder,
    this.portBuilder,
  });

  /// Unique type id, stored in the logic file.
  final String type;

  /// Default title.
  final String title;

  /// Palette category.
  final String category;

  /// Description, shown in the palette and by static nodes.
  final String? description;

  /// Header icon.
  final IconData? icon;

  /// Extra search keywords for the palette.
  final List<String> tags;

  /// Ports.
  final List<PortSpec> ports;

  /// Parameters.
  final List<ParamSpec> params;

  /// Built-in widget flavour.
  final NodeVariant variant;

  /// Initial size. When null it is computed from ports and parameters.
  final Size? defaultSize;

  /// Minimum size when resizing.
  final Size minSize;

  /// Maximum size when resizing.
  final Size maxSize;

  /// Whether the user can resize instances.
  final bool resizable;

  /// Whether the user can delete instances.
  final bool deletable;

  /// Whether the user can copy instances.
  final bool copyable;

  /// Whether the overlay menu is shown when an instance is selected. Null
  /// defers to `NodeEditorConfig.showNodeMenu`.
  final bool? showMenu;

  /// Default visual style.
  final NodeStyle? style;

  /// Port placement rules for the built-in layout.
  final PortLayout portLayout;

  /// Custom widget builder replacing the built-in node body. Ports,
  /// selection outline and resize handles are still drawn around it.
  final NodeWidgetBuilder? builder;

  /// Custom port visual for this node type (see [PortRenderContext]).
  final PortWidgetBuilder? portBuilder;

  /// Input ports.
  Iterable<PortSpec> get inputs => ports.where((p) => p.isInput);

  /// Output ports.
  Iterable<PortSpec> get outputs => ports.where((p) => p.isOutput);

  /// Finds a parameter spec by name.
  ParamSpec? param(String name) {
    for (final p in params) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// Initial parameter values.
  Map<String, Object?> initialParams() => {
    for (final p in params) p.name: p.initialValue,
  };

  /// Size needed to fit the ports (and inline parameters for dynamic nodes)
  /// with the built-in layout.
  Size contentSize([List<PortSpec> extraPorts = const []]) {
    final all = [...ports, ...extraPorts];
    var left = 0, right = 0, top = 0, bottom = 0;
    for (final p in all) {
      switch (p.effectiveSide) {
        case PortSide.left:
          left++;
        case PortSide.right:
          right++;
        case PortSide.top:
          top++;
        case PortSide.bottom:
          bottom++;
      }
    }
    final l = portLayout;
    final rows = math.max(left, right);
    final inline = variant == NodeVariant.dynamic
        ? params.where((p) => p.showInNode).length
        : 0;
    final height =
        l.headerHeight +
        l.padding * 2 +
        rows * l.rowHeight +
        inline * l.paramRowHeight +
        (variant == NodeVariant.static && description != null ? 20 : 0);
    final width = math.max(
      160.0,
      math.max(top, bottom) * l.rowHeight + l.padding * 2,
    );
    return Size(width, height);
  }

  /// Effective minimum size: [minSize] grown to fit the ports.
  Size resolvedMinSize([List<PortSpec> extraPorts = const []]) {
    final c = contentSize(extraPorts);
    return Size(
      math.min(minSize.width, maxSize.width),
      math.min(math.max(minSize.height, c.height), maxSize.height),
    );
  }

  /// Effective initial size.
  Size resolvedDefaultSize([List<PortSpec> extraPorts = const []]) {
    if (defaultSize != null) return clampSize(defaultSize!, extraPorts);
    final c = contentSize(extraPorts);
    return clampSize(Size(math.max(c.width, 180), c.height), extraPorts);
  }

  /// Clamps [size] between the resolved minimum and [maxSize].
  Size clampSize(Size size, [List<PortSpec> extraPorts = const []]) {
    final min = resolvedMinSize(extraPorts);
    return Size(
      size.width.clamp(min.width, math.max(min.width, maxSize.width)),
      size.height.clamp(min.height, math.max(min.height, maxSize.height)),
    );
  }
}

/// A placeholder definition used when a file references a node type that is
/// not registered. It preserves ports and parameters so nothing is lost on
/// re-save.
class UnknownNodeDefinition extends NodeDefinition {
  /// Creates a placeholder for [type].
  const UnknownNodeDefinition(String type, {super.ports})
    : super(
        type: type,
        title: 'Unknown: $type',
        category: 'Unknown',
        description: 'This node type is not registered.',
      );
}

/// Holds the node definitions and port types available to an editor.
class NodeRegistry extends ChangeNotifier {
  /// Creates a registry, optionally pre-filled with [definitions].
  NodeRegistry({
    Iterable<NodeDefinition> definitions = const [],
    Iterable<PortType> portTypes = const [],
  }) {
    for (final t in PortType.builtIns) {
      _portTypes[t.name] = t;
    }
    for (final t in portTypes) {
      _portTypes[t.name] = t;
    }
    for (final d in definitions) {
      _definitions[d.type] = d;
    }
  }

  final Map<String, NodeDefinition> _definitions = {};
  final Map<String, PortType> _portTypes = {};

  /// All registered definitions, in registration order.
  Iterable<NodeDefinition> get definitions => _definitions.values;

  /// All registered port types.
  Iterable<PortType> get portTypes => _portTypes.values;

  /// Distinct categories, in registration order.
  List<String> get categories =>
      {for (final d in _definitions.values) d.category}.toList();

  /// Registers (or replaces) a definition.
  void register(NodeDefinition definition) {
    _definitions[definition.type] = definition;
    notifyListeners();
  }

  /// Registers several definitions at once.
  void registerAll(Iterable<NodeDefinition> definitions) {
    for (final d in definitions) {
      _definitions[d.type] = d;
    }
    notifyListeners();
  }

  /// Removes the definition of [type].
  void unregister(String type) {
    if (_definitions.remove(type) != null) notifyListeners();
  }

  /// Registers a custom port type.
  void registerPortType(PortType type) => _portTypes[type.name] = type;

  /// The definition of [type], or null.
  NodeDefinition? operator [](String type) => _definitions[type];

  /// Whether [type] is registered.
  bool contains(String type) => _definitions.containsKey(type);

  /// The definition of [type], or an [UnknownNodeDefinition].
  NodeDefinition resolve(String type, {List<PortSpec> ports = const []}) =>
      _definitions[type] ?? UnknownNodeDefinition(type, ports: ports);

  /// The port type called [name] (unknown names become an untyped type of
  /// that name, compatible with nothing but itself and `any`).
  PortType portType(String name) => _portTypes[name] ?? PortType(name);
}

/// A node placed in a graph.
///
/// Instances are mutated only through the `NodeEditorController` so that
/// every change is undoable and listeners are notified.
class NodeInstance {
  /// Creates a node instance.
  NodeInstance({
    required this.id,
    required this.definition,
    required this.position,
    required this.size,
    this.locked = false,
    this.title,
    this.style,
    Map<String, Object?>? params,
    Map<String, Object?>? data,
    List<PortSpec>? customPorts,
  }) : params = params ?? definition.initialParams(),
       data = data ?? {},
       customPorts = customPorts ?? const [];

  /// Creates an instance of [definition] at [position] with default size and
  /// parameters.
  factory NodeInstance.create(
    NodeDefinition definition, {
    required Offset position,
    NodeId? id,
    Map<String, Object?>? params,
    Size? size,
    String? title,
    List<PortSpec>? customPorts,
  }) => NodeInstance(
    id: id ?? IdGenerator.node(),
    definition: definition,
    position: position,
    size: size ?? definition.resolvedDefaultSize(customPorts ?? const []),
    params: {...definition.initialParams(), ...?params},
    title: title,
    customPorts: customPorts,
  );

  /// Unique id.
  final NodeId id;

  /// The definition this node is an instance of.
  NodeDefinition definition;

  /// Top-left corner in canvas coordinates.
  Offset position;

  /// Size in canvas units.
  Size size;

  /// Locked nodes cannot be moved, resized or deleted by the user.
  bool locked;

  /// Title override (falls back to [NodeDefinition.title]).
  String? title;

  /// Visual overrides.
  NodeStyle? style;

  /// Parameter values keyed by [ParamSpec.name].
  final Map<String, Object?> params;

  /// Free, JSON-serializable payload for the host application (runtime
  /// status, results...). Persisted in the logic file.
  final Map<String, Object?> data;

  /// Transient state written by execution engines (status, previews,
  /// results). Never saved nor undoable. See
  /// `NodeEditorController.setRuntimeData`.
  final Map<String, Object?> runtime = {};

  /// Ports added to this instance on top of the definition ports (e.g. a
  /// switch node with a configurable number of outputs).
  List<PortSpec> customPorts;

  List<PortSpec>? _portsCache;

  /// Definition type id.
  String get type => definition.type;

  /// Effective title.
  String get displayTitle => title ?? definition.title;

  /// Bounds in canvas coordinates.
  Rect get rect => position & size;

  /// All ports: definition ports followed by [customPorts].
  List<PortSpec> get ports => customPorts.isEmpty
      ? definition.ports
      : (_portsCache ??= [...definition.ports, ...customPorts]);

  /// Invalidates cached derived data after [definition] or [customPorts]
  /// changed.
  void invalidatePorts() => _portsCache = null;

  /// Finds a port by id.
  PortSpec? port(String portId) {
    for (final p in ports) {
      if (p.id == portId) return p;
    }
    return null;
  }

  /// Deep copy with an optional new [id].
  NodeInstance copy({NodeId? id, Offset? position}) => NodeInstance(
    id: id ?? this.id,
    definition: definition,
    position: position ?? this.position,
    size: size,
    locked: locked,
    title: title,
    style: style,
    params: Map.of(params),
    data: Map.of(data),
    customPorts: List.of(customPorts),
  );

  @override
  String toString() => 'NodeInstance(${id.value}, $type)';
}
