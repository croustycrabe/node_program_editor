# Node palette

`NodePalette` lists every registered definition grouped by category.

```dart
NodePalette(
  controller: controller,
  mode: NodePaletteMode.both,        // click, drag or both
  layout: NodePaletteLayout.list,    // list, grid or compact
  showSearch: true,
  showFilters: true,                 // category chips + port type filter
  title: 'Nodes',
  filter: (def) => !def.tags.contains('hidden'),
  categoryOrder: ['Triggers', 'Actions', 'Flow'],
  initiallyCollapsed: {'Advanced'},
  itemBuilder: null,                 // custom item (tap / drag still handled)
  headerBuilder: null,               // custom category header
)
```

- **Click** adds the node at the center of the viewport (successive clicks
  cascade so nodes do not stack).
- **Drag** drops the node where it is released. Items drag horizontally, so
  the list still scrolls vertically on touch screens.
- **Search** matches title, tags, category, description, and subsequences
  ("gblur" finds "Gaussian blur"), best matches first.
- The palette listens to the registry: definitions registered later (for
  example super nodes, under "Functions") appear immediately. Categories
  starting with `__` are hidden.

Custom item:

```dart
NodePalette(
  controller: controller,
  layout: NodePaletteLayout.grid,
  itemBuilder: (context, def) => Card(
    child: ListTile(leading: Icon(def.icon), title: Text(def.title)),
  ),
)
```

Your own drag source works too:

```dart
Draggable<NodeDragData>(
  data: const NodeDragData('http.request', params: {'method': 'POST'}),
  feedback: const Material(child: Text('HTTP Request')),
  child: const Text('POST request'),
)
```
