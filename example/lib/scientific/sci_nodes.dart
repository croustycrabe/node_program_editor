import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:node_program_editor/node_program_editor.dart';

import 'sci_engine.dart';

const _src = NodeStyle(headerColor: Color(0xFF0D9488));
const _math = NodeStyle(headerColor: Color(0xFF4F46E5));
const _dyn = NodeStyle(headerColor: Color(0xFFEA580C));
const _ana = NodeStyle(headerColor: Color(0xFFDB2777));
const _sink = NodeStyle(headerColor: Color(0xFF334155));

const _sigIn = PortSpec.input('in', label: 'in', type: PortType.signal);
const _sigOut = PortSpec.output('out', label: 'out', type: PortType.signal);

const _freq = DoubleParam(
  min: 0.1,
  max: 60,
  step: 0.1,
  precision: 1,
  slider: true,
  unit: 'Hz',
  defaultValue: 2,
);
const _amp = DoubleParam(
  min: 0,
  max: 5,
  step: 0.05,
  precision: 2,
  slider: true,
  defaultValue: 1,
);

/// Definitions of the scientific showcase. Display nodes use custom bodies
/// fed by [engine].
List<NodeDefinition> scientificNodes(SciEngine engine) => [
  const NodeDefinition(
    type: 'sci.sine',
    title: 'Sine wave',
    category: 'Sources',
    icon: Icons.waves,
    tags: ['signal', 'generator', 'oscillator'],
    style: _src,
    variant: NodeVariant.dynamic,
    ports: [_sigOut],
    params: [
      ParamSpec('freq', _freq, label: 'Frequency', showInNode: true),
      ParamSpec('amp', _amp, label: 'Amplitude', showInNode: true),
      ParamSpec(
        'phase',
        DoubleParam(
          min: -math.pi,
          max: math.pi,
          slider: true,
          precision: 2,
          unit: 'rad',
        ),
        label: 'Phase',
      ),
    ],
  ),
  const NodeDefinition(
    type: 'sci.square',
    title: 'Square wave',
    category: 'Sources',
    icon: Icons.square_outlined,
    style: _src,
    variant: NodeVariant.dynamic,
    ports: [_sigOut],
    params: [
      ParamSpec('freq', _freq, label: 'Frequency', showInNode: true),
      ParamSpec('amp', _amp, label: 'Amplitude'),
      ParamSpec(
        'duty',
        DoubleParam(
          min: 0.05,
          max: 0.95,
          slider: true,
          precision: 2,
          defaultValue: 0.5,
        ),
        label: 'Duty cycle',
        showInNode: true,
      ),
    ],
  ),
  const NodeDefinition(
    type: 'sci.step',
    title: 'Step',
    category: 'Sources',
    icon: Icons.stairs_outlined,
    style: _src,
    variant: NodeVariant.dynamic,
    ports: [_sigOut],
    params: [
      ParamSpec(
        'time',
        DoubleParam(
          min: 0,
          max: 2,
          slider: true,
          precision: 2,
          unit: 's',
          defaultValue: 0.2,
        ),
        label: 'Step time',
        showInNode: true,
      ),
      ParamSpec('height', DoubleParam(defaultValue: 1), label: 'Height'),
    ],
  ),
  const NodeDefinition(
    type: 'sci.chirp',
    title: 'Chirp',
    category: 'Sources',
    icon: Icons.graphic_eq,
    style: _src,
    ports: [_sigOut],
    params: [
      ParamSpec(
        'f0',
        DoubleParam(min: 0.1, max: 100, defaultValue: 1, unit: 'Hz'),
        label: 'Start frequency',
      ),
      ParamSpec(
        'f1',
        DoubleParam(min: 0.1, max: 200, defaultValue: 30, unit: 'Hz'),
        label: 'End frequency',
      ),
    ],
  ),
  const NodeDefinition(
    type: 'sci.noise',
    title: 'White noise',
    category: 'Sources',
    icon: Icons.grain,
    style: _src,
    variant: NodeVariant.dynamic,
    ports: [_sigOut],
    params: [
      ParamSpec(
        'amp',
        DoubleParam(
          min: 0,
          max: 2,
          slider: true,
          precision: 2,
          defaultValue: 0.2,
        ),
        label: 'Amplitude',
        showInNode: true,
      ),
      ParamSpec('seed', IntParam(defaultValue: 42), label: 'Seed'),
    ],
  ),
  const NodeDefinition(
    type: 'sci.const',
    title: 'Constant',
    category: 'Sources',
    icon: Icons.pin_outlined,
    style: _src,
    variant: NodeVariant.dynamic,
    ports: [PortSpec.output('out', label: 'value', type: PortType.number)],
    params: [
      ParamSpec(
        'value',
        DoubleParam(defaultValue: 1),
        label: 'Value',
        showInNode: true,
      ),
    ],
  ),
  const NodeDefinition(
    type: 'sci.gain',
    title: 'Gain',
    category: 'Math',
    icon: Icons.close,
    style: _math,
    variant: NodeVariant.dynamic,
    ports: [_sigIn, _sigOut],
    params: [
      ParamSpec(
        'k',
        DoubleParam(
          min: -10,
          max: 10,
          step: 0.1,
          slider: true,
          precision: 1,
          defaultValue: 2,
        ),
        label: 'k',
        showInNode: true,
      ),
    ],
  ),
  const NodeDefinition(
    type: 'sci.offset',
    title: 'Offset',
    category: 'Math',
    icon: Icons.vertical_align_center,
    style: _math,
    variant: NodeVariant.dynamic,
    ports: [_sigIn, _sigOut],
    params: [
      ParamSpec('offset', DoubleParam(), label: 'Offset', showInNode: true),
    ],
  ),
  NodeDefinition(
    type: 'sci.sum',
    title: 'Sum',
    category: 'Math',
    icon: Icons.add,
    style: _math,
    variant: NodeVariant.dynamic,
    ports: const [
      PortSpec.input('a', label: 'a', type: PortType.signal),
      PortSpec.input('b', label: 'b', type: PortType.signal),
      _sigOut,
    ],
    params: [
      ParamSpec(
        'signs',
        EnumParam.values(['+ +', '+ −'], segmented: true),
        label: 'Signs',
        showInNode: true,
      ),
    ],
  ),
  const NodeDefinition(
    type: 'sci.product',
    title: 'Product',
    category: 'Math',
    icon: Icons.clear,
    style: _math,
    ports: [
      PortSpec.input('a', label: 'a', type: PortType.signal),
      PortSpec.input('b', label: 'b', type: PortType.signal),
      _sigOut,
    ],
  ),
  const NodeDefinition(
    type: 'sci.abs',
    title: 'Absolute value',
    category: 'Math',
    icon: Icons.unfold_more,
    style: _math,
    ports: [_sigIn, _sigOut],
  ),
  const NodeDefinition(
    type: 'sci.expr',
    title: 'Expression',
    category: 'Math',
    icon: Icons.functions,
    description: 'Any formula of a, b and t (sin, exp, pow, pi...).',
    tags: ['formula', 'math'],
    style: _math,
    variant: NodeVariant.dynamic,
    defaultSize: Size(240, 130),
    ports: [
      PortSpec.input('a', label: 'a', type: PortType.signal),
      PortSpec.input('b', label: 'b', type: PortType.signal),
      _sigOut,
    ],
    params: [
      ParamSpec(
        'expr',
        ExpressionParam(
          defaultValue: 'a * exp(-t) + 0.3*b',
          variables: ['a', 'b', 't'],
        ),
        label: 'f(a, b, t)',
        showInNode: true,
      ),
    ],
  ),
  const NodeDefinition(
    type: 'sci.integrator',
    title: 'Integrator',
    category: 'Dynamics',
    icon: Icons.area_chart_outlined,
    style: _dyn,
    ports: [_sigIn, _sigOut],
    params: [ParamSpec('initial', DoubleParam(), label: 'Initial value')],
  ),
  const NodeDefinition(
    type: 'sci.derivative',
    title: 'Derivative',
    category: 'Dynamics',
    icon: Icons.show_chart,
    style: _dyn,
    ports: [_sigIn, _sigOut],
  ),
  const NodeDefinition(
    type: 'sci.lowpass',
    title: 'Low-pass filter',
    category: 'Dynamics',
    icon: Icons.filter_list,
    tags: ['rc', 'filter', 'smooth'],
    style: _dyn,
    variant: NodeVariant.dynamic,
    ports: [_sigIn, _sigOut],
    params: [
      ParamSpec(
        'cutoff',
        DoubleParam(
          min: 0.1,
          max: 100,
          slider: true,
          precision: 1,
          unit: 'Hz',
          defaultValue: 5,
        ),
        label: 'Cutoff',
        showInNode: true,
      ),
    ],
  ),
  const NodeDefinition(
    type: 'sci.movavg',
    title: 'Moving average',
    category: 'Dynamics',
    icon: Icons.timeline,
    style: _dyn,
    variant: NodeVariant.dynamic,
    ports: [_sigIn, _sigOut],
    params: [
      ParamSpec(
        'window',
        IntParam(min: 1, max: 256, slider: true, defaultValue: 16),
        label: 'Window',
        showInNode: true,
      ),
    ],
  ),
  const NodeDefinition(
    type: 'sci.pid',
    title: 'PID loop',
    category: 'Dynamics',
    icon: Icons.tune,
    description: 'PID controller closing the loop on a first-order plant.',
    tags: ['control', 'feedback'],
    style: _dyn,
    variant: NodeVariant.dynamic,
    defaultSize: Size(250, 160),
    ports: [
      PortSpec.input('sp', label: 'setpoint', type: PortType.signal),
      PortSpec.output('y', label: 'output', type: PortType.signal),
      PortSpec.output('u', label: 'command', type: PortType.signal),
    ],
    params: [
      ParamSpec(
        'gains',
        VectorParam(
          dimension: 3,
          labels: ['Kp', 'Ki', 'Kd'],
          defaultValue: [2, 1, 0.05],
        ),
        label: 'Gains',
        showInNode: true,
      ),
      ParamSpec(
        'tau',
        DoubleParam(
          min: 0.01,
          max: 2,
          slider: true,
          precision: 2,
          unit: 's',
          defaultValue: 0.3,
        ),
        label: 'Plant τ',
        showInNode: true,
        group: 'Plant',
      ),
      ParamSpec(
        'plantGain',
        DoubleParam(defaultValue: 1),
        label: 'Plant gain',
        group: 'Plant',
      ),
    ],
  ),
  NodeDefinition(
    type: 'sci.fft',
    title: 'FFT',
    category: 'Analysis',
    icon: Icons.bar_chart,
    description: 'Magnitude spectrum (radix-2, 1024 points).',
    tags: const ['spectrum', 'fourier', 'frequency'],
    style: _ana,
    variant: NodeVariant.dynamic,
    ports: const [
      _sigIn,
      PortSpec.output('out', label: 'spectrum', type: PortType.signal),
    ],
    params: [
      ParamSpec(
        'window',
        EnumParam.values(['Hann', 'Rectangular']),
        label: 'Window',
        showInNode: true,
      ),
    ],
  ),
  NodeDefinition(
    type: 'sci.threshold',
    title: 'Schmitt trigger',
    category: 'Analysis',
    icon: Icons.compare_arrows,
    style: _ana,
    variant: NodeVariant.dynamic,
    ports: const [_sigIn, _sigOut],
    params: const [
      ParamSpec(
        'band',
        RangeParam(
          min: -2,
          max: 2,
          step: 0.05,
          defaultValue: RangeValue(-0.2, 0.2),
        ),
        label: 'Hysteresis',
        showInNode: true,
      ),
    ],
  ),
  NodeDefinition(
    type: 'sci.stats',
    title: 'Statistics',
    category: 'Analysis',
    icon: Icons.analytics_outlined,
    style: _ana,
    defaultSize: const Size(190, 170),
    ports: const [
      _sigIn,
      PortSpec.output('mean', label: 'mean', type: PortType.number),
      PortSpec.output('rms', label: 'rms', type: PortType.number),
    ],
    builder: (context, rc) => DefaultNodeBody(
      node: rc.node,
      content: _StatsView(engine: engine, id: rc.node.id),
    ),
  ),
  NodeDefinition(
    type: 'sci.scope',
    title: 'Scope',
    category: 'Display',
    icon: Icons.monitor_heart_outlined,
    description: 'Plots up to three signals.',
    tags: const ['plot', 'oscilloscope', 'chart'],
    style: _sink,
    defaultSize: const Size(340, 250),
    minSize: const Size(220, 170),
    ports: const [
      PortSpec.input(
        'ch1',
        label: 'ch1',
        type: PortType.signal,
        style: PortStyle(color: Color(0xFF38BDF8)),
      ),
      PortSpec.input(
        'ch2',
        label: 'ch2',
        type: PortType.signal,
        style: PortStyle(color: Color(0xFFF97316)),
      ),
      PortSpec.input(
        'ch3',
        label: 'ch3',
        type: PortType.signal,
        style: PortStyle(color: Color(0xFFA3E635)),
      ),
    ],
    params: const [
      ParamSpec('autoscale', BoolParam(defaultValue: true), label: 'Autoscale'),
      ParamSpec(
        'range',
        RangeParam(min: -10, max: 10, defaultValue: RangeValue(-2, 2)),
        label: 'Y range',
      ),
    ],
    builder: (context, rc) => DefaultNodeBody(
      node: rc.node,
      content: ScopePlot(engine: engine, node: rc.node),
    ),
  ),
  NodeDefinition(
    type: 'sci.display',
    title: 'Numeric display',
    category: 'Display',
    icon: Icons.numbers,
    style: _sink,
    defaultSize: const Size(180, 110),
    ports: const [PortSpec.input('in', label: 'value', type: PortType.number)],
    builder: (context, rc) => DefaultNodeBody(
      node: rc.node,
      content: _DisplayView(engine: engine, id: rc.node.id),
    ),
  ),
  const NodeDefinition(
    type: 'sci.csv',
    title: 'CSV export',
    category: 'Display',
    icon: Icons.table_view,
    style: _sink,
    variant: NodeVariant.dynamic,
    ports: [_sigIn],
    params: [
      ParamSpec(
        'path',
        FilePathParam(extensions: ['csv'], mode: FilePickMode.save),
        label: 'File',
        defaultValue: 'signal.csv',
      ),
      ParamSpec(
        'export',
        TriggerParam(buttonLabel: 'Export CSV'),
        label: 'Export',
        showInNode: true,
      ),
    ],
  ),
];

/// Live plot body of the scope node.
class ScopePlot extends StatelessWidget {
  const ScopePlot({super.key, required this.engine, required this.node});
  final SciEngine engine;
  final NodeInstance node;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final chans = engine.scopes[node.id.value] ?? const [];
        final auto = node.params['autoscale'] as bool? ?? true;
        final range =
            node.params['range'] as RangeValue? ?? const RangeValue(-2, 2);
        return Padding(
          padding: const EdgeInsets.only(left: 18, bottom: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CustomPaint(
              painter: _ScopePainter(
                chans,
                [for (final p in node.ports) p.style?.color ?? p.type.color],
                auto ? null : range,
                engine.spectrum[node.id.value] ?? false,
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }
}

class _ScopePainter extends CustomPainter {
  _ScopePainter(this.chans, this.colors, this.range, this.spectrum);
  final List<Float64List?> chans;
  final List<Color> colors;
  final RangeValue? range;
  final bool spectrum;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0B1220),
    );
    final grid = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    var lo = range?.start ?? double.infinity;
    var hi = range?.end ?? -double.infinity;
    if (range == null) {
      for (final c in chans) {
        if (c == null) continue;
        for (final v in c) {
          if (v < lo) lo = v;
          if (v > hi) hi = v;
        }
      }
      if (!lo.isFinite) {
        lo = -1;
        hi = 1;
      }
      final pad = (hi - lo).abs() * 0.1 + 1e-6;
      lo -= pad;
      hi += pad;
    }
    if (lo < 0 && hi > 0) {
      final y0 = size.height * (1 - (0 - lo) / (hi - lo));
      canvas.drawLine(
        Offset(0, y0),
        Offset(size.width, y0),
        Paint()..color = const Color(0xFF334155),
      );
    }
    for (var ci = 0; ci < chans.length; ci++) {
      final c = chans[ci];
      if (c == null || c.isEmpty) continue;
      // Decimate to ~2 points per pixel.
      final step = math.max(1, c.length ~/ (size.width * 2).ceil());
      final path = Path();
      for (var i = 0; i < c.length; i += step) {
        final x = size.width * i / (c.length - 1);
        final y = size.height * (1 - (c[i] - lo) / (hi - lo));
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[ci % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    final label = TextPainter(
      text: TextSpan(
        text:
            '${hi.toStringAsFixed(2)}\n\n${lo.toStringAsFixed(2)}'
            '${spectrum ? '   ·  0–256 Hz' : '   ·  2 s'}',
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    label.paint(canvas, const Offset(4, 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _StatsView extends StatelessWidget {
  const _StatsView({required this.engine, required this.id});
  final SciEngine engine;
  final NodeId id;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: engine,
    builder: (context, _) {
      final s = engine.stats[id.value];
      if (s == null) return const Text('No input');
      return DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        child: FittedBox(
          alignment: Alignment.topLeft,
          fit: BoxFit.scaleDown,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in s.entries)
                Text('${e.key.padRight(5)} ${e.value.toStringAsFixed(4)}'),
            ],
          ),
        ),
      );
    },
  );
}

class _DisplayView extends StatelessWidget {
  const _DisplayView({required this.engine, required this.id});
  final SciEngine engine;
  final NodeId id;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: engine,
    builder: (context, _) {
      final v = engine.displays[id.value];
      return FittedBox(
        child: Text(
          v == null || v.isNaN ? '—' : v.toStringAsFixed(3),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      );
    },
  );
}
