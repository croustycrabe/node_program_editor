import 'dart:async';

import 'package:flutter/material.dart';
import 'package:node_program_editor/node_program_editor.dart';

import '../shared/file_io.dart';
import '../shared/showcase_page.dart';
import 'vimage.dart';
import 'vision_engine.dart';
import 'vision_nodes.dart';

/// Basler pylon-like machine vision pipeline builder.
class VisionPage extends StatefulWidget {
  const VisionPage({super.key});

  /// The engine of the last created page (used by tests).
  @visibleForTesting
  static VisionEngine? debugLastEngine;

  @override
  State<VisionPage> createState() => _VisionPageState();
}

class _VisionPageState extends State<VisionPage> {
  late final NodeEditorController c = NodeEditorController(
    canvasSettings: const CanvasSettings(
      gridStyle: GridStyle.cross,
      gridSpacing: 20,
      snapToGrid: true,
      defaultEdgeStyle: EdgeStyle(
        pathType: EdgePathType.smoothStep,
        width: 3,
        cornerRadius: 14,
      ),
    ),
  );
  late final VisionEngine engine = VisionEngine(c);
  Timer? _debounce;
  Timer? _grab;

  @override
  void initState() {
    super.initState();
    VisionPage.debugLastEngine = engine;
    c.registry.registerAll(visionNodes(engine));
    c.validator = const ConnectionValidator(allowCycles: false);
    c.revision.addListener(_schedule);
    _buildDemo();
    unawaited(engine.run());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _grab?.cancel();
    c.revision.removeListener(_schedule);
    engine.dispose();
    c.dispose();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 40), engine.run);
  }

  void _toggleGrab() {
    setState(() {
      if (_grab != null) {
        _grab!.cancel();
        _grab = null;
      } else {
        _grab = Timer.periodic(const Duration(milliseconds: 120), (_) {
          engine.frame++;
          unawaited(engine.run());
        });
      }
    });
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

    final cam = add('vis.camera', 0, 0);
    final gray = add('vis.gray', 300, 20);
    final blur = add('vis.blur', 540, 0);
    final thr = add('vis.threshold', 800, 0);
    final morph = add('vis.morph', 1060, 0);
    final blobs = add('vis.blobs', 1320, 0);
    final result = add('vis.result', 1600, 40, title: 'Part count');
    link(cam, 'out', gray, 'in');
    link(gray, 'out', blur, 'in');
    link(blur, 'out', thr, 'in');
    link(thr, 'out', morph, 'in');
    link(morph, 'out', blobs, 'in');
    link(blobs, 'count', result, 'in');

    final hist = add('vis.histogram', 540, 300);
    final edges = add('vis.edges', 800, 300);
    final cmap = add('vis.colormap', 1060, 300, params: {'map': 'magma'});
    final display = add('vis.display', 1320, 320, title: 'Edges');
    link(gray, 'out', hist, 'in');
    link(blur, 'out', edges, 'in');
    link(edges, 'out', cmap, 'in');
    link(cmap, 'out', display, 'in');

    final src = add('vis.source', 0, 620, params: {'pattern': 'Coins'});
    final lut = add('vis.lut', 300, 620);
    final conv = add('vis.conv', 560, 620, title: 'Sharpen');
    final display2 = add('vis.display', 820, 600, title: 'Enhanced');
    link(src, 'out', lut, 'in');
    link(lut, 'out', conv, 'in');
    link(conv, 'out', display2, 'in');
    c.history.clear();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => c.fitView(animate: false),
    );
  }

  Future<ImageRef?> _pickImage(BuildContext context, ImageParam param) async {
    final samples = <String, ImageRef>{};
    for (final p in ['Parts', 'Coins', 'Checkerboard', 'Gradient']) {
      samples[p] = ImageRef(
        bytes: await Samples.generate(p, seed: 3).toPng(),
        name: '$p (synthetic)',
        width: Samples.w,
        height: Samples.h,
        mimeType: 'image/png',
      );
    }
    if (!context.mounted) return null;
    return showDialog<ImageRef>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose an image'),
        children: [
          for (final e in samples.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, e.value),
              child: Row(
                children: [
                  Image.memory(
                    e.value.bytes!,
                    width: 64,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                  const SizedBox(width: 12),
                  Text(e.key),
                ],
              ),
            ),
          if (canUseBrowserFiles)
            SimpleDialogOption(
              onPressed: () async {
                final f = await pickBinaryFile();
                if (f != null && context.mounted) {
                  Navigator.pop(context, ImageRef(bytes: f.$2, name: f.$1));
                }
              },
              child: const Row(
                children: [
                  Icon(Icons.upload_file, size: 40),
                  SizedBox(width: 12),
                  Text('Upload a PNG / JPEG…'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ShowcasePage(
      title: 'Computer vision builder',
      subtitle: 'Basler pylon-like pipeline: camera, filters, segmentation, blob analysis, inspection verdict. Live previews in every node.',
      icon: Icons.camera_outlined,
      controller: c,
      fileStem: 'vision',
      services: NodeEditorServices(pickImage: _pickImage),
      actions: [
        ListenableBuilder(
          listenable: engine,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              'pipeline ${(engine.lastRun.inMicroseconds / 1000).toStringAsFixed(1)} ms',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: _toggleGrab,
          icon: Icon(_grab != null ? Icons.stop : Icons.videocam),
          label: Text(_grab != null ? 'Stop grab' : 'Grab continuous'),
        ),
      ],
    );
  }
}
