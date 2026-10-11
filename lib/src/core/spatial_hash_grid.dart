import 'dart:ui';

/// A uniform-grid spatial hash for rectangles.
///
/// Insert, move and remove are O(cells covered by the rect), which is O(1)
/// for node sized rects. [query] visits only the cells under the query rect
/// (or every item when that is cheaper), making viewport culling, marquee
/// selection and hit testing independent of the total graph size.
///
/// Cell keys are packed into a single number with arithmetic only (no bit
/// shifts) so the same code is correct on the web, where bitwise operators
/// truncate to 32 bits.
class SpatialHashGrid<K> {
  /// Creates a grid with square cells of [cellSize] canvas units.
  SpatialHashGrid({this.cellSize = 256});

  /// Cell edge length.
  final double cellSize;

  static const int _bias = 1 << 20;
  static const int _span = 1 << 21;

  final Map<int, Set<K>> _cells = {};
  final Map<K, Rect> _bounds = {};
  final Map<K, _CellRange> _ranges = {};

  /// Number of indexed items.
  int get length => _bounds.length;

  /// Whether nothing is indexed.
  bool get isEmpty => _bounds.isEmpty;

  /// The indexed bounds of [key].
  Rect? boundsOf(K key) => _bounds[key];

  /// All indexed keys.
  Iterable<K> get keys => _bounds.keys;

  /// Union of all indexed rects (null when empty).
  Rect? get totalBounds {
    Rect? r;
    for (final b in _bounds.values) {
      r = r == null ? b : r.expandToInclude(b);
    }
    return r;
  }

  int _cell(double v) => (v / cellSize).floor();

  static int _key(int cx, int cy) => (cx + _bias) * _span + (cy + _bias);

  _CellRange _rangeOf(Rect r) =>
      _CellRange(_cell(r.left), _cell(r.top), _cell(r.right), _cell(r.bottom));

  /// Inserts or moves [key] to [rect].
  void insert(K key, Rect rect) {
    final range = _rangeOf(rect);
    final old = _ranges[key];
    _bounds[key] = rect;
    if (old != null) {
      if (old == range) return;
      _removeFromCells(key, old);
    }
    _ranges[key] = range;
    for (var x = range.x0; x <= range.x1; x++) {
      for (var y = range.y0; y <= range.y1; y++) {
        (_cells[_key(x, y)] ??= <K>{}).add(key);
      }
    }
  }

  /// Removes [key].
  void remove(K key) {
    final range = _ranges.remove(key);
    _bounds.remove(key);
    if (range != null) _removeFromCells(key, range);
  }

  void _removeFromCells(K key, _CellRange r) {
    for (var x = r.x0; x <= r.x1; x++) {
      for (var y = r.y0; y <= r.y1; y++) {
        final k = _key(x, y);
        final set = _cells[k];
        if (set == null) continue;
        set.remove(key);
        if (set.isEmpty) _cells.remove(k);
      }
    }
  }

  /// Removes everything.
  void clear() {
    _cells.clear();
    _bounds.clear();
    _ranges.clear();
  }

  /// Keys whose rect overlaps [area].
  List<K> query(Rect area) {
    final result = <K>[];
    final r = _rangeOf(area);
    final cellCount = (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1);
    if (cellCount > _bounds.length) {
      for (final e in _bounds.entries) {
        if (e.value.overlaps(area)) result.add(e.key);
      }
      return result;
    }
    final seen = <K>{};
    for (var x = r.x0; x <= r.x1; x++) {
      for (var y = r.y0; y <= r.y1; y++) {
        final set = _cells[_key(x, y)];
        if (set == null) continue;
        for (final k in set) {
          if (seen.add(k) && _bounds[k]!.overlaps(area)) result.add(k);
        }
      }
    }
    return result;
  }

  /// Keys whose rect contains [point].
  List<K> queryPoint(Offset point) {
    final set = _cells[_key(_cell(point.dx), _cell(point.dy))];
    if (set == null) return const [];
    return [
      for (final k in set)
        if (_bounds[k]!.contains(point)) k,
    ];
  }
}

class _CellRange {
  const _CellRange(this.x0, this.y0, this.x1, this.y1);
  final int x0, y0, x1, y1;

  @override
  bool operator ==(Object other) =>
      other is _CellRange &&
      other.x0 == x0 &&
      other.y0 == y0 &&
      other.x1 == x1 &&
      other.y1 == y1;

  @override
  int get hashCode => Object.hash(x0, y0, x1, y1);
}
