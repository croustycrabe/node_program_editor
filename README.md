# node_program_editor

**A high-performance node graph engine for Flutter — React Flow, for Flutter.**

Build LabVIEW / Simulink style dataflow tools, n8n style automation builders or
machine-vision pipeline editors (Basler pylon like) on desktop, tablet and the
web. The package gives you the engine — canvas, nodes, ports, links,
interactions, panels, undo/redo and serialization — and you decide what the
nodes look like and what they do.

- **Zero dependencies** (Flutter SDK only).
- **Built for big graphs**: spatial index culling, a node layer that pans and
  zooms with a single layer transform (no rebuild, no relayout), and a
  level-of-detail renderer that draws tens of thousands of nodes in one
  `drawVertices` call.
- **GPU fragment shaders** for the infinite grid and animated "data flowing"
  links, with CPU fallbacks.
- **Everything is customizable**: node bodies, port shapes and placement,
  edge routing, colors, menus, toolbar, palette.

<!-- Add a GIF of the showcase here: doc/images/showcase.gif -->

## Features

| | |
|---|---|
| **Nodes** | Static or dynamic (inline parameters) built-in body, or your own widget. Resizable with min/max size, lockable, overlay menu (edit, copy, lock, delete + your actions), edit dialog generated from parameters. |
| **Ports** | Typed (`PortType` compatibility rules), input/output, `maxLinks` (-1 = unlimited), any side, automatic or explicit placement, 5 shapes or a custom builder. Compatible ports highlight while linking. |
| **Parameters** | 25 types: int, double, bool, text, multiline, password, code, expression, enum, multi-select, list, table, JSON, quantity with units, range, vector, matrix, curve / LUT, color, image, ROI, point, file path, date/time, trigger button, color map. |
| **Links** | Straight, bezier, step, smooth step, orthogonal and polyline with draggable waypoints, or your own routing. Markers, dashes, labels, colors, animated flow. Edit dialog with live preview. |
| **Canvas** | Dots / lines / cross grid, snapping of nodes and waypoints, pan & zoom with mouse, trackpad and touch, selection box, keyboard shortcuts. |
| **Panels** | Node palette (categories, search, filters, click and/or drag & drop), minimap, toolbar (undo/redo, save, zoom, grid, snap, align, distribute + custom items). |
| **Super nodes** | Group a selection into a reusable function (Ctrl+G), open it, choose which inner parameters are exposed, ungroup, save to / load from a library. |
| **Files** | Two documents: a **design** file (how it looks) and a **logic** file (what it does) that you can send to an execution engine. `LogicDocument.flatten()` inlines super nodes. |
| **Runtime** | Show execution status on nodes and animate the running path on links without touching the document or the undo history. |

## Install

```yaml
dependencies:
  node_program_editor: ^3.0.0
```

Requires Flutter ≥ 3.47 / Dart ≥ 3.13.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:node_program_editor/node_program_editor.dart';

final registry = NodeRegistry(definitions: [
  NodeDefinition(
    type: 'math.add',
    title: 'Add',
    category: 'Math',
    icon: Icons.add,
    variant: NodeVariant.dynamic,
    ports: const [
      PortSpec.input('a', label: 'a', type: PortType.number),
      PortSpec.input('b', label: 'b', type: PortType.number),
      PortSpec.output('sum', label: 'sum', type: PortType.number),
    ],
    params: const [
      ParamSpec('bias', DoubleParam(min: -10, max: 10, slider: true), showInNode: true),
    ],
  ),
]);

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final controller = NodeEditorController(registry: registry);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: NodeEditor(
          controller: controller,
          onSave: (c) {
            final logic = c.exportLogic().toJsonString();   // send to your engine
            final design = c.exportDesign().toJsonString(); // keep for the UI
          },
        ),
      );
}
```

`NodeEditor` = palette + canvas + toolbar + minimap. Each piece is also a
standalone widget (`NodePalette`, `NodeCanvas`, `NodeToolbar`, `NodeMiniMap`,
`SuperNodeBreadcrumb`) bound to the same controller.

## Showcase

The [example](example/) app is a web-first showcase with three complete
builders and a stress test:

- **Workflow automation** (n8n like) with a simulated run that animates the
  execution path.
- **Scientific & control** (Simulink / LabVIEW like): generators, filters,
  PID loop, FFT, live oscilloscopes, CSV export.
- **Computer vision** (pylon like): camera with AOI, filters, threshold,
  morphology, blob analysis, PASS / FAIL verdict, live previews in nodes.
- **Stress test**: up to 50 000 nodes with an FPS meter.

```bash
cd example
flutter run -d chrome
flutter build web --wasm --release --no-web-resources-cdn   # deploy build/web
```

See [web deployment on Cloudflare](doc/web-deployment-cloudflare.md).

## Documentation

Start with [Getting started](doc/getting-started.md), then:

- [Architecture](doc/architecture.md) — controller, commands, layers, LOD
- [Nodes and ports](doc/nodes-and-ports.md)
- [Parameters](doc/parameters.md)
- [Edges](doc/edges.md)
- [Canvas, grid and viewport](doc/canvas-and-grid.md)
- [Palette](doc/palette.md) · [Minimap](doc/minimap.md) · [Toolbar](doc/toolbar.md)
- [Menus and edit dialogs](doc/menus-and-editing.md)
- [Selection, clipboard and undo](doc/selection-and-clipboard.md)
- [Super nodes](doc/super-nodes.md)
- [Serialization: design and logic files](doc/serialization.md)
- [Connecting an execution engine](doc/execution-engine.md)
- [Theming and customization](doc/theming-and-customization.md)
- [Keyboard shortcuts](doc/keyboard-shortcuts.md)
- [Performance guide](doc/performance.md)
- [Web deployment (Cloudflare)](doc/web-deployment-cloudflare.md)
- [Migrating from 2.x](doc/migration-from-2.x.md)

The full API reference is generated by `dart doc` (every public member is
documented).

## License

See [LICENSE](LICENSE).
