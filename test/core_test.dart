import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:node_program_editor/node_program_editor.dart';

import 'helpers.dart';

void main() {
  group('Graph', () {
    test('adjacency and link counts', () {
      final c = testController();
      final (s, g, k) = buildChain(c);
      final graph = c.graph;
      expect(graph.nodeCount, 3);
      expect(graph.edgeCount, 2);
      expect(graph.linkCount(PortRef(s.id, 'out')), 1);
      expect(graph.incoming(g.id).single.source.node, s.id);
      expect(graph.outgoing(g.id).single.target.node, k.id);
      expect(graph.hasPath(s.id, k.id), isTrue);
      expect(graph.hasPath(k.id, s.id), isFalse);
      expect(graph.topologicalOrder().map((n) => n.id), [s.id, g.id, k.id]);
    });

    test('removeNode removes its edges', () {
      final c = testController();
      final (_, g, _) = buildChain(c);
      final removed = c.graph.removeNode(g.id);
      expect(removed.length, 2);
      expect(c.graph.edgeCount, 0);
    });

    test('bringToFront changes z order', () {
      final c = testController();
      final (s, _, k) = buildChain(c);
      c.bringToFront(s.id);
      expect(c.graph.nodes.last.id, s.id);
      expect(c.graph.indexOfNode(k.id), 1);
    });
  });

  group('SpatialHashGrid', () {
    test('query matches brute force', () {
      final rnd = Random(42);
      final grid = SpatialHashGrid<int>(cellSize: 100);
      final rects = <int, Rect>{};
      for (var i = 0; i < 2000; i++) {
        final r = Rect.fromLTWH(
          rnd.nextDouble() * 10000 - 5000,
          rnd.nextDouble() * 10000 - 5000,
          20 + rnd.nextDouble() * 300,
          20 + rnd.nextDouble() * 200,
        );
        rects[i] = r;
        grid.insert(i, r);
      }
      // Move some.
      for (var i = 0; i < 500; i++) {
        final r = rects[i]!.shift(
          Offset(rnd.nextDouble() * 400, -rnd.nextDouble() * 400),
        );
        rects[i] = r;
        grid.insert(i, r);
      }
      for (var i = 500; i < 600; i++) {
        grid.remove(i);
        rects.remove(i);
      }
      for (var q = 0; q < 50; q++) {
        final area = Rect.fromLTWH(
          rnd.nextDouble() * 8000 - 4000,
          rnd.nextDouble() * 8000 - 4000,
          rnd.nextDouble() * 3000,
          rnd.nextDouble() * 3000,
        );
        final expected = {
          for (final e in rects.entries)
            if (e.value.overlaps(area)) e.key,
        };
        expect(grid.query(area).toSet(), expected);
      }
    });

    test('50k nodes: viewport query is fast', () {
      final grid = SpatialHashGrid<int>();
      for (var i = 0; i < 50000; i++) {
        grid.insert(
          i,
          Rect.fromLTWH((i % 250) * 300.0, (i ~/ 250) * 200.0, 200, 120),
        );
      }
      final sw = Stopwatch()..start();
      var found = 0;
      for (var i = 0; i < 100; i++) {
        found += grid
            .query(Rect.fromLTWH(i * 100.0, i * 50.0, 1920, 1080))
            .length;
      }
      sw.stop();
      expect(found, greaterThan(0));
      // 100 viewport queries over 50k items must be far below a frame each.
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group('ConnectionValidator', () {
    test('rules', () {
      final c = testController();
      final s = c.addNode('source', position: Offset.zero);
      final k = c.addNode('sink', position: const Offset(400, 0));
      final v = c.validator;
      expect(
        v.validate(c.graph, PortRef(s.id, 'out'), PortRef(k.id, 'a')).isValid,
        isTrue,
      );
      // Reverse order is normalized.
      final r = v.validate(c.graph, PortRef(k.id, 'a'), PortRef(s.id, 'out'));
      expect(r.isValid, isTrue);
      expect(r.request!.source, PortRef(s.id, 'out'));
      expect(
        v.validate(c.graph, PortRef(s.id, 'out'), PortRef(k.id, 'img')).error,
        ConnectionError.incompatibleTypes,
      );
      expect(
        v.validate(c.graph, PortRef(k.id, 'a'), PortRef(k.id, 'b')).error,
        ConnectionError.sameDirection,
      );
      c.connect(PortRef(s.id, 'out'), PortRef(k.id, 'b'));
      expect(
        v.validate(c.graph, PortRef(s.id, 'out'), PortRef(k.id, 'b')).error,
        ConnectionError.duplicate,
      );
    });

    test('maxLinks 1 replaces the existing link', () {
      final c = testController();
      final s1 = c.addNode('source', position: Offset.zero);
      final s2 = c.addNode('source', position: const Offset(0, 200));
      final k = c.addNode('sink', position: const Offset(400, 0));
      c.connect(PortRef(s1.id, 'out'), PortRef(k.id, 'a'));
      c.connect(PortRef(s2.id, 'out'), PortRef(k.id, 'a'));
      final links = c.graph.edgesOfPort(PortRef(k.id, 'a')).toList();
      expect(links.single.source.node, s2.id);
      c.undo();
      expect(c.graph.edgesOfPort(PortRef(k.id, 'a')).single.source.node, s1.id);
    });

    test('cycles can be forbidden', () {
      final c = testController();
      c.validator = const ConnectionValidator(allowCycles: false);
      final a = c.addNode('gain', position: Offset.zero);
      final b = c.addNode('gain', position: const Offset(300, 0));
      expect(c.connect(PortRef(a.id, 'out'), PortRef(b.id, 'in')), isNotNull);
      expect(
        c.canConnect(PortRef(b.id, 'out'), PortRef(a.id, 'in')).error,
        ConnectionError.cycle,
      );
    });
  });

  group('Commands and history', () {
    test('add / remove / undo / redo', () {
      final c = testController();
      final (s, g, _) = buildChain(c);
      expect(c.history.undoDepth, 5);
      c.remove(nodes: [g.id]);
      expect(c.graph.nodeCount, 2);
      expect(c.graph.edgeCount, 0);
      c.undo();
      expect(c.graph.nodeCount, 3);
      expect(c.graph.edgeCount, 2);
      expect(c.graph.indexOfNode(g.id), 1, reason: 'z-order restored');
      c.redo();
      expect(c.graph.containsNode(g.id), isFalse);
      c.undo();
      c.moveNodes({s.id: const Offset(10, 20)});
      expect(c.graph.node(s.id)!.position, const Offset(10, 20));
      c.undo();
      expect(c.graph.node(s.id)!.position, Offset.zero);
    });

    test('a drag is one undo step and snaps to grid', () {
      final c = testController();
      c.canvasSettings.value = const CanvasSettings(
        snapToGrid: true,
        gridSpacing: 20,
      );
      final (s, g, _) = buildChain(c);
      c.selectNodes([s.id, g.id]);
      final depth = c.history.undoDepth;
      c.beginNodeDrag(s.id);
      for (var i = 1; i <= 10; i++) {
        c.updateNodeDrag(Offset(i * 3.3, i * 1.7));
      }
      c.endNodeDrag();
      expect(c.history.undoDepth, depth + 1);
      expect(c.graph.node(s.id)!.position, const Offset(40, 20));
      expect(c.graph.node(g.id)!.position, const Offset(340, 20));
      c.undo();
      expect(c.graph.node(s.id)!.position, Offset.zero);
      expect(c.graph.node(g.id)!.position, const Offset(300, 0));
    });

    test('locked nodes are not dragged nor deleted', () {
      final c = testController();
      final (s, g, _) = buildChain(c);
      c.setLocked([s.id], true);
      c.selectNodes([s.id, g.id]);
      c.beginNodeDrag(g.id);
      c.updateNodeDrag(const Offset(50, 0));
      c.endNodeDrag();
      expect(c.graph.node(s.id)!.position, Offset.zero);
      expect(c.graph.node(g.id)!.position, const Offset(350, 0));
      c.deleteSelection();
      expect(c.graph.containsNode(s.id), isTrue);
      expect(c.graph.containsNode(g.id), isFalse);
    });

    test('params are normalized and merged', () {
      final c = testController();
      final s = c.addNode('source', position: Offset.zero);
      c.setParam(s.id, 'value', 50.0);
      expect(s.params['value'], 10.0, reason: 'clamped to max');
      final depth = c.history.undoDepth;
      c.setParam(s.id, 'label', 'a');
      c.setParam(s.id, 'label', 'ab');
      c.setParam(s.id, 'label', 'abc');
      expect(c.history.undoDepth, depth + 1, reason: 'typing merges');
      c.undo();
      expect(s.params['label'], 'src');
    });

    test('node notifiers fire only for the changed node', () {
      final c = testController();
      final (s, g, _) = buildChain(c);
      var sCount = 0, gCount = 0, sMoves = 0;
      c.nodeListenable(s.id).addListener(() => sCount++);
      c.nodeListenable(g.id).addListener(() => gCount++);
      c.nodePositionListenable(s.id).addListener(() => sMoves++);
      c.setParam(s.id, 'value', 1.0);
      c.moveNodes({s.id: const Offset(5, 5)});
      expect(sCount, 1, reason: 'moving does not rebuild node content');
      expect(sMoves, 1);
      expect(gCount, 0);
      c.selectNodes([g.id]);
      expect(gCount, 1);
    });

    test('marquee selects nodes and inner edges', () {
      final c = testController();
      final (s, g, k) = buildChain(c);
      c.beginMarquee(const Offset(-10, -10));
      c.updateMarquee(const Offset(450, 300));
      c.endMarquee();
      expect(c.selection.value.nodes, {s.id, g.id});
      expect(c.selection.value.edges.length, 1);
      expect(c.selection.value.nodes.contains(k.id), isFalse);
    });

    test('connection drag snaps to compatible ports', () {
      final c = testController();
      final (_, g, k) = buildChain(c);
      final anchor = c.portAnchor(PortRef(k.id, 'b'))!;
      c.beginConnection(PortRef(g.id, 'out'));
      c.updateConnection(anchor + const Offset(5, 3));
      expect(c.connectionDraft.value!.hoverTarget, PortRef(k.id, 'b'));
      expect(c.connectionDraft.value!.hoverValid, isTrue);
      final e = c.endConnection();
      expect(e, isNotNull);
      expect(c.graph.linkCount(PortRef(k.id, 'b')), 1);
    });
  });

  group('EditorViewport', () {
    test('zoom around focal keeps point fixed', () {
      const v = EditorViewport(offset: Offset(100, 50), zoom: 1);
      final c = v.toCanvas(const Offset(400, 300));
      final z = v.zoomAround(const Offset(400, 300), 2);
      expect(z.toScreen(c), const Offset(400, 300));
    });

    test('fitView frames all nodes', () {
      final c = testController();
      buildChain(c);
      c.fitView(animate: false);
      final visible = c.viewport.value.visibleRect(c.viewportSize);
      expect(visible.contains(c.boundsOf()!.topLeft), isTrue);
      expect(visible.contains(c.boundsOf()!.bottomRight), isTrue);
    });
  });

  group('Edge geometry', () {
    for (final type in EdgePathType.values) {
      test('routes $type', () {
        final g = EdgeRouter.route(
          EdgePathInput(
            source: const Offset(0, 0),
            sourceSide: PortSide.right,
            target: const Offset(-200, 150),
            targetSide: PortSide.left,
            style: EdgeStyle(pathType: type),
            waypoints: const [Offset(50, 80)],
          ),
        );
        expect(g.polyline.first, const Offset(0, 0));
        expect(g.polyline.last, const Offset(-200, 150));
        expect(g.length, greaterThan(0));
        if (type == EdgePathType.step || type == EdgePathType.smoothStep) {
          for (var i = 1; i < g.polyline.length; i++) {
            final a = g.polyline[i - 1], b = g.polyline[i];
            expect(a.dx == b.dx || a.dy == b.dy, isTrue, reason: 'orthogonal');
          }
        }
      });
    }

    test('edgeAt hit tests', () {
      final c = testController();
      final (s, g, _) = buildChain(c);
      final e = c.graph.outgoing(s.id).single;
      final geom = c.edgeGeometry(e)!;
      expect(c.edgeAt(geom.midpoint)?.id, e.id);
      expect(c.edgeAt(geom.midpoint + const Offset(0, 200)), isNull);
      expect(g, isNotNull);
    });
  });

  test('autoLayout orders nodes left to right in one undo step', () {
    final c = testController();
    final (s, g, k) = buildChain(c);
    c.moveNodes({s.id: const Offset(900, 500), k.id: const Offset(-300, 40)});
    final depth = c.history.undoDepth;
    c.autoLayout();
    expect(c.history.undoDepth, depth + 1);
    expect(
      s.position.dx < g.position.dx && g.position.dx < k.position.dx,
      isTrue,
    );
    c.undo();
    expect(s.position, const Offset(900, 500));
  });
}
