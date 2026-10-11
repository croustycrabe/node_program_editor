# Architecture

```
┌────────────────────────── NodeEditor (optional composite) ─────────────────────────┐
│ NodePalette │ NodeCanvas                                                            │
│             │  ├─ GridPainter            (grid.frag shader, CPU fallback)           │
│             │  ├─ EdgePainter            (culled, cached routes; LOD line batches)  │
│             │  ├─ AnimatedEdgePainter    (edge_flow.frag, only animated edges)      │
│             │  ├─ LodNodePainter         (zoomed out: one drawVertices call)        │
│             │  ├─ NodeLayer              (zoomed in: culled node widgets)           │
│             │  ├─ InteractionPainter     (link being dragged, selection box)        │
│             │  ├─ EdgeWaypointOverlay / NodeMenuOverlay / EdgeMenuOverlay           │
│             │  └─ overlays: NodeToolbar, NodeMiniMap, SuperNodeBreadcrumb, yours…   │
└─────────────┴───────────────────────────────────────────────────────────────────────┘
                                   │ reads / listens
                                   ▼
                        NodeEditorController ──── GraphCommand ──► HistoryStack
                         │  Graph (current scope)       (undo / redo, transactions)
                         │  SpatialHashGrid (nodes, edges)
                         │  NodeRegistry, SuperNodeLibrary
                         └  viewport, selection, canvasSettings, runtime state
```

## Model layer (`lib/src/core`)

| Type | Role |
|---|---|
| `NodeDefinition` / `NodeRegistry` | What kinds of nodes exist (ports, params, size, look). |
| `NodeInstance` | A node in a graph: id, definition, position, size, params, lock, style, `data` (saved) and `runtime` (transient). |
| `PortSpec`, `PortType`, `PortRef` | Port declarations, data types and references. |
| `Edge`, `EdgeStyle` | Links between an output and an input port. |
| `Graph` | Store with O(1) lookups and adjacency (`edgesOfPort`, `linkCount`, `incoming`, `outgoing`, `topologicalOrder`). |
| `SpatialHashGrid` | Uniform grid index of node rects and edge bounds: culling, hit testing, marquee. |
| `PortGeometry` | Port anchors computed from the node model (never from measured widgets). |
| `EdgeRouter` / `EdgeGeometry` | Edge routing and polyline approximations for hit testing. |
| `ConnectionValidator` | Link rules (types, `maxLinks`, duplicates, cycles, custom). |
| `GraphCommand`, `HistoryStack` | Undoable edits, merging and transactions. |
| `LogicDocument`, `DesignDocument`, `GraphFragment` | Serialization. |
| `SuperNodeDefinition`, `SuperNodeLibrary` | Reusable sub-graphs. |

The model has no widget dependency except `NodeDefinition.builder` /
`portBuilder` signatures.

## The controller

`NodeEditorController` implements `GraphMutator`: the low-level mutations
(`insertNode`, `deleteEdge`, `setNodeGeometry`...) that keep the graph, the
spatial indexes, caches and listeners in sync. **Commands** call these
mutations; **public methods** (`addNode`, `connect`, `moveNodes`,
`setParams`...) build commands and `execute` them, so every user-visible change
is undoable.

```dart
controller.transaction('Layout', () {
  controller.moveNodes({a: const Offset(0, 0), b: const Offset(300, 0)});
  controller.setParam(a, 'gain', 2.0);
}); // one undo step
```

### Fine-grained notifications

Widgets subscribe only to what they display:

| Listenable | Fires when | Used by |
|---|---|---|
| `nodeListenable(id)` | params, selection, lock, style or size of one node change | node widget content |
| `nodePositionListenable(id)` | one node moves | node parent data (no rebuild of content) |
| `structure` | nodes added / removed / reordered | node layer |
| `geometry` | any node moved / resized | LOD renderer, minimap |
| `edgesListenable` | edges added / removed / restyled, endpoints moved | edge painters |
| `viewport`, `selection`, `canvasSettings`, `history`, `scopeListenable` | as named | toolbar, overlays |
| `revision` | any document change | autosave, dirty flags, engines |

Mutations run inside `batch()`: a paste of 1 000 nodes notifies each listener
once.

## Rendering pipeline and level of detail

**Zoom ≥ `NodeEditorConfig.lodThreshold` (default 0.4):**

1. `NodeLayer` queries the node spatial index with the viewport (plus
   `cullingMargin`) and builds widgets only for those nodes. The query rect is
   snapped to 256-unit cells, so small pans do not even requery.
2. Its render object is a repaint boundary whose layer is a persistent
   `TransformLayer`. Panning and zooming call
   `markNeedsCompositedLayerUpdate()`: the transform changes, nothing is
   rebuilt, laid out or repainted.
3. Moving a node updates its parent data only; the node content is not
   rebuilt (separate position notifier).
4. Edges are culled with the edge spatial index; routed paths are cached per
   edge until an endpoint or the style changes.

**Zoom < `lodThreshold`:** no node widget is built. `LodNodePainter` draws all
nodes as colored quads (body + header) in one `drawVertices` call from a
cached buffer; only selected nodes (usually the dragged ones) are rebuilt per
frame. Edges become straight segments batched per color into
`drawRawPoints` calls from cached buffers. Titles are drawn from cached
paragraphs above `lodTextThreshold`.

**Shaders:** `shaders/grid.frag` draws the whole grid in one call;
`shaders/edge_flow.frag` animates running links. Animated edges are on their own
layer, and its ticker only runs while animated edges exist. See
[Performance](performance.md).

## Interaction model

- Node drag / tap, port drag, resize and waypoint handles are gesture
  recognizers inside the node layer (they receive canvas coordinates through
  `NodeEditorScope.globalToCanvas`).
- The canvas background owns pan / pinch / selection box (a
  `ScaleGestureRecognizer`), taps (edge hit testing through the spatial
  index), the mouse wheel and keyboard shortcuts.
- Widgets inside node bodies that need their own drag (sliders, text fields,
  plots) are wrapped in `NoNodeDrag`.

## Scopes (super nodes)

`controller.scopes` is a stack: the root graph, then the interior graph of each
opened super node. `controller.graph`, the indexes and the history always refer
to the current scope; `exportLogic` / `exportDesign` always serialize the root
and every used definition.
