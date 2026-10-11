import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'ids.dart';
import 'json.dart';
import 'ports.dart';

/// How an edge is routed between its two ports (draw.io style).
enum EdgePathType {
  /// Straight segment.
  straight,

  /// Cubic bezier leaving / entering ports along their side normals.
  bezier,

  /// Orthogonal segments with rounded corners.
  smoothStep,

  /// Orthogonal segments with sharp corners.
  step,

  /// Orthogonal path through user-defined waypoints.
  orthogonal,

  /// Polyline through user-defined waypoints.
  polyline,

  /// A user supplied `EdgePathBuilder` looked up by
  /// [EdgeStyle.customPath].
  custom,
}

/// Decoration at an edge end.
enum EdgeMarker {
  /// Nothing.
  none,

  /// Open arrow head.
  arrow,

  /// Filled arrow head.
  arrowClosed,

  /// Filled circle.
  circle,

  /// Filled diamond.
  diamond,
}

/// Visual style of an edge. Null fields fall back to the theme or to the
/// source port type color.
@immutable
class EdgeStyle {
  /// Creates an edge style.
  const EdgeStyle({
    this.pathType = EdgePathType.bezier,
    this.color,
    this.width,
    this.dashPattern,
    this.startMarker = EdgeMarker.none,
    this.endMarker = EdgeMarker.none,
    this.animated = false,
    this.curvature = 0.5,
    this.cornerRadius = 8,
    this.customPath,
    this.labelColor,
    this.labelBackground,
    this.labelFontSize,
  });

  /// Routing algorithm.
  final EdgePathType pathType;

  /// Stroke color.
  final Color? color;

  /// Stroke width in canvas units.
  final double? width;

  /// Alternating dash / gap lengths, null for a solid line.
  final List<double>? dashPattern;

  /// Marker at the source end.
  final EdgeMarker startMarker;

  /// Marker at the target end.
  final EdgeMarker endMarker;

  /// Whether a flow animation runs along the edge.
  final bool animated;

  /// Bezier curvature factor.
  final double curvature;

  /// Corner radius for [EdgePathType.smoothStep] / orthogonal paths.
  final double cornerRadius;

  /// Name of a registered custom path builder.
  final String? customPath;

  /// Label text color.
  final Color? labelColor;

  /// Label background color.
  final Color? labelBackground;

  /// Label font size.
  final double? labelFontSize;

  /// Returns a copy with the given fields replaced.
  EdgeStyle copyWith({
    EdgePathType? pathType,
    Color? color,
    double? width,
    List<double>? dashPattern,
    bool clearDash = false,
    EdgeMarker? startMarker,
    EdgeMarker? endMarker,
    bool? animated,
    double? curvature,
    double? cornerRadius,
    String? customPath,
    Color? labelColor,
    Color? labelBackground,
    double? labelFontSize,
  }) => EdgeStyle(
    pathType: pathType ?? this.pathType,
    color: color ?? this.color,
    width: width ?? this.width,
    dashPattern: clearDash ? null : (dashPattern ?? this.dashPattern),
    startMarker: startMarker ?? this.startMarker,
    endMarker: endMarker ?? this.endMarker,
    animated: animated ?? this.animated,
    curvature: curvature ?? this.curvature,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    customPath: customPath ?? this.customPath,
    labelColor: labelColor ?? this.labelColor,
    labelBackground: labelBackground ?? this.labelBackground,
    labelFontSize: labelFontSize ?? this.labelFontSize,
  );

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'pathType': pathType.name,
    'color': colorToJson(color),
    'width': width,
    'dashPattern': dashPattern,
    'startMarker': startMarker == EdgeMarker.none ? null : startMarker.name,
    'endMarker': endMarker == EdgeMarker.none ? null : endMarker.name,
    'animated': animated ? true : null,
    'curvature': curvature == 0.5 ? null : curvature,
    'cornerRadius': cornerRadius == 8 ? null : cornerRadius,
    'customPath': customPath,
    'labelColor': colorToJson(labelColor),
    'labelBackground': colorToJson(labelBackground),
    'labelFontSize': labelFontSize,
  });

  /// Parses JSON produced by [toJson].
  factory EdgeStyle.fromJson(Map<String, Object?> json) => EdgeStyle(
    pathType:
        enumByName(EdgePathType.values, json['pathType']) ??
        EdgePathType.bezier,
    color: colorFromJson(json['color']),
    width: readDouble(json['width']),
    dashPattern: json['dashPattern'] == null
        ? null
        : asJsonList(json['dashPattern'])
              .map((e) => readDouble(e) ?? 4)
              .toList(),
    startMarker:
        enumByName(EdgeMarker.values, json['startMarker']) ?? EdgeMarker.none,
    endMarker:
        enumByName(EdgeMarker.values, json['endMarker']) ?? EdgeMarker.none,
    animated: json['animated'] == true,
    curvature: readDouble(json['curvature']) ?? 0.5,
    cornerRadius: readDouble(json['cornerRadius']) ?? 8,
    customPath: json['customPath'] as String?,
    labelColor: colorFromJson(json['labelColor']),
    labelBackground: colorFromJson(json['labelBackground']),
    labelFontSize: readDouble(json['labelFontSize']),
  );

  @override
  bool operator ==(Object other) =>
      other is EdgeStyle &&
      other.pathType == pathType &&
      other.color == color &&
      other.width == width &&
      listEquals(other.dashPattern, dashPattern) &&
      other.startMarker == startMarker &&
      other.endMarker == endMarker &&
      other.animated == animated &&
      other.curvature == curvature &&
      other.cornerRadius == cornerRadius &&
      other.customPath == customPath &&
      other.labelColor == labelColor &&
      other.labelBackground == labelBackground &&
      other.labelFontSize == labelFontSize;

  @override
  int get hashCode => Object.hash(
    pathType,
    color,
    width,
    dashPattern == null ? null : Object.hashAll(dashPattern!),
    startMarker,
    endMarker,
    animated,
    curvature,
    cornerRadius,
    customPath,
    labelColor,
    labelBackground,
    labelFontSize,
  );
}

/// A link between an output port ([source]) and an input port ([target]).
@immutable
class Edge {
  /// Creates an edge.
  const Edge({
    required this.id,
    required this.source,
    required this.target,
    this.style = const EdgeStyle(),
    this.label,
    this.waypoints = const [],
    this.data = const {},
  });

  /// Unique id.
  final EdgeId id;

  /// Output port the edge starts from.
  final PortRef source;

  /// Input port the edge ends at.
  final PortRef target;

  /// Visual style (design file).
  final EdgeStyle style;

  /// Optional label drawn at the middle of the edge.
  final String? label;

  /// Intermediate points for orthogonal / polyline routing, canvas units.
  final List<Offset> waypoints;

  /// Free, JSON-serializable payload (logic file).
  final Map<String, Object?> data;

  /// Whether the edge touches node [id].
  bool touches(NodeId id) => source.node == id || target.node == id;

  /// Returns a copy with the given fields replaced.
  Edge copyWith({
    EdgeId? id,
    PortRef? source,
    PortRef? target,
    EdgeStyle? style,
    String? label,
    bool clearLabel = false,
    List<Offset>? waypoints,
    Map<String, Object?>? data,
  }) => Edge(
    id: id ?? this.id,
    source: source ?? this.source,
    target: target ?? this.target,
    style: style ?? this.style,
    label: clearLabel ? null : (label ?? this.label),
    waypoints: waypoints ?? this.waypoints,
    data: data ?? this.data,
  );

  @override
  String toString() => 'Edge(${id.value}: $source -> $target)';
}
