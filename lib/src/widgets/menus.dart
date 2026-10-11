import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/edge.dart';
import '../core/ids.dart';
import '../core/node.dart';
import '../core/supernode/super_node.dart';
import 'scope.dart';
import 'theme.dart';

/// A custom action of the node menu.
class NodeMenuAction {
  /// Creates an action.
  const NodeMenuAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.isVisible,
  });

  /// Icon.
  final IconData icon;

  /// Label / tooltip.
  final String label;

  /// Called with the controller and the node.
  final void Function(NodeEditorController controller, NodeInstance node)
  onSelected;

  /// Whether the action applies to a node (default: always).
  final bool Function(NodeInstance node)? isVisible;
}

/// A custom action of the edge menu.
class EdgeMenuAction {
  /// Creates an action.
  const EdgeMenuAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.isVisible,
  });

  /// Icon.
  final IconData icon;

  /// Label / tooltip.
  final String label;

  /// Called with the controller and the edge.
  final void Function(NodeEditorController controller, Edge edge) onSelected;

  /// Whether the action applies to an edge (default: always).
  final bool Function(Edge edge)? isVisible;
}

class _Item {
  const _Item(
    this.icon,
    this.label,
    this.onTap, {
    this.destructive = false,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool enabled;
}

List<_Item> _nodeItems(
  NodeEditorController c,
  NodeInstance node,
  List<NodeMenuAction> extra,
) {
  final cfg = c.config;
  final isSuper = node.definition is SuperNodeNodeDefinition;
  final multi = c.selection.value.nodes.length > 1;
  return [
    _Item(Icons.tune, 'Edit', () => c.editNodeHandler?.call(node.id)),
    if (isSuper)
      _Item(Icons.login, 'Open function', () => c.enterSuperNode(node.id)),
    if (node.definition.copyable) _Item(Icons.copy, 'Copy', c.copySelection),
    if (node.definition.copyable)
      _Item(Icons.control_point_duplicate, 'Duplicate', c.duplicateSelection),
    _Item(
      node.locked ? Icons.lock_open : Icons.lock_outline,
      node.locked ? 'Unlock' : 'Lock',
      c.toggleLockSelection,
    ),
    if (multi)
      _Item(
        Icons.account_tree_outlined,
        'Group into function',
        () => c.groupSelection(),
      ),
    if (isSuper) _Item(Icons.call_split, 'Ungroup', c.ungroupSelection),
    if (isSuper)
      _Item(
        Icons.fork_right,
        'Make unique copy',
        () => c.superNodes.detach(c, node.id),
      ),
    for (final a in extra)
      if (a.isVisible?.call(node) ?? true)
        _Item(a.icon, a.label, () => a.onSelected(c, node)),
    if (cfg.deletable && node.definition.deletable && !node.locked)
      _Item(
        Icons.delete_outline,
        'Delete',
        c.deleteSelection,
        destructive: true,
      ),
  ];
}

List<_Item> _edgeItems(
  NodeEditorController c,
  Edge edge,
  List<EdgeMenuAction> extra,
) {
  return [
    _Item(Icons.tune, 'Edit link', () => c.editEdgeHandler?.call(edge.id)),
    _Item(
      edge.style.animated ? Icons.motion_photos_off : Icons.animation,
      edge.style.animated ? 'Stop animation' : 'Animate',
      () => c.updateEdge(
        edge.id,
        (e) => e.copyWith(style: e.style.copyWith(animated: !e.style.animated)),
      ),
    ),
    for (final a in extra)
      if (a.isVisible?.call(edge) ?? true)
        _Item(a.icon, a.label, () => a.onSelected(c, edge)),
    if (c.config.deletable)
      _Item(
        Icons.delete_outline,
        'Delete link',
        () => c.remove(edges: [edge.id]),
        destructive: true,
      ),
  ];
}

class _MenuBar extends StatelessWidget {
  const _MenuBar({required this.items, required this.theme});
  final List<_Item> items;
  final NodeEditorThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.panelColor,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.panelBorderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final i in items)
              IconButton(
                tooltip: i.label,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: i.destructive
                    ? theme.invalidTargetColor
                    : theme.panelForeground,
                icon: Icon(i.icon),
                onPressed: i.onTap,
              ),
          ],
        ),
      ),
    );
  }
}

/// Floating menu above the selected node (delete, copy, lock, edit...).
class NodeMenuOverlay extends StatelessWidget {
  /// Creates the overlay.
  const NodeMenuOverlay({
    super.key,
    required this.controller,
    this.extraActions = const [],
  });

  /// Controller.
  final NodeEditorController controller;

  /// Custom actions.
  final List<NodeMenuAction> extraActions;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ValueListenableBuilder<NodeId?>(
      valueListenable: c.menuNode,
      builder: (context, id, _) {
        final node = id == null ? null : c.graph.node(id);
        if (node == null ||
            !(node.definition.showMenu ?? c.config.showNodeMenu)) {
          return const SizedBox.shrink();
        }
        final theme = NodeEditorScope.of(context).theme;
        return ListenableBuilder(
          listenable: Listenable.merge([
            c.viewport,
            c.nodePositionListenable(node.id),
            c.nodeListenable(node.id),
            c.connectionDraft,
          ]),
          builder: (context, _) {
            final v = c.viewport.value;
            if (v.zoom < c.config.lodThreshold ||
                c.connectionDraft.value != null ||
                !c.graph.containsNode(node.id)) {
              return const SizedBox.shrink();
            }
            final anchor = v.toScreen(
              Offset(node.rect.center.dx, node.rect.top),
            );
            return Stack(
              children: [
                Positioned(
                  left: anchor.dx,
                  top: anchor.dy - 52,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, 0),
                    child: _MenuBar(
                      items: _nodeItems(c, node, extraActions),
                      theme: theme,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Floating menu at the tap position of the selected edge.
class EdgeMenuOverlay extends StatelessWidget {
  /// Creates the overlay.
  const EdgeMenuOverlay({
    super.key,
    required this.controller,
    this.extraActions = const [],
  });

  /// Controller.
  final NodeEditorController controller;

  /// Custom actions.
  final List<EdgeMenuAction> extraActions;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ValueListenableBuilder<(EdgeId, Offset)?>(
      valueListenable: c.menuEdge,
      builder: (context, value, _) {
        final edge = value == null ? null : c.graph.edge(value.$1);
        if (edge == null || !c.config.showEdgeMenu) {
          return const SizedBox.shrink();
        }
        final theme = NodeEditorScope.of(context).theme;
        return ValueListenableBuilder(
          valueListenable: c.viewport,
          builder: (context, v, _) {
            final p = v.toScreen(value!.$2);
            return Stack(
              children: [
                Positioned(
                  left: p.dx,
                  top: p.dy - 52,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, 0),
                    child: _MenuBar(
                      items: _edgeItems(c, edge, extraActions),
                      theme: theme,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

Future<void> _showItems(
  BuildContext context,
  Offset global,
  List<_Item> items,
) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(global);
  final selected = await showMenu<_Item>(
    context: context,
    position: RelativeRect.fromLTRB(
      local.dx,
      local.dy,
      overlay.size.width - local.dx,
      overlay.size.height - local.dy,
    ),
    items: [
      for (final i in items)
        PopupMenuItem(
          value: i,
          enabled: i.enabled,
          height: 36,
          child: Row(
            children: [
              Icon(
                i.icon,
                size: 18,
                color: i.destructive
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
              const SizedBox(width: 10),
              Text(i.label),
            ],
          ),
        ),
    ],
  );
  selected?.onTap();
}

/// Shows the context menu of node [id] at [global].
Future<void> showNodeContextMenu(
  BuildContext context,
  NodeEditorController controller,
  NodeId id,
  Offset global, {
  List<NodeMenuAction> extraActions = const [],
}) async {
  final node = controller.graph.node(id);
  if (node == null) return;
  await _showItems(context, global, _nodeItems(controller, node, extraActions));
}

/// Shows the context menu of edge [id] at [global].
Future<void> showEdgeContextMenu(
  BuildContext context,
  NodeEditorController controller,
  EdgeId id,
  Offset global, {
  List<EdgeMenuAction> extraActions = const [],
}) async {
  final edge = controller.graph.edge(id);
  if (edge == null) return;
  await _showItems(context, global, _edgeItems(controller, edge, extraActions));
}

/// An entry of the canvas context menu (right click on empty canvas).
class CanvasMenuAction {
  /// Creates an action.
  const CanvasMenuAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.isVisible,
    this.isEnabled,
    this.destructive = false,
  });

  /// Icon.
  final IconData icon;

  /// Label.
  final String label;

  /// Called with the canvas context, the controller and the clicked canvas
  /// position.
  final void Function(
    BuildContext context,
    NodeEditorController controller,
    Offset canvasPosition,
  )
  onSelected;

  /// Whether the action is listed (default: always).
  final bool Function(NodeEditorController controller)? isVisible;

  /// Whether the action can be chosen (default: always).
  final bool Function(NodeEditorController controller)? isEnabled;

  /// Shown in the error color.
  final bool destructive;

  /// "Add node…": searchable node list, the node is added where the user
  /// clicked.
  static final addNode = CanvasMenuAction(
    icon: Icons.add_box_outlined,
    label: 'Add node…',
    onSelected: (context, c, pos) => showQuickAddDialog(context, c, pos),
  );

  /// "Paste here".
  static final paste = CanvasMenuAction(
    icon: Icons.content_paste,
    label: 'Paste here',
    isEnabled: (c) => c.clipboard != null || c.config.useSystemClipboard,
    onSelected: (context, c, pos) => c.paste(at: pos),
  );

  /// "Select all".
  static final selectAll = CanvasMenuAction(
    icon: Icons.select_all,
    label: 'Select all',
    isEnabled: (c) => c.graph.nodeCount > 0,
    onSelected: (context, c, pos) => c.selectAll(),
  );

  /// "Fit view".
  static final fitView = CanvasMenuAction(
    icon: Icons.fit_screen,
    label: 'Fit view',
    isEnabled: (c) => c.graph.nodeCount > 0,
    onSelected: (context, c, pos) => c.fitView(),
  );

  /// "Auto layout".
  static final autoLayout = CanvasMenuAction(
    icon: Icons.auto_fix_high,
    label: 'Auto layout',
    isEnabled: (c) => c.graph.nodeCount > 1,
    onSelected: (context, c, pos) {
      c.autoLayout();
      c.fitView();
    },
  );

  /// "Undo".
  static final undo = CanvasMenuAction(
    icon: Icons.undo,
    label: 'Undo',
    isEnabled: (c) => c.history.canUndo,
    onSelected: (context, c, pos) => c.undo(),
  );

  /// "Leave function" (only inside a super node).
  static final exitFunction = CanvasMenuAction(
    icon: Icons.arrow_back,
    label: 'Leave function',
    isVisible: (c) => c.scopes.length > 1,
    onSelected: (context, c, pos) => c.exitSuperNode(),
  );

  /// The default menu.
  static List<CanvasMenuAction> get defaults => [
    addNode,
    paste,
    selectAll,
    fitView,
    autoLayout,
    undo,
    exitFunction,
  ];
}

/// Shows the canvas context menu at [global] with [actions].
Future<void> showCanvasContextMenu(
  BuildContext context,
  NodeEditorController controller,
  Offset canvasPosition,
  Offset global, {
  List<CanvasMenuAction>? actions,
}) async {
  final items = [
    for (final a in actions ?? CanvasMenuAction.defaults)
      if (a.isVisible?.call(controller) ?? true)
        _Item(
          a.icon,
          a.label,
          () => a.onSelected(context, controller, canvasPosition),
          destructive: a.destructive,
          enabled: a.isEnabled?.call(controller) ?? true,
        ),
  ];
  if (items.isEmpty) return;
  await _showItems(context, global, items);
}

/// Searchable list of node types; the chosen node is added with its
/// top-left corner at [canvasPosition].
Future<void> showQuickAddDialog(
  BuildContext context,
  NodeEditorController controller,
  Offset canvasPosition,
) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _QuickAddDialog(controller: controller, position: canvasPosition),
  );
}

class _QuickAddDialog extends StatefulWidget {
  const _QuickAddDialog({required this.controller, required this.position});
  final NodeEditorController controller;
  final Offset position;

  @override
  State<_QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<_QuickAddDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final q = _query.trim().toLowerCase();
    final defs = [
      for (final d in c.registry.definitions)
        if (!d.category.startsWith('__') &&
            c.canInsertType(d.type) &&
            (q.isEmpty ||
                d.title.toLowerCase().contains(q) ||
                d.category.toLowerCase().contains(q) ||
                d.tags.any((t) => t.toLowerCase().contains(q))))
          d,
    ];
    void add(NodeDefinition d) {
      Navigator.pop(context);
      c.addNode(d.type, position: widget.position);
    }

    return AlertDialog(
      title: const Text('Add node'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Search…',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
              onSubmitted: (_) {
                if (defs.isNotEmpty) add(defs.first);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final d in defs)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        d.icon ?? Icons.widgets_outlined,
                        color: d.style?.headerColor,
                      ),
                      title: Text(d.title),
                      subtitle: Text(d.category),
                      onTap: () => add(d),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
