# Connecting an execution engine

The editor does not run graphs: it produces a **logic file** that your engine
executes, in Dart, in another isolate, on a server, in Rust, Python or C++.

## 1. Get a flat logic document

```dart
final logic = controller.exportLogic().flatten();
```

`flatten()` removes super nodes (see [Super nodes](super-nodes.md)), so the
engine only sees your node types.

## 2. Evaluate

A typical dataflow engine walks the nodes in topological order:

```dart
final incoming = {for (final e in logic.edges) e.target: e.source};
final values = <PortRef, Object>{};

for (final node in topologicalOrder(logic)) {
  Object? input(String port) => values[incoming[PortRef(node.id, port)]];
  final def = controller.registry[node.type]!;
  T param<T>(String name) => def.param(name)!.type.decodeAny(node.params[name]) as T;

  switch (node.type) {
    case 'math.gain':
      values[PortRef(node.id, 'out')] = (input('in') as double) * param<double>('k');
    // ...
  }
}
```

If the graph lives in the editor, `controller.graph.topologicalOrder()` gives
the order directly. Decode parameter values with the definition's
`ParamType.decodeAny`, or read the raw JSON on a non-Dart backend.

For event / workflow engines (n8n style), start from trigger nodes and follow
outgoing links port by port, as the automation showcase does.

## 3. Run automatically

```dart
Timer? debounce;
controller.revision.addListener(() {
  debounce?.cancel();
  debounce = Timer(const Duration(milliseconds: 40), () => engine.run(controller.exportLogic().flatten()));
});
```

`revision` changes on every document change (not on selection, viewport or
runtime state).

## 4. Show results

Use runtime state. It is not saved, not undoable, and only repaints what
changed.

```dart
controller.setRuntimeData(nodeId, {
  'status': 'running',            // running | success | warning | error
  'statusText': 'Waiting for camera…',
  'preview': uiImage,             // anything your custom body reads
});
controller.setEdgeRuntime(edgeId, const EdgeRuntimeState(
    animated: true, color: Colors.green, label: '12 items'));
controller.clearRuntime();
```

For a flattened document, map ids back with `id.value.split('/').first`
(the top-level instance).

For rich results (plots, images, tables), give the node a custom body that
listens to your engine:

```dart
NodeDefinition(
  type: 'scope',
  title: 'Scope',
  ports: const [PortSpec.input('in', type: PortType.signal)],
  builder: (context, rc) => DefaultNodeBody(
    node: rc.node,
    content: ListenableBuilder(
      listenable: engine,
      builder: (_, _) => Plot(engine.results[rc.node.id]),
    ),
  ),
)
```

## 5. Actions from nodes

`TriggerParam` buttons ("Capture", "Calibrate", "Export") call
`NodeEditorServices.onTrigger(nodeId, paramName)`.

The showcase contains three complete examples: a workflow runner
(`example/lib/automation`), a signal-processing engine
(`example/lib/scientific/sci_engine.dart`) and an image pipeline
(`example/lib/vision/vision_engine.dart`).
