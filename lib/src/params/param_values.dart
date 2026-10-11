import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/json.dart';

/// A number with a unit, e.g. `12.5 ms` or `3 px`.
@immutable
class Quantity {
  /// Creates a quantity.
  const Quantity(this.value, this.unit);

  /// The numeric value.
  final double value;

  /// The unit symbol.
  final String unit;

  /// Returns a copy with the given fields replaced.
  Quantity copyWith({double? value, String? unit}) =>
      Quantity(value ?? this.value, unit ?? this.unit);

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {'value': value, 'unit': unit};

  /// Parses JSON produced by [toJson].
  factory Quantity.fromJson(Map<String, Object?> json) =>
      Quantity(readDouble(json['value']) ?? 0, json['unit'] as String? ?? '');

  @override
  bool operator ==(Object other) =>
      other is Quantity && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => '$value $unit';
}

/// A closed numeric interval.
@immutable
class RangeValue {
  /// Creates a range.
  const RangeValue(this.start, this.end);

  /// Lower bound.
  final double start;

  /// Upper bound.
  final double end;

  /// Serializes to JSON.
  List<double> toJson() => [start, end];

  /// Parses JSON produced by [toJson].
  factory RangeValue.fromJson(Object? json) {
    final l = asJsonList(json);
    return RangeValue(
      readDouble(l.elementAtOrNull(0)) ?? 0,
      readDouble(l.elementAtOrNull(1)) ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RangeValue && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '[$start, $end]';
}

/// A dense row-major matrix of doubles (e.g. a convolution kernel or a
/// calibration matrix).
@immutable
class Matrix {
  /// Creates a matrix from row-major [data] (`rows * cols` long).
  Matrix(this.rows, this.cols, List<double> data)
    : assert(data.length == rows * cols),
      data = List.unmodifiable(data);

  /// A zero filled matrix.
  factory Matrix.zeros(int rows, int cols) =>
      Matrix(rows, cols, List.filled(rows * cols, 0));

  /// An identity matrix.
  factory Matrix.identity(int n) => Matrix(n, n, [
    for (var i = 0; i < n * n; i++) i % (n + 1) == 0 ? 1.0 : 0.0,
  ]);

  /// Number of rows.
  final int rows;

  /// Number of columns.
  final int cols;

  /// Row-major values.
  final List<double> data;

  /// Value at row [r], column [c].
  double at(int r, int c) => data[r * cols + c];

  /// Returns a copy with the cell at ([r], [c]) set to [v].
  Matrix withValue(int r, int c, double v) {
    final d = [...data];
    d[r * cols + c] = v;
    return Matrix(rows, cols, d);
  }

  /// Returns a resized copy, keeping overlapping values.
  Matrix resized(int newRows, int newCols) => Matrix(newRows, newCols, [
    for (var r = 0; r < newRows; r++)
      for (var c = 0; c < newCols; c++) r < rows && c < cols ? at(r, c) : 0.0,
  ]);

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {'rows': rows, 'cols': cols, 'data': data};

  /// Parses JSON produced by [toJson].
  factory Matrix.fromJson(Map<String, Object?> json) {
    final rows = readInt(json['rows']) ?? 0;
    final cols = readInt(json['cols']) ?? 0;
    final data = asJsonList(json['data'])
        .map((e) => readDouble(e) ?? 0)
        .toList();
    if (data.length != rows * cols) return Matrix.zeros(rows, cols);
    return Matrix(rows, cols, data);
  }

  @override
  bool operator ==(Object other) =>
      other is Matrix &&
      other.rows == rows &&
      other.cols == cols &&
      listEquals(other.data, data);

  @override
  int get hashCode => Object.hash(rows, cols, Object.hashAll(data));
}

/// Shape of a region of interest.
enum RoiShape {
  /// Axis aligned (or rotated, see [Roi.angle]) rectangle.
  rectangle,

  /// Ellipse inscribed in the rect.
  ellipse,
}

/// A region of interest in image coordinates.
@immutable
class Roi {
  /// Creates a region of interest.
  const Roi(this.rect, {this.angle = 0, this.shape = RoiShape.rectangle});

  /// Bounds before rotation.
  final Rect rect;

  /// Rotation around the rect center, radians.
  final double angle;

  /// Shape inside [rect].
  final RoiShape shape;

  /// Returns a copy with the given fields replaced.
  Roi copyWith({Rect? rect, double? angle, RoiShape? shape}) => Roi(
    rect ?? this.rect,
    angle: angle ?? this.angle,
    shape: shape ?? this.shape,
  );

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
    'rect': rectToJson(rect),
    'angle': angle,
    'shape': shape.name,
  };

  /// Parses JSON produced by [toJson].
  factory Roi.fromJson(Map<String, Object?> json) => Roi(
    rectFromJson(json['rect']),
    angle: readDouble(json['angle']) ?? 0,
    shape: enumByName(RoiShape.values, json['shape']) ?? RoiShape.rectangle,
  );

  @override
  bool operator ==(Object other) =>
      other is Roi &&
      other.rect == rect &&
      other.angle == angle &&
      other.shape == shape;

  @override
  int get hashCode => Object.hash(rect, angle, shape);
}

/// A reference to an image: either a [uri] (asset, network, file path) or
/// inline encoded [bytes] (PNG / JPEG).
@immutable
class ImageRef {
  /// Creates an image reference.
  const ImageRef({
    this.uri,
    this.bytes,
    this.name,
    this.width,
    this.height,
    this.mimeType,
  }) : assert(uri != null || bytes != null);

  /// Location of the image, interpreted by the host application.
  final String? uri;

  /// Encoded image bytes, stored base64 in JSON.
  final Uint8List? bytes;

  /// Display name.
  final String? name;

  /// Pixel width, when known.
  final int? width;

  /// Pixel height, when known.
  final int? height;

  /// MIME type, e.g. `image/png`.
  final String? mimeType;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => compactJson({
    'uri': uri,
    'bytes': bytes == null ? null : base64Encode(bytes!),
    'name': name,
    'width': width,
    'height': height,
    'mimeType': mimeType,
  });

  /// Parses JSON produced by [toJson].
  factory ImageRef.fromJson(Map<String, Object?> json) => ImageRef(
    uri: json['uri'] as String?,
    bytes: json['bytes'] == null
        ? null
        : base64Decode(json['bytes']! as String),
    name: json['name'] as String?,
    width: readInt(json['width']),
    height: readInt(json['height']),
    mimeType: json['mimeType'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is ImageRef &&
      other.uri == uri &&
      other.name == name &&
      identical(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(uri, name, bytes);
}
