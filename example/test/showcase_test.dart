import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:node_program_editor_showcase/main.dart';
import 'package:node_program_editor_showcase/vision/vision_page.dart';

Future<void> _loadFonts() async {
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

Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['NPE_SCREENSHOTS'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

final _key = GlobalKey();

void main() {
  setUpAll(_loadFonts);

  testWidgets('every showcase page builds without errors', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(key: _key, child: const ShowcaseApp()),
    );
    await tester.pump();
    await _shot(tester, 'app_overview');
    for (final (label, name) in [
      ('Automation', 'app_automation'),
      ('Scientific', 'app_scientific'),
      ('Vision', 'app_vision'),
      ('Stress test', 'app_stress'),
    ]) {
      await tester.tap(find.text(label).first);
      await tester.pump();
      // Let async engines (image decoding) settle.
      await tester.runAsync(() async {
        if (label == 'Vision') await VisionPage.debugLastEngine!.run();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await _shot(tester, name);
    }
    // Run the automation workflow.
    await tester.tap(find.text('Automation').first);
    await tester.pump();
    await tester.tap(find.text('Execute workflow'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await _shot(tester, 'app_automation_run');
    await tester.pump(const Duration(seconds: 3));
  });
}
