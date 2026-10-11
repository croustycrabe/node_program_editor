import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:node_program_editor/node_program_editor.dart';

import 'expr.dart';

/// A minimal dataflow executor for the scientific showcase.
///
/// It consumes the **logic file** exactly like an external engine would:
/// `controller.exportLogic().flatten()` → topological order → evaluate each
/// node on 1024-sample signals. Results that nodes display (scopes,
/// statistics, numeric displays) are published through [ChangeNotifier].
class SciEngine extends ChangeNotifier {
  SciEngine(this.controller);

  final NodeEditorController controller;

  /// Samples per signal.
  static const int n = 1024;

  /// Sampling frequency (Hz) → 2 s window.
  static const double fs = 512;

  static const double dt = 1 / fs;

  /// Time shift used by the live mode.
  double timeOffset = 0;

  /// Scope channels per node id.
  final Map<String, List<Float64List?>> scopes = {};

  /// Whether a scope shows a spectrum (x axis in Hz).
  final Map<String, bool> spectrum = {};

  /// Statistics per node id.
  final Map<String, Map<String, double>> stats = {};

  /// Scalar displays per node id.
  final Map<String, double> displays = {};

  /// Last input of CSV export nodes.
  final Map<String, Float64List> csv = {};

  /// Errors per node id.
  final Map<String, String> errors = {};

  /// Duration of the last evaluation.
  Duration lastRun = Duration.zero;

  // Values are Float64List (signals) or double (scalars).
  final Map<PortRef, Object> _values = {};

  T _param<T>(LogicNode node, String name, T fallback) {
    final spec = controller.registry[node.type]?.param(name);
    final raw = node.params[name];
    if (spec == null) return raw is T ? raw : fallback;
    final v = spec.type.decodeAny(raw);
    return v is T ? v : fallback;
  }

  void run() {
    final sw = Stopwatch()..start();
    _values.clear();
    scopes.clear();
    stats.clear();
    displays.clear();
    errors.clear();
    spectrum.clear();
    final logic = controller.exportLogic().flatten();
    final incoming = <PortRef, PortRef>{};
    for (final e in logic.edges) {
      incoming[e.target] = e.source;
    }
    final byId = {for (final x in logic.nodes) x.id: x};
    // Topological order (Kahn).
    final indeg = {for (final x in logic.nodes) x.id: 0};
    final next = <NodeId, List<NodeId>>{};
    for (final e in logic.edges) {
      indeg[e.target.node] = (indeg[e.target.node] ?? 0) + 1;
      (next[e.source.node] ??= []).add(e.target.node);
    }
    final queue = [
      for (final e in indeg.entries)
        if (e.value == 0) e.key,
    ];
    final order = <NodeId>[];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      order.add(id);
      for (final t in next[id] ?? const <NodeId>[]) {
        indeg[t] = indeg[t]! - 1;
        if (indeg[t] == 0) queue.add(t);
      }
    }

    Float64List? input(NodeId id, String port) {
      final src = incoming[PortRef(id, port)];
      if (src == null) return null;
      final v = _values[src];
      if (v is Float64List) return v;
      if (v is double) return Float64List(n)..fillRange(0, n, v);
      return null;
    }

    double? scalar(NodeId id, String port) {
      final src = incoming[PortRef(id, port)];
      final v = src == null ? null : _values[src];
      if (v is double) return v;
      if (v is Float64List && v.isNotEmpty) return v.last;
      return null;
    }

    Float64List gen(double Function(double t) f) {
      final out = Float64List(n);
      for (var i = 0; i < n; i++) {
        out[i] = f(i * dt + timeOffset);
      }
      return out;
    }

    Float64List map1(Float64List? a, double Function(double x) f) {
      final out = Float64List(n);
      if (a == null) return out;
      for (var i = 0; i < n; i++) {
        out[i] = f(a[i]);
      }
      return out;
    }

    for (final id in order) {
      final node = byId[id]!;
      final key = id.value;
      final shortKey = key.split('/').last;
      void out(String port, Object v) => _values[PortRef(id, port)] = v;
      try {
        switch (node.type) {
          case 'sci.sine':
            final f = _param(node, 'freq', 2.0);
            final a = _param(node, 'amp', 1.0);
            final p = _param(node, 'phase', 0.0);
            out('out', gen((t) => a * math.sin(2 * math.pi * f * t + p)));
          case 'sci.square':
            final f = _param(node, 'freq', 2.0);
            final a = _param(node, 'amp', 1.0);
            final duty = _param(node, 'duty', 0.5);
            out('out', gen((t) => ((t * f) % 1) < duty ? a : -a));
          case 'sci.step':
            final at = _param(node, 'time', 0.5);
            final h = _param(node, 'height', 1.0);
            out('out', gen((t) => (t - timeOffset) >= at ? h : 0));
          case 'sci.chirp':
            final f0 = _param(node, 'f0', 1.0), f1 = _param(node, 'f1', 20.0);
            const total = n / fs;
            out(
              'out',
              gen((t) {
                final tt = (t - timeOffset);
                return math.sin(
                  2 * math.pi * (f0 * tt + (f1 - f0) * tt * tt / (2 * total)),
                );
              }),
            );
          case 'sci.noise':
            final a = _param(node, 'amp', 0.2);
            final seed = _param(node, 'seed', 1);
            final rnd = math.Random(seed + (timeOffset * 60).floor());
            out('out', gen((_) => (rnd.nextDouble() * 2 - 1) * a));
          case 'sci.const':
            out('out', _param(node, 'value', 1.0));
          case 'sci.gain':
            final k = _param(node, 'k', 2.0);
            out('out', map1(input(id, 'in'), (x) => x * k));
          case 'sci.offset':
            final o = _param(node, 'offset', 0.0);
            out('out', map1(input(id, 'in'), (x) => x + o));
          case 'sci.abs':
            out('out', map1(input(id, 'in'), (x) => x.abs()));
          case 'sci.sum':
            final a = input(id, 'a') ?? Float64List(n);
            final b = input(id, 'b') ?? Float64List(n);
            final minus = _param(node, 'signs', '+ +') == '+ −';
            out(
              'out',
              Float64List.fromList([
                for (var i = 0; i < n; i++) minus ? a[i] - b[i] : a[i] + b[i],
              ]),
            );
          case 'sci.product':
            final a = input(id, 'a') ?? Float64List(n);
            final b = input(id, 'b') ?? Float64List(n);
            out(
              'out',
              Float64List.fromList([for (var i = 0; i < n; i++) a[i] * b[i]]),
            );
          case 'sci.expr':
            final f = Expr.compile(_param(node, 'expr', 'a'));
            final a = input(id, 'a'), b = input(id, 'b');
            final vars = <String, double>{};
            final o = Float64List(n);
            for (var i = 0; i < n; i++) {
              vars
                ..['a'] = a?[i] ?? 0
                ..['b'] = b?[i] ?? 0
                ..['t'] = i * dt + timeOffset
                ..['i'] = i.toDouble();
              o[i] = f(vars);
            }
            out('out', o);
          case 'sci.integrator':
            final a = input(id, 'in') ?? Float64List(n);
            var acc = _param(node, 'initial', 0.0);
            out(
              'out',
              Float64List.fromList([
                for (var i = 0; i < n; i++) acc += a[i] * dt,
              ]),
            );
          case 'sci.derivative':
            final a = input(id, 'in') ?? Float64List(n);
            out(
              'out',
              Float64List.fromList([
                for (var i = 0; i < n; i++) i == 0 ? 0 : (a[i] - a[i - 1]) / dt,
              ]),
            );
          case 'sci.lowpass':
            final a = input(id, 'in') ?? Float64List(n);
            final fc = _param(node, 'cutoff', 5.0);
            final rc = 1 / (2 * math.pi * fc);
            final alpha = dt / (rc + dt);
            var y = a.isEmpty ? 0.0 : a[0];
            out(
              'out',
              Float64List.fromList([
                for (var i = 0; i < n; i++) y += alpha * (a[i] - y),
              ]),
            );
          case 'sci.movavg':
            final a = input(id, 'in') ?? Float64List(n);
            final w = _param(node, 'window', 16).clamp(1, n);
            var sum = 0.0;
            final o = Float64List(n);
            for (var i = 0; i < n; i++) {
              sum += a[i];
              if (i >= w) sum -= a[i - w];
              o[i] = sum / math.min(i + 1, w);
            }
            out('out', o);
          case 'sci.threshold':
            final a = input(id, 'in') ?? Float64List(n);
            final band = _param(node, 'band', const RangeValue(-0.2, 0.2));
            var state = 0.0;
            out(
              'out',
              Float64List.fromList([
                for (var i = 0; i < n; i++)
                  state = a[i] > band.end ? 1 : (a[i] < band.start ? 0 : state),
              ]),
            );
          case 'sci.pid':
            final sp = input(id, 'sp') ?? Float64List(n);
            final g = _param(node, 'gains', const [1.0, 0.5, 0.0]);
            final tau = _param(node, 'tau', 0.3);
            final k = _param(node, 'plantGain', 1.0);
            var y = 0.0, integral = 0.0, prevErr = 0.0;
            final ys = Float64List(n), us = Float64List(n);
            for (var i = 0; i < n; i++) {
              final err = sp[i] - y;
              integral += err * dt;
              final deriv = i == 0 ? 0.0 : (err - prevErr) / dt;
              prevErr = err;
              final u = g[0] * err + g[1] * integral + g[2] * deriv;
              y += dt / tau * (k * u - y);
              ys[i] = y;
              us[i] = u;
            }
            out('y', ys);
            out('u', us);
          case 'sci.fft':
            final a = input(id, 'in') ?? Float64List(n);
            final hann = _param(node, 'window', 'Hann') == 'Hann';
            out('out', _spectrum(a, hann));
            _values[PortRef(id, '__spectrum')] = 1.0;
          case 'sci.stats':
            final a = input(id, 'in') ?? Float64List(n);
            var sum = 0.0,
                sq = 0.0,
                mn = double.infinity,
                mx = -double.infinity;
            for (final x in a) {
              sum += x;
              sq += x * x;
              mn = math.min(mn, x);
              mx = math.max(mx, x);
            }
            final mean = sum / n;
            final s = {
              'mean': mean,
              'rms': math.sqrt(sq / n),
              'min': mn,
              'max': mx,
              'std': math.sqrt(math.max(0, sq / n - mean * mean)),
            };
            stats[key] = s;
            stats[shortKey] = s;
            out('mean', mean);
            out('rms', s['rms']!);
          case 'sci.scope':
            final chans = [
              input(id, 'ch1'),
              input(id, 'ch2'),
              input(id, 'ch3'),
            ];
            scopes[key] = chans;
            scopes[shortKey] = chans;
            final isSpec = ['ch1', 'ch2', 'ch3'].any((p) {
              final src = incoming[PortRef(id, p)];
              return src != null &&
                  _values.containsKey(PortRef(src.node, '__spectrum'));
            });
            spectrum[key] = isSpec;
            spectrum[shortKey] = isSpec;
          case 'sci.display':
            final v = scalar(id, 'in') ?? double.nan;
            displays[key] = v;
            displays[shortKey] = v;
          case 'sci.csv':
            final a = input(id, 'in');
            if (a != null) {
              csv[key] = a;
              csv[shortKey] = a;
            }
        }
      } catch (e) {
        errors[key] = '$e';
        errors[shortKey] = '$e';
      }
    }
    lastRun = sw.elapsed;
    notifyListeners();
  }

  /// Magnitude spectrum (radix-2 FFT), N/2 bins.
  static Float64List _spectrum(Float64List x, bool hann) {
    final re = Float64List(n), im = Float64List(n);
    for (var i = 0; i < n; i++) {
      final w = hann ? 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)) : 1.0;
      re[i] = x[i] * w;
    }
    // Bit reversal.
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final t = re[i];
        re[i] = re[j];
        re[j] = t;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final ang = -2 * math.pi / len;
      for (var i = 0; i < n; i += len) {
        for (var k = 0; k < len ~/ 2; k++) {
          final c = math.cos(ang * k), s = math.sin(ang * k);
          final a = i + k, b = i + k + len ~/ 2;
          final tr = re[b] * c - im[b] * s, ti = re[b] * s + im[b] * c;
          re[b] = re[a] - tr;
          im[b] = im[a] - ti;
          re[a] += tr;
          im[a] += ti;
        }
      }
    }
    return Float64List.fromList([
      for (var i = 0; i < n ~/ 2; i++)
        2 * math.sqrt(re[i] * re[i] + im[i] * im[i]) / n,
    ]);
  }
}
