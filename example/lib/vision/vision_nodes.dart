import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:node_program_editor/node_program_editor.dart';

import 'vision_engine.dart';

const _acq = NodeStyle(headerColor: Color(0xFF0F766E));
const _pre = NodeStyle(headerColor: Color(0xFF2563EB));
const _seg = NodeStyle(headerColor: Color(0xFF9333EA));
const _meas = NodeStyle(headerColor: Color(0xFFC2410C));
const _out = NodeStyle(headerColor: Color(0xFF334155));

const _imgIn = PortSpec.input('in', label: 'image', type: PortType.image);
const _imgOut = PortSpec.output('out', label: 'image', type: PortType.image);

/// Definitions of the vision showcase; every processing node shows a live
/// preview of its output.
List<NodeDefinition> visionNodes(VisionEngine engine) {
  Widget body(BuildContext context, NodeRenderContext rc) => DefaultNodeBody(
    node: rc.node,
    content: _VisionContent(engine: engine, node: rc.node),
  );

  NodeDefinition def({
    required String type,
    required String title,
    required String category,
    required IconData icon,
    required NodeStyle style,
    List<PortSpec> ports = const [_imgIn, _imgOut],
    List<ParamSpec> params = const [],
    String? description,
    List<String> tags = const [],
    Size size = const Size(220, 220),
  }) => NodeDefinition(
    type: type,
    title: title,
    category: category,
    icon: icon,
    style: style,
    ports: ports,
    params: params,
    description: description,
    tags: tags,
    variant: NodeVariant.dynamic,
    defaultSize: size,
    minSize: const Size(160, 120),
    builder: body,
  );

  return [
    def(
      type: 'vis.camera',
      title: 'Camera',
      category: 'Acquisition',
      icon: Icons.videocam_outlined,
      style: _acq,
      description: 'Simulated industrial camera (pylon-like features).',
      tags: const ['basler', 'pylon', 'acquisition', 'grab'],
      ports: const [_imgOut],
      size: const Size(240, 250),
      params: [
        const ParamSpec(
          'exposure',
          QuantityParam(
            ['µs', 'ms'],
            min: 0,
            max: 100000,
            defaultValue: Quantity(10, 'ms'),
          ),
          label: 'Exposure',
          showInNode: true,
        ),
        const ParamSpec(
          'gain',
          DoubleParam(
            min: 0.2,
            max: 3,
            step: 0.1,
            slider: true,
            precision: 1,
            defaultValue: 1,
          ),
          label: 'Gain',
          showInNode: true,
        ),
        ParamSpec(
          'trigger',
          EnumParam.values(['Freerun', 'Software', 'Line 1']),
          label: 'Trigger mode',
          group: 'Acquisition',
        ),
        const ParamSpec(
          'fps',
          IntParam(min: 1, max: 120, defaultValue: 30, unit: 'fps'),
          label: 'Frame rate',
          group: 'Acquisition',
        ),
        const ParamSpec(
          'aoi',
          RoiParam(
            frame: Size(256, 192),
            defaultValue: Roi(Rect.fromLTWH(0, 0, 256, 192)),
          ),
          label: 'AOI',
          group: 'Image format',
        ),
        ParamSpec(
          'pixel',
          EnumParam.values(['Mono8', 'RGB8', 'BayerRG8']),
          label: 'Pixel format',
          group: 'Image format',
        ),
      ],
    ),
    def(
      type: 'vis.source',
      title: 'Image source',
      category: 'Acquisition',
      icon: Icons.image_outlined,
      style: _acq,
      description: 'Synthetic test pattern or an image you load.',
      ports: const [_imgOut],
      params: [
        const ParamSpec(
          'image',
          ImageParam(),
          label: 'Image',
          showInNode: true,
        ),
        ParamSpec(
          'pattern',
          EnumParam.values(['Parts', 'Coins', 'Checkerboard', 'Gradient']),
          label: 'Pattern',
          showInNode: true,
        ),
        const ParamSpec(
          'noise',
          DoubleParam(
            min: 0,
            max: 60,
            slider: true,
            precision: 0,
            defaultValue: 8,
          ),
          label: 'Noise',
        ),
        const ParamSpec('seed', IntParam(defaultValue: 1), label: 'Seed'),
      ],
      size: const Size(230, 250),
    ),
    def(
      type: 'vis.gray',
      title: 'Grayscale',
      category: 'Pre-processing',
      icon: Icons.contrast,
      style: _pre,
      params: const [
        ParamSpec(
          'weights',
          VectorParam(
            dimension: 3,
            labels: ['R', 'G', 'B'],
            defaultValue: [0.299, 0.587, 0.114],
          ),
          label: 'Weights',
        ),
      ],
      size: const Size(200, 190),
    ),
    def(
      type: 'vis.blur',
      title: 'Gaussian blur',
      category: 'Pre-processing',
      icon: Icons.blur_on,
      style: _pre,
      tags: const ['smooth', 'denoise'],
      params: const [
        ParamSpec(
          'sigma',
          DoubleParam(
            min: 0,
            max: 6,
            step: 0.1,
            slider: true,
            precision: 1,
            defaultValue: 1.5,
          ),
          label: 'Sigma',
          showInNode: true,
        ),
      ],
    ),
    def(
      type: 'vis.conv',
      title: 'Convolution',
      category: 'Pre-processing',
      icon: Icons.grid_3x3,
      style: _pre,
      tags: const ['kernel', 'filter', 'sharpen'],
      params: [
        ParamSpec(
          'kernel',
          MatrixParam(
            resizable: true,
            defaultValue: Matrix(3, 3, const [0, -1, 0, -1, 5, -1, 0, -1, 0]),
          ),
          label: 'Kernel',
          showInNode: true,
        ),
        const ParamSpec(
          'normalize',
          BoolParam(defaultValue: true),
          label: 'Normalize',
        ),
      ],
    ),
    def(
      type: 'vis.lut',
      title: 'Tone curve',
      category: 'Pre-processing',
      icon: Icons.ssid_chart,
      style: _pre,
      tags: const ['lut', 'gamma', 'contrast'],
      params: const [
        ParamSpec(
          'curve',
          CurveParam.lut(
            defaultValue: [
              Offset(0, 0),
              Offset(90, 40),
              Offset(170, 220),
              Offset(255, 255),
            ],
          ),
          label: 'Curve',
          showInNode: true,
        ),
      ],
    ),
    def(
      type: 'vis.threshold',
      title: 'Threshold',
      category: 'Segmentation',
      icon: Icons.tonality,
      style: _seg,
      tags: const ['binarize', 'mask'],
      params: const [
        ParamSpec(
          'range',
          RangeParam(
            min: 0,
            max: 255,
            step: 1,
            precision: 0,
            defaultValue: RangeValue(110, 255),
          ),
          label: 'Range',
          showInNode: true,
        ),
        ParamSpec('invert', BoolParam(), label: 'Invert'),
      ],
    ),
    def(
      type: 'vis.edges',
      title: 'Sobel edges',
      category: 'Segmentation',
      icon: Icons.border_style,
      style: _seg,
      tags: const ['gradient', 'contour'],
      params: const [
        ParamSpec(
          'scale',
          DoubleParam(
            min: 0.1,
            max: 4,
            slider: true,
            precision: 1,
            defaultValue: 1,
          ),
          label: 'Scale',
          showInNode: true,
        ),
      ],
    ),
    def(
      type: 'vis.morph',
      title: 'Morphology',
      category: 'Segmentation',
      icon: Icons.blur_circular,
      style: _seg,
      tags: const ['erode', 'dilate', 'open', 'close'],
      params: [
        ParamSpec(
          'op',
          EnumParam.values([
            'Erode',
            'Dilate',
            'Open',
            'Close',
          ], defaultValue: 'Open'),
          label: 'Operation',
          showInNode: true,
        ),
        const ParamSpec(
          'size',
          IntParam(min: 1, max: 9, step: 2, slider: true, defaultValue: 3),
          label: 'Kernel size',
        ),
      ],
    ),
    def(
      type: 'vis.roi',
      title: 'ROI crop',
      category: 'Pre-processing',
      icon: Icons.crop,
      style: _pre,
      params: const [
        ParamSpec(
          'roi',
          RoiParam(
            frame: Size(256, 192),
            defaultValue: Roi(Rect.fromLTWH(48, 32, 160, 120)),
          ),
          label: 'Region',
        ),
      ],
    ),
    def(
      type: 'vis.colormap',
      title: 'Color map',
      category: 'Display',
      icon: Icons.palette_outlined,
      style: _out,
      params: const [
        ParamSpec('map', ColorMapParam(), label: 'Map', showInNode: true),
      ],
    ),
    def(
      type: 'vis.histogram',
      title: 'Histogram',
      category: 'Measurement',
      icon: Icons.equalizer,
      style: _meas,
      ports: const [
        _imgIn,
        PortSpec.output('out', label: 'mean', type: PortType.number),
      ],
      size: const Size(220, 170),
    ),
    def(
      type: 'vis.blobs',
      title: 'Blob analysis',
      category: 'Measurement',
      icon: Icons.bubble_chart_outlined,
      style: _meas,
      tags: const ['connected components', 'count', 'particles'],
      ports: const [
        PortSpec.input('in', label: 'mask', type: PortType.image),
        PortSpec.output('out', label: 'overlay', type: PortType.image),
        PortSpec.output('count', label: 'count', type: PortType.number),
      ],
      params: const [
        ParamSpec(
          'area',
          RangeParam(
            min: 0,
            max: 8000,
            step: 10,
            precision: 0,
            defaultValue: RangeValue(60, 6000),
          ),
          label: 'Area (px)',
          showInNode: true,
        ),
      ],
      size: const Size(230, 250),
    ),
    def(
      type: 'vis.measure',
      title: 'Mean intensity',
      category: 'Measurement',
      icon: Icons.light_mode_outlined,
      style: _meas,
      ports: const [
        _imgIn,
        PortSpec.output('out', label: 'mean', type: PortType.number),
      ],
      size: const Size(200, 110),
    ),
    def(
      type: 'vis.result',
      title: 'Inspection result',
      category: 'Measurement',
      icon: Icons.fact_check_outlined,
      style: _meas,
      ports: const [
        PortSpec.input('in', label: 'value', type: PortType.number),
      ],
      params: const [
        ParamSpec(
          'tolerance',
          RangeParam(
            min: 0,
            max: 50,
            step: 1,
            precision: 0,
            defaultValue: RangeValue(8, 10),
          ),
          label: 'Accept',
          showInNode: true,
        ),
      ],
      size: const Size(220, 160),
    ),
    def(
      type: 'vis.display',
      title: 'Display',
      category: 'Display',
      icon: Icons.tv,
      style: _out,
      ports: const [_imgIn],
      size: const Size(320, 270),
    ),
  ];
}

class _VisionContent extends StatelessWidget {
  const _VisionContent({required this.engine, required this.node});
  final VisionEngine engine;
  final NodeInstance node;

  @override
  Widget build(BuildContext context) {
    final def = node.definition;
    final inline = def.params.where((p) => p.showInNode).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final spec in inline)
          SizedBox(
            height: def.portLayout.paramRowHeight,
            child: InlineParamEditor(node: node, spec: spec),
          ),
        Expanded(
          child: ListenableBuilder(
            listenable: engine,
            builder: (context, _) => _result(context),
          ),
        ),
      ],
    );
  }

  Widget _result(BuildContext context) {
    final id = node.id.value;
    final info = engine.info[id];
    if (node.type == 'vis.histogram') {
      final h = engine.histograms[id];
      return h == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: CustomPaint(
                painter: _HistogramPainter(h),
                size: Size.infinite,
              ),
            );
    }
    if (node.type == 'vis.result') {
      final pass = engine.verdicts[id];
      if (pass == null) return const Center(child: Text('—'));
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: pass ? const Color(0xFF12B76A) : const Color(0xFFF04438),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              '${pass ? 'PASS' : 'FAIL'}  ·  $info',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }
    final img = engine.previews[id];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: img == null
                ? Container(
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      size: 18,
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: ColoredBox(
                      color: Colors.black,
                      child: RawImage(
                        image: img,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
          ),
          if (info != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                info,
                style: const TextStyle(fontSize: 10),
                maxLines: 1,
              ),
            ),
        ],
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  _HistogramPainter(this.bins);
  final List<int> bins;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0B1220),
    );
    final mx = bins.reduce(math.max).toDouble();
    if (mx == 0) return;
    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i < 256; i++) {
      final x = size.width * i / 255;
      final y = size.height * (1 - math.sqrt(bins[i] / mx));
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, 0),
          const [Color(0xFF475569), Color(0xFFF8FAFC)],
        ),
    );
  }

  @override
  bool shouldRepaint(_HistogramPainter old) => old.bins != bins;
}
