import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/node.dart';
import '../core/ports.dart';
import 'canvas.dart';
import 'theme.dart';

/// How palette items add nodes.
enum NodePaletteMode {
  /// Tap adds the node at the viewport center.
  click,

  /// Drag the item onto the canvas.
  drag,

  /// Both.
  both,
}

/// Visual arrangement of palette items.
enum NodePaletteLayout {
  /// One row per node with description.
  list,

  /// Cards in a grid.
  grid,

  /// Dense chips.
  compact,
}

/// Builds a palette item.
typedef PaletteItemBuilder = Widget Function(
  BuildContext context,
  NodeDefinition definition,
);

/// Builds a palette category header.
typedef PaletteHeaderBuilder = Widget Function(
  BuildContext context,
  String category,
  int count,
  bool expanded,
);

/// The node menu: every registered definition grouped by category, with
/// search, category / port-type filters, and click and / or drag & drop
/// insertion.
class NodePalette extends StatefulWidget {
  /// Creates a palette.
  const NodePalette({
    super.key,
    required this.controller,
    this.mode = NodePaletteMode.both,
    this.layout = NodePaletteLayout.list,
    this.showSearch = true,
    this.showFilters = true,
    this.title,
    this.filter,
    this.categoryOrder,
    this.itemBuilder,
    this.headerBuilder,
    this.initiallyCollapsed = const {},
    this.theme,
  });

  /// Controller (its registry is listed).
  final NodeEditorController controller;

  /// Click / drag behaviour.
  final NodePaletteMode mode;

  /// Item arrangement.
  final NodePaletteLayout layout;

  /// Whether the search field is shown.
  final bool showSearch;

  /// Whether category and port-type filters are shown.
  final bool showFilters;

  /// Optional header title.
  final String? title;

  /// Hides definitions for which it returns false.
  final bool Function(NodeDefinition definition)? filter;

  /// Category order (others follow in registration order).
  final List<String>? categoryOrder;

  /// Custom item widget (wrapped with tap / drag handling).
  final PaletteItemBuilder? itemBuilder;

  /// Custom category header.
  final PaletteHeaderBuilder? headerBuilder;

  /// Categories collapsed at start.
  final Set<String> initiallyCollapsed;

  /// Theme override.
  final NodeEditorThemeData? theme;

  @override
  State<NodePalette> createState() => _NodePaletteState();
}

class _NodePaletteState extends State<NodePalette> {
  final TextEditingController _search = TextEditingController();
  late final Set<String> _collapsed = {...widget.initiallyCollapsed};
  String? _category;
  String? _portType;
  int _added = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static int? _score(NodeDefinition d, String q) {
    if (q.isEmpty) return 0;
    final title = d.title.toLowerCase();
    if (title == q) return 100;
    if (title.startsWith(q)) return 80;
    if (title.contains(q)) return 60;
    if (d.tags.any((t) => t.toLowerCase().contains(q))) return 40;
    if (d.category.toLowerCase().contains(q)) return 30;
    if ((d.description ?? '').toLowerCase().contains(q)) return 20;
    // Subsequence ("gblur" -> "Gaussian blur").
    var i = 0;
    for (final ch in title.runes) {
      if (i < q.length && ch == q.codeUnitAt(i)) i++;
    }
    return i == q.length ? 10 : null;
  }

  void _add(NodeDefinition def) {
    final c = widget.controller;
    final step = (_added++ % 6) * 24.0;
    c.addNodeCentered(def.type, c.viewportCenter + Offset(step, step));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? NodeEditorThemeData.of(context);
    return ListenableBuilder(
      listenable: widget.controller.registry,
      builder: (context, _) {
        final registry = widget.controller.registry;
        final q = _search.text.trim().toLowerCase();
        final scored = <(NodeDefinition, int)>[];
        for (final d in registry.definitions) {
          if (d.category.startsWith('__')) continue;
          if (widget.filter != null && !widget.filter!(d)) continue;
          if (_category != null && d.category != _category) continue;
          if (_portType != null &&
              !d.ports.any((p) => p.type.name == _portType)) {
            continue;
          }
          final s = _score(d, q);
          if (s != null) scored.add((d, s));
        }
        if (q.isNotEmpty) scored.sort((a, b) => b.$2.compareTo(a.$2));
        final byCategory = <String, List<NodeDefinition>>{};
        for (final (d, _) in scored) {
          (byCategory[d.category] ??= []).add(d);
        }
        final order = [
          ...?widget.categoryOrder?.where(byCategory.containsKey),
          ...byCategory.keys.where(
            (k) => !(widget.categoryOrder?.contains(k) ?? false),
          ),
        ];
        final allCategories = [
          for (final c in registry.categories)
            if (!c.startsWith('__')) c,
        ];
        final portTypes = {
          for (final d in registry.definitions)
            if (!d.category.startsWith('__'))
              for (final p in d.ports)
                if (!p.type.isAny) p.type.name,
        }.toList()..sort();

        return Material(
          color: theme.panelColor,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: theme.panelForeground, fontSize: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Text(
                      widget.title!,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.panelForeground,
                      ),
                    ),
                  ),
                if (widget.showSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search nodes…',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                iconSize: 16,
                                icon: const Icon(Icons.clear),
                                onPressed: () =>
                                    setState(() => _search.clear()),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                if (widget.showFilters && allCategories.length > 1)
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        for (final c in allCategories)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: FilterChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                c,
                                style: const TextStyle(fontSize: 11),
                              ),
                              selected: _category == c,
                              onSelected: (on) =>
                                  setState(() => _category = on ? c : null),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (widget.showFilters && portTypes.length > 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: DropdownButton<String?>(
                      value: _portType,
                      isExpanded: true,
                      isDense: true,
                      hint: const Text(
                        'Any port type',
                        style: TextStyle(fontSize: 12),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text(
                            'Any port type',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        for (final t in portTypes)
                          DropdownMenuItem(
                            value: t,
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: registry.portType(t).color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(t, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _portType = v),
                    ),
                  ),
                const SizedBox(height: 4),
                Expanded(
                  child: scored.isEmpty
                      ? const Center(child: Text('No node found'))
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 12),
                          children: [
                            for (final cat in order) ...[
                              _header(
                                context,
                                theme,
                                cat,
                                byCategory[cat]!.length,
                                q.isNotEmpty,
                              ),
                              if (!_collapsed.contains(cat) || q.isNotEmpty)
                                _items(context, theme, byCategory[cat]!),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(
    BuildContext context,
    NodeEditorThemeData theme,
    String cat,
    int count,
    bool searching,
  ) {
    final expanded = searching || !_collapsed.contains(cat);
    final child =
        widget.headerBuilder?.call(context, cat, count, expanded) ??
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: theme.panelForeground,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  cat.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: theme.panelForeground.withValues(alpha: 0.7),
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.panelForeground.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        );
    return InkWell(
      onTap: searching
          ? null
          : () => setState(
              () => _collapsed.contains(cat)
                  ? _collapsed.remove(cat)
                  : _collapsed.add(cat),
            ),
      child: child,
    );
  }

  Widget _items(
    BuildContext context,
    NodeEditorThemeData theme,
    List<NodeDefinition> defs,
  ) {
    switch (widget.layout) {
      case NodePaletteLayout.list:
        return Column(
          children: [
            for (final d in defs) _wrap(context, theme, d, _listTile(theme, d)),
          ],
        );
      case NodePaletteLayout.grid:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: LayoutBuilder(
            builder: (context, c) {
              final cols = (c.maxWidth / 110).floor().clamp(1, 6);
              final w = (c.maxWidth - (cols - 1) * 6) / cols;
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in defs)
                    SizedBox(
                      width: w,
                      child: _wrap(context, theme, d, _gridCard(theme, d)),
                    ),
                ],
              );
            },
          ),
        );
      case NodePaletteLayout.compact:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final d in defs) _wrap(context, theme, d, _chip(theme, d)),
            ],
          ),
        );
    }
  }

  Color _color(NodeEditorThemeData theme, NodeDefinition d) =>
      d.style?.headerColor ?? theme.nodeHeaderColor;

  Widget _listTile(NodeEditorThemeData theme, NodeDefinition d) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.panelBorderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _color(theme, d),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              d.icon ?? Icons.widgets_outlined,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (d.description != null)
                  Text(
                    d.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.panelForeground.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          _portDots(d),
        ],
      ),
    ),
  );

  Widget _portDots(NodeDefinition d) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final p in d.ports.take(6))
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: p.type.color,
            shape: p.direction == PortDirection.input
                ? BoxShape.circle
                : BoxShape.rectangle,
          ),
        ),
    ],
  );

  Widget _gridCard(NodeEditorThemeData theme, NodeDefinition d) => Container(
    height: 76,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: theme.panelBorderColor),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(d.icon ?? Icons.widgets_outlined, color: _color(theme, d)),
        const SizedBox(height: 6),
        Text(
          d.title,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    ),
  );

  Widget _chip(NodeEditorThemeData theme, NodeDefinition d) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _color(theme, d).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _color(theme, d).withValues(alpha: 0.5)),
    ),
    child: Text(d.title, style: const TextStyle(fontSize: 11)),
  );

  Widget _wrap(
    BuildContext context,
    NodeEditorThemeData theme,
    NodeDefinition d,
    Widget fallback,
  ) {
    final child = widget.itemBuilder?.call(context, d) ?? fallback;
    final clickable = widget.mode != NodePaletteMode.drag;
    final draggable = widget.mode != NodePaletteMode.click;
    Widget item = MouseRegion(
      cursor: draggable ? SystemMouseCursors.grab : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: clickable ? () => _add(d) : null,
        child: Tooltip(
          message: d.description ?? d.title,
          waitDuration: const Duration(milliseconds: 700),
          child: child,
        ),
      ),
    );
    if (draggable) {
      item = Draggable<NodeDragData>(
        data: NodeDragData(d.type),
        affinity: Axis.horizontal,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _DragFeedback(definition: d, theme: theme),
        child: item,
      );
    }
    return item;
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.definition, required this.theme});
  final NodeDefinition definition;
  final NodeEditorThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.85,
        child: Container(
          width: 160,
          decoration: BoxDecoration(
            color: theme.nodeColor,
            borderRadius: BorderRadius.circular(theme.nodeRadius),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12)],
          ),
          clipBehavior: Clip.antiAlias,
          child: Container(
            height: 34,
            color: definition.style?.headerColor ?? theme.nodeHeaderColor,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                if (definition.icon != null)
                  Icon(definition.icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    definition.title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
