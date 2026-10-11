import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:node_program_editor/node_program_editor.dart';

import 'helpers.dart';

/// Loads Roboto + Material icons from the Flutter SDK so screenshots show
/// real glyphs instead of the test font boxes.
Future<void> loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$dir/$f');
      if (file.existsSync()) {
        loader.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

/// Saves a PNG of [key]'s boundary when NPE_SCREENSHOTS is set.
Future<void> screenshot(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['NPE_SCREENSHOTS'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

final _shotKey = GlobalKey();

Future<NodeEditorController> pumpEditor(
  WidgetTester tester, {
  bool dark = false,
  void Function(NodeEditorController c)? setup,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = testController();
  setup?.call(c);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      home: RepaintBoundary(
        key: _shotKey,
        child: Scaffold(body: NodeEditor(controller: c)),
      ),
    ),
  );
  await tester.pump();
  return c;
}

Finder nodeTitle(String title) => find.descendant(
  of: find.byType(DefaultNodeBody),
  matching: find.text(title),
);

void main() {
  setUpAll(loadFonts);

  testWidgets('renders nodes, palette, toolbar and minimap', (tester) async {
    late (NodeInstance, NodeInstance, NodeInstance) chain;
    final c = await pumpEditor(
      tester,
      setup: (c) {
        chain = buildChain(c);
        c.setViewport(const EditorViewport(offset: Offset(80, 200)));
      },
    );
    await tester.pump();
    expect(nodeTitle('Gain'), findsOneWidget);
    expect(find.byType(NodeWidget), findsNWidgets(3));
    expect(find.byType(NodePalette), findsOneWidget);
    expect(find.byType(NodeMiniMap), findsOneWidget);
    expect(find.byType(NodeToolbar), findsOneWidget);
    c.selectNodes([chain.$2.id]);
    await tester.pump();
    await screenshot(tester, _shotKey, 'editor_light');
  });

  testWidgets('dragging a node moves it as one undo step', (tester) async {
    late NodeInstance gain;
    final c = await pumpEditor(
      tester,
      setup: (c) {
        gain = buildChain(c).$2;
        c.setViewport(const EditorViewport(offset: Offset(80, 200)));
      },
    );
    await tester.pump();
    final start = gain.position;
    final depth = c.history.undoDepth;
    await tester.drag(nodeTitle('Gain'), const Offset(120, 60));
    await tester.pump();
    expect(gain.position.dx, closeTo(start.dx + 120, 25));
    expect(gain.position.dy, closeTo(start.dy + 60, 25));
    expect(c.history.undoDepth, depth + 1);
    c.undo();
    expect(gain.position, start);
  });

  testWidgets('dragging from a port creates a link', (tester) async {
    late (NodeInstance, NodeInstance, NodeInstance) chain;
    final c = await pumpEditor(
      tester,
      setup: (c) {
        chain = buildChain(c);
        c.setViewport(const EditorViewport(offset: Offset(80, 200)));
      },
    );
    await tester.pump();
    final (_, g, k) = chain;
    final from = c.viewport.value.toScreen(c.portAnchor(PortRef(g.id, 'out'))!);
    final to = c.viewport.value.toScreen(c.portAnchor(PortRef(k.id, 'b'))!);
    final box = tester.getTopLeft(find.byType(NodeCanvas));
    final gesture = await tester.startGesture(box + from);
    await gesture.moveBy(const Offset(20, 10));
    await tester.pump();
    await gesture.moveTo(box + to + const Offset(3, 2));
    await tester.pump();
    expect(c.connectionDraft.value?.hoverTarget, PortRef(k.id, 'b'));
    await screenshot(tester, _shotKey, 'connecting');
    await gesture.up();
    await tester.pump();
    expect(c.graph.linkCount(PortRef(k.id, 'b')), 1);
  });

  testWidgets('keyboard: delete, undo, select all', (tester) async {
    late NodeInstance gain;
    final c = await pumpEditor(
      tester,
      setup: (c) {
        gain = buildChain(c).$2;
        c.setViewport(const EditorViewport(offset: Offset(80, 200)));
      },
    );
    await tester.pump();
    await tester.tap(nodeTitle('Gain'));
    await tester.pump();
    expect(c.selection.value.nodes, {gain.id});
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(c.graph.containsNode(gain.id), isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.graph.containsNode(gain.id), isTrue);
    expect(c.selection.value.nodes.length, 3);
  });

  testWidgets('shift drag on background draws a selection box', (tester) async {
    final c = await pumpEditor(
      tester,
      setup: (c) {
        buildChain(c);
        c.setViewport(const EditorViewport(offset: Offset(80, 200)));
      },
    );
    await tester.pump();
    final box = tester.getTopLeft(find.byType(NodeCanvas));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final g = await tester.startGesture(box + const Offset(40, 150));
    await g.moveBy(const Offset(30, 30));
    await tester.pump();
    await g.moveTo(box + const Offset(560, 500));
    await tester.pump();
    expect(c.marquee.value, isNotNull);
    await g.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(c.selection.value.nodes.length, 2);
  });

  testWidgets('zooming out switches to the low-detail renderer', (
    tester,
  ) async {
    final c = await pumpEditor(
      tester,
      setup: (c) {
        for (var i = 0; i < 200; i++) {
          c.addNode(
            i.isEven ? 'gain' : 'source',
            position: Offset((i % 20) * 260.0, (i ~/ 20) * 160.0),
            select: false,
          );
        }
      },
    );
    c.setViewport(const EditorViewport(zoom: 0.2));
    await tester.pump();
    expect(find.byType(NodeWidget), findsNothing);
    await screenshot(tester, _shotKey, 'lod');
    c.setViewport(const EditorViewport(zoom: 1));
    await tester.pump();
    expect(find.byType(NodeWidget), findsWidgets);
    final built = tester.widgetList(find.byType(NodeWidget)).length;
    expect(built, lessThan(200), reason: 'culled to the viewport');
  });

  testWidgets('palette click adds a node; minimap navigates', (tester) async {
    final c = await pumpEditor(tester);
    final palette = find.byType(NodePalette);
    await tester.tap(find.descendant(of: palette, matching: find.text('Sink')));
    await tester.pump();
    expect(c.graph.nodes.single.type, 'sink');
    final before = c.viewport.value;
    await tester.tapAt(
      tester.getCenter(find.byType(NodeMiniMap)) + const Offset(60, 40),
    );
    await tester.pumpAndSettle();
    expect(c.viewport.value, isNot(before));
  });

  testWidgets('edit dialog changes params as one undo step', (tester) async {
    late NodeInstance gain;
    final c = await pumpEditor(
      tester,
      setup: (c) {
        gain = buildChain(c).$2;
        c.setViewport(const EditorViewport(offset: Offset(80, 200)));
      },
    );
    await tester.pump();
    c.editNodeHandler!(gain.id);
    await tester.pumpAndSettle();
    expect(find.text('Edit Gain'), findsOneWidget);
    await screenshot(tester, _shotKey, 'edit_dialog');
    final field = find.descendant(
      of: find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(NumberField),
      ),
      matching: find.byType(TextField),
    );
    await tester.enterText(field.first, '7.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(gain.params['k'], 7.5);
    c.undo();
    expect(gain.params['k'], 2.0);
  });

  testWidgets('dark theme and super node breadcrumb', (tester) async {
    late (NodeInstance, NodeInstance, NodeInstance) chain;
    final c = await pumpEditor(
      tester,
      dark: true,
      setup: (c) {
        chain = buildChain(c);
        c.setViewport(const EditorViewport(offset: Offset(80, 200)));
      },
    );
    await tester.pump();
    c.selectNodes([chain.$2.id]);
    final inst = c.groupSelection(name: 'Amplifier')!;
    await tester.pump();
    await screenshot(tester, _shotKey, 'dark_group');
    c.enterSuperNode(inst.id);
    await tester.pumpAndSettle();
    expect(find.byType(SuperNodeBreadcrumb), findsOneWidget);
    expect(find.text('Amplifier'), findsWidgets);
    await screenshot(tester, _shotKey, 'inside_function');
    c.exitSuperNode();
    await tester.pumpAndSettle();
    expect(c.scopes.length, 1);
  });

  testWidgets('dragging an edge "+" handle inserts a waypoint', (tester) async {
    late (NodeInstance, NodeInstance, NodeInstance) chain;
    final c = await pumpEditor(
      tester,
      setup: (c) {
        chain = buildChain(c);
        c.setViewport(const EditorViewport(offset: Offset(80, 200)));
      },
    );
    await tester.pump();
    final edge = c.graph.outgoing(chain.$1.id).single;
    c.selectEdges([edge.id]);
    await tester.pump();
    final handle = find.byIcon(Icons.add).last;
    await tester.drag(handle, const Offset(0, 120));
    await tester.pump();
    final updated = c.graph.edge(edge.id)!;
    expect(updated.waypoints.length, 1);
    expect(updated.style.pathType, EdgePathType.polyline);
    await screenshot(tester, _shotKey, 'waypoint');
    c.undo();
    expect(c.graph.edge(edge.id)!.waypoints, isEmpty);
  });

  testWidgets('typing in a node text field does not trigger graph shortcuts', (
    tester,
  ) async {
    late NodeInstance gain;
    final c = await pumpEditor(
      tester,
      setup: (c) {
        gain = buildChain(c).$2;
        c.setViewport(const EditorViewport(offset: Offset(80, 200)));
      },
    );
    await tester.pump();
    c.selectNodes([gain.id]);
    await tester.pump();
    final field = find.descendant(
      of: find.byType(NodeWidget),
      matching: find.byType(TextField),
    );
    await tester.tap(field.first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(c.graph.containsNode(gain.id), isTrue);
    expect(c.history.undoLabel, isNot('Move node'));
  });
}
