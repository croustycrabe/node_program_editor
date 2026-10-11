import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:node_program_editor/node_program_editor.dart';

import '../shared/fps_meter.dart';

/// Generates very large graphs to demonstrate culling, the low-detail
/// renderer and the shader grid.
class StressPage extends StatefulWidget {
  const StressPage({super.key});

  @override
  State<StressPage> createState() => _StressPageState();
}

class _StressPageState extends State<StressPage>
    with SingleTickerProviderStateMixin {
  static const _colors = [
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFF7C3AED),
  ];

  late final NodeEditorController c = NodeEditorController(
    registry: NodeRegistry(
      definitions: [
        for (var i = 0; i < _colors.length; i++)
          NodeDefinition(
            type: 'stress.$i',
            title: 'Block ${String.fromCharCode(65 + i)}',
            category: 'Stress',
            icon: Icons.memory,
            defaultSize: const Size(180, 84),
            style: NodeStyle(headerColor: _colors[i]),
            ports: const [
              PortSpec.input('in', label: 'in', type: PortType.number),
              PortSpec.output('out', label: 'out', type: PortType.number),
            ],
          ),
      ],
    ),
  );
  late final Ticker _auto = createTicker(_onAuto);
  int _count = 0;
  Duration _buildTime = Duration.zero;
  bool _animating = false;
  bool _shaders = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate(1000));
  }

  @override
  void dispose() {
    _auto.dispose();
    c.dispose();
    super.dispose();
  }

  void _generate(int n) {
    final sw = Stopwatch()..start();
    c.clear();
    final cols = math.sqrt(n * 1.8).ceil();
    final nodes = <NodeInstance>[];
    final edges = <Edge>[];
    final defs = c.registry.definitions.toList();
    for (var i = 0; i < n; i++) {
      final col = i % cols, row = i ~/ cols;
      nodes.add(
        NodeInstance.create(
          defs[(row + col) % defs.length],
          position: Offset(col * 240.0, row * 140.0),
        ),
      );
      if (col > 0) {
        edges.add(
          Edge(
            id: IdGenerator.edge(),
            source: PortRef(nodes[i - 1].id, 'out'),
            target: PortRef(nodes[i].id, 'in'),
            style: EdgeStyle(animated: i % 97 == 0),
          ),
        );
      }
    }
    c.addElements(nodes, edges, label: 'Generate');
    c.history.clear();
    sw.stop();
    setState(() {
      _count = n;
      _buildTime = sw.elapsed;
    });
    c.fitView(animate: false, padding: 24);
  }

  void _onAuto(Duration t) {
    final s = t.inMicroseconds / 1e6;
    final b = c.boundsOf();
    if (b == null) return;
    // Sweep zoom across the LOD threshold while drifting over the graph.
    final zoom = 0.08 + 0.9 * (0.5 + 0.5 * math.sin(s * 0.6));
    final focus = Offset(
      b.left + b.width * (0.5 + 0.4 * math.sin(s * 0.23)),
      b.top + b.height * (0.5 + 0.4 * math.cos(s * 0.17)),
    );
    c.setViewport(
      EditorViewport(
        offset: c.viewportSize.center(Offset.zero) - focus * zoom,
        zoom: zoom,
      ),
    );
  }

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
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Icon(Icons.speed, color: t.colorScheme.primary),
                Text('Stress test', style: t.textTheme.titleMedium),
                const SizedBox(width: 12),
                for (final n in [1000, 5000, 10000, 25000, 50000])
                  OutlinedButton(
                    onPressed: () => _generate(n),
                    child: Text('${n ~/ 1000}k nodes'),
                  ),
                FilterChip(
                  label: const Text('Auto pan & zoom'),
                  selected: _animating,
                  onSelected: (on) {
                    setState(() => _animating = on);
                    on ? _auto.start() : _auto.stop();
                  },
                ),
                FilterChip(
                  label: const Text('GPU shaders'),
                  selected: _shaders,
                  onSelected: (on) => setState(() => _shaders = on),
                ),
                Text(
                  'built in ${_buildTime.inMilliseconds} ms',
                  style: t.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: NodeEditor(
            controller: c,
            showPalette: false,
            useShaders: _shaders,
            overlays: [
              Positioned(
                left: 12,
                bottom: 12,
                child: ListenableBuilder(
                  listenable: c.viewport,
                  builder: (context, _) => FpsMeter(
                    extra: () => [
                      'nodes $_count · edges ${c.graph.edgeCount}',
                      'zoom ${c.viewport.value.zoom.toStringAsFixed(2)} · '
                          '${c.viewport.value.zoom < c.config.lodThreshold ? 'LOD (vertices)' : 'widgets'}',
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
