import 'package:flutter_test/flutter_test.dart';
import 'package:node_program_editor/node_program_editor.dart';

import 'helpers.dart';

void main() {
  test('group exposes boundary ports and reconnects edges', () {
    final c = testController();
    final (s, g, k) = buildChain(c);
    c.selectNodes([g.id]);
    final inst = c.groupSelection(name: 'Amp')!;
    expect(c.graph.nodeCount, 3);
    expect(c.graph.containsNode(g.id), isFalse);
    expect(inst.definition, isA<SuperNodeNodeDefinition>());
    expect(inst.ports.where((p) => p.isInput).length, 1);
    expect(inst.ports.where((p) => p.isOutput).length, 1);
    expect(c.graph.incoming(inst.id).single.source.node, s.id);
    expect(c.graph.outgoing(inst.id).single.target.node, k.id);
    final def = c.superNodes.definitionOf(inst.type)!;
    expect(def.graph.nodeCount, 3, reason: 'gain + 2 proxies');
    expect(def.graph.edgeCount, 2);

    c.undo();
    expect(c.graph.containsNode(g.id), isTrue);
    expect(c.graph.edgeCount, 2);
    expect(c.registry.contains(inst.type), isFalse);
    c.redo();
    expect(c.graph.containsNode(inst.id), isTrue);
    expect(c.registry.contains(inst.type), isTrue);
  });

  test('ungroup restores interior and applies exposed params', () {
    final c = testController();
    final (s, g, k) = buildChain(c);
    c.selectNodes([g.id]);
    final inst = c.groupSelection()!;
    final def = c.superNodes.definitionOf(inst.type)!;
    c.superNodes.setExposedParams(c, def, [
      ParamBinding(name: 'gain', label: 'Gain', node: g.id, param: 'k'),
    ]);
    final inst2 = c.graph.node(inst.id)!;
    expect(inst2.definition.params.single.name, 'gain');
    expect(inst2.params['gain'], 2.0);
    c.setParam(inst.id, 'gain', 5.0);
    c.selectNodes([inst.id]);
    c.ungroupSelection();
    expect(c.graph.nodeCount, 3);
    final restored = c.graph.nodes.firstWhere((n) => n.type == 'gain');
    expect(restored.params['k'], 5.0);
    expect(c.graph.incoming(restored.id).single.source.node, s.id);
    expect(c.graph.outgoing(restored.id).single.target.node, k.id);
  });

  test('enter / exit scope edits the definition', () {
    final c = testController();
    final (_, g, _) = buildChain(c);
    c.selectNodes([g.id]);
    final inst = c.groupSelection()!;
    expect(c.enterSuperNode(inst.id), isTrue);
    expect(c.scopes.length, 2);
    expect(c.graph.nodeCount, 3);
    c.addNode('source', position: const Offset(0, 500));
    expect(c.graph.nodeCount, 4);
    c.exitSuperNode();
    expect(c.scopes.length, 1);
    expect(c.superNodes.definitionOf(inst.type)!.graph.nodeCount, 4);
  });

  test('documents with super nodes round trip and flatten', () {
    final c = testController();
    final (s, g, k) = buildChain(c);
    c.selectNodes([g.id]);
    final inst = c.groupSelection()!;
    final logic = c.exportLogic();
    expect(logic.superNodes.length, 1);

    final c2 = testController()
      ..load(
        LogicDocument.fromJsonString(logic.toJsonString()),
        DesignDocument.fromJsonString(c.exportDesign().toJsonString()),
      );
    final inst2 = c2.graph.node(inst.id)!;
    expect(inst2.definition, isA<SuperNodeNodeDefinition>());
    expect(c2.graph.edgeCount, 2);

    final flat = logic.flatten();
    expect(flat.superNodes, isEmpty);
    expect(flat.nodes.map((n) => n.type).toSet(), {'source', 'gain', 'sink'});
    expect(flat.edges.length, 2);
    final gainId = flat.nodes.firstWhere((n) => n.type == 'gain').id;
    expect(gainId.value, '${inst.id.value}/${g.id.value}');
    expect(
      flat.edges.any((e) => e.source.node == s.id && e.target.node == gainId),
      isTrue,
    );
    expect(
      flat.edges.any((e) => e.source.node == gainId && e.target.node == k.id),
      isTrue,
    );
  });

  test('nested super nodes flatten', () {
    final c = testController();
    final (s, g, k) = buildChain(c);
    c.selectNodes([g.id]);
    final inner = c.groupSelection(name: 'Inner')!;
    c.selectNodes([inner.id, k.id]);
    c.groupSelection(name: 'Outer');
    final flat = c.exportLogic().flatten();
    expect(flat.nodes.map((n) => n.type).toList()..sort(), [
      'gain',
      'sink',
      'source',
    ]);
    expect(flat.edges.length, 2);
    final gain = flat.nodes.firstWhere((n) => n.type == 'gain').id;
    expect(
      flat.edges.any((e) => e.source.node == s.id && e.target.node == gain),
      isTrue,
    );
  });

  test(
    'copy / paste a super node into another editor carries its definition',
    () {
      final c = testController();
      final (_, g, _) = buildChain(c);
      c.selectNodes([g.id]);
      c.groupSelection(name: 'F');
      final f = c.copySelection()!;
      expect(f.superNodes.length, 1);
      final c2 = testController();
      final pasted = c2.pasteFragment(
        GraphFragment.tryParse(f.toJsonString())!,
      );
      expect(pasted.single.definition, isA<SuperNodeNodeDefinition>());
      expect(c2.superNodes.definitions.length, 1);
    },
  );

  test('library export / import', () {
    final c = testController();
    final (_, g, _) = buildChain(c);
    c.selectNodes([g.id]);
    c.groupSelection(name: 'Lib');
    final lib = c.superNodes.exportLibrary();
    final c2 = testController();
    final ids = c2.superNodes.importLibrary(lib);
    expect(ids.length, 1);
    final def = c2.superNodes[ids.single]!;
    final n = c2.addNode(def.type, position: Offset.zero);
    expect(n.ports.length, 2);
  });

  test('a function cannot be placed inside itself', () {
    final c = testController();
    final (_, g, _) = buildChain(c);
    c.selectNodes([g.id]);
    final inner = c.groupSelection(name: 'Inner')!;
    // Outer contains Inner.
    c.selectNodes([inner.id]);
    final outer = c.groupSelection(name: 'Outer')!;
    final innerType = inner.type;

    expect(c.enterSuperNode(outer.id), isTrue);
    expect(c.canInsertType(outer.type), isFalse, reason: 'itself');
    expect(c.canInsertType(innerType), isTrue);
    expect(
      () => c.addNode(outer.type, position: Offset.zero),
      throwsStateError,
    );
    final innerInstance = c.graph.nodes.firstWhere((n) => n.type == innerType);
    expect(c.enterSuperNode(innerInstance.id), isTrue);
    expect(c.canInsertType(innerType), isFalse, reason: 'itself');
    expect(c.canInsertType(outer.type), isFalse, reason: 'contains it');
    expect(c.canInsertType('gain'), isTrue);

    // Pasting an instance of the open function is skipped.
    c.exitSuperNode(depth: 0);
    c.selectNodes([outer.id]);
    final fragment = c.copySelection()!;
    c.enterSuperNode(outer.id);
    final before = c.graph.nodeCount;
    expect(c.pasteFragment(fragment), isEmpty);
    expect(c.graph.nodeCount, before);
  });

  test('flatten survives a recursive definition from a file', () {
    final c = testController();
    final (_, g, _) = buildChain(c);
    c.selectNodes([g.id]);
    final inst = c.groupSelection()!;
    final def = c.superNodes.definitionOf(inst.type)!;
    // Bypass the guards like a hand-edited file would.
    def.graph.addNode(
      NodeInstance.create(c.registry[inst.type]!, position: Offset.zero),
    );
    final flat = c.exportLogic().flatten();
    expect(flat.nodes.where((n) => n.type == 'gain').length, 1);
    expect(
      flat.nodes.where((n) => n.type == inst.type).length,
      1,
      reason: 'the recursive instance is kept as an opaque node',
    );
  });

  test('function ports can be added, renamed, retyped and removed', () {
    final c = testController();
    final (s, g, k) = buildChain(c);
    c.selectNodes([g.id]);
    final inst = c.groupSelection(name: 'Amp')!;
    final def = c.superNodes.definitionOf(inst.type)!;
    final input = def.inputs.single;
    final output = def.outputs.single;

    // From outside: rename + retype the input, add one, remove the output.
    c.superNodes.setInterface(
      c,
      def,
      inputs: [
        input.copyWith(label: 'signal', type: PortType.signal),
        const PortSpec.input('in2', label: 'gain', type: PortType.number),
      ],
      outputs: const [],
    );
    final now = c.graph.node(inst.id)!;
    expect(now.ports.where((p) => p.isInput).map((p) => p.label), [
      'signal',
      'gain',
    ]);
    expect(now.ports.where((p) => p.isOutput), isEmpty);
    expect(
      c.graph.incoming(inst.id).single.source.node,
      s.id,
      reason: 'kept id keeps the link',
    );
    expect(
      c.graph.edgesOfNode(k.id),
      isEmpty,
      reason: 'link to the removed output is deleted',
    );
    expect(def.graph.edgesOfNode(def.outputProxy), isEmpty);

    // From inside, through the proxy: undoable.
    c.enterSuperNode(inst.id);
    c.superNodes.setInterface(
      c,
      def,
      inputs: def.inputs,
      outputs: [output.copyWith(label: 'result')],
    );
    expect(def.outputs.single.label, 'result');
    c.undo();
    expect(def.outputs, isEmpty);
    c.redo();
    c.exitSuperNode();
    expect(
      c.graph.node(inst.id)!.ports.where((p) => p.isOutput).single.label,
      'result',
    );
  });
}
