# Getting started

This guide builds a small editor in five steps. Every snippet compiles against
`node_program_editor` 3.x.

## 1. Describe your nodes

A `NodeDefinition` declares a kind of node: its ports, parameters, size rules
and look. Definitions live in a `NodeRegistry`.

```dart
import 'package:flutter/material.dart';
import 'package:node_program_editor/node_program_editor.dart';

const imageType = PortType('image', color: Color(0xFF7E57C2));

final registry = NodeRegistry(
  portTypes: const [imageType],
  definitions: [
    const NodeDefinition(
      type: 'camera',
      title: 'Camera',
      category: 'Acquisition',
      icon: Icons.videocam_outlined,
      ports: [PortSpec.output('frame', label: 'frame', type: imageType)],
      params: [
        ParamSpec('exposure', QuantityParam(['µs', 'ms'], defaultValue: Quantity(10, 'ms'))),
      ],
    ),
    NodeDefinition(
      type: 'threshold',
      title: 'Threshold',
      category: 'Segmentation',
      icon: Icons.tonality,
      variant: NodeVariant.dynamic,            // shows inline editors
      ports: const [
        PortSpec.input('in', label: 'image', type: imageType),
        PortSpec.output('out', label: 'mask', type: imageType),
      ],
      params: const [
        ParamSpec('range', RangeParam(min: 0, max: 255, defaultValue: RangeValue(128, 255)),
            showInNode: true),
        ParamSpec('invert', BoolParam()),
      ],
    ),
  ],
);
```

Read more in [Nodes and ports](nodes-and-ports.md) and
[Parameters](parameters.md).

## 2. Create a controller

The `NodeEditorController` is the single source of truth: graph, viewport,
selection, undo history and interaction state. Create one per editor and
dispose it with the widget that owns it.

```dart
final controller = NodeEditorController(
  registry: registry,
  canvasSettings: const CanvasSettings(
    gridStyle: GridStyle.dots,
    snapToGrid: true,
    defaultEdgeStyle: EdgeStyle(pathType: EdgePathType.smoothStep),
  ),
);
```

## 3. Show it

```dart
Scaffold(body: NodeEditor(controller: controller))
```

`NodeEditor` composes a palette, the canvas, a floating toolbar, a minimap and
the super node breadcrumb. To build your own layout, use the pieces directly:

```dart
Row(children: [
  SizedBox(width: 260, child: NodePalette(controller: controller)),
  Expanded(
    child: NodeCanvas(
      controller: controller,
      overlays: [
        Positioned(top: 12, left: 12, child: NodeToolbar(controller: controller)),
        Positioned(right: 12, bottom: 12, child: NodeMiniMap(controller: controller)),
      ],
    ),
  ),
])
```

## 4. Build graphs from code

Every mutation goes through the controller so it is undoable and the UI is
notified.

```dart
final cam = controller.addNode('camera', position: const Offset(0, 0));
final thr = controller.addNode('threshold', position: const Offset(300, 0),
    params: {'invert': true});
controller.connect(PortRef(cam.id, 'frame'), PortRef(thr.id, 'in'));
controller.fitView();
```

## 5. Save and load

```dart
final logic = controller.exportLogic();   // what the graph does
final design = controller.exportDesign(); // how it looks
await File('graph.logic.json').writeAsString(logic.toJsonString());
await File('graph.design.json').writeAsString(design.toJsonString());

controller.load(
  LogicDocument.fromJsonString(logicText),
  DesignDocument.fromJsonString(designText), // optional: auto layout without it
);
```

See [Serialization](serialization.md) and
[Connecting an execution engine](execution-engine.md).

## What next

- Restyle everything: [Theming and customization](theming-and-customization.md)
- Big graphs: [Performance guide](performance.md)
- Reusable functions: [Super nodes](super-nodes.md)
