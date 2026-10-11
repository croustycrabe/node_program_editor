# Menus and edit dialogs

## Node overlay menu

When exactly one node is selected, a floating menu appears above it:

- **Edit**: opens the edit dialog
- **Open function**: super nodes only
- **Copy** and **Duplicate**
- **Lock / Unlock**: a locked node cannot be moved, resized, deleted or edited
- **Group into function**: with several nodes selected
- **Ungroup** and **Make unique copy**: super nodes only
- your actions
- **Delete**

Right clicking a node shows the same actions as a context menu.

```dart
NodeEditor(
  controller: controller,
  nodeMenuActions: [
    NodeMenuAction(
      icon: Icons.play_arrow,
      label: 'Run from here',
      isVisible: (node) => node.definition.category != 'Display',
      onSelected: (controller, node) => engine.runFrom(node.id),
    ),
  ],
)
```

Hide it globally with `NodeEditorConfig(showNodeMenu: false)` or per
definition with `NodeDefinition(showMenu: false)`.

## Node edit dialog

Opened by double tap, the **Edit** action or `controller.editNodeHandler?.call(id)`:

- title override;
- every parameter, grouped by `ParamSpec.group`, with descriptions and
  validation (Apply is disabled while a value is invalid);
- appearance: header and body colors;
- for super nodes, the function name and the exposed inner parameters.

All changes are applied as **one undo step**. Replace the dialog with your own
inspector:

```dart
NodeCanvas(
  controller: controller,
  onEditNode: (context, id) => openInspector(controller.graph.node(id)!),
)
```

Or open the built-in one from anywhere: `showNodeEditDialog(context, controller, id)`.

## Edge menu and dialog

Tapping a link shows **Edit link**, **Animate / Stop animation**, your
`EdgeMenuAction`s and **Delete link**. The edit dialog
(`showEdgeEditDialog`, or `NodeCanvas.onEditEdge` to replace it) edits routing,
curvature / corner radius, color, width, dash style, markers, animation, label
and waypoints with a live preview, recorded as one undo step.

## Canvas context menu

A right click on empty canvas opens a menu. The default entries
(`CanvasMenuAction.defaults`) are **Add node…** (searchable list, the node is
placed where you clicked), **Paste here**, **Select all**, **Fit view**,
**Auto layout**, **Undo** and **Leave function** (inside a function).

Choose the entries:

```dart
NodeEditor(
  controller: controller,
  canvasMenuActions: [
    CanvasMenuAction(
      icon: Icons.play_arrow,
      label: 'Run',
      isEnabled: (c) => c.graph.nodeCount > 0,
      onSelected: (context, c, canvasPos) => engine.run(c.exportLogic()),
    ),
    CanvasMenuAction.addNode,
    CanvasMenuAction.paste,
  ],
)
```

An empty list disables the menu. To show something completely different,
set `controller.onCanvasContextMenu = (canvasPos, globalPos) { ... }`; it
replaces the menu. `showCanvasContextMenu(...)` and `showQuickAddDialog(...)`
are public if you want to open them yourself.

### Browser context menu (web)

On the web, the browser shows its own menu on right click, on top of the
editor's. `NodeCanvas` / `NodeEditor` disable it while they are mounted
(`disableBrowserContextMenu: true`, the default) and restore it when the last
canvas is disposed. Note that this applies to the whole page while the editor
is shown, including the native copy / paste menu of text fields. Pass
`false` to keep the browser menu.
