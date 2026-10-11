# Minimap

```dart
NodeMiniMap(
  controller: controller,
  width: 200,
  height: 140,
  nodeColor: (node) => node.locked ? Colors.grey : Colors.blue, // default: header color
  interactive: true,     // tap / drag to navigate
  zoomable: true,        // scroll over it to zoom the canvas
  borderRadius: 8,
)
```

The minimap shows the union of all nodes and the visible area, masks what is
outside the viewport and outlines the viewport. Nodes are drawn as rectangles
in one `drawVertices` call from a cached buffer, rebuilt only when
non-selected nodes change, so it stays cheap with very large graphs.

Place it anywhere: as a canvas overlay (`NodeCanvas.overlays` with a
`Positioned`), in a side panel, or toggle it with your own state.
`NodeEditor(showMinimap: false)` hides the built-in one.
