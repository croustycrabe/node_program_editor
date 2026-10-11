# Performance guide

The engine is built so the cost of a frame depends on **what is visible and
what changed**, not on the size of the graph.

## What happens when…

| Event | Work done |
|---|---|
| Pan / zoom (zoomed in) | node layer: one `TransformLayer` update, no rebuild / relayout / repaint; edges: repaint of visible edges from cached paths; grid: one shader draw |
| Pan / zoom (zoomed out) | one cached `drawVertices` for all nodes, cached line batches for edges |
| Visible area crosses a 256-unit cell | spatial query + rebuild of the node list (keyed, existing node widgets are reused) |
| Drag a node | its parent data, its edges' spatial bounds and paths; not its content |
| Edit a parameter | that node's content widget |
| Select a node | the nodes whose selection state changed |
| Animated edges | only the animated edge layer repaints each frame |

## Tuning

- **`lodThreshold`** (default 0.4): below this zoom no node widget exists.
  Raise it for heavy custom bodies (plots, images); lower it for simple nodes.
- **`lodTextThreshold`**: below it, low-detail nodes have no titles.
- **`cullingMargin`** (default 0.25): extra area kept alive around the
  viewport. Larger values mean fewer rebuilds while panning, but more widgets.
- **Shaders**: keep `useShaders: true`. The CPU grid fallback is batched but
  costs more at small spacings.
- **Edge routes**: bezier and step routes are cached; custom
  `EdgePathBuilder`s are called only when an endpoint or style changes. Keep
  them pure.
- **Animated edges**: each animated edge is drawn every frame. Use them for
  highlights (`setEdgeRuntime`), not for thousands of edges at once.

## Writing fast node bodies

- Read data in `build`, but do heavy work in your engine and publish results.
  Listen to them with a `ListenableBuilder` scoped to the body (see the scope
  node of the showcase).
- Avoid `node.size` based layout when a `LayoutBuilder` works; the body is
  already laid out at the node size.
- Images: pass `ui.Image`s (`RawImage`) instead of re-decoding bytes each
  build. Dispose replaced images.
- Do not rebuild every node to show a global state: put it in
  `node.runtime` with `setRuntimeData` (only that node rebuilds).

## Big graphs

- Build them in one command: `controller.addElements(nodes, edges)` (one
  notification, one undo step), then `controller.history.clear()` if it is an
  initial load.
- Avoid `controller.graph.nodes` loops in widgets; use spatial queries
  (`controller.nodesIn(rect)`, `controller.nodeIndex.query(rect)`).
- Loading a file decodes everything in one batch and rebuilds the indexes once.

## Measuring

Run the example's **Stress test** page in profile or release mode
(`flutter run --profile`, or a `--release` web build): generate 10k–50k
nodes, enable **Auto pan & zoom** and read the FPS meter. The unit test
`SpatialHashGrid 50k nodes` checks that viewport queries stay far below a
frame budget.

## Web

- Build with `flutter build web --wasm` (skwasm renderer, falls back to
  CanvasKit on browsers without WasmGC).
- Serve with cross-origin isolation headers to enable multi-threaded
  rendering (see [web deployment](web-deployment-cloudflare.md)).
- `--no-web-resources-cdn` bundles the engine files with your site, so it
  works without reaching Google's CDN.
