import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:node_program_editor/node_program_editor.dart';
import 'package:node_program_editor_showcase/scientific/expr.dart';
import 'package:node_program_editor_showcase/scientific/sci_engine.dart';
import 'package:node_program_editor_showcase/scientific/sci_nodes.dart';
import 'package:node_program_editor_showcase/vision/vision_engine.dart';
import 'package:node_program_editor_showcase/vision/vision_nodes.dart';

void main() {
  testWidgets('vision pipeline counts the synthetic parts', (tester) async {
    final c = NodeEditorController(
      config: const NodeEditorConfig(useSystemClipboard: false),
    );
    final engine = VisionEngine(c);
    c.registry.registerAll(visionNodes(engine));
    NodeInstance add(String t) =>
        c.addNode(t, position: Offset.zero, select: false);
    final cam = add('vis.camera');
    final gray = add('vis.gray');
    final blur = add('vis.blur');
    final thr = add('vis.threshold');
    final morph = add('vis.morph');
    final blobs = add('vis.blobs');
    final result = add('vis.result');
    for (final (a, ap, b, bp) in [
      (cam, 'out', gray, 'in'),
      (gray, 'out', blur, 'in'),
      (blur, 'out', thr, 'in'),
      (thr, 'out', morph, 'in'),
      (morph, 'out', blobs, 'in'),
      (blobs, 'count', result, 'in'),
    ]) {
      expect(c.connect(PortRef(a.id, ap), PortRef(b.id, bp)), isNotNull);
    }
    await tester.runAsync(engine.run);
    expect(engine.previews[blobs.id.value], isNotNull);
    final count = int.parse(engine.info[blobs.id.value]!.split(' ').first);
    expect(count, inInclusiveRange(7, 10));
    expect(engine.verdicts[result.id.value], isNotNull);
    final dir = Platform.environment['NPE_SCREENSHOTS'];
    if (dir != null) {
      await tester.runAsync(() async {
        for (final (name, n) in [
          ('vision_blobs', blobs),
          ('vision_camera', cam),
        ]) {
          final png = await engine.previews[n.id.value]!.toByteData(
            format: ui.ImageByteFormat.png,
          );
          File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
        }
      });
    }
  });

  test('expression compiler', () {
    final f = Expr.compile('a * sin(2*pi*t) + b^2 - max(1, 2)');
    expect(f({'a': 2, 't': 0.25, 'b': 3}), closeTo(2 + 9 - 2, 1e-9));
    expect(() => Expr.compile('1 +'), throwsFormatException);
  });

  test('scientific engine: gain and stats', () {
    final c = NodeEditorController(
      config: const NodeEditorConfig(useSystemClipboard: false),
    );
    final engine = SciEngine(c);
    c.registry.registerAll(scientificNodes(engine));
    final k = c.addNode(
      'sci.const',
      position: Offset.zero,
      params: {'value': 3.0},
    );
    final g = c.addNode('sci.gain', position: Offset.zero, params: {'k': 2.0});
    final s = c.addNode('sci.stats', position: Offset.zero);
    c.connect(PortRef(k.id, 'out'), PortRef(g.id, 'in'));
    c.connect(PortRef(g.id, 'out'), PortRef(s.id, 'in'));
    engine.run();
    expect(engine.stats[s.id.value]!['mean'], closeTo(6, 1e-9));
  });
}
