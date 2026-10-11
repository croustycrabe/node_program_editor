import 'dart:ui';

import 'package:flutter/foundation.dart';

/// What a primary-button drag on empty canvas does.
enum PanOnDrag {
  /// Pans the viewport (hold Shift for a selection box).
  pan,

  /// Draws a selection box (hold Space or use the middle button to pan).
  select,
}

/// What a secondary (right) button drag on the canvas does. A right click
/// without dragging always opens the context menu.
enum SecondaryDrag {
  /// Draws a selection box (Ctrl / ⌘ adds to the selection).
  select,

  /// Pans the viewport.
  pan,

  /// Nothing.
  none,
}

/// Interaction and rendering options of an editor (React Flow style flags).
@immutable
class NodeEditorConfig {
  /// Creates a configuration.
  const NodeEditorConfig({
    this.nodesDraggable = true,
    this.nodesConnectable = true,
    this.nodesResizable = true,
    this.elementsSelectable = true,
    this.edgesSelectable = true,
    this.deletable = true,
    this.panOnDrag = PanOnDrag.pan,
    this.secondaryDrag = SecondaryDrag.select,
    this.zoomOnScroll = true,
    this.zoomOnPinch = true,
    this.minZoom = 0.05,
    this.maxZoom = 4,
    this.zoomStep = 1.2,
    this.translateExtent,
    this.lodThreshold = 0.4,
    this.lodTextThreshold = 0.18,
    this.cullingMargin = 0.25,
    this.connectionSnapRadius = 28,
    this.edgeHitTolerance = 8,
    this.showNodeMenu = true,
    this.showEdgeMenu = true,
    this.selectEdgesOnMarquee = true,
    this.marqueeRequiresFullContainment = false,
    this.doubleTapToEdit = true,
    this.useSystemClipboard = true,
    this.pasteOffset = 24,
    this.nudgeStep = 1,
    this.nudgeStepLarge = 10,
  });

  /// A read-only viewer: pan and zoom only.
  static const readOnly = NodeEditorConfig(
    nodesDraggable: false,
    nodesConnectable: false,
    nodesResizable: false,
    elementsSelectable: false,
    edgesSelectable: false,
    deletable: false,
    showNodeMenu: false,
    showEdgeMenu: false,
  );

  /// Whether nodes can be dragged.
  final bool nodesDraggable;

  /// Whether new links can be created by dragging from ports.
  final bool nodesConnectable;

  /// Whether nodes can be resized.
  final bool nodesResizable;

  /// Whether nodes can be selected.
  final bool elementsSelectable;

  /// Whether edges can be selected.
  final bool edgesSelectable;

  /// Whether elements can be deleted by the user.
  final bool deletable;

  /// Behaviour of a primary drag on empty canvas.
  final PanOnDrag panOnDrag;

  /// Behaviour of a right button drag on the canvas.
  final SecondaryDrag secondaryDrag;

  /// Whether the mouse wheel zooms.
  final bool zoomOnScroll;

  /// Whether pinch / trackpad gestures zoom.
  final bool zoomOnPinch;

  /// Minimum zoom.
  final double minZoom;

  /// Maximum zoom.
  final double maxZoom;

  /// Factor applied by zoom in / out buttons and one wheel notch.
  final double zoomStep;

  /// Limits panning to this canvas area (null = infinite canvas).
  final Rect? translateExtent;

  /// Below this zoom, nodes are rendered by the batched low-detail renderer
  /// instead of widgets.
  final double lodThreshold;

  /// Below this zoom, low-detail nodes are drawn without titles.
  final double lodTextThreshold;

  /// Extra area around the viewport (fraction of its size) in which node
  /// widgets are kept alive, to avoid rebuilds while panning.
  final double cullingMargin;

  /// Distance (screen px) within which a dragged link snaps to a port.
  final double connectionSnapRadius;

  /// Distance (screen px) within which a tap selects an edge.
  final double edgeHitTolerance;

  /// Whether the overlay menu appears above a selected node.
  final bool showNodeMenu;

  /// Whether the overlay menu appears on a selected edge.
  final bool showEdgeMenu;

  /// Whether the selection box also selects edges between selected nodes.
  final bool selectEdgesOnMarquee;

  /// Whether nodes must be fully inside the selection box.
  final bool marqueeRequiresFullContainment;

  /// Whether double tapping a node opens its edit dialog (or enters a super
  /// node).
  final bool doubleTapToEdit;

  /// Whether copy / paste also go through the system clipboard (as JSON).
  final bool useSystemClipboard;

  /// Offset applied to pasted elements.
  final double pasteOffset;

  /// Arrow key nudge distance.
  final double nudgeStep;

  /// Shift + arrow key nudge distance.
  final double nudgeStepLarge;

  /// Returns a copy with the given fields replaced.
  NodeEditorConfig copyWith({
    bool? nodesDraggable,
    bool? nodesConnectable,
    bool? nodesResizable,
    bool? elementsSelectable,
    bool? edgesSelectable,
    bool? deletable,
    PanOnDrag? panOnDrag,
    SecondaryDrag? secondaryDrag,
    bool? zoomOnScroll,
    bool? zoomOnPinch,
    double? minZoom,
    double? maxZoom,
    double? zoomStep,
    Rect? translateExtent,
    double? lodThreshold,
    double? lodTextThreshold,
    double? cullingMargin,
    double? connectionSnapRadius,
    double? edgeHitTolerance,
    bool? showNodeMenu,
    bool? showEdgeMenu,
    bool? selectEdgesOnMarquee,
    bool? marqueeRequiresFullContainment,
    bool? doubleTapToEdit,
    bool? useSystemClipboard,
    double? pasteOffset,
    double? nudgeStep,
    double? nudgeStepLarge,
  }) => NodeEditorConfig(
    nodesDraggable: nodesDraggable ?? this.nodesDraggable,
    nodesConnectable: nodesConnectable ?? this.nodesConnectable,
    nodesResizable: nodesResizable ?? this.nodesResizable,
    elementsSelectable: elementsSelectable ?? this.elementsSelectable,
    edgesSelectable: edgesSelectable ?? this.edgesSelectable,
    deletable: deletable ?? this.deletable,
    panOnDrag: panOnDrag ?? this.panOnDrag,
    secondaryDrag: secondaryDrag ?? this.secondaryDrag,
    zoomOnScroll: zoomOnScroll ?? this.zoomOnScroll,
    zoomOnPinch: zoomOnPinch ?? this.zoomOnPinch,
    minZoom: minZoom ?? this.minZoom,
    maxZoom: maxZoom ?? this.maxZoom,
    zoomStep: zoomStep ?? this.zoomStep,
    translateExtent: translateExtent ?? this.translateExtent,
    lodThreshold: lodThreshold ?? this.lodThreshold,
    lodTextThreshold: lodTextThreshold ?? this.lodTextThreshold,
    cullingMargin: cullingMargin ?? this.cullingMargin,
    connectionSnapRadius: connectionSnapRadius ?? this.connectionSnapRadius,
    edgeHitTolerance: edgeHitTolerance ?? this.edgeHitTolerance,
    showNodeMenu: showNodeMenu ?? this.showNodeMenu,
    showEdgeMenu: showEdgeMenu ?? this.showEdgeMenu,
    selectEdgesOnMarquee: selectEdgesOnMarquee ?? this.selectEdgesOnMarquee,
    marqueeRequiresFullContainment:
        marqueeRequiresFullContainment ?? this.marqueeRequiresFullContainment,
    doubleTapToEdit: doubleTapToEdit ?? this.doubleTapToEdit,
    useSystemClipboard: useSystemClipboard ?? this.useSystemClipboard,
    pasteOffset: pasteOffset ?? this.pasteOffset,
    nudgeStep: nudgeStep ?? this.nudgeStep,
    nudgeStepLarge: nudgeStepLarge ?? this.nudgeStepLarge,
  );
}
