/// JSON helpers shared by every serializable model of the package.
///
/// All `fromJson` factories are lenient: numbers may arrive as `int` or
/// `double`, and missing optional keys fall back to defaults, so files edited
/// by hand or produced by other tools still load.
library;

import 'dart:ui';

/// Encodes a color as an `0xAARRGGBB` hex string (`null` stays `null`).
String? colorToJson(Color? color) => color == null
    ? null
    : '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// Decodes a color produced by [colorToJson]. Also accepts `#RRGGBB` and raw
/// ARGB integers.
Color? colorFromJson(Object? json) {
  if (json == null) return null;
  if (json is int) return Color(json);
  if (json is String) {
    var hex = json.startsWith('#') ? json.substring(1) : json;
    if (hex.startsWith('0x')) hex = hex.substring(2);
    if (hex.length == 6) hex = 'FF$hex';
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }
  return null;
}

/// Reads a nullable double from a JSON number.
double? readDouble(Object? json) => json is num ? json.toDouble() : null;

/// Reads a nullable int from a JSON number.
int? readInt(Object? json) => json is num ? json.toInt() : null;

/// Casts a decoded JSON object to a string keyed map.
Map<String, Object?> asJsonMap(Object? json) =>
    json is Map<String, Object?> ? json : (json as Map).cast<String, Object?>();

/// Casts a decoded JSON array (`null` gives an empty list).
List<Object?> asJsonList(Object? json) =>
    json == null ? const [] : (json as List).cast<Object?>();

/// Resolves an enum value from its [Enum.name] (null when unknown).
T? enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// Removes `null` values so files only contain what was actually set.
Map<String, Object?> compactJson(Map<String, Object?> map) =>
    map..removeWhere((_, v) => v == null);

/// Encodes an [Offset] as `[x, y]`.
List<double> offsetToJson(Offset o) => [o.dx, o.dy];

/// Decodes an [Offset] from `[x, y]` or `{"x":..,"y":..}`.
Offset offsetFromJson(Object? json) {
  if (json is List) {
    return Offset((json[0] as num).toDouble(), (json[1] as num).toDouble());
  }
  if (json is Map) {
    return Offset((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
  }
  return Offset.zero;
}

/// Encodes a [Rect] as `[left, top, width, height]`.
List<double> rectToJson(Rect r) => [r.left, r.top, r.width, r.height];

/// Decodes a [Rect] from `[left, top, width, height]`.
Rect rectFromJson(Object? json) {
  final l = (json as List).cast<num>();
  return Rect.fromLTWH(
    l[0].toDouble(),
    l[1].toDouble(),
    l[2].toDouble(),
    l[3].toDouble(),
  );
}
