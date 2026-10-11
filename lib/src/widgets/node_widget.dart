import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/controller.dart';
import '../core/node.dart';
import '../core/port_geometry.dart';
import '../core/ports.dart';
import '../render/node_layer.dart';
import 'node_render_context.dart';
import 'param_editors.dart';
import 'scope.dart';
import 'theme.dart';

/// The complete widget of one node: frame (selection, ports, resize) around
/// either the definition's custom body or [DefaultNodeBody].
class NodeWidget extends StatelessWidget {
  /// Creates the widget.
  const NodeWidget({super.key, required this.node, this.portBuilder});

  /// Node.
  final NodeInstance node;

  /// Custom port builder for every node (definition ports may still use
  /// their own style).
  final PortWidgetBuilder? portBuilder;

  @override
  Widget build(BuildContext context) {
    final scope = NodeEditorScope.of(context);
    final c = scope.controller;
    final selected = c.isNodeSelected(node.id);
    final builder = node.definition.builder;
    final body = builder != null
        ? builder(
            context,
            NodeRenderContext(
              controller: c,
              node: node,
              selected: selected,
              zoom: c.viewport.value.zoom,
            ),
          )
        : DefaultNodeBody(node: node);
    return NodeFrame(
      node: node,
      selected: selected,
      portBuilder: portBuilder,
      child: body,
    );
  }
}

class _NodePanRecognizer extends PanGestureRecognizer {
  _NodePanRecognizer(this.isBlocked) {
    dragStartBehavior = DragStartBehavior.down;
  }

  final bool Function(int pointer) isBlocked;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      !isBlocked(event.pointer) && super.isPointerAllowed(event);
}

/// Node chrome: body decoration, selection outline, drag / tap / resize
/// handling and port handles placed at their model anchors.
///
/// Laid out with the node size inflated by [kNodeHitMargin].
class NodeFrame extends StatefulWidget {
  /// Creates a frame.
  const NodeFrame({
    super.key,
    required this.node,
    required this.selected,
    required this.child,
    this.portBuilder,
  });

  /// Node.
  final NodeInstance node;

  /// Whether the node is selected.
  final bool selected;

  /// Body.
  final Widget child;

  /// Custom port builder.
  final PortWidgetBuilder? portBuilder;

  @override
  State<NodeFrame> createState() => _NodeFrameState();
}

class _NodeFrameState extends State<NodeFrame> {
  final Set<int> _blocked = {};
  Offset? _dragOrigin;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  Rect? _resizeStart;
  Offset? _resizeOrigin;

  NodeInstance get node => widget.node;

  bool get _multiKey {
    final k = HardwareKeyboard.instance;
    return k.isControlPressed || k.isMetaPressed || k.isShiftPressed;
  }

  void _onTapUp(NodeEditorScope scope, TapUpDetails d) {
    final c = scope.controller;
    final now = DateTime.now();
    final isDouble = now.difference(_lastTap) < kDoubleTapTimeout;
    _lastTap = isDouble ? DateTime.fromMillisecondsSinceEpoch(0) : now;
    if (_multiKey) {
      c.toggleNodeSelection(node.id);
    } else if (!c.isNodeSelected(node.id) ||
        c.selection.value.nodes.length > 1 ||
        c.selection.value.edges.isNotEmpty) {
      c.selectNodes([node.id]);
    }
    c.onNodeTap?.call(node);
    if (isDouble) {
      final handled = c.onNodeDoubleTap?.call(node) ?? false;
      if (!handled && c.config.doubleTapToEdit) {
        if (!c.enterSuperNode(node.id)) c.editNodeHandler?.call(node.id);
      }
    }
  }

  Widget _decorated(NodeEditorThemeData theme, Widget child) {
    final colors = resolveNodeColors(node, theme);
    final radius = BorderRadius.circular(colors.radius);
    final borderWidth = widget.selected
        ? theme.selectedBorderWidth
        : colors.borderWidth;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.body,
        borderRadius: radius,
        boxShadow: theme.nodeShadow,
      ),
      position: DecorationPosition.background,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: widget.selected ? theme.selectedBorderColor : colors.border,
            width: borderWidth,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
        child: ClipRRect(borderRadius: radius, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = NodeEditorScope.of(context);
    final c = scope.controller;
    final theme = scope.theme;
    final cfg = c.config;
    const m = kNodeHitMargin;
    final draggable = cfg.nodesDraggable && !node.locked;

    Widget body = _decorated(theme, widget.child);
    body = RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _NodePanRecognizer:
            GestureRecognizerFactoryWithHandlers<_NodePanRecognizer>(
              () => _NodePanRecognizer(_blocked.contains),
              (r) => r
                ..onStart = (d) {
                  if (!draggable) return;
                  c.bringToFront(node.id);
                  c.beginNodeDrag(node.id);
                  _dragOrigin = scope.globalToCanvas(d.globalPosition);
                }
                ..onUpdate = (d) {
                  final o = _dragOrigin;
                  if (o == null) return;
                  c.updateNodeDrag(scope.globalToCanvas(d.globalPosition) - o);
                }
                ..onEnd = (_) {
                  _endDrag(c);
                }
                ..onCancel = () {
                  _endDrag(c);
                },
            ),
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (r) => r
                ..onTapDown = (_) {
                  Focus.maybeOf(context)?.requestFocus();
                }
                ..onTapUp = (d) {
                  _onTapUp(scope, d);
                }
                ..onSecondaryTapUp = (d) {
                  if (!c.isNodeSelected(node.id)) c.selectNodes([node.id]);
                  scope.onNodeContextMenu?.call(node.id, d.globalPosition);
                },
            ),
      },
      child: MouseRegion(
        cursor: draggable ? SystemMouseCursors.move : MouseCursor.defer,
        child: NodeDragBlocker(blocked: _blocked, child: body),
      ),
    );

    final anchors = PortGeometry.relativeAnchors(node);
    final resizable =
        widget.selected &&
        cfg.nodesResizable &&
        node.definition.resizable &&
        !node.locked;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: m,
          top: m,
          width: node.size.width,
          height: node.size.height,
          child: body,
        ),
        if (node.locked)
          Positioned(
            right: m + 6,
            top: m + 6,
            child: IgnorePointer(
              child: Icon(Icons.lock, size: 12, color: theme.lockedColor),
            ),
          ),
        for (final p in node.ports)
          _positionedPort(context, scope, p, anchors[p.id]!),
        if (resizable)
          Positioned(
            right: m - 7,
            bottom: m - 7,
            width: 16,
            height: 16,
            child: _resizeHandle(scope),
          ),
      ],
    );
  }

  void _endDrag(NodeEditorController c) {
    if (_dragOrigin == null) return;
    _dragOrigin = null;
    c.endNodeDrag();
  }

  Widget _positionedPort(
    BuildContext context,
    NodeEditorScope scope,
    PortSpec p,
    Offset anchor,
  ) {
    final size = p.style?.size ?? scope.theme.portSize;
    final hit = math.max(size + 10, 22.0);
    return Positioned(
      left: kNodeHitMargin + anchor.dx - hit / 2,
      top: kNodeHitMargin + anchor.dy - hit / 2,
      width: hit,
      height: hit,
      child: PortHandle(
        node: node,
        port: p,
        size: size,
        builder: widget.portBuilder,
      ),
    );
  }

  Widget _resizeHandle(NodeEditorScope scope) {
    final c = scope.controller;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (d) {
          _resizeStart = node.rect;
          _resizeOrigin = scope.globalToCanvas(d.globalPosition);
          c.beginTransaction('Resize');
        },
        onPanUpdate: (d) {
          final start = _resizeStart, origin = _resizeOrigin;
          if (start == null || origin == null) return;
          final delta = scope.globalToCanvas(d.globalPosition) - origin;
          final settings = c.canvasSettings.value;
          final right = settings.snap(start.right + delta.dx);
          final bottom = settings.snap(start.bottom + delta.dy);
          c.setNodeRect(
            node.id,
            Rect.fromLTRB(start.left, start.top, right, bottom),
          );
        },
        onPanEnd: (_) {
          _resizeStart = null;
          c.commitTransaction();
        },
        onPanCancel: () {
          _resizeStart = null;
          c.commitTransaction();
        },
        child: CustomPaint(
          painter: _ResizeGripPainter(scope.theme.selectedBorderColor),
        ),
      ),
    );
  }
}

class _ResizeGripPainter extends CustomPainter {
  _ResizeGripPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i <= 3; i++) {
      final o = size.width * i / 4;
      canvas.drawLine(Offset(o, size.height - 2), Offset(size.width - 2, o), p);
    }
  }

  @override
  bool shouldRepaint(_ResizeGripPainter old) => old.color != color;
}

/// A port handle: draws the port and starts link drags.
class PortHandle extends StatelessWidget {
  /// Creates a handle.
  const PortHandle({
    super.key,
    required this.node,
    required this.port,
    required this.size,
    this.builder,
  });

  /// Node.
  final NodeInstance node;

  /// Port.
  final PortSpec port;

  /// Visual size.
  final double size;

  /// Custom visual.
  final PortWidgetBuilder? builder;

  @override
  Widget build(BuildContext context) {
    final scope = NodeEditorScope.of(context);
    final c = scope.controller;
    final ref = PortRef(node.id, port.id);
    final connectable = c.config.nodesConnectable;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: connectable
          ? (d) => c
              ..beginConnection(ref)
              ..updateConnection(scope.globalToCanvas(d.globalPosition))
          : null,
      onPanUpdate: connectable
          ? (d) => c.updateConnection(scope.globalToCanvas(d.globalPosition))
          : null,
      onPanEnd: connectable ? (_) => c.endConnection() : null,
      onPanCancel: connectable ? c.cancelConnection : null,
      child: MouseRegion(
        cursor: connectable ? SystemMouseCursors.precise : MouseCursor.defer,
        child: ValueListenableBuilder<ConnectionDraft?>(
          valueListenable: c.connectionDraft,
          builder: (context, draft, _) {
            var state = PortVisualState.idle;
            if (draft != null) {
              if (draft.from == ref) {
                state = PortVisualState.source;
              } else if (draft.hoverTarget == ref) {
                state = draft.hoverValid
                    ? PortVisualState.hoverValid
                    : PortVisualState.hoverInvalid;
              } else {
                state = c.validator.isCompatible(c.graph, draft.from, ref)
                    ? PortVisualState.compatible
                    : PortVisualState.incompatible;
              }
            }
            final ctx = PortRenderContext(
              node: node,
              port: port,
              state: state,
              connected: c.graph.linkCount(ref) > 0,
              size: size,
              theme: scope.theme,
            );
            Widget visual =
                builder?.call(context, ctx) ??
                CustomPaint(size: Size.square(size), painter: PortPainter(ctx));
            if (port.tooltip != null) {
              visual = Tooltip(
                message: port.tooltip!,
                waitDuration: const Duration(milliseconds: 500),
                child: visual,
              );
            }
            return Center(child: visual);
          },
        ),
      ),
    );
  }
}

/// Default port visual.
class PortPainter extends CustomPainter {
  /// Creates the painter.
  PortPainter(this.ctx);

  /// Port data.
  final PortRenderContext ctx;

  @override
  void paint(Canvas canvas, Size size) {
    final theme = ctx.theme;
    final style = ctx.port.style;
    final base = style?.color ?? ctx.port.type.color;
    var r = size.width / 2;
    var fill = ctx.connected ? base : theme.nodeColor;
    var border = ctx.connected
        ? (style?.borderColor ?? theme.portBorderColor)
        : base;
    var ring = Colors.transparent;
    var opacity = 1.0;
    switch (ctx.state) {
      case PortVisualState.idle:
        break;
      case PortVisualState.source:
        fill = base;
        ring = theme.connectionColor;
      case PortVisualState.compatible:
        ring = theme.validTargetColor;
      case PortVisualState.incompatible:
        opacity = 0.3;
      case PortVisualState.hoverValid:
        r *= 1.35;
        fill = theme.validTargetColor;
        border = theme.portBorderColor;
      case PortVisualState.hoverInvalid:
        r *= 1.35;
        fill = theme.invalidTargetColor;
        border = theme.portBorderColor;
    }
    final center = size.center(Offset.zero);
    if (ring != Colors.transparent) {
      canvas.drawCircle(
        center,
        r + 3.5,
        Paint()
          ..color = ring.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    final path = _shapePath(style?.shape ?? theme.portShape, center, r);
    canvas
      ..drawPath(
        path,
        Paint()..color = fill.withValues(alpha: fill.a * opacity),
      )
      ..drawPath(
        path,
        Paint()
          ..color = border.withValues(alpha: border.a * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = style?.borderWidth ?? 2,
      );
  }

  Path _shapePath(PortShape shape, Offset c, double r) {
    switch (shape) {
      case PortShape.circle:
        return Path()..addOval(Rect.fromCircle(center: c, radius: r));
      case PortShape.square:
        return Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCircle(center: c, radius: r * 0.9),
            Radius.circular(r * 0.25),
          ),
        );
      case PortShape.diamond:
        return Path()
          ..moveTo(c.dx, c.dy - r)
          ..lineTo(c.dx + r, c.dy)
          ..lineTo(c.dx, c.dy + r)
          ..lineTo(c.dx - r, c.dy)
          ..close();
      case PortShape.triangle:
        final n = ctx.port.effectiveSide.normal;
        final tip = c + n * r;
        final perp = Offset(-n.dy, n.dx) * r;
        final back = c - n * r;
        return Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo((back + perp).dx, (back + perp).dy)
          ..lineTo((back - perp).dx, (back - perp).dy)
          ..close();
      case PortShape.bar:
        final horizontal = ctx.port.effectiveSide.isHorizontal;
        return Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: c,
              width: horizontal ? r * 0.8 : r * 2.4,
              height: horizontal ? r * 2.4 : r * 0.8,
            ),
            Radius.circular(r * 0.4),
          ),
        );
    }
  }

  @override
  bool shouldRepaint(PortPainter old) =>
      old.ctx.state != ctx.state ||
      old.ctx.connected != ctx.connected ||
      old.ctx.port != ctx.port ||
      old.ctx.theme != ctx.theme;
}

/// Runtime status shown as a badge in node headers, read from
/// `node.runtime['status']` (or `node.data['status']`).
enum NodeRunStatus {
  /// Waiting / running.
  running,

  /// Finished successfully.
  success,

  /// Finished with a warning.
  warning,

  /// Failed.
  error,
}

/// The built-in node body: colored header with icon, title and status,
/// port labels aligned with the anchors, and either the description
/// ([NodeVariant.static]) or inline parameter editors
/// ([NodeVariant.dynamic]). Adapts to the node size.
class DefaultNodeBody extends StatelessWidget {
  /// Creates the body.
  const DefaultNodeBody({super.key, required this.node, this.content});

  /// Node.
  final NodeInstance node;

  /// Replaces the description / parameter area.
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final scope = NodeEditorScope.of(context);
    final theme = scope.theme;
    final def = node.definition;
    final layout = def.portLayout;
    final colors = resolveNodeColors(node, theme);
    final anchors = PortGeometry.relativeAnchors(node);
    final status = node.runtime['status'] ?? node.data['status'];
    final statusColor = switch (status) {
      'running' => const Color(0xFF2E90FA),
      'success' => const Color(0xFF12B76A),
      'warning' => const Color(0xFFF79009),
      'error' => const Color(0xFFF04438),
      _ => null,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final w = constraints.maxWidth;
        final headerH = math.min(layout.headerHeight, h);
        final header = SizedBox(
          height: headerH,
          child: ColoredBox(
            color: colors.header,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  if (def.icon != null && w > 90) ...[
                    Icon(def.icon, size: 16, color: colors.text),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      node.displayTitle,
                      style: theme.titleStyle.copyWith(color: colors.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (statusColor != null)
                    Tooltip(
                      message:
                          (node.runtime['statusText'] ??
                                  node.data['statusText'] ??
                                  status)
                              .toString(),
                      child: _StatusDot(
                        color: statusColor,
                        pulsing: status == 'running',
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        if (h <= headerH + 6) return header;

        var leftRows = 0, rightRows = 0;
        for (final p in node.ports) {
          if (p.alignment != null) continue;
          if (p.effectiveSide == PortSide.left) leftRows++;
          if (p.effectiveSide == PortSide.right) rightRows++;
        }
        final rowsH = math.max(leftRows, rightRows) * layout.rowHeight;
        final showLabels = w >= 110;
        final labelWidth = (w / 2) - 16;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if (showLabels)
                    for (final p in node.ports)
                      if (p.effectiveSide.isHorizontal &&
                          p.label.isNotEmpty &&
                          (p.style?.showLabel ?? true))
                        Positioned(
                          top: anchors[p.id]!.dy - headerH - 8,
                          left: p.effectiveSide == PortSide.left ? 12 : null,
                          right: p.effectiveSide == PortSide.right ? 12 : null,
                          height: 16,
                          width: labelWidth,
                          child: Text(
                            p.label,
                            style: theme.portLabelStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: p.effectiveSide == PortSide.left
                                ? TextAlign.left
                                : TextAlign.right,
                          ),
                        ),
                  Positioned(
                    left: 10,
                    right: 10,
                    top: rowsH + layout.padding,
                    bottom: 4,
                    child: content ?? _defaultContent(context, theme),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _defaultContent(BuildContext context, NodeEditorThemeData theme) {
    final def = node.definition;
    if (def.variant == NodeVariant.dynamic) {
      final specs = def.params.where((p) => p.showInNode).toList();
      if (specs.isEmpty) return const SizedBox.shrink();
      return SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final spec in specs)
              SizedBox(
                height: def.portLayout.paramRowHeight,
                child: InlineParamEditor(node: node, spec: spec),
              ),
          ],
        ),
      );
    }
    final text = node.data['text'] as String? ?? def.description;
    if (text == null) return const SizedBox.shrink();
    return Text(text, style: theme.bodyStyle, overflow: TextOverflow.fade);
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.pulsing});
  final Color color;
  final bool pulsing;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _anim.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_anim.isAnimating) {
      _anim.repeat(reverse: true);
    } else if (!widget.pulsing) {
      _anim.stop();
      _anim.value = 1;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.35, end: 1.0).animate(_anim),
    child: Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    ),
  );
}
