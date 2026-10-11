import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/json.dart';
import 'param_values.dart';

/// Describes the type of a node parameter: its default value, JSON codec and
/// validation rules.
///
/// The package ships types for the common needs of automation, scientific and
/// computer-vision editors. Create your own by extending this class and
/// registering an editor for its [id] in the `ParamEditorRegistry`.
@immutable
abstract class ParamType<T> {
  /// Const constructor for subclasses.
  const ParamType();

  /// Stable identifier, used to look up editors.
  String get id;

  /// Value used when a node is created.
  T get defaultValue;

  /// Converts [value] to a JSON compatible object.
  Object? encode(T value);

  /// Converts JSON produced by [encode] back to a value.
  T decode(Object? json);

  /// Returns an error message when [value] is invalid, otherwise null.
  String? validate(T value) => null;

  /// Normalizes [value] (e.g. clamps numbers). Called before storing values.
  T normalize(T value) => value;

  /// Whether [value] has the runtime type of this parameter.
  bool isValueOfType(Object? value) => value is T;

  /// Type-erased [encode]: falls back to [defaultValue] on type mismatch.
  Object? encodeAny(Object? value) => encode(value is T ? value : defaultValue);

  /// Type-erased [decode]: never throws, returns [defaultValue] on bad data.
  T decodeAny(Object? json) {
    if (json == null) return defaultValue;
    try {
      return decode(json);
    } catch (_) {
      return defaultValue;
    }
  }

  /// Type-erased [validate].
  String? validateAny(Object? value) =>
      value is T ? validate(value) : 'Expected a value of type $T';

  /// Type-erased [normalize].
  Object? normalizeAny(Object? value) => value is T ? normalize(value) : value;
}

double _clampD(double v, double? min, double? max) {
  if (min != null && v < min) return min;
  if (max != null && v > max) return max;
  return v;
}

/// Integer parameter, optionally edited with a slider.
class IntParam extends ParamType<int> {
  /// Creates an integer parameter.
  const IntParam({
    this.min,
    this.max,
    this.step = 1,
    this.slider = false,
    this.unit,
    int? defaultValue,
  }) : _default = defaultValue;

  /// Minimum value.
  final int? min;

  /// Maximum value.
  final int? max;

  /// Increment used by steppers and sliders.
  final int step;

  /// Whether to edit with a slider (requires [min] and [max]).
  final bool slider;

  /// Optional unit suffix.
  final String? unit;
  final int? _default;

  @override
  String get id => 'int';

  @override
  int get defaultValue => _default ?? min ?? 0;

  @override
  Object? encode(int value) => value;

  @override
  int decode(Object? json) => (json as num).toInt();

  @override
  int normalize(int value) =>
      _clampD(value.toDouble(), min?.toDouble(), max?.toDouble()).toInt();

  @override
  String? validate(int value) {
    if (min != null && value < min!) return 'Must be ≥ $min';
    if (max != null && value > max!) return 'Must be ≤ $max';
    return null;
  }
}

/// Floating point parameter.
class DoubleParam extends ParamType<double> {
  /// Creates a floating point parameter.
  const DoubleParam({
    this.min,
    this.max,
    this.step,
    this.precision = 3,
    this.slider = false,
    this.unit,
    double? defaultValue,
  }) : _default = defaultValue;

  /// Minimum value.
  final double? min;

  /// Maximum value.
  final double? max;

  /// Slider / stepper increment.
  final double? step;

  /// Decimal digits shown by editors.
  final int precision;

  /// Whether to edit with a slider (requires [min] and [max]).
  final bool slider;

  /// Optional unit suffix.
  final String? unit;
  final double? _default;

  @override
  String get id => 'double';

  @override
  double get defaultValue => _default ?? min ?? 0;

  @override
  Object? encode(double value) => value;

  @override
  double decode(Object? json) => (json as num).toDouble();

  @override
  double normalize(double value) => _clampD(value, min, max);

  @override
  String? validate(double value) {
    if (value.isNaN) return 'Not a number';
    if (min != null && value < min!) return 'Must be ≥ $min';
    if (max != null && value > max!) return 'Must be ≤ $max';
    return null;
  }
}

/// Boolean parameter.
class BoolParam extends ParamType<bool> {
  /// Creates a boolean parameter.
  const BoolParam({bool defaultValue = false}) : _default = defaultValue;
  final bool _default;

  @override
  String get id => 'bool';

  @override
  bool get defaultValue => _default;

  @override
  Object? encode(bool value) => value;

  @override
  bool decode(Object? json) => json! as bool;
}

/// Single line text parameter.
class TextParam extends ParamType<String> {
  /// Creates a text parameter.
  const TextParam({
    this.hint,
    this.maxLength,
    this.pattern,
    String defaultValue = '',
  }) : _default = defaultValue;

  /// Placeholder text.
  final String? hint;

  /// Maximum length.
  final int? maxLength;

  /// Regular expression the value must fully match.
  final String? pattern;
  final String _default;

  @override
  String get id => 'text';

  @override
  String get defaultValue => _default;

  @override
  Object? encode(String value) => value;

  @override
  String decode(Object? json) => json! as String;

  @override
  String? validate(String value) {
    if (maxLength != null && value.length > maxLength!) {
      return 'At most $maxLength characters';
    }
    if (pattern != null && !RegExp('^(?:$pattern)\$').hasMatch(value)) {
      return 'Invalid format';
    }
    return null;
  }
}

/// Multi-line text parameter.
class MultilineTextParam extends TextParam {
  /// Creates a multi-line text parameter.
  const MultilineTextParam({
    this.lines = 4,
    super.hint,
    super.maxLength,
    super.defaultValue,
  });

  /// Visible lines in editors.
  final int lines;

  @override
  String get id => 'multiline';
}

/// Secret text parameter (API keys, passwords). Obscured in editors.
class PasswordParam extends TextParam {
  /// Creates a password parameter.
  const PasswordParam({super.hint});

  @override
  String get id => 'password';
}

/// Source code / expression parameter edited with a monospace editor.
class CodeParam extends TextParam {
  /// Creates a code parameter.
  const CodeParam({
    this.language = 'text',
    this.lines = 8,
    super.defaultValue,
    super.hint,
  });

  /// Language hint (`python`, `javascript`, `glsl`, `expression`...).
  final String language;

  /// Visible lines in editors.
  final int lines;

  @override
  String get id => 'code';
}

/// A single line math expression, e.g. `a * sin(t) + b`.
class ExpressionParam extends CodeParam {
  /// Creates an expression parameter.
  const ExpressionParam({
    this.variables = const [],
    super.defaultValue,
    super.hint,
  }) : super(language: 'expression', lines: 1);

  /// Variable names available in the expression, shown as hints.
  final List<String> variables;

  @override
  String get id => 'expression';
}

/// One choice of an [EnumParam] / [MultiSelectParam].
@immutable
class ParamOption {
  /// Creates an option.
  const ParamOption(this.value, [String? label, this.description])
    : label = label ?? value;

  /// Stored value.
  final String value;

  /// Displayed label.
  final String label;

  /// Optional description.
  final String? description;
}

/// Single choice parameter.
class EnumParam extends ParamType<String> {
  /// Creates a single choice parameter.
  const EnumParam(this.options, {this.segmented = false, String? defaultValue})
    : _default = defaultValue;

  /// Builds options from plain strings.
  EnumParam.values(
    List<String> values, {
    bool segmented = false,
    String? defaultValue,
  }) : this(
         [for (final v in values) ParamOption(v)],
         segmented: segmented,
         defaultValue: defaultValue,
       );

  /// Available choices.
  final List<ParamOption> options;

  /// Whether to show a segmented button instead of a dropdown.
  final bool segmented;
  final String? _default;

  @override
  String get id => 'enum';

  @override
  String get defaultValue =>
      _default ?? (options.isEmpty ? '' : options.first.value);

  @override
  Object? encode(String value) => value;

  @override
  String decode(Object? json) => json! as String;

  @override
  String? validate(String value) =>
      options.any((o) => o.value == value) ? null : 'Unknown option';
}

/// Multiple choice parameter.
class MultiSelectParam extends ParamType<List<String>> {
  /// Creates a multiple choice parameter.
  const MultiSelectParam(this.options, {List<String> defaultValue = const []})
    : _default = defaultValue;

  /// Available choices.
  final List<ParamOption> options;
  final List<String> _default;

  @override
  String get id => 'multiselect';

  @override
  List<String> get defaultValue => _default;

  @override
  Object? encode(List<String> value) => value;

  @override
  List<String> decode(Object? json) => asJsonList(json).cast<String>();
}

/// Homogeneous list parameter, items typed by [itemType].
class ListParam extends ParamType<List<Object?>> {
  /// Creates a list parameter.
  const ListParam(
    this.itemType, {
    this.minItems = 0,
    this.maxItems,
    List<Object?> defaultValue = const [],
  }) : _default = defaultValue;

  /// Type of each item.
  final ParamType<Object?> itemType;

  /// Minimum number of items.
  final int minItems;

  /// Maximum number of items.
  final int? maxItems;
  final List<Object?> _default;

  @override
  String get id => 'list';

  @override
  List<Object?> get defaultValue => _default;

  @override
  Object? encode(List<Object?> value) => [
    for (final v in value) itemType.encodeAny(v),
  ];

  @override
  List<Object?> decode(Object? json) => [
    for (final v in asJsonList(json)) itemType.decodeAny(v),
  ];

  @override
  String? validate(List<Object?> value) {
    if (value.length < minItems) return 'At least $minItems items';
    if (maxItems != null && value.length > maxItems!) {
      return 'At most $maxItems items';
    }
    for (final v in value) {
      final e = itemType.validateAny(v);
      if (e != null) return e;
    }
    return null;
  }
}

/// A column of a [TableParam].
@immutable
class TableColumn {
  /// Creates a column.
  const TableColumn(this.name, this.type, {String? label})
    : label = label ?? name;

  /// Key in each row map.
  final String name;

  /// Displayed header.
  final String label;

  /// Cell type.
  final ParamType<Object?> type;
}

/// Table parameter: a list of rows with typed columns (e.g. HTTP headers,
/// calibration points, lookup tables).
class TableParam extends ParamType<List<Map<String, Object?>>> {
  /// Creates a table parameter.
  const TableParam(
    this.columns, {
    List<Map<String, Object?>> defaultValue = const [],
  }) : _default = defaultValue;

  /// Column definitions.
  final List<TableColumn> columns;
  final List<Map<String, Object?>> _default;

  @override
  String get id => 'table';

  @override
  List<Map<String, Object?>> get defaultValue => _default;

  /// A new row filled with column defaults.
  Map<String, Object?> emptyRow() => {
    for (final c in columns) c.name: c.type.defaultValue,
  };

  @override
  Object? encode(List<Map<String, Object?>> value) => [
    for (final row in value)
      {for (final c in columns) c.name: c.type.encodeAny(row[c.name])},
  ];

  @override
  List<Map<String, Object?>> decode(Object? json) => [
    for (final row in asJsonList(json))
      {
        for (final c in columns)
          c.name: c.type.decodeAny(asJsonMap(row)[c.name]),
      },
  ];
}

/// Free form JSON parameter.
class JsonParam extends ParamType<Object?> {
  /// Creates a JSON parameter.
  const JsonParam({Object? defaultValue}) : _default = defaultValue;
  final Object? _default;

  @override
  String get id => 'json';

  @override
  Object? get defaultValue => _default;

  @override
  Object? encode(Object? value) => value;

  @override
  Object? decode(Object? json) => json;
}

/// A value with a selectable unit.
class QuantityParam extends ParamType<Quantity> {
  /// Creates a quantity parameter. The first unit is the default.
  const QuantityParam(
    this.units, {
    this.min,
    this.max,
    this.precision = 3,
    Quantity? defaultValue,
  }) : _default = defaultValue;

  /// Selectable unit symbols.
  final List<String> units;

  /// Minimum value.
  final double? min;

  /// Maximum value.
  final double? max;

  /// Decimal digits shown by editors.
  final int precision;
  final Quantity? _default;

  @override
  String get id => 'quantity';

  @override
  Quantity get defaultValue =>
      _default ?? Quantity(min ?? 0, units.isEmpty ? '' : units.first);

  @override
  Object? encode(Quantity value) => value.toJson();

  @override
  Quantity decode(Object? json) => Quantity.fromJson(asJsonMap(json));

  @override
  Quantity normalize(Quantity value) =>
      value.copyWith(value: _clampD(value.value, min, max));
}

/// Numeric interval parameter (e.g. hysteresis thresholds, frequency band).
class RangeParam extends ParamType<RangeValue> {
  /// Creates a range parameter.
  const RangeParam({
    this.min = 0,
    this.max = 1,
    this.step,
    this.precision = 2,
    RangeValue? defaultValue,
  }) : _default = defaultValue;

  /// Lower limit.
  final double min;

  /// Upper limit.
  final double max;

  /// Slider increment.
  final double? step;

  /// Decimal digits shown by editors.
  final int precision;
  final RangeValue? _default;

  @override
  String get id => 'range';

  @override
  RangeValue get defaultValue => _default ?? RangeValue(min, max);

  @override
  Object? encode(RangeValue value) => value.toJson();

  @override
  RangeValue decode(Object? json) => RangeValue.fromJson(json);

  @override
  RangeValue normalize(RangeValue value) {
    final a = _clampD(value.start, min, max);
    final b = _clampD(value.end, min, max);
    return RangeValue(math.min(a, b), math.max(a, b));
  }
}

/// Fixed size numeric vector (2D / 3D / 4D).
class VectorParam extends ParamType<List<double>> {
  /// Creates a vector parameter.
  const VectorParam({
    this.dimension = 3,
    this.labels,
    this.min,
    this.max,
    this.precision = 3,
    List<double>? defaultValue,
  }) : _default = defaultValue;

  /// Number of components.
  final int dimension;

  /// Component labels (defaults to x, y, z, w).
  final List<String>? labels;

  /// Minimum component value.
  final double? min;

  /// Maximum component value.
  final double? max;

  /// Decimal digits shown by editors.
  final int precision;
  final List<double>? _default;

  /// Effective component labels.
  List<String> get effectiveLabels =>
      labels ?? const ['x', 'y', 'z', 'w'].take(dimension).toList();

  @override
  String get id => 'vector';

  @override
  List<double> get defaultValue => _default ?? List.filled(dimension, 0);

  @override
  Object? encode(List<double> value) => value;

  @override
  List<double> decode(Object? json) =>
      asJsonList(json).map((e) => readDouble(e) ?? 0).toList();

  @override
  String? validate(List<double> value) =>
      value.length == dimension ? null : 'Expected $dimension components';
}

/// Matrix parameter (convolution kernels, homographies, camera matrices).
class MatrixParam extends ParamType<Matrix> {
  /// Creates a matrix parameter.
  const MatrixParam({
    this.rows = 3,
    this.cols = 3,
    this.resizable = false,
    this.precision = 3,
    Matrix? defaultValue,
  }) : _default = defaultValue;

  /// Default row count.
  final int rows;

  /// Default column count.
  final int cols;

  /// Whether editors allow changing the dimensions.
  final bool resizable;

  /// Decimal digits shown by editors.
  final int precision;
  final Matrix? _default;

  @override
  String get id => 'matrix';

  @override
  Matrix get defaultValue => _default ?? Matrix.zeros(rows, cols);

  @override
  Object? encode(Matrix value) => value.toJson();

  @override
  Matrix decode(Object? json) => Matrix.fromJson(asJsonMap(json));
}

/// Editable curve made of control points (tone curves, lookup tables,
/// transfer functions). Points are kept sorted by x.
class CurveParam extends ParamType<List<Offset>> {
  /// Creates a curve parameter.
  const CurveParam({
    this.minX = 0,
    this.maxX = 1,
    this.minY = 0,
    this.maxY = 1,
    List<Offset>? defaultValue,
  }) : _default = defaultValue;

  /// An 8-bit lookup table (`0..255 -> 0..255`), identity by default.
  const CurveParam.lut({List<Offset>? defaultValue})
    : this(minX: 0, maxX: 255, minY: 0, maxY: 255, defaultValue: defaultValue);

  /// Domain start.
  final double minX;

  /// Domain end.
  final double maxX;

  /// Range start.
  final double minY;

  /// Range end.
  final double maxY;
  final List<Offset>? _default;

  @override
  String get id => 'curve';

  @override
  List<Offset> get defaultValue =>
      _default ?? [Offset(minX, minY), Offset(maxX, maxY)];

  @override
  Object? encode(List<Offset> value) => [
    for (final p in value) [p.dx, p.dy],
  ];

  @override
  List<Offset> decode(Object? json) => [
    for (final p in asJsonList(json)) offsetFromJson(p),
  ];

  @override
  List<Offset> normalize(List<Offset> value) => [
    for (final p in value)
      Offset(_clampD(p.dx, minX, maxX), _clampD(p.dy, minY, maxY)),
  ]..sort((a, b) => a.dx.compareTo(b.dx));

  /// Evaluates the piecewise-linear curve at [x].
  static double evaluate(List<Offset> points, double x) {
    if (points.isEmpty) return x;
    if (x <= points.first.dx) return points.first.dy;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      if (x <= b.dx) {
        final t = b.dx == a.dx ? 0.0 : (x - a.dx) / (b.dx - a.dx);
        return a.dy + (b.dy - a.dy) * t;
      }
    }
    return points.last.dy;
  }
}

/// Color parameter.
class ColorParam extends ParamType<Color> {
  /// Creates a color parameter.
  const ColorParam({
    this.alpha = true,
    Color defaultValue = const Color(0xFF2196F3),
  }) : _default = defaultValue;

  /// Whether the alpha channel is editable.
  final bool alpha;
  final Color _default;

  @override
  String get id => 'color';

  @override
  Color get defaultValue => _default;

  @override
  Object? encode(Color value) => colorToJson(value);

  @override
  Color decode(Object? json) => colorFromJson(json) ?? _default;
}

/// Image parameter. Picking is delegated to the host app through
/// `NodeEditorServices.pickImage`.
class ImageParam extends ParamType<ImageRef?> {
  /// Creates an image parameter.
  const ImageParam({this.accept = const ['png', 'jpg', 'jpeg', 'bmp']});

  /// Accepted file extensions, passed to the picker.
  final List<String> accept;

  @override
  String get id => 'image';

  @override
  ImageRef? get defaultValue => null;

  @override
  Object? encode(ImageRef? value) => value?.toJson();

  @override
  ImageRef? decode(Object? json) =>
      json == null ? null : ImageRef.fromJson(asJsonMap(json));
}

/// Region of interest parameter, editable by dragging over a reference
/// frame.
class RoiParam extends ParamType<Roi> {
  /// Creates a region of interest parameter.
  const RoiParam({
    this.frame = const Size(640, 480),
    this.rotatable = false,
    this.shapes = const [RoiShape.rectangle],
    Roi? defaultValue,
  }) : _default = defaultValue;

  /// Coordinate space of the region (usually the image size).
  final Size frame;

  /// Whether the rotation handle is shown.
  final bool rotatable;

  /// Allowed shapes.
  final List<RoiShape> shapes;
  final Roi? _default;

  @override
  String get id => 'roi';

  @override
  Roi get defaultValue =>
      _default ??
      Roi(
        Rect.fromLTWH(
          frame.width * 0.25,
          frame.height * 0.25,
          frame.width * 0.5,
          frame.height * 0.5,
        ),
      );

  @override
  Object? encode(Roi value) => value.toJson();

  @override
  Roi decode(Object? json) => Roi.fromJson(asJsonMap(json));

  @override
  Roi normalize(Roi value) {
    final r = value.rect;
    final left = _clampD(r.left, 0, frame.width);
    final top = _clampD(r.top, 0, frame.height);
    final right = _clampD(r.right, left, frame.width);
    final bottom = _clampD(r.bottom, top, frame.height);
    return value.copyWith(rect: Rect.fromLTRB(left, top, right, bottom));
  }
}

/// 2D point parameter (e.g. an anchor, seed point or kernel center).
class PointParam extends ParamType<Offset> {
  /// Creates a point parameter.
  const PointParam({this.bounds, Offset defaultValue = Offset.zero})
    : _default = defaultValue;

  /// Optional allowed area.
  final Rect? bounds;
  final Offset _default;

  @override
  String get id => 'point';

  @override
  Offset get defaultValue => _default;

  @override
  Object? encode(Offset value) => offsetToJson(value);

  @override
  Offset decode(Object? json) => offsetFromJson(json);

  @override
  Offset normalize(Offset value) => bounds == null
      ? value
      : Offset(
          _clampD(value.dx, bounds!.left, bounds!.right),
          _clampD(value.dy, bounds!.top, bounds!.bottom),
        );
}

/// What a [FilePathParam] picks.
enum FilePickMode {
  /// An existing file.
  open,

  /// A file to write.
  save,

  /// A directory.
  directory,
}

/// File system path parameter. Picking is delegated to the host app through
/// `NodeEditorServices.pickFile`; the package performs no I/O.
class FilePathParam extends ParamType<String> {
  /// Creates a file path parameter.
  const FilePathParam({
    this.extensions = const [],
    this.mode = FilePickMode.open,
  });

  /// Accepted extensions (empty for any).
  final List<String> extensions;

  /// Pick mode.
  final FilePickMode mode;

  @override
  String get id => 'file';

  @override
  String get defaultValue => '';

  @override
  Object? encode(String value) => value;

  @override
  String decode(Object? json) => json! as String;
}

/// Which parts of a [DateTimeParam] are edited.
enum DateTimeMode {
  /// Date only.
  date,

  /// Time of day only.
  time,

  /// Date and time.
  dateTime,
}

/// Date / time parameter, stored as ISO-8601.
class DateTimeParam extends ParamType<DateTime> {
  /// Creates a date / time parameter.
  const DateTimeParam({this.mode = DateTimeMode.dateTime});

  /// Edited components.
  final DateTimeMode mode;

  @override
  String get id => 'datetime';

  @override
  DateTime get defaultValue => DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Object? encode(DateTime value) => value.toIso8601String();

  @override
  DateTime decode(Object? json) => DateTime.parse(json! as String);
}

/// A button parameter: it holds no value but fires
/// `NodeEditorServices.onTrigger` (e.g. "Capture", "Calibrate", "Run").
class TriggerParam extends ParamType<Object?> {
  /// Creates a trigger parameter.
  const TriggerParam({this.buttonLabel = 'Run'});

  /// Button text.
  final String buttonLabel;

  @override
  String get id => 'trigger';

  @override
  Object? get defaultValue => null;

  @override
  Object? encode(Object? value) => null;

  @override
  Object? decode(Object? json) => null;
}

/// Scientific color map selection (gray, jet, viridis...).
class ColorMapParam extends ParamType<String> {
  /// Creates a color map parameter.
  const ColorMapParam({String defaultValue = 'viridis'})
    : _default = defaultValue;
  final String _default;

  /// Built-in color maps as gradient stops.
  static const Map<String, List<Color>> maps = {
    'gray': [Color(0xFF000000), Color(0xFFFFFFFF)],
    'jet': [
      Color(0xFF00007F),
      Color(0xFF0000FF),
      Color(0xFF00FFFF),
      Color(0xFFFFFF00),
      Color(0xFFFF0000),
      Color(0xFF7F0000),
    ],
    'viridis': [
      Color(0xFF440154),
      Color(0xFF3B528B),
      Color(0xFF21908C),
      Color(0xFF5DC863),
      Color(0xFFFDE725),
    ],
    'magma': [
      Color(0xFF000004),
      Color(0xFF51127C),
      Color(0xFFB73779),
      Color(0xFFFC8961),
      Color(0xFFFCFDBF),
    ],
    'hot': [
      Color(0xFF000000),
      Color(0xFFFF0000),
      Color(0xFFFFFF00),
      Color(0xFFFFFFFF),
    ],
    'cool': [Color(0xFF00FFFF), Color(0xFFFF00FF)],
  };

  @override
  String get id => 'colormap';

  @override
  String get defaultValue => _default;

  @override
  Object? encode(String value) => value;

  @override
  String decode(Object? json) => json! as String;

  @override
  String? validate(String value) =>
      maps.containsKey(value) ? null : 'Unknown color map';

  /// Samples color map [name] at [t] in `[0, 1]`.
  static Color sample(String name, double t) {
    final stops = maps[name] ?? maps['gray']!;
    final x = t.clamp(0.0, 1.0) * (stops.length - 1);
    final i = x.floor().clamp(0, stops.length - 2);
    return Color.lerp(stops[i], stops[i + 1], x - i)!;
  }
}

/// Declares one parameter of a node.
@immutable
class ParamSpec {
  /// Creates a parameter specification.
  const ParamSpec(
    this.name,
    this.type, {
    String? label,
    this.description,
    this.group,
    this.showInNode = false,
    this.readOnly = false,
    this.defaultValue,
  }) : label = label ?? name;

  /// Key in `NodeInstance.params`.
  final String name;

  /// Value type.
  final ParamType<Object?> type;

  /// Displayed label.
  final String label;

  /// Help text.
  final String? description;

  /// Section in the edit dialog.
  final String? group;

  /// Whether the default node widget shows an inline editor for it.
  final bool showInNode;

  /// Whether the value can only be changed programmatically.
  final bool readOnly;

  /// Overrides [ParamType.defaultValue].
  final Object? defaultValue;

  /// The initial value for new nodes.
  Object? get initialValue => defaultValue ?? type.defaultValue;

  /// Returns a copy with the given fields replaced.
  ParamSpec copyWith({
    String? name,
    String? label,
    String? description,
    String? group,
    bool? showInNode,
    bool? readOnly,
    Object? defaultValue,
  }) => ParamSpec(
    name ?? this.name,
    type,
    label: label ?? this.label,
    description: description ?? this.description,
    group: group ?? this.group,
    showInNode: showInNode ?? this.showInNode,
    readOnly: readOnly ?? this.readOnly,
    defaultValue: defaultValue ?? this.defaultValue,
  );
}
