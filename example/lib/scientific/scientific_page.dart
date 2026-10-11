import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:node_program_editor/node_program_editor.dart';

import '../shared/file_io.dart';
import '../shared/showcase_page.dart';
import 'sci_engine.dart';
import 'sci_nodes.dart';

/// Simulink / LabVIEW-like signal processing and control showcase.
class ScientificPage extends StatefulWidget {
  const ScientificPage({super.key});

  @override
  State<ScientificPage> createState() => _ScientificPageState();
}

class _ScientificPageState extends State<ScientificPage>
    with SingleTickerProviderStateMixin {
  late final NodeEditorController c = NodeEditorController(
    canvasSettings: const CanvasSettings(
      gridStyle: GridStyle.lines,
      gridSpacing: 20,
      majorEvery: 5,
      snapToGrid: true,
      defaultEdgeStyle: EdgeStyle(pathType: EdgePathType.bezier, width: 2.5),
    ),
  );
  late final SciEngine engine = SciEngine(c);
  late final Ticker _live = createTicker(_onLive);
  Timer? _debounce;
  bool _isLive = false;

  @override
  void initState() {
    super.initState();
    c.registry.registerAll(scientificNodes(engine));
    // Simulink style: forbid algebraic loops.
    c.validator = const ConnectionValidator(allowCycles: false);
    c.revision.addListener(_schedule);
    _buildDemo();
    engine.run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _live.dispose();
    c.revision.removeListener(_schedule);
    engine.dispose();
    c.dispose();
    super.dispose();
  }

  void _schedule() {
    if (_isLive) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 30), engine.run);
  }

  void _onLive(Duration elapsed) {
    engine.timeOffset = elapsed.inMicroseconds / 1e6;
    engine.run();
  }

  void _toggleLive() {
    setState(() => _isLive = !_isLive);
    if (_isLive) {
      _live.start();
    } else {
      _live.stop();
      engine.timeOffset = 0;
      engine.run();
    }
  }

  void _buildDemo() {
    NodeInstance add(
      String type,
      double x,
      double y, {
      Map<String, Object?>? params,
      String? title,
    }) => c.addNode(
      type,
      position: Offset(x, y),
      params: params,
      title: title,
      select: false,
    );
    void link(NodeInstance a, String ap, NodeInstance b, String bp) =>
        c.connect(PortRef(a.id, ap), PortRef(b.id, bp));

    final sine = add('sci.sine', 0, 0);
    final noise = add('sci.noise', 0, 200);
    final sum = add('sci.sum', 280, 80);
    final lp = add('sci.lowpass', 540, 160);
    final scope = add('sci.scope', 820, 0, title: 'Noisy vs filtered');
    final stats = add('sci.stats', 540, 330);
    final display = add('sci.display', 820, 330, title: 'Mean');
    link(sine, 'out', sum, 'a');
    link(noise, 'out', sum, 'b');
    link(sum, 'out', lp, 'in');
    link(sum, 'out', scope, 'ch1');
    link(lp, 'out', scope, 'ch2');
    link(sum, 'out', stats, 'in');
    link(stats, 'mean', display, 'in');

    final step = add('sci.step', 0, 560);
    final pid = add('sci.pid', 280, 540);
    final scope2 = add('sci.scope', 620, 520, title: 'PID step response');
    link(step, 'out', pid, 'sp');
    link(step, 'out', scope2, 'ch3');
    link(pid, 'y', scope2, 'ch1');
    link(pid, 'u', scope2, 'ch2');

    final chirp = add('sci.chirp', 0, 860);
    final fft = add('sci.fft', 280, 860);
    final scope3 = add('sci.scope', 620, 820, title: 'Spectrum');
    final expr = add('sci.expr', 280, 1010);
    link(chirp, 'out', fft, 'in');
    link(fft, 'out', scope3, 'ch1');
    link(chirp, 'out', expr, 'a');
    link(expr, 'out', scope3, 'ch2');
    c.history.clear();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => c.fitView(animate: false),
    );
  }

  void _onTrigger(NodeId node, String param) {
    final data = engine.csv[node.value];
    final messenger = ScaffoldMessenger.of(context);
    if (data == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Connect a signal to export.')),
      );
      return;
    }
    final name = c.graph.node(node)?.params['path'] as String? ?? 'signal.csv';
    final csv = StringBuffer('t,value\n');
    for (var i = 0; i < data.length; i++) {
      csv.writeln('${(i * SciEngine.dt).toStringAsFixed(5)},${data[i]}');
    }
    if (canUseBrowserFiles) {
      downloadText(
        name.isEmpty ? 'signal.csv' : name,
        csv.toString(),
        mime: 'text/csv',
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${data.length} samples ready (download is web only).'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShowcasePage(
      title: 'Scientific & control',
      subtitle: 'Simulink / LabVIEW-like dataflow: generators, filters, PID, FFT, live scopes. Evaluated on every edit.',
      icon: Icons.science_outlined,
      controller: c,
      fileStem: 'simulation',
      services: NodeEditorServices(onTrigger: _onTrigger),
      actions: [
        ListenableBuilder(
          listenable: engine,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              'eval ${engine.lastRun.inMicroseconds / 1000} ms',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: _toggleLive,
          icon: Icon(_isLive ? Icons.pause : Icons.play_arrow),
          label: Text(_isLive ? 'Stop live' : 'Run live'),
        ),
      ],
    );
  }
}
