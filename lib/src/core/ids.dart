import 'dart:math';

/// Unique identifier of a node inside a graph.
extension type const NodeId(String value) {}

/// Unique identifier of an edge inside a graph.
extension type const EdgeId(String value) {}

/// Generates short, collision resistant identifiers.
///
/// Ids are composed of a prefix, a base-36 time component, a per-process
/// counter and a random suffix, so ids created on different machines (and
/// then merged through copy / paste or file import) do not collide.
abstract final class IdGenerator {
  static final Random _random = Random();
  static int _counter = 0;

  /// Returns a new unique id string starting with [prefix].
  static String next([String prefix = '']) {
    _counter = (_counter + 1) % 1679616; // 36^4
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final count = _counter.toRadixString(36).padLeft(4, '0');
    final rand = _random.nextInt(1679616).toRadixString(36).padLeft(4, '0');
    return '$prefix${time.substring(time.length > 6 ? time.length - 6 : 0)}$count$rand';
  }

  /// Returns a new [NodeId].
  static NodeId node() => NodeId(next('n'));

  /// Returns a new [EdgeId].
  static EdgeId edge() => EdgeId(next('e'));
}
