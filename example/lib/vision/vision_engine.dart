import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:node_program_editor/node_program_editor.dart';

import 'vimage.dart';

/// Evaluates the vision pipeline from the logic file and publishes per-node
/// previews (GPU images), histograms and measurements.
class VisionEngine extends ChangeNotifier {
  VisionEngine(this.controller);

  final NodeEditorController controller;

  /// Preview of each node output.
  final Map<String, ui.Image> previews = {};

  /// Histograms per node.
  final Map<String, List<int>> histograms = {};

  /// Text results per node (counts, verdicts...).
  final Map<String, String> info = {};

  /// Pass / fail verdicts per node.
  final Map<String, bool> verdicts = {};

  /// Frame counter of the simulated camera.
  int frame = 0;

  Duration lastRun = Duration.zero;

  final Map<Object, VImage> _decoded = {};
  bool _running = false;
  bool _again = false;

  T _p<T>(LogicNode n, String name, T fallback) {
    final spec = controller.registry[n.type]?.param(name);
    final raw = n.params[name];
    if (spec == null) return raw is T ? raw : fallback;
    final v = spec.type.decodeAny(raw);
    return v is T ? v : fallback;
  }

  Future<VImage> _source(LogicNode n) async {
    final ref = _p<ImageRef?>(n, 'image', null);
    if (ref?.bytes != null) {
      final key = ref!.bytes!;
      return _decoded[key] ??= await VImage.decode(ref.bytes!);
    }
    return Samples.generate(
      _p(n, 'pattern', 'Parts'),
      seed: _p(n, 'seed', 1),
      noise: _p(n, 'noise', 8.0),
    );
  }

  Future<void> run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    do {
      _again = false;
      await _runOnce();
    } while (_again);
    _running = false;
  }

  Future<void> _runOnce() async {
    final sw = Stopwatch()..start();
    final logic = controller.exportLogic().flatten();
    final incoming = <PortRef, PortRef>{};
    for (final e in logic.edges) {
      incoming[e.target] = e.source;
    }
    final byId = {for (final n in logic.nodes) n.id: n};
    final indeg = {for (final n in logic.nodes) n.id: 0};
    final next = <NodeId, List<NodeId>>{};
    for (final e in logic.edges) {
      indeg[e.target.node] = indeg[e.target.node]! + 1;
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

    final values = <PortRef, Object>{};
    final shown = <String, VImage>{};
    final newHist = <String, List<int>>{};
    final newInfo = <String, String>{};
    final newVerdicts = <String, bool>{};

    VImage? img(NodeId id, [String port = 'in']) {
      final s = incoming[PortRef(id, port)];
      final v = s == null ? null : values[s];
      return v is VImage ? v : null;
    }

    double? num(NodeId id, String port) {
      final s = incoming[PortRef(id, port)];
      final v = s == null ? null : values[s];
      return v is double ? v : null;
    }

    for (final id in order) {
      final n = byId[id]!;
      final keys = {id.value, id.value.split('/').last};
      void show(VImage i) {
        for (final k in keys) {
          shown[k] = i;
        }
      }

      void put(Map<String, Object> m, Object v) {
        for (final k in keys) {
          m[k] = v;
        }
      }

      VImage? out;
      switch (n.type) {
        case 'vis.source':
          out = await _source(n);
        case 'vis.camera':
          final exposure = _p(n, 'exposure', const Quantity(10, 'ms'));
          final ms = exposure.unit == 'µs'
              ? exposure.value / 1000
              : exposure.value;
          final gain = _p(n, 'gain', 1.0);
          var frameImg = Samples.generate(
            'Parts',
            seed: 7,
            noise: 4 + gain * 4,
            brightness: (ms / 10) * gain,
            jitter: (frame % 40) * 2.0,
          );
          final aoi = _p<Roi?>(n, 'aoi', null);
          if (aoi != null) frameImg = Ops.crop(frameImg, aoi.rect);
          out = frameImg;
          put(newInfo, 'frame #$frame · ${frameImg.width}×${frameImg.height}');
        case 'vis.gray':
          final i = img(id);
          if (i != null) {
            out = i.toGray(_p(n, 'weights', const [0.299, 0.587, 0.114]));
          }
        case 'vis.blur':
          final i = img(id);
          if (i != null) out = Ops.blur(i, _p(n, 'sigma', 1.5));
        case 'vis.conv':
          final i = img(id);
          if (i != null) {
            out = Ops.convolve(
              i,
              _p(n, 'kernel', Matrix.identity(3)),
              normalize: _p(n, 'normalize', true),
            );
          }
        case 'vis.lut':
          final i = img(id);
          if (i != null) out = Ops.lut(i, _p(n, 'curve', const <ui.Offset>[]));
        case 'vis.threshold':
          final i = img(id);
          if (i != null) {
            final r = _p(n, 'range', const RangeValue(128, 255));
            out = Ops.threshold(i, r.start, r.end, _p(n, 'invert', false));
          }
        case 'vis.edges':
          final i = img(id);
          if (i != null) out = Ops.sobel(i, _p(n, 'scale', 1.0));
        case 'vis.morph':
          final i = img(id);
          if (i != null) {
            final size = _p(n, 'size', 3);
            out = Ops.morphology(
              i,
              _p(n, 'op', 'Open'),
              size.isEven ? size + 1 : size,
            );
          }
        case 'vis.roi':
          final i = img(id);
          if (i != null) {
            out = Ops.crop(
              i,
              _p(n, 'roi', const Roi(ui.Rect.fromLTWH(64, 48, 128, 96))).rect,
            );
          }
        case 'vis.colormap':
          final i = img(id);
          if (i != null) out = Ops.colorize(i, _p(n, 'map', 'viridis'));
        case 'vis.histogram':
          final i = img(id);
          if (i != null) {
            final h = Ops.histogram(i);
            put(newHist, h);
            values[PortRef(id, 'out')] = Ops.mean(i);
          }
        case 'vis.blobs':
          final i = img(id);
          if (i != null) {
            final area = _p(n, 'area', const RangeValue(40, 6000));
            final boxes = Ops.blobs(i, area.start, area.end);
            values[PortRef(id, 'count')] = boxes.length.toDouble();
            out = Ops.drawBoxes(i, boxes);
            values[PortRef(id, 'out')] = out;
            put(newInfo, '${boxes.length} blob(s)');
          }
        case 'vis.measure':
          final i = img(id);
          if (i != null) {
            final m = Ops.mean(i);
            values[PortRef(id, 'out')] = m;
            put(newInfo, 'mean ${m.toStringAsFixed(1)}');
          }
        case 'vis.result':
          final v = num(id, 'in');
          final tol = _p(n, 'tolerance', const RangeValue(8, 10));
          if (v != null) {
            final pass = v >= tol.start && v <= tol.end;
            put(newVerdicts, pass);
            put(newInfo, v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2));
          }
        case 'vis.display':
          final i = img(id);
          if (i != null) show(i);
      }
      if (out != null) {
        values[PortRef(id, 'out')] = values[PortRef(id, 'out')] ?? out;
        show(out);
      }
    }

    // Upload previews to the GPU.
    final newPreviews = <String, ui.Image>{};
    final uploaded = <VImage, ui.Image>{};
    for (final e in shown.entries) {
      newPreviews[e.key] = uploaded[e.value] ??= await e.value.toUiImage();
    }
    final old = previews.values.toSet();
    previews
      ..clear()
      ..addAll(newPreviews);
    histograms
      ..clear()
      ..addAll(newHist);
    info
      ..clear()
      ..addAll(newInfo);
    verdicts
      ..clear()
      ..addAll(newVerdicts);
    lastRun = sw.elapsed;
    notifyListeners();
    // Dispose replaced GPU images after the frame that stops using them.
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        for (final i in old) {
          if (!newPreviews.values.contains(i)) i.dispose();
        }
      })
      ..scheduleFrame();
  }

  @override
  void dispose() {
    for (final i in previews.values.toSet()) {
      i.dispose();
    }
    super.dispose();
  }
}
