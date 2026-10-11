import 'package:flutter/material.dart';

import '../core/node.dart';
import '../core/ports.dart';

/// Visual theme of the editor. Register it as a [ThemeExtension] on your
/// [ThemeData] (or pass it to the widgets) to restyle every component.
@immutable
class NodeEditorThemeData extends ThemeExtension<NodeEditorThemeData> {
  /// Creates a theme. Prefer [NodeEditorThemeData.light] /
  /// [NodeEditorThemeData.dark] with [copyWith].
  const NodeEditorThemeData({
    required this.brightness,
    required this.backgroundColor,
    required this.gridColor,
    required this.majorGridColor,
    this.gridThickness = 1.2,
    required this.nodeColor,
    required this.nodeHeaderColor,
    required this.nodeBorderColor,
    this.nodeBorderWidth = 1,
    this.nodeRadius = 10,
    this.nodeShadow = const [],
    required this.selectedBorderColor,
    this.selectedBorderWidth = 2,
    required this.lockedColor,
    required this.titleStyle,
    required this.bodyStyle,
    required this.portLabelStyle,
    this.portSize = 12,
    this.portShape = PortShape.circle,
    required this.portBorderColor,
    required this.validTargetColor,
    required this.invalidTargetColor,
    required this.edgeColor,
    this.edgeWidth = 2,
    required this.selectedEdgeColor,
    this.colorEdgesByType = true,
    required this.edgeLabelStyle,
    required this.edgeLabelBackground,
    required this.connectionColor,
    required this.marqueeFill,
    required this.marqueeBorder,
    required this.minimapBackground,
    required this.minimapNodeColor,
    required this.minimapViewportColor,
    required this.minimapMaskColor,
    required this.panelColor,
    required this.panelBorderColor,
    required this.panelForeground,
    required this.accentColor,
  });

  /// Default light theme.
  factory NodeEditorThemeData.light() => const NodeEditorThemeData(
    brightness: Brightness.light,
    backgroundColor: Color(0xFFF6F7F9),
    gridColor: Color(0xFFCBD2DC),
    majorGridColor: Color(0xFFB0B9C6),
    nodeColor: Color(0xFFFFFFFF),
    nodeHeaderColor: Color(0xFF3B82F6),
    nodeBorderColor: Color(0xFFD5DBE3),
    nodeShadow: [
      BoxShadow(color: Color(0x1A101828), blurRadius: 8, offset: Offset(0, 2)),
    ],
    selectedBorderColor: Color(0xFFFF8A00),
    lockedColor: Color(0xFF8A94A6),
    titleStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFFFFFFFF),
    ),
    bodyStyle: TextStyle(fontSize: 12, color: Color(0xFF344054)),
    portLabelStyle: TextStyle(fontSize: 11, color: Color(0xFF475467)),
    portBorderColor: Color(0xFFFFFFFF),
    validTargetColor: Color(0xFF12B76A),
    invalidTargetColor: Color(0xFFF04438),
    edgeColor: Color(0xFF98A2B3),
    selectedEdgeColor: Color(0xFFFF8A00),
    edgeLabelStyle: TextStyle(fontSize: 11, color: Color(0xFF344054)),
    edgeLabelBackground: Color(0xFFFFFFFF),
    connectionColor: Color(0xFF3B82F6),
    marqueeFill: Color(0x1A3B82F6),
    marqueeBorder: Color(0xFF3B82F6),
    minimapBackground: Color(0xF2FFFFFF),
    minimapNodeColor: Color(0xFF98A2B3),
    minimapViewportColor: Color(0xFF3B82F6),
    minimapMaskColor: Color(0x14101828),
    panelColor: Color(0xFFFFFFFF),
    panelBorderColor: Color(0xFFE4E7EC),
    panelForeground: Color(0xFF344054),
    accentColor: Color(0xFF3B82F6),
  );

  /// Default dark theme.
  factory NodeEditorThemeData.dark() => const NodeEditorThemeData(
    brightness: Brightness.dark,
    backgroundColor: Color(0xFF14161B),
    gridColor: Color(0xFF2A2F38),
    majorGridColor: Color(0xFF363C47),
    nodeColor: Color(0xFF22262E),
    nodeHeaderColor: Color(0xFF2F6FED),
    nodeBorderColor: Color(0xFF353B46),
    nodeShadow: [
      BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 3)),
    ],
    selectedBorderColor: Color(0xFFFFA940),
    lockedColor: Color(0xFF6B7280),
    titleStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFFFFFFFF),
    ),
    bodyStyle: TextStyle(fontSize: 12, color: Color(0xFFD0D5DD)),
    portLabelStyle: TextStyle(fontSize: 11, color: Color(0xFFAAB2C0)),
    portBorderColor: Color(0xFF14161B),
    validTargetColor: Color(0xFF32D583),
    invalidTargetColor: Color(0xFFF97066),
    edgeColor: Color(0xFF667085),
    selectedEdgeColor: Color(0xFFFFA940),
    edgeLabelStyle: TextStyle(fontSize: 11, color: Color(0xFFD0D5DD)),
    edgeLabelBackground: Color(0xFF22262E),
    connectionColor: Color(0xFF5B8DEF),
    marqueeFill: Color(0x1F5B8DEF),
    marqueeBorder: Color(0xFF5B8DEF),
    minimapBackground: Color(0xF21C1F25),
    minimapNodeColor: Color(0xFF667085),
    minimapViewportColor: Color(0xFF5B8DEF),
    minimapMaskColor: Color(0x33000000),
    panelColor: Color(0xFF1C1F25),
    panelBorderColor: Color(0xFF2D323C),
    panelForeground: Color(0xFFD0D5DD),
    accentColor: Color(0xFF5B8DEF),
  );

  /// The theme for [context]: the registered extension, or the light / dark
  /// default matching the ambient brightness.
  static NodeEditorThemeData of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<NodeEditorThemeData>() ??
        (theme.brightness == Brightness.dark
            ? NodeEditorThemeData.dark()
            : NodeEditorThemeData.light());
  }

  /// Light or dark.
  final Brightness brightness;

  /// Canvas background.
  final Color backgroundColor;

  /// Minor grid color.
  final Color gridColor;

  /// Major grid color.
  final Color majorGridColor;

  /// Grid dot radius / line width, logical pixels.
  final double gridThickness;

  /// Node body color.
  final Color nodeColor;

  /// Node header color.
  final Color nodeHeaderColor;

  /// Node border color.
  final Color nodeBorderColor;

  /// Node border width.
  final double nodeBorderWidth;

  /// Node corner radius.
  final double nodeRadius;

  /// Node shadow.
  final List<BoxShadow> nodeShadow;

  /// Outline of selected nodes.
  final Color selectedBorderColor;

  /// Width of the selection outline.
  final double selectedBorderWidth;

  /// Lock badge color.
  final Color lockedColor;

  /// Node title style.
  final TextStyle titleStyle;

  /// Node body text style.
  final TextStyle bodyStyle;

  /// Port label style.
  final TextStyle portLabelStyle;

  /// Default port diameter.
  final double portSize;

  /// Default port shape.
  final PortShape portShape;

  /// Port border color.
  final Color portBorderColor;

  /// Highlight of ports that accept the dragged link.
  final Color validTargetColor;

  /// Highlight of a hovered port that rejects the dragged link.
  final Color invalidTargetColor;

  /// Default edge color.
  final Color edgeColor;

  /// Default edge width.
  final double edgeWidth;

  /// Selected edge color.
  final Color selectedEdgeColor;

  /// Whether edges without an explicit color take their source port type
  /// color.
  final bool colorEdgesByType;

  /// Edge label style.
  final TextStyle edgeLabelStyle;

  /// Edge label background.
  final Color edgeLabelBackground;

  /// Color of the link being dragged.
  final Color connectionColor;

  /// Selection box fill.
  final Color marqueeFill;

  /// Selection box border.
  final Color marqueeBorder;

  /// Minimap background.
  final Color minimapBackground;

  /// Default minimap node color.
  final Color minimapNodeColor;

  /// Minimap viewport outline.
  final Color minimapViewportColor;

  /// Minimap area outside the viewport.
  final Color minimapMaskColor;

  /// Background of panels (palette, toolbar, menus).
  final Color panelColor;

  /// Border of panels.
  final Color panelBorderColor;

  /// Text / icon color on panels.
  final Color panelForeground;

  /// Accent (active toggles, focus).
  final Color accentColor;

  @override
  NodeEditorThemeData copyWith({
    Brightness? brightness,
    Color? backgroundColor,
    Color? gridColor,
    Color? majorGridColor,
    double? gridThickness,
    Color? nodeColor,
    Color? nodeHeaderColor,
    Color? nodeBorderColor,
    double? nodeBorderWidth,
    double? nodeRadius,
    List<BoxShadow>? nodeShadow,
    Color? selectedBorderColor,
    double? selectedBorderWidth,
    Color? lockedColor,
    TextStyle? titleStyle,
    TextStyle? bodyStyle,
    TextStyle? portLabelStyle,
    double? portSize,
    PortShape? portShape,
    Color? portBorderColor,
    Color? validTargetColor,
    Color? invalidTargetColor,
    Color? edgeColor,
    double? edgeWidth,
    Color? selectedEdgeColor,
    bool? colorEdgesByType,
    TextStyle? edgeLabelStyle,
    Color? edgeLabelBackground,
    Color? connectionColor,
    Color? marqueeFill,
    Color? marqueeBorder,
    Color? minimapBackground,
    Color? minimapNodeColor,
    Color? minimapViewportColor,
    Color? minimapMaskColor,
    Color? panelColor,
    Color? panelBorderColor,
    Color? panelForeground,
    Color? accentColor,
  }) => NodeEditorThemeData(
    brightness: brightness ?? this.brightness,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    gridColor: gridColor ?? this.gridColor,
    majorGridColor: majorGridColor ?? this.majorGridColor,
    gridThickness: gridThickness ?? this.gridThickness,
    nodeColor: nodeColor ?? this.nodeColor,
    nodeHeaderColor: nodeHeaderColor ?? this.nodeHeaderColor,
    nodeBorderColor: nodeBorderColor ?? this.nodeBorderColor,
    nodeBorderWidth: nodeBorderWidth ?? this.nodeBorderWidth,
    nodeRadius: nodeRadius ?? this.nodeRadius,
    nodeShadow: nodeShadow ?? this.nodeShadow,
    selectedBorderColor: selectedBorderColor ?? this.selectedBorderColor,
    selectedBorderWidth: selectedBorderWidth ?? this.selectedBorderWidth,
    lockedColor: lockedColor ?? this.lockedColor,
    titleStyle: titleStyle ?? this.titleStyle,
    bodyStyle: bodyStyle ?? this.bodyStyle,
    portLabelStyle: portLabelStyle ?? this.portLabelStyle,
    portSize: portSize ?? this.portSize,
    portShape: portShape ?? this.portShape,
    portBorderColor: portBorderColor ?? this.portBorderColor,
    validTargetColor: validTargetColor ?? this.validTargetColor,
    invalidTargetColor: invalidTargetColor ?? this.invalidTargetColor,
    edgeColor: edgeColor ?? this.edgeColor,
    edgeWidth: edgeWidth ?? this.edgeWidth,
    selectedEdgeColor: selectedEdgeColor ?? this.selectedEdgeColor,
    colorEdgesByType: colorEdgesByType ?? this.colorEdgesByType,
    edgeLabelStyle: edgeLabelStyle ?? this.edgeLabelStyle,
    edgeLabelBackground: edgeLabelBackground ?? this.edgeLabelBackground,
    connectionColor: connectionColor ?? this.connectionColor,
    marqueeFill: marqueeFill ?? this.marqueeFill,
    marqueeBorder: marqueeBorder ?? this.marqueeBorder,
    minimapBackground: minimapBackground ?? this.minimapBackground,
    minimapNodeColor: minimapNodeColor ?? this.minimapNodeColor,
    minimapViewportColor: minimapViewportColor ?? this.minimapViewportColor,
    minimapMaskColor: minimapMaskColor ?? this.minimapMaskColor,
    panelColor: panelColor ?? this.panelColor,
    panelBorderColor: panelBorderColor ?? this.panelBorderColor,
    panelForeground: panelForeground ?? this.panelForeground,
    accentColor: accentColor ?? this.accentColor,
  );

  @override
  NodeEditorThemeData lerp(
    covariant ThemeExtension<NodeEditorThemeData>? other,
    double t,
  ) {
    if (other is! NodeEditorThemeData) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => a + (b - a) * t;
    return NodeEditorThemeData(
      brightness: t < 0.5 ? brightness : other.brightness,
      backgroundColor: c(backgroundColor, other.backgroundColor),
      gridColor: c(gridColor, other.gridColor),
      majorGridColor: c(majorGridColor, other.majorGridColor),
      gridThickness: d(gridThickness, other.gridThickness),
      nodeColor: c(nodeColor, other.nodeColor),
      nodeHeaderColor: c(nodeHeaderColor, other.nodeHeaderColor),
      nodeBorderColor: c(nodeBorderColor, other.nodeBorderColor),
      nodeBorderWidth: d(nodeBorderWidth, other.nodeBorderWidth),
      nodeRadius: d(nodeRadius, other.nodeRadius),
      nodeShadow: BoxShadow.lerpList(nodeShadow, other.nodeShadow, t) ?? [],
      selectedBorderColor: c(selectedBorderColor, other.selectedBorderColor),
      selectedBorderWidth: d(selectedBorderWidth, other.selectedBorderWidth),
      lockedColor: c(lockedColor, other.lockedColor),
      titleStyle: TextStyle.lerp(titleStyle, other.titleStyle, t)!,
      bodyStyle: TextStyle.lerp(bodyStyle, other.bodyStyle, t)!,
      portLabelStyle: TextStyle.lerp(portLabelStyle, other.portLabelStyle, t)!,
      portSize: d(portSize, other.portSize),
      portShape: t < 0.5 ? portShape : other.portShape,
      portBorderColor: c(portBorderColor, other.portBorderColor),
      validTargetColor: c(validTargetColor, other.validTargetColor),
      invalidTargetColor: c(invalidTargetColor, other.invalidTargetColor),
      edgeColor: c(edgeColor, other.edgeColor),
      edgeWidth: d(edgeWidth, other.edgeWidth),
      selectedEdgeColor: c(selectedEdgeColor, other.selectedEdgeColor),
      colorEdgesByType: t < 0.5 ? colorEdgesByType : other.colorEdgesByType,
      edgeLabelStyle: TextStyle.lerp(edgeLabelStyle, other.edgeLabelStyle, t)!,
      edgeLabelBackground: c(edgeLabelBackground, other.edgeLabelBackground),
      connectionColor: c(connectionColor, other.connectionColor),
      marqueeFill: c(marqueeFill, other.marqueeFill),
      marqueeBorder: c(marqueeBorder, other.marqueeBorder),
      minimapBackground: c(minimapBackground, other.minimapBackground),
      minimapNodeColor: c(minimapNodeColor, other.minimapNodeColor),
      minimapViewportColor: c(minimapViewportColor, other.minimapViewportColor),
      minimapMaskColor: c(minimapMaskColor, other.minimapMaskColor),
      panelColor: c(panelColor, other.panelColor),
      panelBorderColor: c(panelBorderColor, other.panelBorderColor),
      panelForeground: c(panelForeground, other.panelForeground),
      accentColor: c(accentColor, other.accentColor),
    );
  }
}

/// Effective colors of a node: instance style, then definition style, then
/// theme.
typedef NodeColors = ({
  Color body,
  Color header,
  Color border,
  Color text,
  double radius,
  double borderWidth,
});

/// Resolves the effective [NodeColors] of [node].
NodeColors resolveNodeColors(NodeInstance node, NodeEditorThemeData theme) {
  final style = (node.definition.style ?? const NodeStyle()).merge(node.style);
  return (
    body: style.color ?? theme.nodeColor,
    header: style.headerColor ?? theme.nodeHeaderColor,
    border: style.borderColor ?? theme.nodeBorderColor,
    text: style.textColor ?? theme.titleStyle.color ?? const Color(0xFFFFFFFF),
    radius: style.borderRadius ?? theme.nodeRadius,
    borderWidth: style.borderWidth ?? theme.nodeBorderWidth,
  );
}
