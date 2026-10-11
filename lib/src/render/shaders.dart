import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Loads and caches the package fragment shaders.
///
/// Shaders are optional accelerators: every painter has a CPU fallback, so
/// the editor works when shaders are unavailable (unit tests, very old GPU
/// drivers) or disabled with [enabled].
abstract final class EditorShaders {
  /// Globally enables / disables shader usage.
  static bool enabled = true;

  static ui.FragmentProgram? _grid;
  static ui.FragmentProgram? _edgeFlow;
  static Future<void>? _loading;

  /// Notifies when the shaders finished loading.
  static final ValueNotifier<bool> loaded = ValueNotifier(false);

  /// Grid program, null until loaded or when unavailable.
  static ui.FragmentProgram? get grid => enabled ? _grid : null;

  /// Edge flow program, null until loaded or when unavailable.
  static ui.FragmentProgram? get edgeFlow => enabled ? _edgeFlow : null;

  /// Starts loading (idempotent).
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    _grid = await _tryLoad('packages/node_program_editor/shaders/grid.frag');
    _edgeFlow = await _tryLoad(
      'packages/node_program_editor/shaders/edge_flow.frag',
    );
    loaded.value = true;
  }

  static Future<ui.FragmentProgram?> _tryLoad(String asset) async {
    try {
      return await ui.FragmentProgram.fromAsset(asset);
    } catch (e) {
      debugPrint(
        'node_program_editor: shader $asset unavailable ($e); '
        'using CPU fallback.',
      );
      return null;
    }
  }
}

/// Writes straight-alpha color components into consecutive float uniforms.
int setColorUniform(ui.FragmentShader shader, int index, ui.Color color) {
  shader
    ..setFloat(index, color.r)
    ..setFloat(index + 1, color.g)
    ..setFloat(index + 2, color.b)
    ..setFloat(index + 3, color.a);
  return index + 4;
}
