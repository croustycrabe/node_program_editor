import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:node_program_editor/node_program_editor.dart';

import '../shared/showcase_page.dart';
import 'automation_nodes.dart';

/// n8n-like workflow automation builder with a simulated executor.
class AutomationPage extends StatefulWidget {
  const AutomationPage({super.key});

  @override
  State<AutomationPage> createState() => _AutomationPageState();
}

class _AutomationPageState extends State<AutomationPage> {
  late final NodeEditorController c = NodeEditorController(
    registry: NodeRegistry(definitions: automationNodes, portTypes: [itemType]),
    canvasSettings: const CanvasSettings(
      gridStyle: GridStyle.dots,
      snapToGrid: true,
      defaultEdgeStyle: EdgeStyle(
        pathType: EdgePathType.smoothStep,
        endMarker: EdgeMarker.arrowClosed,
        cornerRadius: 12,
      ),
    ),
  );
  bool _running = false;
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _buildDemo();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
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

    final hook = add('trigger.webhook', 0, 120);
    final http = add(
      'http.request',
      280,
      100,
      params: {
        'url': 'https://api.shop.example/orders/{{id}}',
        'method': 'GET',
      },
      title: 'Fetch order',
    );
    final iff = add('flow.if', 580, 110, title: 'Total > 100 €');
    final ai = add('ai.agent', 860, -40, title: 'Classify order');
    final slack = add('action.slack', 1160, -40);
    final email = add('action.email', 860, 240);
    final merge = add('flow.merge', 1160, 180);
    final db = add('action.db', 1440, 120, title: 'Save order');
    final respond = add('output.respond', 1720, 140);
    link(hook, 'out', http, 'in');
    link(http, 'out', iff, 'in');
    link(iff, 'true', ai, 'in');
    link(ai, 'out', slack, 'in');
    link(iff, 'false', email, 'in');
    link(slack, 'out', merge, 'in1');
    link(email, 'out', merge, 'in2');
    link(merge, 'out', db, 'in');
    link(db, 'out', respond, 'in');

    final cron = add('trigger.schedule', 0, 460, title: 'Every night');
    final query = add(
      'action.db',
      280,
      440,
      params: {'operation': 'Select'},
      title: 'Unpaid orders',
    );
    final filter = add('data.filter', 580, 440);
    final mail = add(
      'action.email',
      860,
      440,
      params: {'subject': 'Payment reminder'},
      title: 'Reminder',
    );
    link(cron, 'out', query, 'in');
    link(query, 'out', filter, 'in');
    link(filter, 'out', mail, 'in');
    c.history.clear();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => c.fitView(animate: false),
    );
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _log.clear();
    });
    c.clearRuntime();
    // Execution engines consume the logic file; flatten() inlines super
    // nodes so the executor only sees primitive nodes.
    final logic = c.exportLogic().flatten();
    final nodes = {for (final n in logic.nodes) n.id: n};
    final outgoing = <NodeId, List<LogicEdge>>{};
    for (final e in logic.edges) {
      (outgoing[e.source.node] ??= []).add(e);
    }
    NodeId topLevel(NodeId id) => NodeId(id.value.split('/').first);

    final queue = <(NodeId, int)>[
      for (final n in logic.nodes)
        if (n.type.startsWith('trigger.')) (n.id, 1),
    ];
    if (queue.isEmpty) {
      _addLog('No trigger node: add a Trigger to start the workflow.');
    }
    final rnd = math.Random();
    final visited = <NodeId>{};
    while (queue.isNotEmpty && mounted) {
      final (id, items) = queue.removeAt(0);
      if (!visited.add(id)) continue;
      final node = nodes[id]!;
      final name = node.title ?? c.registry[node.type]?.title ?? node.type;
      final shown = topLevel(id);
      c.setRuntimeData(shown, {'status': 'running', 'statusText': 'Running…'});
      final ms = 250 + rnd.nextInt(450);
      await Future<void>.delayed(Duration(milliseconds: ms));
      if (!mounted) return;

      // Simulated node behaviour.
      String? error;
      var outItems = items;
      var ports = <String>['out'];
      switch (node.type) {
        case 'http.request':
          if ((node.params['url'] as String? ?? '').isEmpty) {
            error = 'URL is required';
          }
          outItems = items * 3;
        case 'flow.if':
          ports = [rnd.nextBool() ? 'true' : 'false'];
        case 'flow.switch':
          ports = [
            ['c1', 'c2', 'c3', 'fallback'][rnd.nextInt(4)],
          ];
        case 'flow.loop':
          ports = ['done'];
        case 'data.filter':
          outItems = math.max(1, items ~/ 2);
        case 'action.db':
          if (node.params['operation'] == 'Select') outItems = 12;
      }
      if (error != null) {
        c.setRuntimeData(shown, {'status': 'error', 'statusText': error});
        _addLog('✗ $name: $error');
        continue;
      }
      c.setRuntimeData(shown, {
        'status': 'success',
        'statusText': '$outItems item(s) · $ms ms',
      });
      _addLog('✓ $name → $outItems item(s) in $ms ms');
      for (final e in outgoing[id] ?? const <LogicEdge>[]) {
        if (!ports.contains(e.source.port)) continue;
        c.setEdgeRuntime(
          e.id,
          EdgeRuntimeState(
            animated: true,
            color: const Color(0xFF12B76A),
            label: '$outItems item${outItems == 1 ? '' : 's'}',
          ),
        );
        queue.add((e.target.node, outItems));
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    // Stop the flow animation but keep colors / labels until the next run.
    for (final e in c.graph.edges) {
      final r = c.edgeRuntime(e.id);
      if (r != null) {
        c.setEdgeRuntime(
          e.id,
          EdgeRuntimeState(color: r.color, label: r.label),
        );
      }
    }
    setState(() => _running = false);
  }

  void _addLog(String line) {
    if (!mounted) return;
    setState(() => _log.insert(0, line));
  }

  /// Merge nodes get extra inputs through a custom menu action
  /// (demonstrates per-instance custom ports).
  late final List<NodeMenuAction> _menuActions = [
    NodeMenuAction(
      icon: Icons.add_link,
      label: 'Add input',
      isVisible: (n) => n.type == 'flow.merge',
      onSelected: (c, n) {
        final count = n.ports.where((p) => p.isInput).length + 1;
        c.setCustomPorts(n.id, [
          ...n.customPorts,
          PortSpec.input('in$count', label: 'Input $count', type: itemType),
        ]);
      },
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ShowcasePage(
      title: 'Workflow automation',
      subtitle: 'n8n-like builder: triggers, HTTP, branching, AI and actions. Press Execute to simulate a run.',
      icon: Icons.bolt,
      controller: c,
      fileStem: 'workflow',
      nodeMenuActions: _menuActions,
      actions: [
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: _running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: const Text('Execute workflow'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _running ? null : c.clearRuntime,
          child: const Text('Reset'),
        ),
      ],
      sidePanel: _log.isEmpty
          ? null
          : SizedBox(
              width: 280,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(
                      'Execution log',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (final l in _log)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          l,
                          style: TextStyle(
                            fontSize: 12,
                            color: l.startsWith('✗') ? Colors.red : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
