# Selection, clipboard and undo

## Selection

```dart
controller.selectNodes([a.id, b.id]);
controller.selectNodes([c.id], additive: true);
controller.selectEdges([e.id]);
controller.toggleNodeSelection(a.id);
controller.selectAll();
controller.clearSelection();

final sel = controller.selection.value;   // GraphSelection
sel.nodes; sel.edges; sel.singleNode; sel.isEmpty;
controller.selection.addListener(updateInspector);
```

Users select by tapping, Ctrl/⌘/Shift + tapping, or drawing a selection box
(Shift + drag, or plain drag with `PanOnDrag.select`). The box selects nodes it
overlaps (or contains, with `marqueeRequiresFullContainment`) and the edges
between them.

Selected nodes move together. Locked nodes in the selection stay in place;
arrow keys nudge the selection (Shift for a larger step).

## Clipboard

| Action | Shortcut | Code |
|---|---|---|
| Copy | Ctrl/⌘ + C | `controller.copySelection()` |
| Cut | Ctrl/⌘ + X | `controller.cutSelection()` |
| Paste | Ctrl/⌘ + V | `await controller.paste()` |
| Duplicate | Ctrl/⌘ + D | `controller.duplicateSelection()` |

Copying captures the selected nodes and the links between them as a
`GraphFragment`. With `NodeEditorConfig.useSystemClipboard` (default) the
fragment is also put on the system clipboard as JSON, so you can paste between
two editors, two windows or two applications. Super node definitions travel
with the fragment. Pasting creates new ids and offsets the copy (or places it
at `paste(at: canvasPoint)`).

```dart
final fragment = GraphFragment.capture(controller.graph, ids);
final json = fragment.toJsonString();
controller.pasteFragment(GraphFragment.tryParse(json)!, at: const Offset(0, 0));
```

## Undo / redo

Every change made through the controller is a `GraphCommand` recorded in
`controller.history` (`HistoryStack`, 200 steps by default):

```dart
controller.undo();
controller.redo();
controller.history.canUndo;
controller.history.undoLabel;   // "Move nodes", "Edit parameters"...
controller.history.clear();     // e.g. after loading a file
```

- A whole drag, resize, waypoint drag or edge dialog session is one step.
- Typing in a parameter field merges into one step.
- Group your own multi-step operations:

```dart
controller.transaction('Insert template', () {
  final a = controller.addNode('source', position: p);
  final b = controller.addNode('sink', position: p + const Offset(260, 0));
  controller.connect(PortRef(a.id, 'out'), PortRef(b.id, 'in'));
});
```

- Write your own commands by extending `GraphCommand` (`apply`, `revert`,
  optional `mergeWith`) and run them with `controller.execute(command)`. Mutate
  through the `GraphMutator` passed to `apply` / `revert`.

Runtime state (`setRuntimeData`, `setEdgeRuntime`) and viewport changes are not
recorded. Each super node scope has its own history.
