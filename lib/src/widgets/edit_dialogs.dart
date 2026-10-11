import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/edge.dart';
import '../core/ids.dart';
import '../core/node.dart';
import '../core/ports.dart';
import '../core/supernode/super_node.dart';
import '../params/param_types.dart';
import 'param_editors.dart';
import 'scope.dart';
import 'theme.dart';

/// Opens the built-in edit dialog of node [id]: title, parameters (grouped,
/// validated), appearance and, for super nodes, the exposed parameters.
/// Changes are applied as one undo step.
Future<void> showNodeEditDialog(
  BuildContext context,
  NodeEditorController controller,
  NodeId id, {
  NodeEditorServices services = const NodeEditorServices(),
  NodeEditorThemeData? theme,
}) async {
  if (controller.graph.node(id) == null) return;
  await showDialog<void>(
    context: context,
    builder: (_) =>
        NodeEditDialog(controller: controller, nodeId: id, services: services),
  );
}

/// The node edit dialog. See [showNodeEditDialog].
class NodeEditDialog extends StatefulWidget {
  /// Creates the dialog.
  const NodeEditDialog({
    super.key,
    required this.controller,
    required this.nodeId,
    this.services = const NodeEditorServices(),
  });

  /// Controller.
  final NodeEditorController controller;

  /// Edited node.
  final NodeId nodeId;

  /// Host services.
  final NodeEditorServices services;

  @override
  State<NodeEditDialog> createState() => _NodeEditDialogState();
}

class _NodeEditDialogState extends State<NodeEditDialog> {
  late final NodeInstance node = widget.controller.graph.node(widget.nodeId)!;
  late final Map<String, Object?> _values = Map.of(node.params);
  late final TextEditingController _title = TextEditingController(
    text: node.title ?? '',
  );
  late Color? _header = node.style?.headerColor;
  late Color? _body = node.style?.color;
  late final SuperNodeDefinition? _super = widget.controller.superNodes
      .definitionOf(node.type);
  late final TextEditingController _superName = TextEditingController(
    text: _super?.name ?? '',
  );
  late final List<ParamBinding> _bindings = [...?_super?.params];

  /// Function edited through this node: the instance's definition, or the
  /// open function when [node] is one of its Inputs / Outputs proxies.
  late final SuperNodeDefinition? _function =
      _super ??
      (SuperNodeLibrary.isProxy(node)
          ? widget.controller.scope.superNode
          : null);
  late List<PortSpec> _inputs = [...?_function?.inputs];
  late List<PortSpec> _outputs = [...?_function?.outputs];

  static String _portsKey(List<PortSpec> ports) =>
      [for (final p in ports) '${p.id}|${p.label}|${p.type.name}'].join(',');

  @override
  void dispose() {
    _title.dispose();
    _superName.dispose();
    super.dispose();
  }

  Map<String, String> get _errors => {
    for (final spec in node.definition.params)
      spec.name: ?spec.type.validateAny(_values[spec.name]),
  };

  void _apply() {
    final c = widget.controller;
    final changed = <String, Object?>{
      for (final e in _values.entries)
        if (!_equals(node.params[e.key], e.value)) e.key: e.value,
    };
    final title = _title.text.trim().isEmpty ? null : _title.text.trim();
    final style = (_header == null && _body == null)
        ? null
        : NodeStyle(headerColor: _header, color: _body);
    c.transaction('Edit ${node.displayTitle}', () {
      if (changed.isNotEmpty) c.setParams(node.id, changed);
      if (title != node.title || style != node.style) {
        c.setNodeAppearanceOf(node.id, style: style, title: title);
      }
    });
    final fn = _function;
    if (fn != null &&
        (_portsKey(_inputs) != _portsKey(fn.inputs) ||
            _portsKey(_outputs) != _portsKey(fn.outputs))) {
      c.superNodes.setInterface(c, fn, inputs: _inputs, outputs: _outputs);
    }
    final def = _super;
    if (def != null) {
      final name = _superName.text.trim();
      final bindingsChanged = !listEquals(
        [for (final b in def.params) '${b.node.value}/${b.param}/${b.name}'],
        [for (final b in _bindings) '${b.node.value}/${b.param}/${b.name}'],
      );
      final renamed = name.isNotEmpty && name != def.name;
      if (renamed) def.name = name;
      if (bindingsChanged || renamed) {
        c.superNodes.setExposedParams(c, def, _bindings);
      }
    }
    Navigator.pop(context);
  }

  static bool _equals(Object? a, Object? b) {
    if (a is List && b is List) return listEquals(a, b);
    if (a is Map && b is Map) return mapEquals(a, b);
    return a == b;
  }

  @override
  Widget build(BuildContext context) {
    final def = node.definition;
    final errors = _errors;
    final groups = <String?, List<ParamSpec>>{};
    for (final p in def.params) {
      (groups[p.group] ??= []).add(p);
    }
    final t = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          if (def.icon != null) ...[Icon(def.icon), const SizedBox(width: 8)],
          Expanded(child: Text('Edit ${def.title}')),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: 'Title',
                  hintText: def.title,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (def.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(def.description!, style: t.textTheme.bodySmall),
                ),
              for (final g in groups.entries) ...[
                if (g.key != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 4),
                    child: Text(g.key!, style: t.textTheme.titleSmall),
                  )
                else
                  const SizedBox(height: 8),
                for (final spec in g.value)
                  ParamField(
                    ParamEditorContext(
                      spec: spec,
                      value: _values[spec.name],
                      enabled: !spec.readOnly && !node.locked,
                      node: node.id,
                      services: widget.services,
                      onChanged: (v) => setState(
                        () => _values[spec.name] = spec.type.normalizeAny(v),
                      ),
                    ),
                    error: errors[spec.name],
                  ),
              ],
              if (_super != null) _superSection(t),
              if (_function != null) _portsSection(t),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Appearance'),
                children: [
                  _colorRow(
                    'Header color',
                    _header,
                    (c) => setState(() => _header = c),
                  ),
                  _colorRow(
                    'Body color',
                    _body,
                    (c) => setState(() => _body = c),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: errors.isEmpty && !node.locked ? _apply : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _colorRow(String label, Color? value, ValueChanged<Color?> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        InkWell(
          onTap: () async {
            final picked = await showColorPickerDialog(
              context,
              value ?? const Color(0xFF3B82F6),
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            width: 40,
            height: 24,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: value,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black26),
            ),
            child: value == null
                ? const Center(
                    child: Text('auto', style: TextStyle(fontSize: 10)),
                  )
                : null,
          ),
        ),
        IconButton(
          tooltip: 'Reset',
          icon: const Icon(Icons.restart_alt, size: 18),
          onPressed: value == null ? null : () => onChanged(null),
        ),
      ],
    );
  }

  Widget _portsSection(ThemeData t) {
    final types = widget.controller.registry.portTypes.toList();
    final proxy = SuperNodeLibrary.isProxy(node);
    final showInputs = !proxy || node.id == _function!.inputProxy;
    final showOutputs = !proxy || node.id == _function!.outputProxy;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: proxy,
      title: const Text('Function ports'),
      subtitle: const Text(
        'Add, rename, retype or remove the inputs and outputs of the '
        'function. Links to removed ports are deleted.',
      ),
      children: [
        if (showInputs)
          FunctionPortsEditor(
            title: 'Inputs',
            direction: PortDirection.input,
            ports: _inputs,
            types: types,
            onChanged: (p) => setState(() => _inputs = p),
          ),
        if (showOutputs)
          FunctionPortsEditor(
            title: 'Outputs',
            direction: PortDirection.output,
            ports: _outputs,
            types: types,
            onChanged: (p) => setState(() => _outputs = p),
          ),
      ],
    );
  }

  Widget _superSection(ThemeData t) {
    final def = _super!;
    final candidates = <(NodeInstance, ParamSpec)>[
      for (final n in def.graph.nodes)
        if (!SuperNodeLibrary.isProxy(n))
          for (final p in n.definition.params) (n, p),
    ];
    bool exposed(NodeInstance n, ParamSpec p) =>
        _bindings.any((b) => b.node == n.id && b.param == p.name);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: true,
      title: const Text('Function'),
      subtitle: const Text(
        'Checked parameters become parameters of this function. '
        'Unchecked ones keep their inner (fixed) value.',
      ),
      children: [
        TextField(
          controller: _superName,
          decoration: const InputDecoration(
            labelText: 'Function name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        if (candidates.isEmpty)
          Text(
            'The inner nodes have no parameters.',
            style: t.textTheme.bodySmall,
          ),
        for (final (n, p) in candidates)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('${n.displayTitle} › ${p.label}'),
            value: exposed(n, p),
            onChanged: (on) => setState(() {
              if (on ?? false) {
                var name = p.name;
                var i = 2;
                while (_bindings.any((b) => b.name == name)) {
                  name = '${p.name}$i';
                  i++;
                }
                _bindings.add(
                  ParamBinding(
                    name: name,
                    label: '${n.displayTitle} ${p.label}',
                    node: n.id,
                    param: p.name,
                  ),
                );
              } else {
                _bindings.removeWhere(
                  (b) => b.node == n.id && b.param == p.name,
                );
              }
            }),
          ),
      ],
    );
  }
}

/// Opens the edge style dialog (draw.io-like). Changes are previewed live
/// and recorded as one undo step; Cancel reverts them.
Future<void> showEdgeEditDialog(
  BuildContext context,
  NodeEditorController controller,
  EdgeId id, {
  NodeEditorThemeData? theme,
}) async {
  if (controller.graph.edge(id) == null) return;
  controller.beginTransaction('Edit link');
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => EdgeEditDialog(controller: controller, edgeId: id),
  );
  if (ok ?? false) {
    controller.commitTransaction();
  } else {
    controller.cancelTransaction();
  }
}

/// The edge style dialog. See [showEdgeEditDialog].
class EdgeEditDialog extends StatefulWidget {
  /// Creates the dialog.
  const EdgeEditDialog({
    super.key,
    required this.controller,
    required this.edgeId,
  });

  /// Controller.
  final NodeEditorController controller;

  /// Edited edge.
  final EdgeId edgeId;

  @override
  State<EdgeEditDialog> createState() => _EdgeEditDialogState();
}

class _EdgeEditDialogState extends State<EdgeEditDialog> {
  late final TextEditingController _label = TextEditingController(
    text: widget.controller.graph.edge(widget.edgeId)?.label ?? '',
  );

  static const _palette = [
    Color(0xFF98A2B3),
    Color(0xFF3B82F6),
    Color(0xFF12B76A),
    Color(0xFFF79009),
    Color(0xFFF04438),
    Color(0xFF9E77ED),
    Color(0xFFEE46BC),
    Color(0xFF101828),
  ];

  Edge? get _edge => widget.controller.graph.edge(widget.edgeId);

  void _update(Edge Function(Edge e) f) {
    widget.controller.updateEdge(widget.edgeId, f);
    setState(() {});
  }

  void _style(EdgeStyle Function(EdgeStyle s) f) =>
      _update((e) => e.copyWith(style: f(e.style)));

  /// Rebuilds a style with an explicit (nullable) color.
  static EdgeStyle _withColor(EdgeStyle s, Color? color) => EdgeStyle(
    pathType: s.pathType,
    color: color,
    width: s.width,
    dashPattern: s.dashPattern,
    startMarker: s.startMarker,
    endMarker: s.endMarker,
    animated: s.animated,
    curvature: s.curvature,
    cornerRadius: s.cornerRadius,
    customPath: s.customPath,
    labelColor: s.labelColor,
    labelBackground: s.labelBackground,
    labelFontSize: s.labelFontSize,
  );

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edge = _edge;
    if (edge == null) return const SizedBox.shrink();
    final s = edge.style;
    final t = Theme.of(context);
    final dash = s.dashPattern == null
        ? 'solid'
        : (s.dashPattern!.first <= 3 ? 'dotted' : 'dashed');
    Widget section(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: t.textTheme.labelLarge),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
    DropdownButton<EdgeMarker> marker(
      EdgeMarker v,
      ValueChanged<EdgeMarker> onChanged,
    ) => DropdownButton<EdgeMarker>(
      value: v,
      isDense: true,
      items: [
        for (final m in EdgeMarker.values)
          DropdownMenuItem(value: m, child: Text(m.name)),
      ],
      onChanged: (m) => onChanged(m!),
    );

    return AlertDialog(
      title: const Text('Edit link'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _update(
                  (e) => v.isEmpty
                      ? e.copyWith(clearLabel: true)
                      : e.copyWith(label: v),
                ),
              ),
              section(
                'Routing',
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in EdgePathType.values)
                      if (p != EdgePathType.custom || s.customPath != null)
                        ChoiceChip(
                          label: Text(switch (p) {
                            EdgePathType.straight => 'Straight',
                            EdgePathType.bezier => 'Curved',
                            EdgePathType.smoothStep => 'Rounded angles',
                            EdgePathType.step => 'Angles',
                            EdgePathType.orthogonal => 'Orthogonal',
                            EdgePathType.polyline => 'Polyline',
                            EdgePathType.custom => 'Custom',
                          }),
                          selected: s.pathType == p,
                          onSelected: (_) =>
                              _style((st) => st.copyWith(pathType: p)),
                        ),
                  ],
                ),
              ),
              if (s.pathType == EdgePathType.bezier)
                section(
                  'Curvature',
                  Slider(
                    value: s.curvature.clamp(0.0, 1.5),
                    max: 1.5,
                    onChanged: (v) => _style((st) => st.copyWith(curvature: v)),
                  ),
                ),
              if (s.pathType == EdgePathType.smoothStep ||
                  s.pathType == EdgePathType.orthogonal)
                section(
                  'Corner radius',
                  Slider(
                    value: s.cornerRadius.clamp(0.0, 40.0),
                    max: 40,
                    onChanged: (v) =>
                        _style((st) => st.copyWith(cornerRadius: v)),
                  ),
                ),
              section(
                'Color',
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Auto'),
                      selected: s.color == null,
                      onSelected: (_) => _style((st) => _withColor(st, null)),
                    ),
                    for (final c in _palette)
                      InkWell(
                        onTap: () => _style((st) => _withColor(st, c)),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              width: s.color == c ? 3 : 1,
                              color: s.color == c
                                  ? t.colorScheme.primary
                                  : Colors.black26,
                            ),
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Custom color',
                      icon: const Icon(Icons.colorize, size: 18),
                      onPressed: () async {
                        final picked = await showColorPickerDialog(
                          context,
                          s.color ?? _palette[1],
                        );
                        if (picked != null) {
                          _style((st) => _withColor(st, picked));
                        }
                      },
                    ),
                  ],
                ),
              ),
              section(
                'Width',
                Slider(
                  value: (s.width ?? 2).clamp(0.5, 10.0),
                  min: 0.5,
                  max: 10,
                  divisions: 19,
                  label: '${s.width ?? 2}',
                  onChanged: (v) => _style((st) => st.copyWith(width: v)),
                ),
              ),
              section(
                'Line',
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'solid', label: Text('Solid')),
                    ButtonSegment(value: 'dashed', label: Text('Dashed')),
                    ButtonSegment(value: 'dotted', label: Text('Dotted')),
                  ],
                  selected: {dash},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => _style(
                    (st) => switch (v.first) {
                      'dashed' => st.copyWith(dashPattern: const [8, 6]),
                      'dotted' => st.copyWith(dashPattern: const [2, 4]),
                      _ => st.copyWith(clearDash: true),
                    },
                  ),
                ),
              ),
              section(
                'Markers',
                Row(
                  children: [
                    const Text('Start '),
                    marker(
                      s.startMarker,
                      (m) => _style((st) => st.copyWith(startMarker: m)),
                    ),
                    const Spacer(),
                    const Text('End '),
                    marker(
                      s.endMarker,
                      (m) => _style((st) => st.copyWith(endMarker: m)),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Animated flow'),
                value: s.animated,
                onChanged: (v) => _style((st) => st.copyWith(animated: v)),
              ),
              if (edge.waypoints.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.timeline),
                    label: Text('Clear ${edge.waypoints.length} waypoints'),
                    onPressed: () =>
                        _update((e) => e.copyWith(waypoints: const [])),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: t.colorScheme.error),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete'),
          onPressed: () {
            widget.controller.remove(edges: [widget.edgeId]);
            Navigator.pop(context, true);
          },
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// Editor of a list of function ports (label, type, add, remove). Existing
/// port ids are kept so their links survive renames and type changes.
class FunctionPortsEditor extends StatefulWidget {
  /// Creates the editor.
  const FunctionPortsEditor({
    super.key,
    required this.title,
    required this.direction,
    required this.ports,
    required this.types,
    required this.onChanged,
  });

  /// Section title.
  final String title;

  /// Direction of the ports seen from outside the function.
  final PortDirection direction;

  /// Current ports.
  final List<PortSpec> ports;

  /// Selectable port types.
  final List<PortType> types;

  /// Called with the edited list.
  final ValueChanged<List<PortSpec>> onChanged;

  @override
  State<FunctionPortsEditor> createState() => _FunctionPortsEditorState();
}

class _FunctionPortsEditorState extends State<FunctionPortsEditor> {
  final Map<String, TextEditingController> _labels = {};

  bool get _isInput => widget.direction == PortDirection.input;

  TextEditingController _label(PortSpec p) =>
      _labels.putIfAbsent(p.id, () => TextEditingController(text: p.label));

  @override
  void dispose() {
    for (final c in _labels.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _replace(int i, PortSpec p) =>
      widget.onChanged([...widget.ports]..[i] = p);

  void _add() {
    final prefix = _isInput ? 'in' : 'out';
    final ids = {for (final p in widget.ports) p.id};
    var n = widget.ports.length + 1;
    while (ids.contains('$prefix$n')) {
      n++;
    }
    widget.onChanged([
      ...widget.ports,
      PortSpec(
        id: '$prefix$n',
        direction: widget.direction,
        label: '${_isInput ? 'Input' : 'Output'} $n',
        maxLinks: _isInput ? 1 : -1,
      ),
    ]);
  }

  Widget _typeItem(PortType type) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: type.color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(type.name),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: t.textTheme.labelLarge),
          const SizedBox(height: 4),
          if (widget.ports.isEmpty)
            Text(
              'No ${widget.title.toLowerCase()}.',
              style: t.textTheme.bodySmall,
            ),
          for (var i = 0; i < widget.ports.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _label(widget.ports[i]),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Label',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                          _replace(i, widget.ports[i].copyWith(label: v)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: widget.ports[i].type.name,
                    isDense: true,
                    items: [
                      for (final type in {
                        for (final x in widget.types) x.name: x,
                        widget.ports[i].type.name: widget.ports[i].type,
                      }.values)
                        DropdownMenuItem(
                          value: type.name,
                          child: _typeItem(type),
                        ),
                    ],
                    onChanged: (name) => _replace(
                      i,
                      widget.ports[i].copyWith(
                        type: widget.types.firstWhere(
                          (x) => x.name == name,
                          orElse: () => widget.ports[i].type,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () =>
                        widget.onChanged([...widget.ports]..removeAt(i)),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 16),
              label: Text('Add ${_isInput ? 'input' : 'output'}'),
            ),
          ),
        ],
      ),
    );
  }
}
