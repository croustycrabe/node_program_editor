# Canvas, grid and viewport

## NodeCanvas

```dart
NodeCanvas(
  controller: controller,
  theme: null,                       // default: NodeEditorThemeData.of(context)
  services: const NodeEditorServices(),
  nodeBuilder: null,                 // replace every node widget
  portBuilder: null,                 // replace every port visual
  shortcuts: null,                   // default: NodeEditorShortcuts.defaults
  overlays: [...],                   // screen-space widgets (Positioned)
  nodeMenuActions: [...],
  edgeMenuActions: [...],
  onEditNode: null,                  // replace the node edit dialog
  onEditEdge: null,                  // replace the edge edit dialog
  autofocus: true,
  useShaders: true,
  canvasMenuActions: null,           // right click menu (null = defaults)
  disableBrowserContextMenu: true,   // web: hide the browser's own menu
)
```

The canvas accepts `NodeDragData` drops (from `NodePalette` or your own
`Draggable<NodeDragData>`).

## Grid and snapping: CanvasSettings

```dart
controller.canvasSettings.value = const CanvasSettings(
  gridStyle: GridStyle.lines,     // none, dots, lines, cross
  gridSpacing: 20,                // also the snapping step
  majorEvery: 5,                  // major line every 5 cells (≤ 1 disables)
  snapToGrid: true,               // node moves and resizes
  snapEdgesToGrid: true,          // edge waypoints
  defaultEdgeStyle: EdgeStyle(pathType: EdgePathType.smoothStep),
  gridColor: null, majorGridColor: null, backgroundColor: null,
);
```

Canvas settings are saved in the design file. The grid is drawn by
`shaders/grid.frag` in one draw call, independent of its density; when cells
become smaller than 8 px the spacing doubles automatically and minor lines
fade. When shaders are unavailable (or `useShaders: false`) a batched CPU
fallback draws the same grid.

## Interaction options: NodeEditorConfig

```dart
controller.config = const NodeEditorConfig(
  nodesDraggable: true,
  nodesConnectable: true,
  nodesResizable: true,
  elementsSelectable: true,
  edgesSelectable: true,
  deletable: true,
  panOnDrag: PanOnDrag.pan,          // or PanOnDrag.select
  secondaryDrag: SecondaryDrag.select, // right drag: select, pan or none
  zoomOnScroll: true,                // false: wheel pans, Ctrl+wheel zooms
  zoomOnPinch: true,
  minZoom: 0.05, maxZoom: 4, zoomStep: 1.2,
  translateExtent: null,             // e.g. Rect.fromLTWH(-2000, -2000, 8000, 6000)
  lodThreshold: 0.4,                 // below: batched low-detail renderer
  lodTextThreshold: 0.18,            // below: low-detail nodes without titles
  cullingMargin: 0.25,
  connectionSnapRadius: 28,          // px
  edgeHitTolerance: 8,               // px
  showNodeMenu: true,
  showEdgeMenu: true,
  selectEdgesOnMarquee: true,
  marqueeRequiresFullContainment: false,
  doubleTapToEdit: true,
  useSystemClipboard: true,
  pasteOffset: 24, nudgeStep: 1, nudgeStepLarge: 10,
);
```

`NodeEditorConfig.readOnly` turns the editor into a viewer (pan and zoom only).

## Pointer and touch

| Gesture | Action |
|---|---|
| Drag on empty canvas | pan (or selection box with `PanOnDrag.select`) |
| Shift + drag | selection box (or pan with `PanOnDrag.select`) |
| Ctrl / ⌘ + Shift + drag | add to the selection |
| Right button drag | selection box (`secondaryDrag: SecondaryDrag.select`, default), or pan (`SecondaryDrag.pan`) |
| Middle button drag, Space + drag | pan |
| Wheel | zoom at the cursor (`zoomOnScroll`) or pan |
| Ctrl / ⌘ + wheel, trackpad pinch | zoom |
| Two-finger trackpad scroll | pan |
| Two-finger touch | pan + pinch zoom |
| Tap node / edge | select (Ctrl, ⌘ or Shift toggles) |
| Double tap node | edit dialog (open super nodes) |
| Right click node / edge | context menu |
| Right click empty canvas | canvas menu (`canvasMenuActions`), or your `onCanvasContextMenu` |

## Viewport

```dart
controller.fitView();                       // all nodes, animated
controller.fitView(ids: selectedIds, padding: 80, maxZoom: 1);
controller.centerOn(const Offset(500, 300), zoom: 1.2);
controller.zoomIn(); controller.zoomOut(); controller.zoomTo(0.5);
controller.panBy(const Offset(-200, 0));
controller.setViewport(const EditorViewport(offset: Offset(40, 40), zoom: 0.8));
controller.viewport.value.toCanvas(screenPoint);
controller.viewportCenter;                  // canvas point at the center
```

View operations issued before the canvas is laid out are deferred until its
first layout, so calling `fitView()` right after building a graph works.

## Events

```dart
controller
  ..onNodeTap = (node) {}
  ..onNodeDoubleTap = (node) => false     // return true to skip the default
  ..onEdgeTap = (edge) {}
  ..onCanvasTap = (canvasPoint) {}
  ..onCanvasContextMenu = (canvasPoint, globalPoint) {}
  ..onConnect = (edge) {}
  ..onConnectEnd = (details) {            // also fires when dropped on nothing
    if (details.edge == null) showQuickAdd(details.canvasPosition, details.from);
  }
  ..onNodesDeleted = (nodes) {};
controller.revision.addListener(autosave); // any document change
```
