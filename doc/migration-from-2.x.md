# Migrating from 2.x

3.0 is a rewrite. The API, the widgets and the file format changed; 2.x JSON
files are not read by 3.0.

| 2.x | 3.0 |
|---|---|
| `EditorCanvas(controller: EditorController())` | `NodeEditor(controller: NodeEditorController(registry: ...))` or `NodeCanvas` |
| `EditorController.saveToJson()` / `loadFromJson()` | `controller.exportLogic()` + `exportDesign()` / `controller.load(logic, design)` |
| `NodeData(portColor, selectedPortColor, inputPorts, outputPorts, ...)` (positional) | `NodeDefinition(type:, title:, ports:, params:, style:, ...)` registered in a `NodeRegistry` |
| Dragging a `NodeData` onto the canvas | `NodePalette`, or `Draggable<NodeDragData>(data: NodeDragData('type'))` |
| `Port(id: int, maxLinks:, label:)` | `PortSpec.input('id', label:, type:, maxLinks:)` / `PortSpec.output(...)`. Ids are strings, ports are typed. |
| `Connection(fromNodeId, fromPortId, toNodeId, toPortId)` | `Edge(source: PortRef(node, port), target: PortRef(node, port), style:)` |
| int node / connection ids | `NodeId` / `EdgeId` (strings, collision resistant) |
| Ctrl+C / Ctrl+V / Delete | same shortcuts, plus undo / redo, select all, group, lock, nudge, zoom… |
| `auto_size_text` dependency | none (zero dependencies) |

## Steps

1. Raise the SDK constraints: Dart `^3.13.0`, Flutter `>=3.47.0`.
2. Turn every `NodeData` into a `NodeDefinition`:

   ```dart
   // 2.x
   NodeData(Colors.blue, Colors.orange, [Port(id: 1, label: 'in')],
       [Port(id: 2, label: 'out')], Colors.orange, 'Blur', 'Filter',
       Icons.blur_on, Colors.blue);

   // 3.0
   const NodeDefinition(
     type: 'filter.blur',
     title: 'Blur',
     category: 'Filter',
     icon: Icons.blur_on,
     style: NodeStyle(headerColor: Colors.blue),
     ports: [PortSpec.input('in', label: 'in'), PortSpec.output('out', label: 'out')],
   );
   ```

3. Replace `EditorCanvas` with `NodeEditor` (or `NodeCanvas` + panels) and
   keep the controller in your `State`.
4. Replace your save / load calls with the logic / design documents.
5. Convert old files once with a small script: for each 2.x node, create a
   `LogicNode(type: <your new type>, ...)` and a `NodeDesign(position: ...)`,
   for each connection a `LogicEdge`, then save the two documents.

Features removed in 2.0 (node edit pane, minimap, resize, link colors, click
to link) are back in 3.0, together with super nodes, typed ports, parameters,
edge styles and the performance work described in the
[architecture](architecture.md).
