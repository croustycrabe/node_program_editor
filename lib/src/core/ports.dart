import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'ids.dart';
import 'json.dart';

/// Whether a port receives (`input`) or emits (`output`) links.
enum PortDirection {
  /// The port is the target of links.
  input,

  /// The port is the source of links.
  output;

  /// The opposite direction.
  PortDirection get opposite =>
      this == input ? PortDirection.output : PortDirection.input;
}

/// The side of a node a port is attached to.
enum PortSide {
  /// Left edge.
  left,

  /// Right edge.
  right,

  /// Top edge.
  top,

  /// Bottom edge.
  bottom;

  /// Unit vector pointing out of the node from this side.
  Offset get normal => switch (this) {
    PortSide.left => const Offset(-1, 0),
    PortSide.right => const Offset(1, 0),
    PortSide.top => const Offset(0, -1),
    PortSide.bottom => const Offset(0, 1),
  };

  /// Whether the side is left or right.
  bool get isHorizontal => this == PortSide.left || this == PortSide.right;
}

/// Visual shape of a port handle.
enum PortShape {
  /// Filled circle.
  circle,

  /// Square.
  square,

  /// Diamond (rotated square).
  diamond,

  /// Triangle pointing out of the node.
  triangle,

  /// Thin capsule along the node edge.
  bar,
}

/// The data type carried by a port.
///
/// Two ports may be linked when the target type [accepts] the source type.
/// Types are identified by [name] in saved files.
@immutable
class PortType {
  /// Creates a port type.
  const PortType(
    this.name, {
    this.color = const Color(0xFF8A94A6),
    this.compatibleWith = const {},
    this.isAny = false,
  });

  /// Unique name, also used in serialized files.
  final String name;

  /// Default color of ports and edges of this type.
  final Color color;

  /// Names of other types this type accepts as a source.
  final Set<String> compatibleWith;

  /// Whether this type accepts / is accepted by every other type.
  final bool isAny;

  /// Whether a link from a [source] typed port into a port of this type is
  /// valid.
  bool accepts(PortType source) =>
      isAny ||
      source.isAny ||
      source.name == name ||
      compatibleWith.contains(source.name);

  /// Wildcard type accepting anything.
  static const any = PortType('any', isAny: true, color: Color(0xFF9AA4B2));

  /// Control-flow / execution type (n8n, Unreal Blueprint style).
  static const exec = PortType('exec', color: Color(0xFFE6E9EF));

  /// Floating point number.
  static const number = PortType(
    'number',
    color: Color(0xFF4CAF50),
    compatibleWith: {'int', 'bool'},
  );

  /// Integer number.
  static const integer = PortType(
    'int',
    color: Color(0xFF26A69A),
    compatibleWith: {'bool'},
  );

  /// Boolean.
  static const boolean = PortType('bool', color: Color(0xFFE53935));

  /// Text.
  static const string = PortType('string', color: Color(0xFFEC407A));

  /// Image / frame buffer.
  static const image = PortType('image', color: Color(0xFF7E57C2));

  /// Time series signal.
  static const signal = PortType(
    'signal',
    color: Color(0xFF29B6F6),
    compatibleWith: {'number'},
  );

  /// JSON like structured data.
  static const json = PortType('json', color: Color(0xFFFFA726));

  /// List / array.
  static const array = PortType('array', color: Color(0xFF8D6E63));

  /// The built-in types, registered by default in every registry.
  static const builtIns = <PortType>[
    any,
    exec,
    number,
    integer,
    boolean,
    string,
    image,
    signal,
    json,
    array,
  ];

  @override
  bool operator ==(Object other) => other is PortType && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'PortType($name)';
}

/// Visual style of a port handle. Null fields fall back to the theme or the
/// port type color.
@immutable
class PortStyle {
  /// Creates a port style.
  const PortStyle({
    this.shape,
    this.size,
    this.color,
    this.borderColor,
    this.borderWidth,
    this.showLabel,
  });

  /// Handle shape.
  final PortShape? shape;

  /// Handle diameter in canvas units.
  final double? size;

  /// Fill color.
  final Color? color;

  /// Border color.
  final Color? borderColor;

  /// Border width in canvas units.
  final double? borderWidth;

  /// Whether the default node widget draws the port label.
  final bool? showLabel;

  /// Returns a copy with the given fields replaced.
  PortStyle copyWith({
    PortShape? shape,
    double? size,
    Color? color,
    Color? borderColor,
    double? borderWidth,
    bool? showLabel,
  }) => PortStyle(
    shape: shape ?? this.shape,
    size: size ?? this.size,
    color: color ?? this.color,
    borderColor: borderColor ?? this.borderColor,
    borderWidth: borderWidth ?? this.borderWidth,
    showLabel: showLabel ?? this.showLabel,
  );

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'shape': shape?.name,
    'size': size,
    'color': colorToJson(color),
    'borderColor': colorToJson(borderColor),
    'borderWidth': borderWidth,
    'showLabel': showLabel,
  });

  /// Parses JSON produced by [toJson].
  factory PortStyle.fromJson(Map<String, Object?> json) => PortStyle(
    shape: enumByName(PortShape.values, json['shape']),
    size: readDouble(json['size']),
    color: colorFromJson(json['color']),
    borderColor: colorFromJson(json['borderColor']),
    borderWidth: readDouble(json['borderWidth']),
    showLabel: json['showLabel'] as bool?,
  );
}

/// Declaration of a port on a node.
@immutable
class PortSpec {
  /// Creates a port specification.
  const PortSpec({
    required this.id,
    required this.direction,
    this.label = '',
    this.type = PortType.any,
    this.maxLinks = -1,
    this.side,
    this.alignment,
    this.style,
    this.tooltip,
  });

  /// Shorthand for an input port.
  const PortSpec.input(
    this.id, {
    this.label = '',
    this.type = PortType.any,
    this.maxLinks = 1,
    this.side,
    this.alignment,
    this.style,
    this.tooltip,
  }) : direction = PortDirection.input;

  /// Shorthand for an output port.
  const PortSpec.output(
    this.id, {
    this.label = '',
    this.type = PortType.any,
    this.maxLinks = -1,
    this.side,
    this.alignment,
    this.style,
    this.tooltip,
  }) : direction = PortDirection.output;

  /// Id, unique among the ports of a node.
  final String id;

  /// Input or output.
  final PortDirection direction;

  /// Human readable label.
  final String label;

  /// Data type used for connection validation and default colors.
  final PortType type;

  /// Maximum number of links on this port, `-1` for unlimited.
  final int maxLinks;

  /// Side of the node. Defaults to left for inputs and right for outputs.
  final PortSide? side;

  /// Position along the side in `[0, 1]`. Null lets the node layout place
  /// the port automatically.
  final double? alignment;

  /// Visual style overrides.
  final PortStyle? style;

  /// Optional tooltip.
  final String? tooltip;

  /// The effective side.
  PortSide get effectiveSide =>
      side ??
      (direction == PortDirection.input ? PortSide.left : PortSide.right);

  /// Whether this is an input port.
  bool get isInput => direction == PortDirection.input;

  /// Whether this is an output port.
  bool get isOutput => direction == PortDirection.output;

  /// Returns a copy with the given fields replaced.
  PortSpec copyWith({
    String? id,
    PortDirection? direction,
    String? label,
    PortType? type,
    int? maxLinks,
    PortSide? side,
    double? alignment,
    PortStyle? style,
    String? tooltip,
  }) => PortSpec(
    id: id ?? this.id,
    direction: direction ?? this.direction,
    label: label ?? this.label,
    type: type ?? this.type,
    maxLinks: maxLinks ?? this.maxLinks,
    side: side ?? this.side,
    alignment: alignment ?? this.alignment,
    style: style ?? this.style,
    tooltip: tooltip ?? this.tooltip,
  );

  /// Serializes to JSON. Port types are written by name.
  Map<String, Object?> toJson() => compactJson({
    'id': id,
    'direction': direction.name,
    'label': label,
    'type': type.name,
    'maxLinks': maxLinks,
    'side': side?.name,
    'alignment': alignment,
    'style': style?.toJson(),
    'tooltip': tooltip,
  });

  /// Parses JSON produced by [toJson]; [resolveType] maps type names back to
  /// [PortType]s.
  factory PortSpec.fromJson(
    Map<String, Object?> json,
    PortType Function(String name) resolveType,
  ) => PortSpec(
    id: json['id']! as String,
    direction:
        enumByName(PortDirection.values, json['direction']) ??
        PortDirection.input,
    label: json['label'] as String? ?? '',
    type: resolveType(json['type'] as String? ?? 'any'),
    maxLinks: readInt(json['maxLinks']) ?? -1,
    side: enumByName(PortSide.values, json['side']),
    alignment: readDouble(json['alignment']),
    style: json['style'] == null
        ? null
        : PortStyle.fromJson(asJsonMap(json['style'])),
    tooltip: json['tooltip'] as String?,
  );

  @override
  String toString() => 'PortSpec($id, ${direction.name}, ${type.name})';
}

/// A reference to one port of one node.
@immutable
class PortRef {
  /// Creates a port reference.
  const PortRef(this.node, this.port);

  /// The node.
  final NodeId node;

  /// The port id on [node].
  final String port;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {'node': node.value, 'port': port};

  /// Parses JSON produced by [toJson].
  factory PortRef.fromJson(Map<String, Object?> json) =>
      PortRef(NodeId(json['node']! as String), json['port']! as String);

  @override
  bool operator ==(Object other) =>
      other is PortRef && other.node == node && other.port == port;

  @override
  int get hashCode => Object.hash(node, port);

  @override
  String toString() => '${node.value}:$port';
}
