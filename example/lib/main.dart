import 'package:flutter/material.dart';
import 'package:node_program_editor/node_program_editor.dart';

import 'automation/automation_page.dart';
import 'scientific/scientific_page.dart';
import 'stress/stress_page.dart';
import 'vision/vision_page.dart';

void main() => runApp(const ShowcaseApp());

const _seed = Color(0xFF3B82F6);
const repoUrl = 'https://github.com/avagst3/node_program_editor';

class ShowcaseApp extends StatefulWidget {
  const ShowcaseApp({super.key});

  @override
  State<ShowcaseApp> createState() => _ShowcaseAppState();
}

class _ShowcaseAppState extends State<ShowcaseApp> {
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'node_program_editor — showcase',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: ThemeData(
        colorSchemeSeed: _seed,
        brightness: Brightness.light,
        extensions: [NodeEditorThemeData.light()],
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
        extensions: [NodeEditorThemeData.dark()],
      ),
      home: ShowcaseShell(
        dark: _mode == ThemeMode.dark,
        onToggleTheme: () => setState(
          () => _mode = _mode == ThemeMode.dark
              ? ThemeMode.light
              : ThemeMode.dark,
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.builder);
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}

class ShowcaseShell extends StatefulWidget {
  const ShowcaseShell({
    super.key,
    required this.dark,
    required this.onToggleTheme,
  });
  final bool dark;
  final VoidCallback onToggleTheme;

  @override
  State<ShowcaseShell> createState() => _ShowcaseShellState();
}

class _ShowcaseShellState extends State<ShowcaseShell> {
  int _index = 0;
  final Map<int, Widget> _pages = {};

  late final List<_Destination> _destinations = [
    _Destination(
      'Overview',
      Icons.home_outlined,
      (_) => OverviewPage(onOpen: _open),
    ),
    _Destination('Automation', Icons.bolt, (_) => const AutomationPage()),
    _Destination(
      'Scientific',
      Icons.science_outlined,
      (_) => const ScientificPage(),
    ),
    _Destination('Vision', Icons.camera_outlined, (_) => const VisionPage()),
    _Destination('Stress test', Icons.speed, (_) => const StressPage()),
  ];

  void _open(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 1100;
    // Pages are built lazily and kept alive (each owns its controller).
    _pages.putIfAbsent(_index, () => _destinations[_index].builder(context));
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: wide,
            minExtendedWidth: 190,
            selectedIndex: _index,
            onDestinationSelected: _open,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: wide
                  ? const Text(
                      'node_program_editor',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    )
                  : const Icon(Icons.hub),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    tooltip: widget.dark ? 'Light theme' : 'Dark theme',
                    icon: Icon(
                      widget.dark ? Icons.light_mode : Icons.dark_mode,
                    ),
                    onPressed: widget.onToggleTheme,
                  ),
                ),
              ),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                for (var i = 0; i < _destinations.length; i++)
                  _pages[i] ?? const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.onOpen});
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget card(int index, IconData icon, String title, String text) =>
        SizedBox(
          width: 330,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onOpen(index),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 32, color: t.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(title, style: t.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(text, style: t.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    Text(
                      'Open →',
                      style: TextStyle(color: t.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    Widget feature(IconData icon, String text) =>
        Chip(avatar: Icon(icon, size: 16), label: Text(text));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('node_program_editor 3.0', style: t.textTheme.displaySmall),
              const SizedBox(height: 8),
              Text(
                'A node graph engine for Flutter, React Flow style: you bring the nodes, '
                'it brings the canvas, interactions, serialization and performance. '
                'Zero dependencies, GPU fragment shaders, level-of-detail rendering for '
                'tens of thousands of nodes.',
                style: t.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  feature(Icons.bolt, 'Shader grid & animated links'),
                  feature(Icons.layers, 'Viewport culling + LOD'),
                  feature(Icons.undo, 'Undo / redo'),
                  feature(
                    Icons.account_tree_outlined,
                    'Super nodes (functions)',
                  ),
                  feature(Icons.tune, '25 parameter types'),
                  feature(Icons.route, 'Bezier, step, orthogonal, waypoints'),
                  feature(Icons.save_outlined, 'Design + logic files'),
                  feature(Icons.map_outlined, 'Minimap, palette, toolbar'),
                ],
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  card(
                    1,
                    Icons.bolt,
                    'Workflow automation',
                    'An n8n-like builder: triggers, HTTP, branching, AI agents. Execute the workflow and watch data flow through animated links.',
                  ),
                  card(
                    2,
                    Icons.science_outlined,
                    'Scientific & control',
                    'Simulink / LabVIEW-like dataflow: generators, filters, PID loop, FFT and live oscilloscopes recomputed on every edit.',
                  ),
                  card(
                    3,
                    Icons.camera_outlined,
                    'Computer vision',
                    'A Basler pylon-like pipeline: camera with AOI, blur, threshold, morphology, blob analysis and a PASS / FAIL verdict.',
                  ),
                  card(
                    4,
                    Icons.speed,
                    'Stress test',
                    'Generate up to 50 000 nodes and sweep the zoom across the level-of-detail threshold while watching the frame rate.',
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text('Try it', style: t.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                '• Drag nodes from the palette (or click them).\n'
                '• Drag from a port to another port to link them; incompatible ports dim.\n'
                '• Shift + drag on the background draws a selection box.\n'
                '• Select nodes and press Ctrl+G to turn them into a reusable function; double click it to open it.\n'
                '• Click a link, then drag its "+" handle to add waypoints.\n'
                '• Ctrl+Z / Ctrl+Y, Ctrl+C / Ctrl+V, Del, Ctrl+L (lock), Shift+F (fit).\n'
                '• Document → Export shows the separate design and logic JSON files.',
              ),
              const SizedBox(height: 24),
              SelectableText(
                'Documentation and source: $repoUrl',
                style: TextStyle(color: t.colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
