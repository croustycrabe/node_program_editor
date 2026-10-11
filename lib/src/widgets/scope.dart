import 'package:flutter/widgets.dart';

import '../core/controller.dart';
import '../core/ids.dart';
import '../params/param_types.dart';
import '../params/param_values.dart';
import 'theme.dart';

/// Host application hooks used by built-in widgets. The package performs no
/// I/O by itself: file / image pickers and trigger buttons call back into
/// the app.
class NodeEditorServices {
  /// Creates services.
  const NodeEditorServices({
    this.pickFile,
    this.pickImage,
    this.onTrigger,
    this.imageProvider,
  });

  /// Picks a file path for a [FilePathParam].
  final Future<String?> Function(BuildContext context, FilePathParam param)?
  pickFile;

  /// Picks an image for an [ImageParam].
  final Future<ImageRef?> Function(BuildContext context, ImageParam param)?
  pickImage;

  /// Called when a [TriggerParam] button is pressed.
  final void Function(NodeId node, String param)? onTrigger;

  /// Resolves an [ImageRef] to an [ImageProvider] for previews (defaults to
  /// memory bytes, assets for `asset:` uris and network for http uris).
  final ImageProvider? Function(ImageRef ref)? imageProvider;

  /// Resolves [ref] with [imageProvider] or the default rules.
  ImageProvider? resolveImage(ImageRef ref) {
    final custom = imageProvider?.call(ref);
    if (custom != null) return custom;
    if (ref.bytes != null) return MemoryImage(ref.bytes!);
    final uri = ref.uri;
    if (uri == null) return null;
    if (uri.startsWith('asset:')) return AssetImage(uri.substring(6));
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      return NetworkImage(uri);
    }
    return null;
  }
}

/// Makes the editor available to descendants (node bodies, overlays,
/// panels).
class NodeEditorScope extends InheritedWidget {
  /// Creates a scope.
  const NodeEditorScope({
    super.key,
    required this.controller,
    required this.theme,
    required this.services,
    required this.globalToCanvas,
    this.onNodeContextMenu,
    this.onEdgeContextMenu,
    required super.child,
  });

  /// Opens the context menu of node [id] at [globalPosition].
  final void Function(NodeId id, Offset globalPosition)? onNodeContextMenu;

  /// Opens the context menu of edge [id] at [globalPosition].
  final void Function(EdgeId id, Offset globalPosition)? onEdgeContextMenu;

  /// Controller.
  final NodeEditorController controller;

  /// Theme.
  final NodeEditorThemeData theme;

  /// Host services.
  final NodeEditorServices services;

  /// Converts a global (screen) position to canvas coordinates.
  final Offset Function(Offset global) globalToCanvas;

  /// The nearest scope.
  static NodeEditorScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<NodeEditorScope>();
    assert(scope != null, 'No NodeEditorScope found: use inside a NodeCanvas.');
    return scope!;
  }

  /// The nearest scope, or null.
  static NodeEditorScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NodeEditorScope>();

  @override
  bool updateShouldNotify(NodeEditorScope old) =>
      old.controller != controller ||
      old.theme != theme ||
      old.services != services;
}

/// Prevents node dragging from pointers that go down inside [child] (React
/// Flow's `nodrag` class). Wrap sliders, text fields and other interactive
/// widgets placed in node bodies.
class NoNodeDrag extends StatelessWidget {
  /// Creates the wrapper.
  const NoNodeDrag({super.key, required this.child});

  /// Wrapped widget.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final blocker = NodeDragBlocker.maybeOf(context);
    if (blocker == null) return child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => blocker.block(e.pointer),
      onPointerUp: (e) => blocker.release(e.pointer),
      onPointerCancel: (e) => blocker.release(e.pointer),
      child: child,
    );
  }
}

/// Pointer registry shared between a node frame and its [NoNodeDrag]
/// descendants.
class NodeDragBlocker extends InheritedWidget {
  /// Creates a blocker backed by [blocked] (owned by the node frame state).
  const NodeDragBlocker({
    super.key,
    required this.blocked,
    required super.child,
  });

  /// Pointers currently blocked.
  final Set<int> blocked;

  /// Blocks node dragging for [pointer].
  void block(int pointer) => blocked.add(pointer);

  /// Releases [pointer].
  void release(int pointer) => blocked.remove(pointer);

  /// Whether [pointer] is blocked.
  bool isBlocked(int pointer) => blocked.contains(pointer);

  /// The nearest blocker.
  static NodeDragBlocker? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NodeDragBlocker>();

  @override
  bool updateShouldNotify(NodeDragBlocker old) => false;
}
