import 'graph.dart';
import 'ports.dart';

/// Why a connection was rejected.
enum ConnectionError {
  /// One of the ports does not exist.
  missingPort,

  /// Both ports have the same direction.
  sameDirection,

  /// Both ports belong to the same node and self links are disabled.
  selfLink,

  /// The target type does not accept the source type.
  incompatibleTypes,

  /// The source port reached its `maxLinks`.
  sourceFull,

  /// The target port reached its `maxLinks`.
  targetFull,

  /// An identical edge already exists.
  duplicate,

  /// The edge would create a cycle and cycles are disabled.
  cycle,

  /// Rejected by the custom validator.
  rejected,
}

/// A candidate connection, normalized so that [source] is the output.
class ConnectionRequest {
  /// Creates a request.
  const ConnectionRequest({
    required this.graph,
    required this.source,
    required this.target,
    required this.sourcePort,
    required this.targetPort,
  });

  /// The graph the edge would be added to.
  final Graph graph;

  /// Output port reference.
  final PortRef source;

  /// Input port reference.
  final PortRef target;

  /// Output port spec.
  final PortSpec sourcePort;

  /// Input port spec.
  final PortSpec targetPort;
}

/// Result of a validation.
class ConnectionResult {
  const ConnectionResult._(this.error, this.request);

  /// The error, null when valid.
  final ConnectionError? error;

  /// The normalized request (null when a port is missing).
  final ConnectionRequest? request;

  /// Whether the connection is allowed.
  bool get isValid => error == null;
}

/// Decides whether two ports may be linked.
///
/// The built-in rules check direction, [PortType.accepts], `maxLinks` on both
/// ends, duplicates, self links and (optionally) cycles. Add domain rules with
/// [custom]; it runs last and can only reject.
class ConnectionValidator {
  /// Creates a validator.
  const ConnectionValidator({
    this.allowSelfLinks = false,
    this.allowCycles = true,
    this.replaceWhenFull = true,
    this.custom,
  });

  /// Whether a node may link to itself.
  final bool allowSelfLinks;

  /// Whether cycles are allowed (disable for pure dataflow / DAG engines).
  final bool allowCycles;

  /// When an input with `maxLinks == 1` is already linked, connecting to it
  /// replaces the existing edge instead of failing.
  final bool replaceWhenFull;

  /// Extra rule; return false to reject.
  final bool Function(ConnectionRequest request)? custom;

  /// Validates a link between port [a] and port [b] in either order.
  ConnectionResult validate(Graph graph, PortRef a, PortRef b) {
    final pa = graph.port(a), pb = graph.port(b);
    if (pa == null || pb == null) {
      return const ConnectionResult._(ConnectionError.missingPort, null);
    }
    if (pa.direction == pb.direction) {
      return const ConnectionResult._(ConnectionError.sameDirection, null);
    }
    final (src, srcPort, dst, dstPort) = pa.isOutput
        ? (a, pa, b, pb)
        : (b, pb, a, pa);
    final request = ConnectionRequest(
      graph: graph,
      source: src,
      target: dst,
      sourcePort: srcPort,
      targetPort: dstPort,
    );
    ConnectionResult fail(ConnectionError e) => ConnectionResult._(e, request);

    if (!allowSelfLinks && src.node == dst.node) {
      return fail(ConnectionError.selfLink);
    }
    if (!dstPort.type.accepts(srcPort.type)) {
      return fail(ConnectionError.incompatibleTypes);
    }
    for (final e in graph.edgesOfPort(src)) {
      if (e.target == dst) return fail(ConnectionError.duplicate);
    }
    if (srcPort.maxLinks >= 0 && graph.linkCount(src) >= srcPort.maxLinks) {
      return fail(ConnectionError.sourceFull);
    }
    if (dstPort.maxLinks >= 0 &&
        graph.linkCount(dst) >= dstPort.maxLinks &&
        !(replaceWhenFull && dstPort.maxLinks == 1)) {
      return fail(ConnectionError.targetFull);
    }
    if (!allowCycles && graph.hasPath(dst.node, src.node)) {
      return fail(ConnectionError.cycle);
    }
    if (custom != null && !custom!(request)) {
      return fail(ConnectionError.rejected);
    }
    return ConnectionResult._(null, request);
  }

  /// Cheap pre-check used to highlight ports while dragging a link from
  /// [from]: direction, self link and type compatibility only.
  bool isCompatible(Graph graph, PortRef from, PortRef to) {
    final pa = graph.port(from), pb = graph.port(to);
    if (pa == null || pb == null || pa.direction == pb.direction) return false;
    if (!allowSelfLinks && from.node == to.node) return false;
    return pa.isOutput ? pb.type.accepts(pa.type) : pa.type.accepts(pb.type);
  }
}
