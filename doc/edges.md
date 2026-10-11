# Edges

An `Edge` links an output port (`source`) to an input port (`target`):

```dart
final e = controller.connect(PortRef(a.id, 'out'), PortRef(b.id, 'in'),
    style: const EdgeStyle(pathType: EdgePathType.step), label: 'frames');
```

Port order does not matter; the validator normalizes it and returns `null`
when the link is rejected (`controller.canConnect(...)` tells you why).

## Style

```dart
const EdgeStyle(
  pathType: EdgePathType.smoothStep,
  color: null,                    // null = source port type color (or theme)
  width: 2.5,
  dashPattern: [8, 6],            // null = solid
  startMarker: EdgeMarker.none,
  endMarker: EdgeMarker.arrowClosed,   // none, arrow, arrowClosed, circle, diamond
  animated: false,                // flowing pulses (edge_flow.frag)
  curvature: 0.5,                 // bezier
  cornerRadius: 8,                // smoothStep / orthogonal
  customPath: null,               // name of a registered EdgePathBuilder
  labelColor: null, labelBackground: null, labelFontSize: null,
)
```

New links use `CanvasSettings.defaultEdgeStyle`.

| `EdgePathType` | Description |
|---|---|
| `straight` | One segment. |
| `bezier` | Cubic curve leaving and entering along the port sides. |
| `step` | Orthogonal segments, sharp corners. |
| `smoothStep` | Orthogonal segments, rounded corners. |
| `orthogonal` | Orthogonal route through user waypoints. |
| `polyline` | Straight segments through user waypoints. |
| `custom` | Your `EdgePathBuilder`. |

## Waypoints (draw.io style)

Select a link to show its handles:

- drag a **"+"** handle to insert a waypoint (curved links become
  `polyline`, stepped links become `orthogonal`);
- drag a waypoint to move it (snapped to the grid when
  `CanvasSettings.snapEdgesToGrid` is on);
- double tap a waypoint to remove it.

From code: `controller.updateEdge(id, (e) => e.copyWith(waypoints: [...]))`.

## Editing

Tapping a link selects it and shows the edge menu (edit, animate, delete +
your `EdgeMenuAction`s). Right click opens the same actions as a context
menu. Double tap or **Edit** opens the style dialog: routing, curvature /
corner radius, color, width, dashes, markers, animation, label, clear
waypoints. The dialog previews changes live and records them as one undo
step (Cancel reverts).

```dart
controller.updateEdge(id, (e) => e.copyWith(
  label: 'raw',
  style: e.style.copyWith(color: Colors.orange, endMarker: EdgeMarker.arrow),
));
```

## Custom routing

```dart
controller.registerEdgePathBuilder('arc', (input) {
  final s = input.source, t = input.target;
  final mid = Offset((s.dx + t.dx) / 2, math.min(s.dy, t.dy) - 80);
  final path = Path()
    ..moveTo(s.dx, s.dy)
    ..quadraticBezierTo(mid.dx, mid.dy, t.dx, t.dy);
  final pts = [for (var i = 0; i <= 16; i++) _quad(s, mid, t, i / 16)];
  return EdgeGeometry(path, pts);   // polyline used for hit testing and labels
});

controller.updateEdge(id, (e) => e.copyWith(
    style: e.style.copyWith(pathType: EdgePathType.custom, customPath: 'arc')));
```

`EdgePathInput` gives `source`, `sourceSide`, `target`, `targetSide`, `style`
and `waypoints`. The built-in algorithms are available as `EdgeRouter.route`,
`EdgeRouter.bezier`, `EdgeRouter.stepPoints`,
`EdgeRouter.roundedPolylinePath`...

## Execution visualization

To show a run without changing the document or the history:

```dart
controller.setEdgeRuntime(edge.id, const EdgeRuntimeState(
  animated: true, color: Color(0xFF12B76A), label: '42 items'));
controller.setRuntimeData(node.id, {'status': 'success', 'statusText': '42 items · 120 ms'});
...
controller.clearRuntime();
```

Node statuses `running`, `success`, `warning` and `error` show a badge in the
built-in header.
