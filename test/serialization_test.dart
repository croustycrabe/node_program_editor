import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:node_program_editor/node_program_editor.dart';

import 'helpers.dart';

void main() {
  group('Param codecs round trip', () {
    final cases = <ParamType<Object?>, Object?>{
      const IntParam(min: 0, max: 10): 7,
      const DoubleParam(): 3.25,
      const BoolParam(): true,
      const TextParam(): 'hello',
      const MultilineTextParam(): 'a\nb',
      const PasswordParam(): 's3cret',
      const CodeParam(language: 'python'): 'print(1)',
      const ExpressionParam(): 'a*sin(t)',
      EnumParam.values(['a', 'b']): 'b',
      const MultiSelectParam([ParamOption('x'), ParamOption('y')]): ['x', 'y'],
      const ListParam(IntParam()): [1, 2, 3],
      const TableParam([
        TableColumn('k', TextParam()),
        TableColumn('v', DoubleParam()),
      ]): [
        {'k': 'a', 'v': 1.5},
      ],
      const JsonParam(): {
        'a': [1, 2],
      },
      const QuantityParam(['ms', 's']): const Quantity(12, 'ms'),
      const RangeParam(min: 0, max: 255): const RangeValue(10, 200),
      const VectorParam(dimension: 3): [1.0, 2.0, 3.0],
      const MatrixParam(): Matrix.identity(3),
      const CurveParam.lut(): const [
        Offset(0, 0),
        Offset(128, 200),
        Offset(255, 255),
      ],
      const ColorParam(): const Color(0x80FF0000),
      const ImageParam(): ImageRef(
        bytes: Uint8List.fromList([1, 2, 3]),
        name: 'x.png',
      ),
      const RoiParam(): const Roi(Rect.fromLTWH(10, 20, 100, 50), angle: 0.5),
      const PointParam(): const Offset(3, 4),
      const FilePathParam(): '/tmp/a.txt',
      const DateTimeParam(): DateTime.utc(2026, 10, 11, 12),
      const ColorMapParam(): 'jet',
    };
    cases.forEach((type, value) {
      test(type.id, () {
        final encoded = type.encodeAny(value);
        final decoded = type.decodeAny(encoded);
        if (value is ImageRef) {
          expect((decoded! as ImageRef).bytes, value.bytes);
        } else {
          expect(decoded, value);
        }
        expect(type.validateAny(value), isNull);
      });
    });

    test('decodeAny never throws', () {
      expect(const IntParam(defaultValue: 4).decodeAny('garbage'), 4);
      expect(
        const MatrixParam().decodeAny(42),
        const MatrixParam().defaultValue,
      );
    });
  });

  group('Documents', () {
    test('logic + design round trip', () {
      final c = testController();
      final (s, g, k) = buildChain(c);
      c.setParam(s.id, 'value', 3.5);
      c.setLocked([g.id], true);
      c.setNodeAppearanceOf(
        k.id,
        style: const NodeStyle(headerColor: Color(0xFF00FF00)),
        title: 'Out',
      );
      final e = c.graph.outgoing(s.id).single;
      c.updateEdge(
        e.id,
        (e) => e.copyWith(
          label: 'x',
          style: const EdgeStyle(
            pathType: EdgePathType.smoothStep,
            endMarker: EdgeMarker.arrowClosed,
            dashPattern: [4, 2],
            animated: true,
          ),
        ),
      );
      c.canvasSettings.value = const CanvasSettings(
        gridStyle: GridStyle.lines,
        snapToGrid: true,
      );
      c.setViewport(const Viewport(offset: Offset(12, 34), zoom: 0.8));

      final logicJson = c.exportLogic().toJsonString();
      final designJson = c.exportDesign().toJsonString();
      expect(
        logicJson,
        isNot(contains('"x":')),
        reason: 'no geometry in logic',
      );
      expect(
        designJson,
        isNot(contains('"params"')),
        reason: 'no params in design',
      );

      final c2 = testController();
      c2.load(
        LogicDocument.fromJsonString(logicJson),
        DesignDocument.fromJsonString(designJson),
      );
      expect(c2.graph.nodeCount, 3);
      expect(c2.graph.edgeCount, 2);
      final s2 = c2.graph.node(s.id)!;
      expect(s2.params['value'], 3.5);
      expect(s2.position, s.position);
      expect(c2.graph.node(g.id)!.locked, isTrue);
      expect(c2.graph.node(k.id)!.title, 'Out');
      expect(c2.graph.node(k.id)!.style!.headerColor, const Color(0xFF00FF00));
      final e2 = c2.graph.edge(e.id)!;
      expect(e2.label, 'x');
      expect(e2.style.pathType, EdgePathType.smoothStep);
      expect(e2.style.endMarker, EdgeMarker.arrowClosed);
      expect(e2.style.dashPattern, [4, 2]);
      expect(e2.style.animated, isTrue);
      expect(c2.canvasSettings.value.gridStyle, GridStyle.lines);
      expect(
        c2.viewport.value,
        const Viewport(offset: Offset(12, 34), zoom: 0.8),
      );
      expect(c2.exportLogic().toJsonString(), logicJson);
    });

    test('logic without design is auto laid out', () {
      final c = testController();
      buildChain(c);
      final logic = LogicDocument.fromJsonString(
        c.exportLogic().toJsonString(),
      );
      final c2 = testController()..load(logic);
      final xs = c2.graph.topologicalOrder().map((n) => n.position.dx).toList();
      expect(xs[0] < xs[1] && xs[1] < xs[2], isTrue);
    });

    test('unknown node types survive a round trip', () {
      final c = testController();
      buildChain(c);
      final logic = c.exportLogic();
      final c2 = NodeEditorController(
        registry: NodeRegistry(definitions: [sourceDef]),
        config: const NodeEditorConfig(useSystemClipboard: false),
      )..load(logic, c.exportDesign());
      expect(c2.graph.nodeCount, 3);
      expect(c2.graph.edgeCount, 2, reason: 'ports rebuilt from logic file');
      expect(
        c2.graph.nodes
            .where((n) => n.definition is UnknownNodeDefinition)
            .length,
        2,
      );
      final again = c2.exportLogic().toJson();
      expect(again['nodes'], logic.toJson()['nodes']);
    });
  });

  group('Clipboard', () {
    test('copy / paste remaps ids and keeps inner edges only', () {
      final c = testController();
      final (s, g, _) = buildChain(c);
      c.selectNodes([s.id, g.id]);
      final f = c.copySelection()!;
      expect(f.nodes.length, 2);
      expect(f.edges.length, 1);
      final pasted = c.pasteFragment(f);
      expect(pasted.length, 2);
      expect(c.graph.nodeCount, 5);
      expect(c.graph.edgeCount, 3);
      expect(
        pasted.map((n) => n.id).toSet().intersection({s.id, g.id}),
        isEmpty,
      );
      expect(pasted.first.position, s.position + const Offset(24, 24));
      expect(c.selection.value.nodes, pasted.map((n) => n.id).toSet());
      // Through JSON (system clipboard path).
      final parsed = GraphFragment.tryParse(f.toJsonString())!;
      c.pasteFragment(parsed, at: const Offset(1000, 1000));
      expect(c.graph.nodeCount, 7);
      c.undo();
      expect(c.graph.nodeCount, 5);
    });
  });
}
