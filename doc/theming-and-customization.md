# Theming and customization

## Theme

`NodeEditorThemeData` is a `ThemeExtension`. Register it on your app theme
(or pass `theme:` to the widgets):

```dart
MaterialApp(
  theme: ThemeData(extensions: [
    NodeEditorThemeData.light().copyWith(
      nodeHeaderColor: const Color(0xFF0F766E),
      nodeRadius: 6,
      edgeWidth: 2.5,
      colorEdgesByType: false,
      edgeColor: Colors.blueGrey,
      portShape: PortShape.square,
    ),
  ]),
  darkTheme: ThemeData(brightness: Brightness.dark, extensions: [NodeEditorThemeData.dark()]),
)
```

Without an extension, `NodeEditorThemeData.of(context)` picks the light or
dark default from the ambient brightness.

| Area | Properties |
|---|---|
| Canvas | `backgroundColor`, `gridColor`, `majorGridColor`, `gridThickness` |
| Nodes | `nodeColor`, `nodeHeaderColor`, `nodeBorderColor`, `nodeBorderWidth`, `nodeRadius`, `nodeShadow`, `selectedBorderColor`, `selectedBorderWidth`, `lockedColor`, `titleStyle`, `bodyStyle` |
| Ports | `portSize`, `portShape`, `portBorderColor`, `portLabelStyle`, `validTargetColor`, `invalidTargetColor` |
| Edges | `edgeColor`, `edgeWidth`, `selectedEdgeColor`, `colorEdgesByType`, `edgeLabelStyle`, `edgeLabelBackground`, `connectionColor` |
| Selection | `marqueeFill`, `marqueeBorder` |
| Minimap | `minimapBackground`, `minimapNodeColor`, `minimapViewportColor`, `minimapMaskColor` |
| Panels | `panelColor`, `panelBorderColor`, `panelForeground`, `accentColor` |

Color precedence for a node: `NodeInstance.style` → `NodeDefinition.style`
→ theme (`resolveNodeColors(node, theme)` returns the result, also used by
the low-detail renderer and the minimap). Users can change the header and body
colors of one node in its edit dialog.

## Customization levels

From lightest to deepest:

1. **Definition style**: `NodeDefinition(style: NodeStyle(...), icon: ...)`,
   `PortSpec(style: PortStyle(shape:, size:, color:))`.
2. **Port placement**: `PortSpec(side:, alignment:)` and
   `NodeDefinition(portLayout: PortLayout(...))`.
3. **Custom body per type**: `NodeDefinition(builder: ...)`, optionally reusing
   `DefaultNodeBody(node:, content:)` to keep the header and labels.
4. **Custom port visual**: `NodeDefinition(portBuilder: ...)` or
   `NodeCanvas(portBuilder: ...)` for all nodes.
5. **Custom node widget for everything**: `NodeCanvas(nodeBuilder: ...)`.
   Return `NodeFrame(node:, selected:, child: ...)` to keep the built-in
   interactions, or build your own on `NodeEditorScope.of(context)`.
6. **Custom edge routing**: `controller.registerEdgePathBuilder(...)`.
7. **Custom parameter editors**: `ParamEditorRegistry.register(...)`.
8. **Custom dialogs / menus / toolbar / palette items**: `onEditNode`,
   `onEditEdge`, `nodeMenuActions`, `edgeMenuActions`, `customToolbarItems`,
   `NodePalette(itemBuilder:)`.
9. **Your own layout**: drop `NodeEditor` and compose `NodeCanvas`,
   `NodePalette`, `NodeToolbar`, `NodeMiniMap`, `SuperNodeBreadcrumb`.

### Example: a compact "LabVIEW" style node

```dart
NodeDefinition(
  type: 'lv.add',
  title: 'Add',
  defaultSize: const Size(64, 64),
  minSize: const Size(48, 48),
  resizable: false,
  ports: const [
    PortSpec.input('x', type: PortType.number, alignment: 0.3),
    PortSpec.input('y', type: PortType.number, alignment: 0.7),
    PortSpec.output('sum', type: PortType.number, alignment: 0.5,
        style: PortStyle(shape: PortShape.triangle)),
  ],
  builder: (context, rc) => Container(
    color: const Color(0xFFFFF59D),
    alignment: Alignment.center,
    child: const Icon(Icons.add, size: 32),
  ),
)
```

## Using the editor scope in your widgets

Inside node bodies and canvas overlays:

```dart
final scope = NodeEditorScope.of(context);
scope.controller;              // the controller
scope.theme;                   // resolved theme
scope.services;                // host services
scope.globalToCanvas(global);  // pointer → canvas coordinates
```

Wrap draggable widgets of node bodies in `NoNodeDrag`.
