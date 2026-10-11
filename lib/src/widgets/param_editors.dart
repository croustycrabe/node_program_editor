import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ids.dart';
import '../core/node.dart';
import '../params/param_types.dart';
import '../params/param_values.dart';
import 'scope.dart';
import 'theme.dart';

/// Everything a parameter editor needs.
class ParamEditorContext {
  /// Creates a context.
  const ParamEditorContext({
    required this.spec,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.enabled = true,
    this.node,
    this.services = const NodeEditorServices(),
  });

  /// Parameter specification.
  final ParamSpec spec;

  /// Current value.
  final Object? value;

  /// Called with the new value.
  final ValueChanged<Object?> onChanged;

  /// Whether the editor is shown inside a node (small, single line).
  final bool compact;

  /// Whether editing is allowed.
  final bool enabled;

  /// Owning node, when editing a node parameter.
  final NodeId? node;

  /// Host services (pickers, triggers).
  final NodeEditorServices services;

  /// Parameter type.
  ParamType<Object?> get type => spec.type;
}

/// Builds an editor for a parameter type.
typedef ParamEditorBuilder = Widget Function(
  BuildContext context,
  ParamEditorContext ctx,
);

/// Global registry of custom parameter editors, keyed by [ParamType.id].
/// Registered builders take precedence over the built-in editors.
abstract final class ParamEditorRegistry {
  static final Map<String, ParamEditorBuilder> _builders = {};

  /// Registers [builder] for parameter type [typeId].
  static void register(String typeId, ParamEditorBuilder builder) =>
      _builders[typeId] = builder;

  /// Removes the custom editor of [typeId].
  static void unregister(String typeId) => _builders.remove(typeId);

  /// The custom editor of [typeId], if any.
  static ParamEditorBuilder? lookup(String typeId) => _builders[typeId];
}

/// The editor of one parameter (built-in or registered).
class ParamEditor extends StatelessWidget {
  /// Creates an editor.
  const ParamEditor(this.ctx, {super.key});

  /// Editor context.
  final ParamEditorContext ctx;

  @override
  Widget build(BuildContext context) {
    final custom = ParamEditorRegistry.lookup(ctx.type.id);
    if (custom != null) return custom(context, ctx);
    final t = ctx.type;
    return switch (t) {
      IntParam() => _NumberEditor(ctx: ctx, isInt: true),
      DoubleParam() => _NumberEditor(ctx: ctx, isInt: false),
      BoolParam() => _BoolEditor(ctx: ctx),
      ExpressionParam() || CodeParam() => _TextEditor(ctx: ctx, code: true),
      MultilineTextParam() => _TextEditor(ctx: ctx, multiline: true),
      PasswordParam() => _TextEditor(ctx: ctx, obscure: true),
      TextParam() => _TextEditor(ctx: ctx),
      EnumParam() => _EnumEditor(ctx: ctx, type: t),
      MultiSelectParam() => _MultiSelectEditor(ctx: ctx, type: t),
      ListParam() => _ListEditor(ctx: ctx, type: t),
      TableParam() => _TableEditor(ctx: ctx, type: t),
      JsonParam() => _JsonEditor(ctx: ctx),
      QuantityParam() => _QuantityEditor(ctx: ctx, type: t),
      RangeParam() => _RangeEditor(ctx: ctx, type: t),
      VectorParam() => _VectorEditor(ctx: ctx, type: t),
      MatrixParam() => _MatrixEditor(ctx: ctx, type: t),
      CurveParam() => _CurveEditorField(ctx: ctx, type: t),
      ColorParam() => _ColorEditor(ctx: ctx, type: t),
      ImageParam() => _ImageEditor(ctx: ctx, type: t),
      RoiParam() => _RoiEditorField(ctx: ctx, type: t),
      PointParam() => _PointEditor(ctx: ctx),
      FilePathParam() => _FileEditor(ctx: ctx, type: t),
      DateTimeParam() => _DateTimeEditor(ctx: ctx, type: t),
      TriggerParam() => _TriggerEditor(ctx: ctx, type: t),
      ColorMapParam() => _ColorMapEditor(ctx: ctx),
      _ => _FallbackEditor(ctx: ctx),
    };
  }
}

/// A labelled editor with description and validation message, used by edit
/// dialogs.
class ParamField extends StatelessWidget {
  /// Creates a field.
  const ParamField(this.ctx, {super.key, this.error});

  /// Editor context.
  final ParamEditorContext ctx;

  /// Validation message.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ctx.spec.label,
                  style: t.textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (ctx.spec.description != null)
                Tooltip(
                  message: ctx.spec.description!,
                  child: Icon(
                    Icons.info_outline,
                    size: 16,
                    color: t.colorScheme.outline,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ParamEditor(ctx),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error!,
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact editor bound to a node parameter, shown inside dynamic nodes.
class InlineParamEditor extends StatelessWidget {
  /// Creates an inline editor.
  const InlineParamEditor({super.key, required this.node, required this.spec});

  /// Node.
  final NodeInstance node;

  /// Parameter.
  final ParamSpec spec;

  @override
  Widget build(BuildContext context) {
    final scope = NodeEditorScope.of(context);
    final c = scope.controller;
    final theme = scope.theme;
    return NoNodeDrag(
      child: _CompactTheme(
        theme: theme,
        child: ParamEditor(
          ParamEditorContext(
            spec: spec,
            value: node.params[spec.name],
            onChanged: (v) => c.setParam(node.id, spec.name, v),
            compact: true,
            enabled: !spec.readOnly && !node.locked,
            node: node.id,
            services: scope.services,
          ),
        ),
      ),
    );
  }
}

class _CompactTheme extends StatelessWidget {
  const _CompactTheme({required this.theme, required this.child});
  final NodeEditorThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: theme.accentColor,
      brightness: theme.brightness,
    );
    return Theme(
      data: base.copyWith(
        colorScheme: scheme,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        inputDecorationTheme: const InputDecorationTheme(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          border: OutlineInputBorder(),
        ),
        sliderTheme: const SliderThemeData(
          trackHeight: 2,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
        ),
        textTheme: base.textTheme.apply(
          bodyColor: theme.bodyStyle.color,
          displayColor: theme.bodyStyle.color,
        ),
      ),
      child: DefaultTextStyle.merge(style: theme.bodyStyle, child: child),
    );
  }
}

/// Label shown left of compact editors.
class _InlineLabel extends StatelessWidget {
  const _InlineLabel(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Text(
    trailing == null ? text : '$text  $trailing',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: DefaultTextStyle.of(context).style.copyWith(fontSize: 11),
  );
}

Widget _compactRow(String label, Widget editor, {double editorWidth = 84}) =>
    Row(
      children: [
        Expanded(child: _InlineLabel(label)),
        const SizedBox(width: 6),
        SizedBox(width: editorWidth, child: editor),
      ],
    );

String _fmt(num v, int precision) {
  if (v is int) return '$v';
  final s = v.toStringAsFixed(precision);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

// ---------------------------------------------------------------------------
// Numbers
// ---------------------------------------------------------------------------

/// A numeric text field committing on submit / focus loss, with up / down
/// arrow stepping.
class NumberField extends StatefulWidget {
  /// Creates a number field.
  const NumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.isInt = false,
    this.precision = 3,
    this.min,
    this.max,
    this.step,
    this.unit,
    this.enabled = true,
    this.label,
  });

  /// Current value.
  final num value;

  /// Commit callback.
  final ValueChanged<num> onChanged;

  /// Whether to parse integers.
  final bool isInt;

  /// Displayed decimals.
  final int precision;

  /// Minimum.
  final num? min;

  /// Maximum.
  final num? max;

  /// Arrow key step.
  final num? step;

  /// Unit suffix.
  final String? unit;

  /// Whether editable.
  final bool enabled;

  /// Optional prefix label.
  final String? label;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _ctl = TextEditingController(
    text: _fmt(widget.value, widget.precision),
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) {
      _ctl.text = _fmt(widget.value, widget.precision);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  num _clamp(num v) {
    if (widget.min != null && v < widget.min!) v = widget.min!;
    if (widget.max != null && v > widget.max!) v = widget.max!;
    return v;
  }

  void _commit() {
    final parsed = num.tryParse(_ctl.text.trim().replaceAll(',', '.'));
    if (parsed == null) {
      _ctl.text = _fmt(widget.value, widget.precision);
      return;
    }
    final v = _clamp(widget.isInt ? parsed.round() : parsed.toDouble());
    _ctl.text = _fmt(v, widget.precision);
    if (v != widget.value) widget.onChanged(v);
  }

  void _step(int dir) {
    final step = widget.step ?? (widget.isInt ? 1 : 0.1);
    final v = _clamp(widget.value + step * dir);
    widget.onChanged(widget.isInt ? v.round() : v.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
          _step(1);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
          _step(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _ctl,
        focusNode: _focus,
        enabled: widget.enabled,
        keyboardType: TextInputType.numberWithOptions(
          decimal: !widget.isInt,
          signed: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9eE+\-.,]')),
        ],
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          prefixText: widget.label,
          suffixText: widget.unit,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

class _NumberEditor extends StatelessWidget {
  const _NumberEditor({required this.ctx, required this.isInt});
  final ParamEditorContext ctx;
  final bool isInt;

  @override
  Widget build(BuildContext context) {
    final t = ctx.type;
    final num? min, max, step;
    final bool slider;
    final String? unit;
    final int precision;
    if (t is IntParam) {
      min = t.min;
      max = t.max;
      step = t.step;
      slider = t.slider;
      unit = t.unit;
      precision = 0;
    } else {
      final d = t as DoubleParam;
      min = d.min;
      max = d.max;
      step = d.step;
      slider = d.slider;
      unit = d.unit;
      precision = d.precision;
    }
    final value = (ctx.value as num?) ?? (isInt ? 0 : 0.0);
    void emit(num v) => ctx.onChanged(isInt ? v.round() : v.toDouble());
    final field = NumberField(
      value: value,
      onChanged: emit,
      isInt: isInt,
      precision: precision,
      min: min,
      max: max,
      step: step,
      unit: ctx.compact ? null : unit,
      enabled: ctx.enabled,
    );
    if (slider && min != null && max != null && max > min) {
      final divisions = step != null && step > 0
          ? ((max - min) / step).round().clamp(1, 1000)
          : null;
      final s = Slider(
        value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: divisions,
        label: _fmt(value, precision),
        onChanged: ctx.enabled ? emit : null,
      );
      if (ctx.compact) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InlineLabel(
              ctx.spec.label,
              trailing: '${_fmt(value, precision)}${unit ?? ''}',
            ),
            SizedBox(height: 20, child: s),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: s),
          SizedBox(width: 90, child: field),
        ],
      );
    }
    return ctx.compact ? _compactRow(ctx.spec.label, field) : field;
  }
}

class _BoolEditor extends StatelessWidget {
  const _BoolEditor({required this.ctx});
  final ParamEditorContext ctx;

  @override
  Widget build(BuildContext context) {
    final v = ctx.value as bool? ?? false;
    final sw = Switch(value: v, onChanged: ctx.enabled ? ctx.onChanged : null);
    if (ctx.compact) {
      return Row(
        children: [
          Expanded(child: _InlineLabel(ctx.spec.label)),
          Transform.scale(scale: 0.7, child: sw),
        ],
      );
    }
    return Align(alignment: Alignment.centerLeft, child: sw);
  }
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

class _TextEditor extends StatefulWidget {
  const _TextEditor({
    required this.ctx,
    this.multiline = false,
    this.obscure = false,
    this.code = false,
  });
  final ParamEditorContext ctx;
  final bool multiline;
  final bool obscure;
  final bool code;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.ctx.value as String? ?? '',
  );
  bool _reveal = false;

  @override
  void didUpdateWidget(_TextEditor old) {
    super.didUpdateWidget(old);
    final v = widget.ctx.value as String? ?? '';
    if (v != _ctl.text) {
      _ctl.value = TextEditingValue(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
      );
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final t = ctx.type;
    final lines = switch (t) {
      MultilineTextParam(:final lines) => lines,
      ExpressionParam() => 1,
      CodeParam(:final lines) => lines,
      _ => 1,
    };
    final hint = t is TextParam ? t.hint : null;
    final compactLines = ctx.compact ? 1 : lines;
    final field = TextField(
      controller: _ctl,
      enabled: ctx.enabled,
      obscureText: widget.obscure && !_reveal,
      minLines: widget.multiline || widget.code ? compactLines : 1,
      maxLines: widget.multiline || widget.code ? compactLines : 1,
      style: TextStyle(
        fontSize: 12,
        fontFamily: widget.code ? 'monospace' : null,
        fontFamilyFallback: widget.code
            ? const ['Consolas', 'Menlo', 'Courier New']
            : null,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText:
            hint ??
            (t is ExpressionParam && t.variables.isNotEmpty
                ? 'Variables: ${t.variables.join(', ')}'
                : null),
        border: const OutlineInputBorder(),
        suffixIcon: widget.obscure
            ? IconButton(
                iconSize: 16,
                icon: Icon(_reveal ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _reveal = !_reveal),
              )
            : null,
      ),
      onChanged: ctx.onChanged,
    );
    return ctx.compact
        ? _compactRow(ctx.spec.label, field, editorWidth: 110)
        : field;
  }
}

class _JsonEditor extends StatefulWidget {
  const _JsonEditor({required this.ctx});
  final ParamEditorContext ctx;

  @override
  State<_JsonEditor> createState() => _JsonEditorState();
}

class _JsonEditorState extends State<_JsonEditor> {
  late final TextEditingController _ctl = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert(widget.ctx.value),
  );
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ctx.compact) {
      return _compactRow(
        widget.ctx.spec.label,
        Text(
          jsonEncode(widget.ctx.value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        editorWidth: 110,
      );
    }
    return TextField(
      controller: _ctl,
      enabled: widget.ctx.enabled,
      minLines: 4,
      maxLines: 12,
      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        errorText: _error,
      ),
      onChanged: (text) {
        try {
          final v = text.trim().isEmpty ? null : jsonDecode(text);
          setState(() => _error = null);
          widget.ctx.onChanged(v);
        } catch (e) {
          setState(() => _error = 'Invalid JSON');
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Choices
// ---------------------------------------------------------------------------

class _EnumEditor extends StatelessWidget {
  const _EnumEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final EnumParam type;

  @override
  Widget build(BuildContext context) {
    final value = ctx.value as String? ?? type.defaultValue;
    if (type.segmented && !ctx.compact) {
      return SegmentedButton<String>(
        segments: [
          for (final o in type.options)
            ButtonSegment(value: o.value, label: Text(o.label)),
        ],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: ctx.enabled ? (s) => ctx.onChanged(s.first) : null,
      );
    }
    final dd = DropdownButton<String>(
      value: type.options.any((o) => o.value == value) ? value : null,
      isExpanded: true,
      isDense: true,
      style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
      items: [
        for (final o in type.options)
          DropdownMenuItem(
            value: o.value,
            child: Text(o.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: ctx.enabled ? (v) => ctx.onChanged(v) : null,
    );
    return ctx.compact ? _compactRow(ctx.spec.label, dd, editorWidth: 100) : dd;
  }
}

class _MultiSelectEditor extends StatelessWidget {
  const _MultiSelectEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final MultiSelectParam type;

  @override
  Widget build(BuildContext context) {
    final selected = (ctx.value as List?)?.cast<String>() ?? const <String>[];
    if (ctx.compact) {
      return _compactRow(
        ctx.spec.label,
        Text(
          selected.isEmpty ? '—' : selected.join(', '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        editorWidth: 100,
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final o in type.options)
          FilterChip(
            label: Text(o.label),
            selected: selected.contains(o.value),
            onSelected: ctx.enabled
                ? (on) => ctx.onChanged(
                    on
                        ? [...selected, o.value]
                        : selected.where((s) => s != o.value).toList(),
                  )
                : null,
          ),
      ],
    );
  }
}

class _ColorMapEditor extends StatelessWidget {
  const _ColorMapEditor({required this.ctx});
  final ParamEditorContext ctx;

  @override
  Widget build(BuildContext context) {
    final value = ctx.value as String? ?? 'viridis';
    Widget bar(String name) => Container(
      height: 10,
      width: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: LinearGradient(colors: ColorMapParam.maps[name]!),
      ),
    );
    final dd = DropdownButton<String>(
      value: value,
      isDense: true,
      isExpanded: true,
      items: [
        for (final name in ColorMapParam.maps.keys)
          DropdownMenuItem(
            value: name,
            child: Row(
              children: [
                bar(name),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(name, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
      ],
      onChanged: ctx.enabled ? ctx.onChanged : null,
    );
    return ctx.compact ? _compactRow(ctx.spec.label, dd, editorWidth: 110) : dd;
  }
}

// ---------------------------------------------------------------------------
// Collections
// ---------------------------------------------------------------------------

class _ListEditor extends StatelessWidget {
  const _ListEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final ListParam type;

  @override
  Widget build(BuildContext context) {
    final items = (ctx.value as List?)?.cast<Object?>() ?? const <Object?>[];
    if (ctx.compact) {
      return _compactRow(ctx.spec.label, Text('${items.length} items'));
    }
    final canAdd = type.maxItems == null || items.length < type.maxItems!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(width: 24, child: Text('${i + 1}.')),
                Expanded(
                  child: ParamEditor(
                    ParamEditorContext(
                      spec: ParamSpec('${ctx.spec.name}[$i]', type.itemType),
                      value: items[i],
                      enabled: ctx.enabled,
                      services: ctx.services,
                      onChanged: (v) {
                        final next = [...items];
                        next[i] = v;
                        ctx.onChanged(next);
                      },
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_upward, size: 16),
                  onPressed: i == 0 || !ctx.enabled
                      ? null
                      : () {
                          final next = [...items];
                          next.insert(i - 1, next.removeAt(i));
                          ctx.onChanged(next);
                        },
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  onPressed: !ctx.enabled || items.length <= type.minItems
                      ? null
                      : () => ctx.onChanged([...items]..removeAt(i)),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: ctx.enabled && canAdd
                ? () => ctx.onChanged([...items, type.itemType.defaultValue])
                : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add item'),
          ),
        ),
      ],
    );
  }
}

class _TableEditor extends StatelessWidget {
  const _TableEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final TableParam type;

  @override
  Widget build(BuildContext context) {
    final rows =
        (ctx.value as List?)?.cast<Map<String, Object?>>() ??
        const <Map<String, Object?>>[];
    if (ctx.compact) {
      return _compactRow(ctx.spec.label, Text('${rows.length} rows'));
    }
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final c in type.columns)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(c.label, style: t.textTheme.labelMedium),
                ),
              ),
            const SizedBox(width: 40),
          ],
        ),
        const Divider(height: 8),
        for (var r = 0; r < rows.length; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (final c in type.columns)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ParamEditor(
                        ParamEditorContext(
                          spec: ParamSpec(c.name, c.type),
                          value: rows[r][c.name],
                          enabled: ctx.enabled,
                          services: ctx.services,
                          onChanged: (v) {
                            final next = [...rows];
                            next[r] = {...rows[r], c.name: v};
                            ctx.onChanged(next);
                          },
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  width: 40,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    onPressed: ctx.enabled
                        ? () => ctx.onChanged([...rows]..removeAt(r))
                        : null,
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: ctx.enabled
                ? () => ctx.onChanged([...rows, type.emptyRow()])
                : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add row'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scientific
// ---------------------------------------------------------------------------

class _QuantityEditor extends StatelessWidget {
  const _QuantityEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final QuantityParam type;

  @override
  Widget build(BuildContext context) {
    final q = ctx.value as Quantity? ?? type.defaultValue;
    final row = Row(
      children: [
        Expanded(
          child: NumberField(
            value: q.value,
            precision: type.precision,
            min: type.min,
            max: type.max,
            enabled: ctx.enabled,
            onChanged: (v) => ctx.onChanged(q.copyWith(value: v.toDouble())),
          ),
        ),
        const SizedBox(width: 4),
        DropdownButton<String>(
          value: type.units.contains(q.unit) ? q.unit : null,
          isDense: true,
          items: [
            for (final u in type.units)
              DropdownMenuItem(
                value: u,
                child: Text(u, style: const TextStyle(fontSize: 12)),
              ),
          ],
          onChanged: ctx.enabled
              ? (u) => ctx.onChanged(q.copyWith(unit: u))
              : null,
        ),
      ],
    );
    return ctx.compact
        ? _compactRow(ctx.spec.label, row, editorWidth: 120)
        : row;
  }
}

class _RangeEditor extends StatelessWidget {
  const _RangeEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final RangeParam type;

  @override
  Widget build(BuildContext context) {
    final r = ctx.value as RangeValue? ?? type.defaultValue;
    final divisions = type.step != null && type.step! > 0
        ? ((type.max - type.min) / type.step!).round().clamp(1, 1000)
        : null;
    final slider = RangeSlider(
      values: RangeValues(
        r.start.clamp(type.min, type.max),
        r.end.clamp(type.min, type.max),
      ),
      min: type.min,
      max: type.max,
      divisions: divisions,
      labels: RangeLabels(
        _fmt(r.start, type.precision),
        _fmt(r.end, type.precision),
      ),
      onChanged: ctx.enabled
          ? (v) => ctx.onChanged(RangeValue(v.start, v.end))
          : null,
    );
    if (ctx.compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InlineLabel(
            ctx.spec.label,
            trailing:
                '${_fmt(r.start, type.precision)} – ${_fmt(r.end, type.precision)}',
          ),
          SizedBox(height: 20, child: slider),
        ],
      );
    }
    return Column(
      children: [
        slider,
        Row(
          children: [
            Expanded(
              child: NumberField(
                value: r.start,
                precision: type.precision,
                min: type.min,
                max: r.end,
                label: 'min ',
                enabled: ctx.enabled,
                onChanged: (v) =>
                    ctx.onChanged(RangeValue(v.toDouble(), r.end)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NumberField(
                value: r.end,
                precision: type.precision,
                min: r.start,
                max: type.max,
                label: 'max ',
                enabled: ctx.enabled,
                onChanged: (v) =>
                    ctx.onChanged(RangeValue(r.start, v.toDouble())),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VectorEditor extends StatelessWidget {
  const _VectorEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final VectorParam type;

  @override
  Widget build(BuildContext context) {
    final v = (ctx.value as List?)?.cast<double>() ?? type.defaultValue;
    final labels = type.effectiveLabels;
    final row = Row(
      children: [
        for (var i = 0; i < type.dimension; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: NumberField(
              value: i < v.length ? v[i] : 0,
              precision: type.precision,
              min: type.min,
              max: type.max,
              label: ctx.compact ? null : '${labels[i]} ',
              enabled: ctx.enabled,
              onChanged: (x) {
                final next = [...v];
                while (next.length < type.dimension) {
                  next.add(0);
                }
                next[i] = x.toDouble();
                ctx.onChanged(next);
              },
            ),
          ),
        ],
      ],
    );
    return ctx.compact
        ? _compactRow(ctx.spec.label, row, editorWidth: 40.0 * type.dimension)
        : row;
  }
}

class _PointEditor extends StatelessWidget {
  const _PointEditor({required this.ctx});
  final ParamEditorContext ctx;

  @override
  Widget build(BuildContext context) {
    final p = ctx.value as Offset? ?? Offset.zero;
    final row = Row(
      children: [
        Expanded(
          child: NumberField(
            value: p.dx,
            label: ctx.compact ? null : 'x ',
            enabled: ctx.enabled,
            onChanged: (v) => ctx.onChanged(Offset(v.toDouble(), p.dy)),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: NumberField(
            value: p.dy,
            label: ctx.compact ? null : 'y ',
            enabled: ctx.enabled,
            onChanged: (v) => ctx.onChanged(Offset(p.dx, v.toDouble())),
          ),
        ),
      ],
    );
    return ctx.compact
        ? _compactRow(ctx.spec.label, row, editorWidth: 100)
        : row;
  }
}

class _MatrixEditor extends StatelessWidget {
  const _MatrixEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final MatrixParam type;

  @override
  Widget build(BuildContext context) {
    final m = ctx.value as Matrix? ?? type.defaultValue;
    if (ctx.compact) {
      return _compactRow(ctx.spec.label, Text('${m.rows}×${m.cols} matrix'));
    }
    Widget stepper(String label, int value, ValueChanged<int> onChanged) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove, size: 16),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 16),
          onPressed: value < 16 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (type.resizable && ctx.enabled)
          Wrap(
            spacing: 12,
            children: [
              stepper(
                'Rows',
                m.rows,
                (r) => ctx.onChanged(m.resized(r, m.cols)),
              ),
              stepper(
                'Cols',
                m.cols,
                (c) => ctx.onChanged(m.resized(m.rows, c)),
              ),
            ],
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            children: [
              for (var r = 0; r < m.rows; r++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      for (var c = 0; c < m.cols; c++)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: SizedBox(
                            width: 64,
                            child: NumberField(
                              value: m.at(r, c),
                              precision: type.precision,
                              enabled: ctx.enabled,
                              onChanged: (v) => ctx.onChanged(
                                m.withValue(r, c, v.toDouble()),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CurveEditorField extends StatelessWidget {
  const _CurveEditorField({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final CurveParam type;

  @override
  Widget build(BuildContext context) {
    final pts = (ctx.value as List?)?.cast<Offset>() ?? type.defaultValue;
    final editor = CurveEditor(
      points: pts,
      type: type,
      enabled: ctx.enabled && !ctx.compact,
      onChanged: (p) => ctx.onChanged(type.normalize(p)),
    );
    if (ctx.compact) {
      return _compactRow(
        ctx.spec.label,
        SizedBox(height: 32, child: editor),
        editorWidth: 60,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(aspectRatio: 1.6, child: editor),
        const SizedBox(height: 4),
        Text(
          'Drag points to edit, tap to add, double tap to remove.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Interactive piecewise-linear curve editor (tone curves, LUTs, transfer
/// functions).
class CurveEditor extends StatefulWidget {
  /// Creates a curve editor.
  const CurveEditor({
    super.key,
    required this.points,
    required this.type,
    required this.onChanged,
    this.enabled = true,
  });

  /// Control points (value space).
  final List<Offset> points;

  /// Domain / range.
  final CurveParam type;

  /// Change callback.
  final ValueChanged<List<Offset>> onChanged;

  /// Whether editable.
  final bool enabled;

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<CurveEditor> {
  int? _dragging;
  Offset? _lastTap;

  Offset _toLocal(Offset v, Size s) {
    final t = widget.type;
    return Offset(
      (v.dx - t.minX) / (t.maxX - t.minX) * s.width,
      (1 - (v.dy - t.minY) / (t.maxY - t.minY)) * s.height,
    );
  }

  Offset _toValue(Offset l, Size s) {
    final t = widget.type;
    return Offset(
      (t.minX + l.dx / s.width * (t.maxX - t.minX)).clamp(t.minX, t.maxX),
      (t.minY + (1 - l.dy / s.height) * (t.maxY - t.minY)).clamp(
        t.minY,
        t.maxY,
      ),
    );
  }

  int? _nearest(Offset local, Size s) {
    int? best;
    var bestD = 14.0;
    for (var i = 0; i < widget.points.length; i++) {
      final d = (_toLocal(widget.points[i], s) - local).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, cons) {
        final size = cons.biggest;
        final paint = CustomPaint(
          size: size,
          painter: _CurvePainter(
            widget.points,
            widget.type,
            scheme.primary,
            scheme.outlineVariant,
            _toLocal,
          ),
        );
        if (!widget.enabled) return paint;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final now = d.localPosition;
            final i = _nearest(now, size);
            if (_lastTap != null &&
                (now - _lastTap!).distance < 8 &&
                i != null) {
              if (widget.points.length > 2) {
                widget.onChanged([...widget.points]..removeAt(i));
              }
              _lastTap = null;
              return;
            }
            _lastTap = now;
            if (i == null) {
              widget.onChanged([...widget.points, _toValue(now, size)]);
            }
          },
          onPanStart: (d) {
            _dragging = _nearest(d.localPosition, size);
            if (_dragging == null) {
              final pts = [...widget.points, _toValue(d.localPosition, size)];
              widget.onChanged(pts);
              _dragging = pts.length - 1;
            }
          },
          onPanUpdate: (d) {
            final i = _dragging;
            if (i == null || i >= widget.points.length) return;
            final pts = [...widget.points];
            pts[i] = _toValue(d.localPosition, size);
            widget.onChanged(pts);
            // Points are re-sorted by the param type; track the moved point.
            final sorted = widget.type.normalize(pts);
            _dragging = sorted.indexOf(widget.type.normalize([pts[i]]).first);
          },
          onPanEnd: (_) => _dragging = null,
          child: paint,
        );
      },
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.points, this.type, this.color, this.grid, this.toLocal);
  final List<Offset> points;
  final CurveParam type;
  final Color color;
  final Color grid;
  final Offset Function(Offset, Size) toLocal;

  @override
  void paint(Canvas canvas, Size size) {
    final g = Paint()
      ..color = grid
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 4; i++) {
      final x = size.width * i / 4, y = size.height * i / 4;
      canvas
        ..drawLine(Offset(x, 0), Offset(x, size.height), g)
        ..drawLine(Offset(0, y), Offset(size.width, y), g);
    }
    if (points.isEmpty) return;
    final sorted = [...points]..sort((a, b) => a.dx.compareTo(b.dx));
    final path = Path();
    final first = toLocal(Offset(type.minX, sorted.first.dy), size);
    path.moveTo(first.dx, first.dy);
    for (final p in sorted) {
      final l = toLocal(p, size);
      path.lineTo(l.dx, l.dy);
    }
    final last = toLocal(Offset(type.maxX, sorted.last.dy), size);
    path.lineTo(last.dx, last.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (size.height > 40) {
      for (final p in sorted) {
        canvas.drawCircle(toLocal(p, size), 4, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.points != points || old.color != color;
}

// ---------------------------------------------------------------------------
// Vision
// ---------------------------------------------------------------------------

class _ColorEditor extends StatelessWidget {
  const _ColorEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final ColorParam type;

  @override
  Widget build(BuildContext context) {
    final color = ctx.value as Color? ?? type.defaultValue;
    final swatch = InkWell(
      onTap: ctx.enabled
          ? () async {
              final picked = await showColorPickerDialog(
                context,
                color,
                alpha: type.alpha,
              );
              if (picked != null) ctx.onChanged(picked);
            }
          : null,
      child: Container(
        height: ctx.compact ? 20 : 32,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        alignment: Alignment.center,
        child: ctx.compact
            ? null
            : Text(
                '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
                style: TextStyle(
                  fontSize: 12,
                  color: color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                ),
              ),
      ),
    );
    return ctx.compact
        ? _compactRow(ctx.spec.label, swatch, editorWidth: 48)
        : swatch;
  }
}

/// Shows an HSV color picker; returns the picked color or null.
Future<Color?> showColorPickerDialog(
  BuildContext context,
  Color initial, {
  bool alpha = true,
}) {
  var current = initial;
  return showDialog<Color>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Pick a color'),
      content: SizedBox(
        width: 300,
        child: HsvColorPicker(
          initial: initial,
          alpha: alpha,
          onChanged: (c) => current = c,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, current),
          child: const Text('Select'),
        ),
      ],
    ),
  );
}

/// Dependency free HSV color picker (saturation / value square, hue and
/// alpha sliders, hex field and swatches).
class HsvColorPicker extends StatefulWidget {
  /// Creates a picker.
  const HsvColorPicker({
    super.key,
    required this.initial,
    required this.onChanged,
    this.alpha = true,
  });

  /// Initial color.
  final Color initial;

  /// Change callback.
  final ValueChanged<Color> onChanged;

  /// Whether the alpha slider is shown.
  final bool alpha;

  @override
  State<HsvColorPicker> createState() => _HsvColorPickerState();
}

class _HsvColorPickerState extends State<HsvColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(text: _hexOf());

  static const _swatches = [
    Color(0xFFF04438),
    Color(0xFFF79009),
    Color(0xFFFDB022),
    Color(0xFF12B76A),
    Color(0xFF06AED4),
    Color(0xFF2E90FA),
    Color(0xFF6172F3),
    Color(0xFF9E77ED),
    Color(0xFFEE46BC),
    Color(0xFF667085),
    Color(0xFF101828),
    Color(0xFFFFFFFF),
  ];

  String _hexOf() =>
      _hsv.toColor().toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();

  void _set(HSVColor c, {bool updateHex = true}) {
    setState(() => _hsv = c);
    if (updateHex) _hex.text = _hexOf();
    widget.onChanged(c.toColor());
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1.5,
          child: LayoutBuilder(
            builder: (context, c) {
              void pick(Offset p) => _set(
                _hsv
                    .withSaturation((p.dx / c.maxWidth).clamp(0.0, 1.0))
                    .withValue(1 - (p.dy / c.maxHeight).clamp(0.0, 1.0)),
              );
              return GestureDetector(
                onPanDown: (d) => pick(d.localPosition),
                onPanUpdate: (d) => pick(d.localPosition),
                child: CustomPaint(painter: _SvPainter(_hsv)),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _GradientSlider(
          value: _hsv.hue / 360,
          colors: [
            for (var h = 0; h <= 360; h += 60)
              HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
          ],
          onChanged: (v) => _set(_hsv.withHue(v * 360)),
        ),
        if (widget.alpha) ...[
          const SizedBox(height: 8),
          _GradientSlider(
            value: _hsv.alpha,
            colors: [
              _hsv.toColor().withValues(alpha: 0),
              _hsv.toColor().withValues(alpha: 1),
            ],
            onChanged: (v) => _set(_hsv.withAlpha(v)),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _hex,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixText: '#',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (t) {
                  var hex = t.replaceAll('#', '');
                  if (hex.length == 6) hex = 'FF$hex';
                  final v = int.tryParse(hex, radix: 16);
                  if (v != null) {
                    _set(HSVColor.fromColor(Color(v)), updateHex: false);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in _swatches)
              InkWell(
                onTap: () => _set(HSVColor.fromColor(s)),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: s,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black26),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas
      ..save()
      ..clipRRect(rrect)
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white,
              HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
            ],
          ).createShader(rect),
      )
      ..drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black],
          ).createShader(rect),
      )
      ..restore();
    final p = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas
      ..drawCircle(
        p,
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      )
      ..drawCircle(
        p,
        8,
        Paint()
          ..color = Colors.black45
          ..style = PaintingStyle.stroke,
      );
  }

  @override
  bool shouldRepaint(_SvPainter old) => old.hsv != hsv;
}

class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.value,
    required this.colors,
    required this.onChanged,
  });
  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: LayoutBuilder(
        builder: (context, c) {
          void set(Offset p) => onChanged((p.dx / c.maxWidth).clamp(0.0, 1.0));
          return GestureDetector(
            onPanDown: (d) => set(d.localPosition),
            onPanUpdate: (d) => set(d.localPosition),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  top: 3,
                  bottom: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black12),
                      gradient: LinearGradient(colors: colors),
                    ),
                  ),
                ),
                Positioned(
                  left: value * c.maxWidth - 6,
                  top: 0,
                  child: Container(
                    width: 12,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ImageEditor extends StatelessWidget {
  const _ImageEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final ImageParam type;

  @override
  Widget build(BuildContext context) {
    final ref = ctx.value as ImageRef?;
    final provider = ref == null ? null : ctx.services.resolveImage(ref);
    final pick = ctx.services.pickImage;
    final preview = Container(
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: provider == null
          ? const Center(child: Icon(Icons.image_outlined, size: 18))
          : Image(image: provider, fit: BoxFit.contain, gaplessPlayback: true),
    );
    final button = IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: 'Choose image',
      icon: const Icon(Icons.folder_open, size: 16),
      onPressed: ctx.enabled && pick != null
          ? () async {
              final r = await pick(context, type);
              if (r != null) ctx.onChanged(r);
            }
          : null,
    );
    if (ctx.compact) {
      return Row(
        children: [
          Expanded(child: _InlineLabel(ctx.spec.label)),
          SizedBox(width: 40, height: 30, child: preview),
          button,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(aspectRatio: 16 / 9, child: preview),
        Row(
          children: [
            Expanded(
              child: Text(
                ref?.name ?? ref?.uri ?? 'No image',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            button,
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Clear',
              icon: const Icon(Icons.clear, size: 16),
              onPressed: ctx.enabled && ref != null
                  ? () => ctx.onChanged(null)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _RoiEditorField extends StatelessWidget {
  const _RoiEditorField({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final RoiParam type;

  @override
  Widget build(BuildContext context) {
    final roi = ctx.value as Roi? ?? type.defaultValue;
    final r = roi.rect;
    if (ctx.compact) {
      return _compactRow(
        ctx.spec.label,
        Text(
          '${r.left.round()},${r.top.round()} '
          '${r.width.round()}×${r.height.round()}',
        ),
        editorWidth: 110,
      );
    }
    void emit(Roi v) => ctx.onChanged(type.normalize(v));
    Widget num(String label, double value, Rect Function(double v) apply) =>
        Expanded(
          child: NumberField(
            value: value,
            precision: 0,
            label: '$label ',
            enabled: ctx.enabled,
            onChanged: (v) => emit(roi.copyWith(rect: apply(v.toDouble()))),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: type.frame.width / type.frame.height,
          child: RoiEditor(
            roi: roi,
            frame: type.frame,
            enabled: ctx.enabled,
            onChanged: emit,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            num('x', r.left, (v) => Rect.fromLTWH(v, r.top, r.width, r.height)),
            const SizedBox(width: 4),
            num('y', r.top, (v) => Rect.fromLTWH(r.left, v, r.width, r.height)),
            const SizedBox(width: 4),
            num('w', r.width, (v) => Rect.fromLTWH(r.left, r.top, v, r.height)),
            const SizedBox(width: 4),
            num('h', r.height, (v) => Rect.fromLTWH(r.left, r.top, r.width, v)),
          ],
        ),
        if (type.rotatable)
          Row(
            children: [
              const Text('Angle'),
              Expanded(
                child: Slider(
                  value: roi.angle.clamp(-math.pi, math.pi),
                  min: -math.pi,
                  max: math.pi,
                  onChanged: ctx.enabled
                      ? (a) => emit(roi.copyWith(angle: a))
                      : null,
                ),
              ),
              Text('${(roi.angle * 180 / math.pi).round()}°'),
            ],
          ),
        if (type.shapes.length > 1)
          SegmentedButton<RoiShape>(
            segments: [
              for (final s in type.shapes)
                ButtonSegment(value: s, label: Text(s.name)),
            ],
            selected: {roi.shape},
            onSelectionChanged: ctx.enabled
                ? (s) => emit(roi.copyWith(shape: s.first))
                : null,
          ),
      ],
    );
  }
}

/// Drag-to-edit region of interest over a reference frame.
class RoiEditor extends StatefulWidget {
  /// Creates the editor.
  const RoiEditor({
    super.key,
    required this.roi,
    required this.frame,
    required this.onChanged,
    this.enabled = true,
    this.background,
  });

  /// Current region (frame coordinates).
  final Roi roi;

  /// Frame size.
  final Size frame;

  /// Change callback.
  final ValueChanged<Roi> onChanged;

  /// Whether editable.
  final bool enabled;

  /// Optional reference image drawn behind.
  final ImageProvider? background;

  @override
  State<RoiEditor> createState() => _RoiEditorState();
}

class _RoiEditorState extends State<RoiEditor> {
  int _mode = 0; // 0 none, 1 move, 2 resize
  Rect? _start;
  Offset? _origin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final sx = c.maxWidth / widget.frame.width;
        final sy = c.maxHeight / widget.frame.height;
        final r = widget.roi.rect;
        final local = Rect.fromLTRB(
          r.left * sx,
          r.top * sy,
          r.right * sx,
          r.bottom * sy,
        );
        return GestureDetector(
          onPanStart: widget.enabled
              ? (d) {
                  final p = d.localPosition;
                  if ((p - local.bottomRight).distance < 14) {
                    _mode = 2;
                  } else if (local.contains(p)) {
                    _mode = 1;
                  } else {
                    _mode = 3;
                  }
                  _start = r;
                  _origin = Offset(p.dx / sx, p.dy / sy);
                }
              : null,
          onPanUpdate: widget.enabled
              ? (d) {
                  final start = _start, origin = _origin;
                  if (start == null || origin == null) return;
                  final p = Offset(
                    d.localPosition.dx / sx,
                    d.localPosition.dy / sy,
                  );
                  final delta = p - origin;
                  final Rect next = switch (_mode) {
                    1 => start.shift(delta),
                    2 => Rect.fromLTRB(
                      start.left,
                      start.top,
                      math.max(start.left + 2, start.right + delta.dx),
                      math.max(start.top + 2, start.bottom + delta.dy),
                    ),
                    _ => Rect.fromPoints(origin, p),
                  };
                  widget.onChanged(widget.roi.copyWith(rect: next));
                }
              : null,
          onPanEnd: (_) => _mode = 0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              image: widget.background == null
                  ? null
                  : DecorationImage(
                      image: widget.background!,
                      fit: BoxFit.fill,
                    ),
            ),
            child: CustomPaint(
              size: c.biggest,
              painter: _RoiPainter(
                local,
                widget.roi.angle,
                widget.roi.shape,
                scheme.primary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoiPainter extends CustomPainter {
  _RoiPainter(this.rect, this.angle, this.shape, this.color);
  final Rect rect;
  final double angle;
  final RoiShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 0.5;
    for (var i = 1; i < 8; i++) {
      canvas
        ..drawLine(
          Offset(size.width * i / 8, 0),
          Offset(size.width * i / 8, size.height),
          grid,
        )
        ..drawLine(
          Offset(0, size.height * i / 8),
          Offset(size.width, size.height * i / 8),
          grid,
        );
    }
    canvas
      ..save()
      ..translate(rect.center.dx, rect.center.dy)
      ..rotate(angle)
      ..translate(-rect.center.dx, -rect.center.dy);
    final fill = Paint()..color = color.withValues(alpha: 0.2);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (shape == RoiShape.ellipse) {
      canvas
        ..drawOval(rect, fill)
        ..drawOval(rect, stroke);
    } else {
      canvas
        ..drawRect(rect, fill)
        ..drawRect(rect, stroke);
    }
    canvas
      ..drawRect(
        Rect.fromCenter(center: rect.bottomRight, width: 10, height: 10),
        Paint()..color = color,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_RoiPainter old) =>
      old.rect != rect || old.angle != angle || old.shape != shape;
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

class _FileEditor extends StatefulWidget {
  const _FileEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final FilePathParam type;

  @override
  State<_FileEditor> createState() => _FileEditorState();
}

class _FileEditorState extends State<_FileEditor> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.ctx.value as String? ?? '',
  );

  @override
  void didUpdateWidget(_FileEditor old) {
    super.didUpdateWidget(old);
    final v = widget.ctx.value as String? ?? '';
    if (v != _ctl.text) _ctl.text = v;
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final pick = ctx.services.pickFile;
    final field = TextField(
      controller: _ctl,
      enabled: ctx.enabled,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        hintText: widget.type.extensions.isEmpty
            ? null
            : widget.type.extensions.map((e) => '*.$e').join(' '),
        suffixIcon: IconButton(
          iconSize: 16,
          icon: Icon(
            widget.type.mode == FilePickMode.directory
                ? Icons.folder_open
                : Icons.insert_drive_file_outlined,
          ),
          onPressed: ctx.enabled && pick != null
              ? () async {
                  final p = await pick(context, widget.type);
                  if (p != null) ctx.onChanged(p);
                }
              : null,
        ),
      ),
      onChanged: ctx.onChanged,
    );
    return ctx.compact
        ? _compactRow(ctx.spec.label, field, editorWidth: 120)
        : field;
  }
}

class _DateTimeEditor extends StatelessWidget {
  const _DateTimeEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final DateTimeParam type;

  @override
  Widget build(BuildContext context) {
    final v = ctx.value as DateTime? ?? type.defaultValue;
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${v.year}-${two(v.month)}-${two(v.day)}';
    final time = '${two(v.hour)}:${two(v.minute)}';
    final label = switch (type.mode) {
      DateTimeMode.date => date,
      DateTimeMode.time => time,
      DateTimeMode.dateTime => '$date $time',
    };
    final button = OutlinedButton(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: ctx.enabled
          ? () async {
              var result = v;
              if (type.mode != DateTimeMode.time) {
                final d = await showDatePicker(
                  context: context,
                  initialDate: v,
                  firstDate: DateTime(1970),
                  lastDate: DateTime(2200),
                );
                if (d == null) return;
                result = DateTime(d.year, d.month, d.day, v.hour, v.minute);
              }
              if (type.mode != DateTimeMode.date && context.mounted) {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(v),
                );
                if (t == null) return;
                result = DateTime(
                  result.year,
                  result.month,
                  result.day,
                  t.hour,
                  t.minute,
                );
              }
              ctx.onChanged(result);
            }
          : null,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
    return ctx.compact
        ? _compactRow(ctx.spec.label, button, editorWidth: 120)
        : Align(alignment: Alignment.centerLeft, child: button);
  }
}

class _TriggerEditor extends StatelessWidget {
  const _TriggerEditor({required this.ctx, required this.type});
  final ParamEditorContext ctx;
  final TriggerParam type;

  @override
  Widget build(BuildContext context) {
    final trigger = ctx.services.onTrigger;
    final node = ctx.node;
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
      onPressed: ctx.enabled && trigger != null && node != null
          ? () => trigger(node, ctx.spec.name)
          : null,
      icon: const Icon(Icons.play_arrow, size: 16),
      label: Text(type.buttonLabel),
    );
  }
}

class _FallbackEditor extends StatelessWidget {
  const _FallbackEditor({required this.ctx});
  final ParamEditorContext ctx;

  @override
  Widget build(BuildContext context) => ctx.compact
      ? _compactRow(ctx.spec.label, Text('${ctx.value}'))
      : Text('${ctx.value}  (no editor for "${ctx.type.id}")');
}
