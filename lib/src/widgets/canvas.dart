import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/controller.dart';
import '../core/ids.dart';
import '../core/node.dart';
import '../core/viewport.dart';
import '../interaction/shortcuts.dart';
import '../render/edge_painter.dart';
import '../render/grid_painter.dart';
import '../render/lod_painter.dart';
import '../render/node_layer.dart';
import '../render/shaders.dart';
import 'edge_handles.dart';
import 'edit_dialogs.dart';
import 'menus.dart';
import 'node_render_context.dart';
import 'node_widget.dart';
import 'scope.dart';
import 'theme.dart';

/// Payload of palette drags dropped on a [NodeCanvas].
class NodeDragData {
  /// Creates drag data for node [type].
  const NodeDragData(this.type, {this.params});

  /// Node type to create.
  final String type;

  /// Initial parameter values.
  final Map<String, Object?>? params;
}

enum _GestureMode { none, pan, panZoom, marquee }

/// The interactive graph canvas.
///
/// Renders, back to front: grid (fragment shader), edges, animated edges,
/// low-detail nodes, node widgets, link / selection overlay, menus and
/// [overlays]. Handles pan / zoom (mouse, trackpad, touch), selection,
/// drag & drop from a palette and keyboard shortcuts.
class NodeCanvas extends StatefulWidget {
  /// Creates a canvas.
  const NodeCanvas({
    super.key,
    required this.controller,
    this.theme,
    this.services = const NodeEditorServices(),
    this.nodeBuilder,
    this.portBuilder,
    this.shortcuts,
    this.overlays = const [],
    this.nodeMenuActions = const [],
    this.edgeMenuActions = const [],
    this.autofocus = true,
    this.useShaders = true,
    this.onEditNode,
    this.onEditEdge,
  });

  /// Controller.
  final NodeEditorController controller;

  /// Theme (defaults to [NodeEditorThemeData.of]).
  final NodeEditorThemeData? theme;

  /// Host services (pickers, triggers).
  final NodeEditorServices services;

  /// Replaces the widget of every node (definitions can also provide their
  /// own `builder`).
  final NodeSlotBuilder? nodeBuilder;

  /// Replaces the port visual of every node.
  final PortWidgetBuilder? portBuilder;

  /// Key bindings (defaults to [NodeEditorShortcuts.defaults]).
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Widgets stacked over the canvas in screen space (minimap, toolbar...).
  final List<Widget> overlays;

  /// Extra actions of the node overlay / context menu.
  final List<NodeMenuAction> nodeMenuActions;

  /// Extra actions of the edge overlay / context menu.
  final List<EdgeMenuAction> edgeMenuActions;

  /// Whether the canvas grabs keyboard focus on mount.
  final bool autofocus;

  /// Whether fragment shaders are used when available.
  final bool useShaders;

  /// Replaces the built-in node edit dialog.
  final void Function(BuildContext context, NodeId id)? onEditNode;

  /// Replaces the built-in edge edit dialog.
  final void Function(BuildContext context, EdgeId id)? onEditEdge;

  @override
  State<NodeCanvas> createState() => _NodeCanvasState();
}

class _NodeCanvasState extends State<NodeCanvas> with TickerProviderStateMixin {
  final GlobalKey _stackKey = GlobalKey();
  final FocusNode _focus = FocusNode(debugLabel: 'NodeCanvas');
  final EdgeRenderCache _edgeCache = EdgeRenderCache();
  final LodRenderCache _lodCache = LodRenderCache();
  final ValueNotifier<double> _flowTime = ValueNotifier(0);
  late final Ticker _flowTicker = createTicker(_onFlowTick);
  late final AnimationController _viewAnim = AnimationController(vsync: this)
    ..addListener(_onViewAnim);
  EditorViewport? _animFrom;
  EditorViewport? _animTo;

  _GestureMode _mode = _GestureMode.none;
  double _startZoom = 1;
  int _lastButtons = kPrimaryButton;
  PointerDeviceKind _lastKind = PointerDeviceKind.mouse;
  DateTime _lastBackgroundTap = DateTime.fromMillisecondsSinceEpoch(0);

  NodeEditorController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    EditorShaders.enabled = widget.useShaders;
    unawaited(EditorShaders.ensureLoaded());
    _attach(_c);
  }

  @override
  void didUpdateWidget(NodeCanvas old) {
    super.didUpdateWidget(old);
    EditorShaders.enabled = widget.useShaders;
    if (old.controller != widget.controller) {
      _detach(old.controller);
      _edgeCache.clear();
      _lodCache.clear();
      _attach(widget.controller);
    }
  }

  void _attach(NodeEditorController c) {
    c.viewportAnimator = _animateViewport;
    c.editNodeHandler = (id) => widget.onEditNode != null
        ? widget.onEditNode!(context, id)
        : showNodeEditDialog(
            context,
            c,
            id,
            services: widget.services,
            theme: _theme,
          );
    c.editEdgeHandler = (id) => widget.onEditEdge != null
        ? widget.onEditEdge!(context, id)
        : showEdgeEditDialog(context, c, id, theme: _theme);
    c.edgesListenable.addListener(_syncTicker);
    c.viewport.addListener(_syncTicker);
    c.scopeListenable.addListener(_onScope);
    _syncTicker();
  }

  void _detach(NodeEditorController c) {
    if (c.viewportAnimator == _animateViewport) c.viewportAnimator = null;
    c.editNodeHandler = null;
    c.editEdgeHandler = null;
    c.edgesListenable.removeListener(_syncTicker);
    c.viewport.removeListener(_syncTicker);
    c.scopeListenable.removeListener(_onScope);
  }

  @override
  void dispose() {
    _detach(_c);
    _flowTicker.dispose();
    _viewAnim.dispose();
    _focus.dispose();
    _flowTime.dispose();
    _edgeCache.clear();
    _lodCache.clear();
    super.dispose();
  }

  void _onScope() {
    _edgeCache.clear();
    _lodCache.clear();
    _syncTicker();
  }

  NodeEditorThemeData get _theme =>
      widget.theme ?? NodeEditorThemeData.of(context);

  // ---------------------------------------------------------------------
  // Animation
  // ---------------------------------------------------------------------

  void _onFlowTick(Duration elapsed) =>
      _flowTime.value = elapsed.inMicroseconds / 1e6;

  void _syncTicker() {
    final need =
        _c.animatedEdgeCount > 0 &&
        _c.viewport.value.zoom >= _c.config.lodThreshold;
    if (need && !_flowTicker.isActive) {
      _flowTicker.start();
    } else if (!need && _flowTicker.isActive) {
      _flowTicker.stop();
    }
  }

  void _animateViewport(EditorViewport target, Duration duration) {
    _animFrom = _c.viewport.value;
    _animTo = target;
    _viewAnim
      ..duration = duration
      ..forward(from: 0);
  }

  void _onViewAnim() {
    final from = _animFrom, to = _animTo;
    if (from == null || to == null) return;
    final t = Curves.easeOutCubic.transform(_viewAnim.value);
    final center = _c.viewportSize.center(Offset.zero);
    final c0 = from.toCanvas(center), c1 = to.toCanvas(center);
    final zoom = from.zoom * math.pow(to.zoom / from.zoom, t);
    final c = Offset.lerp(c0, c1, t)!;
    _c.viewport.value = EditorViewport(offset: center - c * zoom, zoom: zoom);
  }

  // ---------------------------------------------------------------------
  // Coordinates
  // ---------------------------------------------------------------------

  RenderBox? get _box =>
      _stackKey.currentContext?.findRenderObject() as RenderBox?;

  Offset _globalToLocal(Offset global) => _box?.globalToLocal(global) ?? global;

  Offset _globalToCanvas(Offset global) =>
      _c.viewport.value.toCanvas(_globalToLocal(global));

  // ---------------------------------------------------------------------
  // Background gestures
  // ---------------------------------------------------------------------

  bool get _multiKey {
    final k = HardwareKeyboard.instance;
    return k.isControlPressed || k.isMetaPressed || k.isShiftPressed;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _viewAnim.stop();
    final keys = HardwareKeyboard.instance;
    final space = keys.isLogicalKeyPressed(LogicalKeyboardKey.space);
    final trackpad =
        d.kind == PointerDeviceKind.trackpad ||
        _lastKind == PointerDeviceKind.trackpad;
    if (d.pointerCount >= 2 || trackpad) {
      _mode = _GestureMode.panZoom;
    } else if (_lastButtons & kMiddleMouseButton != 0 || space) {
      _mode = _GestureMode.pan;
    } else {
      final selectFirst = _c.config.panOnDrag == PanOnDrag.select;
      final shift = keys.isShiftPressed;
      _mode = (selectFirst != shift) ? _GestureMode.marquee : _GestureMode.pan;
    }
    _startZoom = _c.viewport.value.zoom;
    if (_mode == _GestureMode.marquee) {
      _c.beginMarquee(
        _c.viewport.value.toCanvas(d.localFocalPoint),
        additive: keys.isControlPressed || keys.isMetaPressed,
      );
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    switch (_mode) {
      case _GestureMode.pan:
        _c.panBy(d.focalPointDelta);
      case _GestureMode.panZoom:
        _c.panBy(d.focalPointDelta);
        if (_c.config.zoomOnPinch && d.scale != 1) {
          final z = (_startZoom * d.scale).clamp(
            _c.config.minZoom,
            _c.config.maxZoom,
          );
          _c.setViewport(_c.viewport.value.zoomAround(d.localFocalPoint, z));
        }
      case _GestureMode.marquee:
        _c.updateMarquee(_c.viewport.value.toCanvas(d.localFocalPoint));
      case _GestureMode.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_mode == _GestureMode.marquee) _c.endMarquee();
    _mode = _GestureMode.none;
  }

  void _onTapUp(TapUpDetails d) {
    final canvasPos = _c.viewport.value.toCanvas(d.localPosition);
    final now = DateTime.now();
    final isDouble = now.difference(_lastBackgroundTap) < kDoubleTapTimeout;
    _lastBackgroundTap = isDouble
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : now;
    final edge = _c.config.edgesSelectable ? _c.edgeAt(canvasPos) : null;
    if (edge != null) {
      if (_multiKey) {
        _c.selectEdges([edge.id], additive: true);
      } else {
        _c.selectEdges([edge.id]);
      }
      if (_c.config.showEdgeMenu) _c.menuEdge.value = (edge.id, canvasPos);
      _c.onEdgeTap?.call(edge);
      if (isDouble) _c.editEdgeHandler?.call(edge.id);
      return;
    }
    if (!_multiKey) _c.clearSelection();
    _c.onCanvasTap?.call(canvasPos);
  }

  void _onSecondaryTapUp(TapUpDetails d) {
    final canvasPos = _c.viewport.value.toCanvas(d.localPosition);
    final edge = _c.config.edgesSelectable ? _c.edgeAt(canvasPos) : null;
    if (edge != null) {
      _c.selectEdges([edge.id]);
      _showEdgeContextMenu(edge.id, d.globalPosition);
      return;
    }
    _c.onCanvasContextMenu?.call(canvasPos, d.globalPosition);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (e) {
        final ev = e as PointerScrollEvent;
        _viewAnim.stop();
        final keys = HardwareKeyboard.instance;
        final zoomKey = keys.isControlPressed || keys.isMetaPressed;
        if ((_c.config.zoomOnScroll && !keys.isShiftPressed) || zoomKey) {
          final factor = math.pow(2, -ev.scrollDelta.dy / 300).toDouble();
          _c.zoomBy(factor, focal: ev.localPosition);
        } else {
          _c.panBy(
            keys.isShiftPressed
                ? Offset(-ev.scrollDelta.dy, -ev.scrollDelta.dx)
                : -ev.scrollDelta,
          );
        }
      });
    } else if (event is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (e) {
        _c.zoomBy((e as PointerScaleEvent).scale, focal: e.localPosition);
      });
    }
  }

  // ---------------------------------------------------------------------
  // Drag & drop, menus
  // ---------------------------------------------------------------------

  void _onDrop(DragTargetDetails<NodeDragData> d) {
    final def = _c.registry[d.data.type];
    if (def == null) return;
    final pos = _globalToCanvas(d.offset);
    _c.addNode(d.data.type, position: pos, params: d.data.params);
    _focus.requestFocus();
  }

  void _showNodeContextMenu(NodeId id, Offset global) {
    showNodeContextMenu(
      context,
      _c,
      id,
      global,
      extraActions: widget.nodeMenuActions,
    );
  }

  void _showEdgeContextMenu(EdgeId id, Offset global) {
    showEdgeContextMenu(
      context,
      _c,
      id,
      global,
      extraActions: widget.edgeMenuActions,
    );
  }

  Map<Type, Action<Intent>> get _actions => {
    DeleteSelectionIntent: CallbackAction<DeleteSelectionIntent>(
      onInvoke: (_) => _c.deleteSelection(),
    ),
    CopySelectionIntent: CallbackAction<CopySelectionIntent>(
      onInvoke: (_) => _c.copySelection(),
    ),
    CutSelectionIntent: CallbackAction<CutSelectionIntent>(
      onInvoke: (_) => _c.cutSelection(),
    ),
    PasteIntent: CallbackAction<PasteIntent>(onInvoke: (_) => _c.paste()),
    DuplicateSelectionIntent: CallbackAction<DuplicateSelectionIntent>(
      onInvoke: (_) => _c.duplicateSelection(),
    ),
    UndoIntent: CallbackAction<UndoIntent>(onInvoke: (_) => _c.undo()),
    RedoIntent: CallbackAction<RedoIntent>(onInvoke: (_) => _c.redo()),
    SelectAllIntent: CallbackAction<SelectAllIntent>(
      onInvoke: (_) => _c.selectAll(),
    ),
    CancelIntent: CallbackAction<CancelIntent>(
      onInvoke: (_) {
        if (_c.connectionDraft.value != null) {
          _c.cancelConnection();
        } else if (_c.marquee.value != null) {
          _c.endMarquee();
        } else {
          _c.clearSelection();
        }
        return null;
      },
    ),
    GroupSelectionIntent: CallbackAction<GroupSelectionIntent>(
      onInvoke: (_) => _c.groupSelection(),
    ),
    UngroupSelectionIntent: CallbackAction<UngroupSelectionIntent>(
      onInvoke: (_) => _c.ungroupSelection(),
    ),
    ToggleLockIntent: CallbackAction<ToggleLockIntent>(
      onInvoke: (_) => _c.toggleLockSelection(),
    ),
    NudgeSelectionIntent: CallbackAction<NudgeSelectionIntent>(
      onInvoke: (i) {
        final step = i.large ? _c.config.nudgeStepLarge : _c.config.nudgeStep;
        _c.nudgeSelection(Offset(i.dx * step, i.dy * step));
        return null;
      },
    ),
    FitViewIntent: CallbackAction<FitViewIntent>(onInvoke: (_) => _c.fitView()),
    ZoomInIntent: CallbackAction<ZoomInIntent>(onInvoke: (_) => _c.zoomIn()),
    ZoomOutIntent: CallbackAction<ZoomOutIntent>(onInvoke: (_) => _c.zoomOut()),
    ExitScopeIntent: CallbackAction<ExitScopeIntent>(
      onInvoke: (_) => _c.exitSuperNode(),
    ),
  };

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  Widget _buildNode(BuildContext context, NodeInstance node) =>
      widget.nodeBuilder?.call(context, node) ??
      NodeWidget(node: node, portBuilder: widget.portBuilder);

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (_c.viewportSize != size) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _c.viewportSize = size;
          });
        }
        return NodeEditorScope(
          controller: _c,
          theme: theme,
          services: widget.services,
          globalToCanvas: _globalToCanvas,
          onNodeContextMenu: _showNodeContextMenu,
          onEdgeContextMenu: _showEdgeContextMenu,
          child: Shortcuts(
            shortcuts: widget.shortcuts ?? NodeEditorShortcuts.defaults,
            child: Actions(
              actions: _actions,
              child: Focus(
                focusNode: _focus,
                autofocus: widget.autofocus,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    _lastButtons = e.buttons;
                    _lastKind = e.kind;
                    if (!_focus.hasFocus) _focus.requestFocus();
                  },
                  onPointerPanZoomStart: (e) =>
                      _lastKind = PointerDeviceKind.trackpad,
                  onPointerSignal: _onPointerSignal,
                  child: DragTarget<NodeDragData>(
                    onWillAcceptWithDetails: (d) =>
                        _c.registry.contains(d.data.type),
                    onAcceptWithDetails: _onDrop,
                    builder: (context, _, _) => RawGestureDetector(
                      behavior: HitTestBehavior.opaque,
                      gestures: {
                        ScaleGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              ScaleGestureRecognizer
                            >(
                              () => ScaleGestureRecognizer(
                                allowedButtonsFilter: (b) =>
                                    b & (kPrimaryButton | kMiddleMouseButton) !=
                                    0,
                              ),
                              (r) => r
                                ..onStart = _onScaleStart
                                ..onUpdate = _onScaleUpdate
                                ..onEnd = _onScaleEnd,
                            ),
                        TapGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              TapGestureRecognizer
                            >(
                              TapGestureRecognizer.new,
                              (r) => r
                                ..onTapUp = _onTapUp
                                ..onSecondaryTapUp = _onSecondaryTapUp,
                            ),
                      },
                      child: ClipRect(
                        child: Material(
                          type: MaterialType.transparency,
                          child: Stack(
                            key: _stackKey,
                            fit: StackFit.expand,
                            children: [
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: GridPainter(
                                    viewport: _c.viewport,
                                    settings: _c.canvasSettings,
                                    theme: theme,
                                  ),
                                ),
                              ),
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: EdgePainter(
                                    controller: _c,
                                    theme: theme,
                                    cache: _edgeCache,
                                  ),
                                ),
                              ),
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: AnimatedEdgePainter(
                                    controller: _c,
                                    theme: theme,
                                    cache: _edgeCache,
                                    time: _flowTime,
                                  ),
                                ),
                              ),
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: LodNodePainter(
                                    controller: _c,
                                    theme: theme,
                                    cache: _lodCache,
                                  ),
                                ),
                              ),
                              NodeLayer(
                                controller: _c,
                                nodeBuilder: _buildNode,
                              ),
                              IgnorePointer(
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    painter: InteractionPainter(
                                      controller: _c,
                                      theme: theme,
                                    ),
                                  ),
                                ),
                              ),
                              EdgeWaypointOverlay(controller: _c),
                              NodeMenuOverlay(
                                controller: _c,
                                extraActions: widget.nodeMenuActions,
                              ),
                              EdgeMenuOverlay(
                                controller: _c,
                                extraActions: widget.edgeMenuActions,
                              ),
                              ...widget.overlays,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
