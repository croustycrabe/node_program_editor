import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:node_program_editor/node_program_editor.dart';

import 'file_io.dart';

/// Common layout of a showcase: header with document actions + editor.
class ShowcasePage extends StatelessWidget {
  const ShowcasePage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.controller,
    required this.fileStem,
    this.actions = const [],
    this.toolbarItems = const [],
    this.nodeMenuActions = const [],
    this.services = const NodeEditorServices(),
    this.sidePanel,
    this.overlays = const [],
    this.paletteLayout = NodePaletteLayout.list,
    this.canvasMenuActions,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final NodeEditorController controller;
  final String fileStem;
  final List<Widget> actions;
  final List<ToolbarEntry> toolbarItems;
  final List<NodeMenuAction> nodeMenuActions;
  final NodeEditorServices services;
  final Widget? sidePanel;
  final List<Widget> overlays;
  final NodePaletteLayout paletteLayout;
  final List<CanvasMenuAction>? canvasMenuActions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: t.colorScheme.surface,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.dividerColor)),
            ),
            child: Row(
              children: [
                Icon(icon, color: t.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.textTheme.titleMedium),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                ...actions,
                const SizedBox(width: 8),
                _DocumentMenu(controller: controller, fileStem: fileStem),
              ],
            ),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: NodeEditor(
                  controller: controller,
                  services: services,
                  customToolbarItems: toolbarItems,
                  nodeMenuActions: nodeMenuActions,
                  paletteLayout: paletteLayout,
                  canvasMenuActions: canvasMenuActions,
                  overlays: overlays,
                  onSave: (c) => showExportDialog(context, c, fileStem),
                ),
              ),
              ?sidePanel,
            ],
          ),
        ),
      ],
    );
  }
}

class _DocumentMenu extends StatelessWidget {
  const _DocumentMenu({required this.controller, required this.fileStem});
  final NodeEditorController controller;
  final String fileStem;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.upload_file),
          onPressed: () => showExportDialog(context, controller, fileStem),
          child: const Text('Export design + logic'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.file_open_outlined),
          onPressed: () => showImportDialog(context, controller),
          child: const Text('Import…'),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.inventory_2_outlined),
          onPressed: () => _exportLibrary(context),
          child: const Text('Export function library'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.library_add_outlined),
          onPressed: () => _importLibrary(context),
          child: const Text('Import function library'),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_sweep_outlined),
          onPressed: controller.clear,
          child: const Text('Clear canvas'),
        ),
      ],
      builder: (context, menu, _) => FilledButton.tonalIcon(
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        icon: const Icon(Icons.description_outlined, size: 18),
        label: const Text('Document'),
      ),
    );
  }

  void _exportLibrary(BuildContext context) {
    final lib = controller.superNodes;
    if (lib.definitions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No function yet: select nodes and press Ctrl+G.'),
        ),
      );
      return;
    }
    _showJson(context, 'Function library', {
      '$fileStem.functions.json': lib.exportLibrary(),
    });
  }

  Future<void> _importLibrary(BuildContext context) async {
    final text = await _askJson(context, 'Import function library');
    if (text == null) return;
    try {
      final ids = controller.superNodes.importLibrary(text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ids.length} function(s) added to the palette.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) _error(context, e);
    }
  }
}

void _error(BuildContext context, Object e) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Error: $e')));

/// Shows the logic, design and flattened logic files.
Future<void> showExportDialog(
  BuildContext context,
  NodeEditorController c,
  String stem,
) {
  final logic = c.exportLogic(
    metadata: {'app': 'node_program_editor showcase'},
  );
  return _showJson(context, 'Export', {
    '$stem.logic.json': logic.toJsonString(),
    '$stem.design.json': c.exportDesign().toJsonString(),
    '$stem.flat.logic.json': logic.flatten().toJsonString(),
  });
}

Future<void> _showJson(
  BuildContext context,
  String title,
  Map<String, String> files,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => DefaultTabController(
      length: files.length,
      child: AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 720,
          height: 480,
          child: Column(
            children: [
              if (files.length > 1)
                TabBar(
                  isScrollable: true,
                  tabs: [for (final f in files.keys) Tab(text: f)],
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final e in files.entries)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  e.value,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '${(e.value.length / 1024).toStringAsFixed(1)} KB',
                              ),
                              const Spacer(),
                              TextButton.icon(
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copy'),
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(text: e.value),
                                ),
                              ),
                              if (canUseBrowserFiles)
                                FilledButton.icon(
                                  icon: const Icon(Icons.download, size: 16),
                                  label: const Text('Download'),
                                  onPressed: () => downloadText(e.key, e.value),
                                ),
                            ],
                          ),
                        ],
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
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}

Future<String?> _askJson(
  BuildContext context,
  String title, {
  String hint = 'Paste JSON here',
}) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 600,
        child: TextField(
          controller: ctl,
          minLines: 12,
          maxLines: 20,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        if (canUseBrowserFiles)
          TextButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('Open file…'),
            onPressed: () async {
              final f = await pickTextFile();
              if (f != null) ctl.text = f.$2;
            },
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctl.text),
          child: const Text('Import'),
        ),
      ],
    ),
  );
}

/// Imports a logic file and an optional design file.
Future<void> showImportDialog(
  BuildContext context,
  NodeEditorController c,
) async {
  final logic = await _askJson(
    context,
    'Import logic file',
    hint: 'Paste a *.logic.json file',
  );
  if (logic == null || logic.trim().isEmpty || !context.mounted) return;
  final design = await _askJson(
    context,
    'Import design file (optional)',
    hint: 'Paste a *.design.json file, or leave empty for automatic layout',
  );
  try {
    c.load(
      LogicDocument.fromJsonString(logic),
      design == null || design.trim().isEmpty
          ? null
          : DesignDocument.fromJsonString(design),
    );
  } catch (e) {
    if (context.mounted) _error(context, e);
  }
}
