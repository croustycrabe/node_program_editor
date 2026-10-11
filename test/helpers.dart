import 'dart:ui';

import 'package:node_program_editor/node_program_editor.dart';

const numberIn = PortSpec.input('in', label: 'In', type: PortType.number);
const numberOut = PortSpec.output('out', label: 'Out', type: PortType.number);

final sourceDef = NodeDefinition(
  type: 'source',
  title: 'Source',
  ports: const [numberOut],
  params: [
    const ParamSpec('value', DoubleParam(min: -10, max: 10)),
    ParamSpec('label', const TextParam(defaultValue: 'src')),
  ],
);

const gainDef = NodeDefinition(
  type: 'gain',
  title: 'Gain',
  ports: [numberIn, numberOut],
  params: [ParamSpec('k', DoubleParam(defaultValue: 2), showInNode: true)],
  variant: NodeVariant.dynamic,
);

const sinkDef = NodeDefinition(
  type: 'sink',
  title: 'Sink',
  ports: [
    PortSpec.input('a', type: PortType.number),
    PortSpec.input('b', type: PortType.number, maxLinks: -1),
    PortSpec.input('img', type: PortType.image),
  ],
);

NodeRegistry testRegistry() =>
    NodeRegistry(definitions: [sourceDef, gainDef, sinkDef]);

NodeEditorController testController({NodeEditorConfig? config}) {
  final c = NodeEditorController(
    registry: testRegistry(),
    config: config ?? const NodeEditorConfig(useSystemClipboard: false),
  );
  c.viewportSize = const Size(1000, 800);
  return c;
}

/// source -> gain -> sink.a ; returns (source, gain, sink).
(NodeInstance, NodeInstance, NodeInstance) buildChain(NodeEditorController c) {
  final s = c.addNode('source', position: const Offset(0, 0), select: false);
  final g = c.addNode('gain', position: const Offset(300, 0), select: false);
  final k = c.addNode('sink', position: const Offset(600, 0), select: false);
  c.connect(PortRef(s.id, 'out'), PortRef(g.id, 'in'));
  c.connect(PortRef(g.id, 'out'), PortRef(k.id, 'a'));
  return (s, g, k);
}
