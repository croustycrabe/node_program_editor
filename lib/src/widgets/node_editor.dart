import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../render/node_layer.dart';
import 'canvas.dart';
import 'menus.dart';
import 'minimap.dart';
import 'node_render_context.dart';
import 'palette.dart';
import 'scope.dart';
import 'theme.dart';
import 'toolbar.dart';

/// Where the palette is docked.
enum PalettePosition {
  /// Left of the canvas.
  left,

  /// Right of the canvas.
  right,
}

/// A ready-made editor: palette + canvas + floating toolbar, minimap and
/// super node breadcrumb, all bound to one [controller].
///
/// Every piece is a public widget ([NodePalette], [NodeCanvas],
/// [NodeToolbar], [NodeMiniMap], [SuperNodeBreadcrumb]) that can be composed
/// differently when this layout does not fit.
class NodeEditor extends StatelessWidget {
  /// Creates an editor.
  const NodeEditor({
    super.key,
    required this.controller,
    this.theme,
    this.services = const NodeEditorServices(),
    this.showPalette = true,
    this.palette,
    this.paletteWidth = 270,
    this.palettePosition = PalettePosition.left,
    this.paletteMode = NodePaletteMode.both,
    this.paletteLayout = NodePaletteLayout.list,
    this.showToolbar = true,
    this.toolbar,
    this.toolbarItems,
    this.customToolbarItems = const [],
    this.onSave,
    this.showMinimap = true,
    this.minimapSize = const Size(200, 140),
    this.showBreadcrumb = true,
    this.nodeBuilder,
    this.portBuilder,
    this.nodeMenuActions = const [],
    this.edgeMenuActions = const [],
    this.overlays = const [],
    this.useShaders = true,
  });

  /// Controller.
  final NodeEditorController controller;

  /// Theme (defaults to [NodeEditorThemeData.of]).
  final NodeEditorThemeData? theme;

  /// Host services.
  final NodeEditorServices services;

  /// Whether the palette is shown.
  final bool showPalette;

  /// Replaces the default palette.
  final Widget? palette;

  /// Palette width.
  final double paletteWidth;

  /// Palette side.
  final PalettePosition palettePosition;

  /// Palette insertion mode.
  final NodePaletteMode paletteMode;

  /// Palette item layout.
  final NodePaletteLayout paletteLayout;

  /// Whether the toolbar is shown.
  final bool showToolbar;

  /// Replaces the default toolbar.
  final Widget? toolbar;

  /// Replaces the default toolbar entries.
  final List<ToolbarEntry>? toolbarItems;

  /// Extra toolbar entries.
  final List<ToolbarEntry> customToolbarItems;

  /// Adds a save button to the toolbar.
  final void Function(NodeEditorController controller)? onSave;

  /// Whether the minimap is shown.
  final bool showMinimap;

  /// Minimap size.
  final Size minimapSize;

  /// Whether the super node breadcrumb is shown.
  final bool showBreadcrumb;

  /// See [NodeCanvas.nodeBuilder].
  final NodeSlotBuilder? nodeBuilder;

  /// See [NodeCanvas.portBuilder].
  final PortWidgetBuilder? portBuilder;

  /// See [NodeCanvas.nodeMenuActions].
  final List<NodeMenuAction> nodeMenuActions;

  /// See [NodeCanvas.edgeMenuActions].
  final List<EdgeMenuAction> edgeMenuActions;

  /// Extra overlays stacked over the canvas.
  final List<Widget> overlays;

  /// See [NodeCanvas.useShaders].
  final bool useShaders;

  @override
  Widget build(BuildContext context) {
    final theme = this.theme ?? NodeEditorThemeData.of(context);
    final canvas = NodeCanvas(
      controller: controller,
      theme: theme,
      services: services,
      nodeBuilder: nodeBuilder,
      portBuilder: portBuilder,
      nodeMenuActions: nodeMenuActions,
      edgeMenuActions: edgeMenuActions,
      useShaders: useShaders,
      overlays: [
        if (showToolbar)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child:
                    toolbar ??
                    NodeToolbar(
                      controller: controller,
                      theme: theme,
                      items: toolbarItems,
                      customItems: customToolbarItems,
                      onSave: onSave,
                    ),
              ),
            ),
          ),
        if (showBreadcrumb)
          Positioned(
            top: showToolbar ? 64 : 12,
            left: 12,
            child: SuperNodeBreadcrumb(controller: controller, theme: theme),
          ),
        if (showMinimap)
          Positioned(
            right: 12,
            bottom: 12,
            child: NodeMiniMap(
              controller: controller,
              theme: theme,
              width: minimapSize.width,
              height: minimapSize.height,
            ),
          ),
        ...overlays,
      ],
    );
    if (!showPalette) return canvas;
    final side = SizedBox(
      width: paletteWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: palettePosition == PalettePosition.right
                ? BorderSide(color: theme.panelBorderColor)
                : BorderSide.none,
            right: palettePosition == PalettePosition.left
                ? BorderSide(color: theme.panelBorderColor)
                : BorderSide.none,
          ),
        ),
        child:
            palette ??
            NodePalette(
              controller: controller,
              theme: theme,
              mode: paletteMode,
              layout: paletteLayout,
            ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (palettePosition == PalettePosition.left) side,
        Expanded(child: canvas),
        if (palettePosition == PalettePosition.right) side,
      ],
    );
  }
}
