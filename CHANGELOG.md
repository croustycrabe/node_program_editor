## 3.0.0

A complete rewrite: "React Flow for Flutter". Not compatible with 2.x (see
`doc/migration-from-2.x.md`).

#### Engine
- `NodeEditorController`: single source of truth with fine-grained
  listenables, batching, undo / redo with transactions and merging.
- Model: `NodeDefinition` / `NodeRegistry`, `NodeInstance`, typed ports
  (`PortType`, `maxLinks`, sides, alignment), `Edge` / `EdgeStyle`, `Graph`
  with O(1) adjacency, `ConnectionValidator` (types, limits, cycles, custom).
- `SpatialHashGrid` for culling, hit testing and selection.
- Model-driven port anchors (`PortGeometry`): links never drift.

#### Rendering
- Grid and animated links on GPU fragment shaders (`shaders/*.frag`) with CPU
  fallbacks.
- Node layer with viewport culling and a persistent transform layer: pan and
  zoom without rebuild, relayout or repaint.
- Level-of-detail renderer: zoomed out, all nodes in one `drawVertices` call
  and edges in batched line draws.

#### Features
- Built-in static and dynamic node bodies, custom node / port builders,
  resize with min / max size, lock, run status badges.
- 25 parameter types with editors, validation and JSON codecs.
- Edge routing: straight, bezier, step, smooth step, orthogonal, polyline,
  custom; markers, dashes, labels, animation; draggable waypoints.
- Node palette, minimap, toolbar (align, distribute, auto layout), overlay and
  context menus, node and edge edit dialogs, keyboard shortcuts.
- Multi-selection, selection box, copy / cut / paste / duplicate through the
  system clipboard.
- Super nodes: group, open, exposed / fixed parameters, ungroup, detach,
  libraries; `LogicDocument.flatten()`.
- Separate logic and design files, automatic layout on import, lenient
  parsing, unknown node types preserved.
- Execution visualization: `setRuntimeData`, `setEdgeRuntime`.

#### Tooling
- Flutter >= 3.47, Dart >= 3.13, zero dependencies.
- Web-first showcase (automation, scientific, computer vision, stress test)
  and full documentation in `doc/`.

## 0.0.1

- Create the package


## 0.0.2

- First Stable

## 1.0.0

- Change usage of json to usage of dart object
- Add object to describe app texts

## 1.0.1

-  Add example code 
  
## 1.1.0

- Add call back function when save config

## 2.0.0

#### Description

The 2.0.0 update is a major update that can be see as a new package.
We rebuild all features of this package from scratch the goal is to have no external dependencies.
All those changes bring some trouble and we where forced to remove some features

2.0.0 is a migration an incomplete version but I really need the update for a personal project.

#### Remove from 1.0.0

- Pre-build node input
- Node modification pane
- Mini map
- Click to link
- To program
- Resize node
- Link type colors
  
#### New features

- Drag to link
- keyboard shortcut to copy, past, delete
  
## 2.1.0

- Fix graph to and from json