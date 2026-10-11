# Parameters

A parameter is declared with a `ParamSpec` on the node definition:

```dart
const ParamSpec(
  'sigma',                       // key in node.params
  DoubleParam(min: 0, max: 6, slider: true, unit: 'px'),
  label: 'Sigma',
  description: 'Standard deviation of the Gaussian kernel.',
  group: 'Filter',               // section in the edit dialog
  showInNode: true,              // inline editor in dynamic nodes
  readOnly: false,
  defaultValue: 1.5,             // overrides the type default
)
```

Each `ParamType` provides a default value, a JSON codec (`encode` / `decode`),
validation and normalization (clamping). Values are normalized when set
through the controller, validated in the edit dialog, and encoded in the logic
file.

## Built-in types

| Type | Value | Editor | Typical use |
|---|---|---|---|
| `IntParam(min, max, step, slider, unit)` | `int` | number field (↑/↓ step) or slider | counts, kernel size |
| `DoubleParam(min, max, step, precision, slider, unit)` | `double` | number field or slider | gains, thresholds |
| `BoolParam()` | `bool` | switch | flags |
| `TextParam(hint, maxLength, pattern)` | `String` | text field | names, URLs |
| `MultilineTextParam(lines)` | `String` | multi-line field | messages |
| `PasswordParam()` | `String` | obscured field | API keys |
| `CodeParam(language, lines)` | `String` | monospace editor | scripts, SQL, GLSL |
| `ExpressionParam(variables)` | `String` | monospace single line | `a*sin(t)+b` |
| `EnumParam(options, segmented)` / `EnumParam.values([...])` | `String` | dropdown / segmented | modes |
| `MultiSelectParam(options)` | `List<String>` | filter chips | options |
| `ListParam(itemType, minItems, maxItems)` | `List<Object?>` | typed list with add / reorder / delete | rules, waypoints |
| `TableParam(columns)` | `List<Map>` | typed grid | HTTP headers, calibration tables |
| `JsonParam()` | JSON | validated JSON editor | request bodies |
| `QuantityParam(units, min, max)` | `Quantity` | number + unit dropdown | exposure 10 ms |
| `RangeParam(min, max, step)` | `RangeValue` | range slider + fields | hysteresis, band-pass |
| `VectorParam(dimension, labels)` | `List<double>` | N fields | PID gains, RGB weights |
| `MatrixParam(rows, cols, resizable)` | `Matrix` | grid (resizable) | convolution kernels, homographies |
| `CurveParam(minX, maxX, minY, maxY)` / `CurveParam.lut()` | `List<Offset>` | interactive curve editor | tone curves, LUTs |
| `ColorParam(alpha)` | `Color` | swatch + HSV picker | display colors |
| `ImageParam(accept)` | `ImageRef?` | thumbnail + picker | reference images |
| `RoiParam(frame, rotatable, shapes)` | `Roi` | drag-to-edit region over a frame + fields | AOI, inspection zones |
| `PointParam(bounds)` | `Offset` | x / y fields | seed points |
| `FilePathParam(extensions, mode)` | `String` | field + browse | model files |
| `DateTimeParam(mode)` | `DateTime` | date / time pickers | schedules |
| `TriggerParam(buttonLabel)` | — | button | Capture, Calibrate, Export |
| `ColorMapParam()` | `String` | gradient dropdown | gray, jet, viridis, magma, hot, cool |

Helpers: `CurveParam.evaluate(points, x)`, `ColorMapParam.sample(name, t)`,
`Matrix.identity(n)`, `Matrix.withValue`, `Matrix.resized`.

## Host services

The package performs no I/O. File, image and trigger parameters call the host
through `NodeEditorServices`:

```dart
NodeEditor(
  controller: controller,
  services: NodeEditorServices(
    pickFile: (context, param) async => await myFilePicker(param.extensions),
    pickImage: (context, param) async {
      final bytes = await myImagePicker();
      return bytes == null ? null : ImageRef(bytes: bytes, name: 'photo.png');
    },
    onTrigger: (nodeId, paramName) => engine.trigger(nodeId, paramName),
    imageProvider: (ref) => ref.uri == null ? null : FileImage(File(ref.uri!)),
  ),
)
```

`ImageRef` stores either `bytes` (base64 in JSON) or a `uri` that your
`imageProvider` resolves (defaults: memory bytes, `asset:path`, `http(s)://`).

## Custom parameter types

```dart
class IpAddressParam extends TextParam {
  const IpAddressParam() : super(pattern: r'(\d{1,3}\.){3}\d{1,3}', defaultValue: '192.168.0.1');
  @override
  String get id => 'ip';
}

// Optional dedicated editor (otherwise the TextParam editor is used):
ParamEditorRegistry.register('ip', (context, ctx) => MyIpField(
  value: ctx.value as String,
  onChanged: ctx.onChanged,
  compact: ctx.compact,     // true inside nodes
));
```

For a brand new value type, extend `ParamType<T>` and implement `id`,
`defaultValue`, `encode`, `decode` (and optionally `validate` / `normalize`).

## Editing from code

```dart
controller.setParam(node.id, 'sigma', 2.0);           // one key
controller.setParams(node.id, {'a': 1, 'b': 2});      // several keys, one undo step
```

Consecutive edits of the same keys within 800 ms (typing) merge into one undo
step.

## Reusing the editors

`ParamEditor(ParamEditorContext(...))`, `ParamField` (label + description +
error), `InlineParamEditor(node:, spec:)`, `NumberField`, `CurveEditor`,
`RoiEditor`, `HsvColorPicker` and `showColorPickerDialog` are public, so
inspector panels outside the canvas can use the same widgets.
