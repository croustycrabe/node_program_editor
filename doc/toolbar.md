# Toolbar

```dart
NodeToolbar(
  controller: controller,
  onSave: (c) => save(c.exportLogic(), c.exportDesign()),
  axis: Axis.horizontal,
  showSelectionItems: true,
  customItems: [
    const ToolbarDivider(),
    ToolbarItem(
      icon: Icons.play_arrow,
      tooltip: 'Run',
      onPressed: (c) => engine.run(c.exportLogic()),
      isEnabled: (c) => c.graph.nodeCount > 0,
    ),
    ToolbarItem(
      icon: Icons.cleaning_services,
      tooltip: 'Clear run results',
      onPressed: (c) => c.clearRuntime(),
    ),
  ],
)
```

Default items:

| Group | Items |
|---|---|
| History | undo, redo (enabled from `controller.history`) |
| File | save (only when `onSave` is given) |
| View | zoom in, zoom out, fit view, auto layout (`controller.autoLayout()`; selection only when 2+ nodes are selected) |
| Canvas | show grid, cycle grid style, snap to grid, selection mode (`PanOnDrag`) |
| Selection (only when something is selected) | delete, copy, duplicate, lock / unlock, group into function, align left / centers / top / middles (2+ nodes), distribute horizontally / vertically (3+ nodes) |

`items:` replaces the defaults entirely (you can start from
`NodeToolbar.defaultItems(onSave: ...)` and edit the list). `ToolbarItem`
supports `isEnabled`, `isActive` (toggle highlight) and `isVisible`;
`ToolbarDivider` supports `isVisible`. The toolbar rebuilds when the history,
selection, canvas settings, config or scope change.

`SuperNodeBreadcrumb(controller: controller)` is the companion widget that
shows `Root › Function › …` while editing super nodes.
