import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../core/controller.dart';
import '../core/ids.dart';
import '../core/node.dart';
import '../core/viewport.dart';

/// Extra space (canvas units) laid out around each node widget so that port
/// handles drawn half outside the node body stay hit-testable.
const double kNodeHitMargin = 16;

/// Builds the widget of one node. The widget receives tight constraints of
/// `node.size` inflated by [kNodeHitMargin] on every side.
typedef NodeSlotBuilder = Widget Function(
  BuildContext context,
  NodeInstance node,
);

/// Displays node widgets for the nodes inside the viewport.
///
/// * Only nodes overlapping the viewport (plus a margin) are built; the set
///   is recomputed through the spatial index when the viewport crosses a
///   cell boundary, nodes are added / removed, or nodes move.
/// * Pan and zoom only update the transform of a persistent
///   [TransformLayer] (`markNeedsCompositedLayerUpdate`): no rebuild, no
///   relayout and no repaint of node widgets.
/// * Moving a node only updates its parent data; its content widget is not
///   rebuilt.
/// * Below `NodeEditorConfig.lodThreshold` no widget is built at all.
class NodeLayer extends StatefulWidget {
  /// Creates the layer.
  const NodeLayer({
    super.key,
    required this.controller,
    required this.nodeBuilder,
  });

  /// Controller.
  final NodeEditorController controller;

  /// Builds one node.
  final NodeSlotBuilder nodeBuilder;

  @override
  State<NodeLayer> createState() => _NodeLayerState();
}

class _NodeLayerState extends State<NodeLayer> {
  List<NodeId> _visible = const [];
  final Map<NodeId, Widget> _slots = {};
  Rect? _queryRect;
  bool _lod = false;

  NodeEditorController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _subscribe(_c);
    _recompute(force: true);
  }

  @override
  void didUpdateWidget(NodeLayer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _unsubscribe(old.controller);
      _subscribe(widget.controller);
      _slots.clear();
      _recompute(force: true);
    } else if (old.nodeBuilder != widget.nodeBuilder) {
      _slots.clear();
    }
  }

  @override
  void dispose() {
    _unsubscribe(_c);
    super.dispose();
  }

  void _subscribe(NodeEditorController c) {
    c.viewport.addListener(_onViewport);
    c.viewportSizeListenable.addListener(_onModel);
    c.structure.addListener(_onModel);
    c.geometry.addListener(_onModel);
    c.scopeListenable.addListener(_onScope);
  }

  void _unsubscribe(NodeEditorController c) {
    c.viewport.removeListener(_onViewport);
    c.viewportSizeListenable.removeListener(_onModel);
    c.structure.removeListener(_onModel);
    c.geometry.removeListener(_onModel);
    c.scopeListenable.removeListener(_onScope);
  }

  void _onViewport() => _recompute();
  void _onModel() => _recompute(force: true);
  void _onScope() {
    _slots.clear();
    _recompute(force: true);
  }

  static const double _cell = 256;

  void _recompute({bool force = false}) {
    final v = _c.viewport.value;
    final lod = v.zoom < _c.config.lodThreshold;
    if (lod) {
      if (!_lod || _visible.isNotEmpty) {
        _lod = true;
        _queryRect = null;
        _set(const []);
      }
      return;
    }
    _lod = false;
    final size = _c.viewportSize;
    var r = v.visibleRect(size);
    r = r.inflate(r.longestSide * _c.config.cullingMargin);
    // Snap the query rect to cell boundaries so small pans do not requery.
    double down(double x) => (x / _cell).floorToDouble() * _cell;
    double up(double x) => (x / _cell).ceilToDouble() * _cell;
    final q = Rect.fromLTRB(
      down(r.left),
      down(r.top),
      up(r.right),
      up(r.bottom),
    );
    if (!force && q == _queryRect) return;
    _queryRect = q;
    final graph = _c.graph;
    final ids = _c.nodeIndex.query(q)
      ..sort((a, b) => graph.indexOfNode(a).compareTo(graph.indexOfNode(b)));
    _set(ids);
  }

  void _set(List<NodeId> ids) {
    if (listEquals(ids, _visible)) return;
    final keep = ids.toSet();
    _slots.removeWhere((id, _) => !keep.contains(id));
    if (mounted) {
      setState(() => _visible = ids);
    } else {
      _visible = ids;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _NodeLayout(
      viewport: _c.viewport,
      children: [
        for (final id in _visible)
          _slots[id] ??= _NodeSlot(
            key: ValueKey(id),
            controller: _c,
            id: id,
            builder: widget.nodeBuilder,
          ),
      ],
    );
  }
}

class _NodeSlot extends StatelessWidget {
  const _NodeSlot({
    super.key,
    required this.controller,
    required this.id,
    required this.builder,
  });

  final NodeEditorController controller;
  final NodeId id;
  final NodeSlotBuilder builder;

  @override
  Widget build(BuildContext context) {
    final content = RepaintBoundary(
      child: ListenableBuilder(
        listenable: controller.nodeListenable(id),
        builder: (context, _) {
          final node = controller.graph.node(id);
          if (node == null) return const SizedBox.shrink();
          return builder(context, node);
        },
      ),
    );
    return ListenableBuilder(
      listenable: controller.nodePositionListenable(id),
      child: content,
      builder: (context, child) {
        final node = controller.graph.node(id);
        return _NodePositioned(
          rect: node == null ? Rect.zero : node.rect.inflate(kNodeHitMargin),
          child: child!,
        );
      },
    );
  }
}

class _NodeParentData extends ContainerBoxParentData<RenderBox> {
  Rect rect = Rect.zero;
}

class _NodePositioned extends ParentDataWidget<_NodeParentData> {
  const _NodePositioned({required this.rect, required super.child});

  final Rect rect;

  @override
  void applyParentData(RenderObject renderObject) {
    final pd = renderObject.parentData! as _NodeParentData;
    if (pd.rect == rect) return;
    final resized = pd.rect.size != rect.size;
    pd
      ..rect = rect
      ..offset = rect.topLeft;
    final parent = renderObject.parent;
    if (parent is RenderObject) {
      resized ? parent.markNeedsLayout() : parent.markNeedsPaint();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _NodeLayout;
}

class _NodeLayout extends MultiChildRenderObjectWidget {
  const _NodeLayout({required this.viewport, super.children});

  final ValueListenable<EditorViewport> viewport;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNodeLayout(viewport);

  @override
  void updateRenderObject(BuildContext context, _RenderNodeLayout ro) {
    ro.viewport = viewport;
  }
}

class _RenderNodeLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _NodeParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _NodeParentData> {
  _RenderNodeLayout(this._viewport);

  ValueListenable<EditorViewport> _viewport;
  set viewport(ValueListenable<EditorViewport> value) {
    if (value == _viewport) return;
    if (attached) _viewport.removeListener(_onViewport);
    _viewport = value;
    if (attached) _viewport.addListener(_onViewport);
    markNeedsCompositedLayerUpdate();
  }

  void _onViewport() => markNeedsCompositedLayerUpdate();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _viewport.addListener(_onViewport);
  }

  @override
  void detach() {
    _viewport.removeListener(_onViewport);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _NodeParentData) {
      child.parentData = _NodeParentData();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    var child = firstChild;
    while (child != null) {
      final pd = child.parentData! as _NodeParentData;
      child.layout(BoxConstraints.tight(pd.rect.size));
      child = pd.nextSibling;
    }
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant TransformLayer? oldLayer,
  }) {
    final layer = oldLayer ?? TransformLayer();
    layer.transform = _viewport.value.matrix;
    return layer;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final pd = child.parentData! as _NodeParentData;
      context.paintChild(child, offset + pd.offset);
      child = pd.nextSibling;
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final pd = child.parentData! as _NodeParentData;
    transform
      ..multiply(_viewport.value.matrix)
      ..translateByDouble(pd.offset.dx, pd.offset.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintTransform(
      transform: _viewport.value.matrix,
      position: position,
      hitTest: (result, local) =>
          defaultHitTestChildren(result, position: local),
    );
  }

  @override
  bool hitTestSelf(Offset position) => false;
}
