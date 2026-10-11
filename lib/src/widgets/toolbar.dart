import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/controller.dart';
import '../core/viewport.dart';
import 'theme.dart';

/// An entry of a [NodeToolbar].
sealed class ToolbarEntry {
  const ToolbarEntry();
}

/// A toolbar button.
class ToolbarItem extends ToolbarEntry {
  /// Creates a button.
  const ToolbarItem({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isEnabled,
    this.isActive,
    this.isVisible,
  });

  /// Icon.
  final IconData icon;

  /// Tooltip.
  final String tooltip;

  /// Action.
  final void Function(NodeEditorController controller) onPressed;

  /// Enabled state (default: enabled).
  final bool Function(NodeEditorController controller)? isEnabled;

  /// Toggle state, highlighted when true.
  final bool Function(NodeEditorController controller)? isActive;

  /// Visibility (default: visible).
  final bool Function(NodeEditorController controller)? isVisible;
}

/// A separator.
class ToolbarDivider extends ToolbarEntry {
  /// Creates a separator.
  const ToolbarDivider({this.isVisible});

  /// Visibility (default: visible).
  final bool Function(NodeEditorController controller)? isVisible;
}

/// Quick actions: undo / redo, save, zoom, grid & snapping toggles, and
/// context actions for the current selection (delete, copy, lock, group,
/// align, distribute). Fully configurable through [items] and
/// [customItems].
class NodeToolbar extends StatelessWidget {
  /// Creates a toolbar.
  const NodeToolbar({
    super.key,
    required this.controller,
    this.items,
    this.customItems = const [],
    this.onSave,
    this.axis = Axis.horizontal,
    this.showSelectionItems = true,
    this.theme,
  });

  /// Controller.
  final NodeEditorController controller;

  /// Replaces the default items.
  final List<ToolbarEntry>? items;

  /// Appended after the default (or [items]) entries.
  final List<ToolbarEntry> customItems;

  /// Shows a save button when provided.
  final void Function(NodeEditorController controller)? onSave;

  /// Orientation.
  final Axis axis;

  /// Whether selection dependent items are shown.
  final bool showSelectionItems;

  /// Theme override.
  final NodeEditorThemeData? theme;

  /// The default entries.
  static List<ToolbarEntry> defaultItems({
    void Function(NodeEditorController controller)? onSave,
    bool selectionItems = true,
  }) {
    bool hasSel(NodeEditorController c) => c.selection.value.isNotEmpty;
    bool hasNodes(NodeEditorController c, [int n = 1]) =>
        c.selection.value.nodes.length >= n;
    return [
      ToolbarItem(
        icon: Icons.undo,
        tooltip: 'Undo (Ctrl+Z)',
        onPressed: (c) => c.undo(),
        isEnabled: (c) => c.history.canUndo,
      ),
      ToolbarItem(
        icon: Icons.redo,
        tooltip: 'Redo (Ctrl+Y)',
        onPressed: (c) => c.redo(),
        isEnabled: (c) => c.history.canRedo,
      ),
      if (onSave != null) ...[
        const ToolbarDivider(),
        ToolbarItem(
          icon: Icons.save_outlined,
          tooltip: 'Save',
          onPressed: onSave,
        ),
      ],
      const ToolbarDivider(),
      ToolbarItem(
        icon: Icons.zoom_in,
        tooltip: 'Zoom in',
        onPressed: (c) => c.zoomIn(),
      ),
      ToolbarItem(
        icon: Icons.zoom_out,
        tooltip: 'Zoom out',
        onPressed: (c) => c.zoomOut(),
      ),
      ToolbarItem(
        icon: Icons.fit_screen,
        tooltip: 'Fit view (Shift+F)',
        onPressed: (c) => c.fitView(),
      ),
      const ToolbarDivider(),
      ToolbarItem(
        icon: Icons.grid_on,
        tooltip: 'Show grid',
        isActive: (c) => c.canvasSettings.value.showGrid,
        onPressed: (c) {
          final s = c.canvasSettings.value;
          c.canvasSettings.value = s.copyWith(
            gridStyle: s.showGrid ? GridStyle.none : GridStyle.dots,
          );
        },
      ),
      ToolbarItem(
        icon: Icons.grid_4x4,
        tooltip: 'Grid style',
        isVisible: (c) => c.canvasSettings.value.showGrid,
        onPressed: (c) {
          final s = c.canvasSettings.value;
          final next = switch (s.gridStyle) {
            GridStyle.dots => GridStyle.lines,
            GridStyle.lines => GridStyle.cross,
            _ => GridStyle.dots,
          };
          c.canvasSettings.value = s.copyWith(gridStyle: next);
        },
      ),
      ToolbarItem(
        icon: Icons.straighten,
        tooltip: 'Snap to grid',
        isActive: (c) => c.canvasSettings.value.snapToGrid,
        onPressed: (c) {
          final s = c.canvasSettings.value;
          c.canvasSettings.value = s.copyWith(snapToGrid: !s.snapToGrid);
        },
      ),
      ToolbarItem(
        icon: Icons.highlight_alt,
        tooltip: 'Selection mode (drag selects)',
        isActive: (c) => c.config.panOnDrag == PanOnDrag.select,
        onPressed: (c) => c.config = c.config.copyWith(
          panOnDrag: c.config.panOnDrag == PanOnDrag.select
              ? PanOnDrag.pan
              : PanOnDrag.select,
        ),
      ),
      if (selectionItems) ...[
        ToolbarDivider(isVisible: hasSel),
        ToolbarItem(
          icon: Icons.delete_outline,
          tooltip: 'Delete (Del)',
          isVisible: hasSel,
          onPressed: (c) => c.deleteSelection(),
        ),
        ToolbarItem(
          icon: Icons.copy,
          tooltip: 'Copy (Ctrl+C)',
          isVisible: hasNodes,
          onPressed: (c) => c.copySelection(),
        ),
        ToolbarItem(
          icon: Icons.control_point_duplicate,
          tooltip: 'Duplicate (Ctrl+D)',
          isVisible: hasNodes,
          onPressed: (c) => c.duplicateSelection(),
        ),
        ToolbarItem(
          icon: Icons.lock_outline,
          tooltip: 'Lock / unlock (Ctrl+L)',
          isVisible: hasNodes,
          isActive: (c) => c.selection.value.nodes.every(
            (id) => c.graph.node(id)?.locked ?? false,
          ),
          onPressed: (c) => c.toggleLockSelection(),
        ),
        ToolbarItem(
          icon: Icons.account_tree_outlined,
          tooltip: 'Group into function (Ctrl+G)',
          isVisible: hasNodes,
          onPressed: (c) => c.groupSelection(),
        ),
        ToolbarItem(
          icon: Icons.align_horizontal_left,
          tooltip: 'Align left',
          isVisible: (c) => hasNodes(c, 2),
          onPressed: (c) => c.alignSelection(NodeAlignment.left),
        ),
        ToolbarItem(
          icon: Icons.align_horizontal_center,
          tooltip: 'Align centers',
          isVisible: (c) => hasNodes(c, 2),
          onPressed: (c) => c.alignSelection(NodeAlignment.centerHorizontal),
        ),
        ToolbarItem(
          icon: Icons.align_vertical_top,
          tooltip: 'Align top',
          isVisible: (c) => hasNodes(c, 2),
          onPressed: (c) => c.alignSelection(NodeAlignment.top),
        ),
        ToolbarItem(
          icon: Icons.align_vertical_center,
          tooltip: 'Align middles',
          isVisible: (c) => hasNodes(c, 2),
          onPressed: (c) => c.alignSelection(NodeAlignment.centerVertical),
        ),
        ToolbarItem(
          icon: Icons.horizontal_distribute,
          tooltip: 'Distribute horizontally',
          isVisible: (c) => hasNodes(c, 3),
          onPressed: (c) => c.distributeSelection(),
        ),
        ToolbarItem(
          icon: Icons.vertical_distribute,
          tooltip: 'Distribute vertically',
          isVisible: (c) => hasNodes(c, 3),
          onPressed: (c) => c.distributeSelection(horizontal: false),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = this.theme ?? NodeEditorThemeData.of(context);
    final entries = [
      ...(items ??
          defaultItems(onSave: onSave, selectionItems: showSelectionItems)),
      ...customItems,
    ];
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        controller.history,
        controller.selection,
        controller.canvasSettings,
        controller.scopeListenable,
      ]),
      builder: (context, _) {
        final children = <Widget>[];
        for (final e in entries) {
          switch (e) {
            case ToolbarItem():
              if (!(e.isVisible?.call(controller) ?? true)) continue;
              final enabled = e.isEnabled?.call(controller) ?? true;
              final active = e.isActive?.call(controller) ?? false;
              children.add(
                IconButton(
                  tooltip: e.tooltip,
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  isSelected: active,
                  style: IconButton.styleFrom(
                    foregroundColor: theme.panelForeground,
                    backgroundColor: active
                        ? theme.accentColor.withValues(alpha: 0.15)
                        : null,
                  ),
                  color: active ? theme.accentColor : theme.panelForeground,
                  icon: Icon(e.icon),
                  onPressed: enabled ? () => e.onPressed(controller) : null,
                ),
              );
            case ToolbarDivider():
              if (!(e.isVisible?.call(controller) ?? true)) continue;
              if (children.isEmpty || children.last is _Sep) continue;
              children.add(_Sep(axis: axis, color: theme.panelBorderColor));
          }
        }
        if (children.isNotEmpty && children.last is _Sep) children.removeLast();
        return Material(
          color: theme.panelColor,
          elevation: 1,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: theme.panelBorderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Flex(
              direction: axis,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        );
      },
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep({required this.axis, required this.color});
  final Axis axis;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: axis == Axis.horizontal ? 1 : 24,
    height: axis == Axis.horizontal ? 24 : 1,
    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    color: color,
  );
}

/// Shows the super node navigation path (Root › Function › ...) and lets
/// the user go back up. Hidden at the root.
class SuperNodeBreadcrumb extends StatelessWidget {
  /// Creates the breadcrumb.
  const SuperNodeBreadcrumb({super.key, required this.controller, this.theme});

  /// Controller.
  final NodeEditorController controller;

  /// Theme override.
  final NodeEditorThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final theme = this.theme ?? NodeEditorThemeData.of(context);
    return ListenableBuilder(
      listenable: controller.scopeListenable,
      builder: (context, _) {
        final scopes = controller.scopes;
        if (scopes.length <= 1) return const SizedBox.shrink();
        return Material(
          color: theme.panelColor,
          elevation: 1,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: theme.panelBorderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Back (Alt+Backspace)',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  color: theme.panelForeground,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: controller.exitSuperNode,
                ),
                for (var i = 0; i < scopes.length; i++) ...[
                  if (i > 0)
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: theme.panelForeground,
                    ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: i == scopes.length - 1
                          ? theme.accentColor
                          : theme.panelForeground,
                    ),
                    onPressed: i == scopes.length - 1
                        ? null
                        : () => controller.exitSuperNode(depth: i),
                    child: Text(scopes[i].label),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
