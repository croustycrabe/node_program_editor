# Nodes and ports

## NodeDefinition

```dart
NodeDefinition(
  type: 'http.request',            // unique id, stored in the logic file
  title: 'HTTP Request',
  category: 'Actions',             // palette section
  description: 'Calls a REST API.',
  icon: Icons.http,
  tags: ['rest', 'api'],           // extra palette search keywords
  ports: [...],
  params: [...],
  variant: NodeVariant.dynamic,    // static | dynamic
  defaultSize: Size(240, 150),     // null = computed from ports / params
  minSize: Size(120, 60),
  maxSize: Size(2000, 2000),
  resizable: true,
  deletable: true,
  copyable: true,
  showMenu: null,                  // null = NodeEditorConfig.showNodeMenu
  style: NodeStyle(headerColor: Color(0xFF16A34A)),
  portLayout: PortLayout(headerHeight: 36, rowHeight: 24, padding: 8, paramRowHeight: 40),
  builder: null,                   // custom body (see below)
  portBuilder: null,               // custom port visual
)
```

### Static and dynamic nodes

- `NodeVariant.static`: colored header (icon, title, run status), port labels,
  and the description (or `node.data['text']`) as body.
- `NodeVariant.dynamic`: the same header and labels, plus a compact inline
  editor for every parameter whose `ParamSpec.showInNode` is true.

Both layouts respond to the node size: labels hide when the node is narrow,
the body hides when only the header fits, text ellipsizes. Users can resize
nodes within `minSize` / `maxSize`. The minimum height automatically grows to
fit the ports.

### Custom node bodies

`builder` replaces the body. The frame (selection outline, ports at their
anchors, resize handle, lock badge) is still drawn around it, so links always
attach correctly.

```dart
NodeDefinition(
  type: 'scope',
  title: 'Scope',
  ports: const [PortSpec.input('ch1', type: PortType.signal)],
  defaultSize: const Size(320, 220),
  builder: (context, node) => DefaultNodeBody(
    node: node.node,                // keep the header and port labels
    content: MyPlot(data: results[node.node.id]),
  ),
)
```

`NodeRenderContext` gives you `node`, `definition`, `selected`, `zoom`,
`size`, `param(name)`, `setParam(name, value)` (undoable), `ports`, `locked`
and the `controller`. Wrap interactive widgets that handle drags themselves in
`NoNodeDrag` so dragging them does not move the node.

To restyle every node at once, pass `NodeCanvas(nodeBuilder: ...)` (or
`NodeEditor(nodeBuilder: ...)`) and return a `NodeWidget` or your own widget.

### Instances

```dart
final n = controller.addNode('http.request',
    position: const Offset(100, 40), params: {'url': 'https://…'}, title: 'Fetch');
n.id; n.type; n.position; n.size; n.locked; n.params; n.style; n.title;
n.data;     // saved, JSON-serializable payload of your app
n.runtime;  // transient (status, previews); never saved
```

Change instances through the controller (`moveNodes`, `setNodeRect`,
`setParams`, `setLocked`, `setNodeAppearanceOf`, `setCustomPorts`,
`setNodeDataOf`) so changes are undoable and visible.

## Ports

```dart
const PortSpec.input('in',
  label: 'image',
  type: imageType,
  maxLinks: 1,                  // default 1 for inputs, -1 (unlimited) for outputs
  side: PortSide.left,          // default left for inputs, right for outputs
  alignment: null,              // 0..1 along the side; null = automatic
  style: PortStyle(shape: PortShape.diamond, size: 14, color: Colors.teal),
  tooltip: 'Gray or RGB image',
);
```

### Placement

Ports without `alignment` are placed automatically:

- left / right sides: stacked under the header, one `PortLayout.rowHeight`
  apart (spread evenly when they do not fit);
- top / bottom sides: spread evenly.

Use `alignment` for exact placement (for example `side: PortSide.top,
alignment: 0.5`). Anchors are computed from the model by `PortGeometry`, so
the edge renderer, hit testing, the low-detail renderer and your widgets
always agree.

### Types and compatibility

```dart
const tensor = PortType('tensor', color: Colors.deepOrange, compatibleWith: {'image'});
```

A link is valid when the target type `accepts` the source type: same name,
listed in `compatibleWith`, or either side is `PortType.any`. Built-ins:
`any`, `exec`, `number` (accepts `int`, `bool`), `int`, `bool`, `string`,
`image`, `signal` (accepts `number`), `json`, `array`. Register custom types
with `NodeRegistry(portTypes: [...])` so files resolve them by name.

### Validation

`ConnectionValidator` runs on every link attempt:

```dart
controller.validator = ConnectionValidator(
  allowSelfLinks: false,
  allowCycles: false,          // dataflow engines usually want a DAG
  replaceWhenFull: true,       // dropping on a full maxLinks=1 input replaces the link
  custom: (r) => !(r.sourcePort.type == PortType.exec && r.target.node == r.source.node),
);
```

While a link is dragged, compatible ports get a ring, incompatible ones dim,
and the snapped target turns green (valid) or red (rejected, e.g. full).

### Per-instance ports

Some nodes need a variable number of ports (switch cases, merge inputs). Add
them to one instance with `customPorts`:

```dart
controller.setCustomPorts(node.id, [
  ...node.customPorts,
  const PortSpec.input('in3', label: 'Input 3', type: itemType),
]);
```

Edges attached to removed ports are deleted in the same undo step. Custom
ports are saved in the logic file.

### Custom port visuals

```dart
NodeDefinition(
  ...,
  portBuilder: (context, p) => Icon(
    p.port.isInput ? Icons.arrow_right : Icons.arrow_right_alt,
    size: p.size + 6,
    color: p.state == PortVisualState.hoverValid ? Colors.green : p.port.type.color,
  ),
)
```

`PortRenderContext` exposes `node`, `port`, `state` (`idle`, `source`,
`compatible`, `incompatible`, `hoverValid`, `hoverInvalid`), `connected`,
`size` and `theme`.
