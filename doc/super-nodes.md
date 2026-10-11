# Super nodes (functions)

A super node packs a selection of nodes into a reusable **function**: one node
on the canvas whose ports are the links that crossed the selection boundary.

## Create

Select nodes and press **Ctrl/⌘ + G** (or the toolbar / menu action, or
`controller.groupSelection(name: 'Denoise')`):

1. The selected nodes move into a new `SuperNodeDefinition` (its interior
   graph).
2. Every link entering the selection becomes an exposed **input**; every link
   leaving it becomes an exposed **output**. Several links into the same inner
   port share one input.
3. Two proxy nodes are added inside: **Inputs** (outputs = exposed inputs) and
   **Outputs** (inputs = exposed outputs).
4. An instance (`type: 'super:<id>'`) replaces the selection and the outer
   links are reconnected to its ports.

This is one undo step, and the definition is registered in the
`NodeRegistry`, so it appears in the palette under **Functions** and can be
added again like any node.

## Open, edit, leave

Double click the instance (or **Open function** in its menu,
`controller.enterSuperNode(id)`) to edit the interior. The breadcrumb
(`SuperNodeBreadcrumb`) shows `Root › Denoise` and leads back
(`controller.exitSuperNode()`, Alt+Backspace).

All instances share the definition: editing the interior updates every
instance. **Make unique copy** (`controller.superNodes.detach(controller, id)`)
gives one instance its own private copy.

## Parameters: exposed or fixed

Open the instance edit dialog → **Function**. Every parameter of every inner
node is listed:

- **checked**: becomes a parameter of the function, editable on each instance
  (inline when the node is dynamic) with the inner value as default;
- **unchecked**: stays fixed at its inner value.

From code:

```dart
final def = controller.superNodes.definitionOf(instance.type)!;
controller.superNodes.setExposedParams(controller, def, [
  ParamBinding(name: 'sigma', label: 'Blur sigma', node: blurId, param: 'sigma'),
]);
controller.setParam(instance.id, 'sigma', 2.5);
```

## Ungroup

**Ungroup** (Ctrl/⌘ + Shift + G, `controller.ungroupSelection()`) replaces an
instance by a copy of its interior, applying the instance's exposed parameter
values and reconnecting the outer links.

## Save and reuse

Definitions used by a graph are saved inside its logic and design files.
To build a library of functions across projects:

```dart
final json = controller.superNodes.exportLibrary();          // all definitions
final some = controller.superNodes.exportLibrary([defA, defB]);
await File('functions.json').writeAsString(json);

final ids = otherController.superNodes.importLibrary(json);  // adds to the palette
```

Copy / paste of an instance carries its definition (and nested ones), even
between two editors.

## Execution

Execution engines usually want primitive nodes only:

```dart
final flat = controller.exportLogic().flatten();
```

`flatten()` inlines every instance recursively, applies exposed parameter
values, removes the proxies and rewires the links. Inner node ids become
`<instanceId>/<innerId>` so results can be traced back to the instance. See
[Connecting an execution engine](execution-engine.md).
