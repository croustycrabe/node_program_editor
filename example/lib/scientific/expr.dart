import 'dart:math' as math;

/// A tiny math expression compiler: numbers, variables, `+ - * / ^`,
/// parentheses, unary minus and common functions.
///
/// ```dart
/// final f = Expr.compile('a * sin(2*pi*3*t) + b');
/// f({'a': 1, 'b': 0.5, 't': 0.1});
/// ```
abstract final class Expr {
  static final Map<String, double Function(Map<String, double>)> _cache = {};

  /// Compiles [source] (cached). Throws [FormatException] on syntax errors.
  static double Function(Map<String, double>) compile(String source) =>
      _cache[source] ??= _Parser(source).parse();
}

typedef _F = double Function(Map<String, double> v);

class _Parser {
  _Parser(this.src);
  final String src;
  int i = 0;

  static final Map<String, double Function(double)> _fn1 = {
    'sin': math.sin,
    'cos': math.cos,
    'tan': math.tan,
    'asin': math.asin,
    'acos': math.acos,
    'atan': math.atan,
    'exp': math.exp,
    'log': math.log,
    'sqrt': math.sqrt,
    'abs': (x) => x.abs(),
    'floor': (x) => x.floorToDouble(),
    'ceil': (x) => x.ceilToDouble(),
    'round': (x) => x.roundToDouble(),
    'sign': (x) => x.sign,
  };

  static final Map<String, double Function(double, double)> _fn2 = {
    'min': math.min,
    'max': math.max,
    'pow': (a, b) => math.pow(a, b).toDouble(),
    'atan2': math.atan2,
  };

  _F parse() {
    final f = _expr();
    _ws();
    if (i < src.length) throw FormatException('Unexpected "${src[i]}"', src, i);
    return f;
  }

  void _ws() {
    while (i < src.length && src[i].trim().isEmpty) {
      i++;
    }
  }

  bool _eat(String c) {
    _ws();
    if (i < src.length && src[i] == c) {
      i++;
      return true;
    }
    return false;
  }

  _F _expr() {
    var left = _term();
    while (true) {
      if (_eat('+')) {
        final l = left, r = _term();
        left = (v) => l(v) + r(v);
      } else if (_eat('-')) {
        final l = left, r = _term();
        left = (v) => l(v) - r(v);
      } else {
        return left;
      }
    }
  }

  _F _term() {
    var left = _power();
    while (true) {
      if (_eat('*')) {
        final l = left, r = _power();
        left = (v) => l(v) * r(v);
      } else if (_eat('/')) {
        final l = left, r = _power();
        left = (v) => l(v) / r(v);
      } else if (_eat('%')) {
        final l = left, r = _power();
        left = (v) => l(v) % r(v);
      } else {
        return left;
      }
    }
  }

  _F _power() {
    final base = _unary();
    if (_eat('^')) {
      final exp = _power();
      return (v) => math.pow(base(v), exp(v)).toDouble();
    }
    return base;
  }

  _F _unary() {
    if (_eat('-')) {
      final f = _unary();
      return (v) => -f(v);
    }
    if (_eat('+')) return _unary();
    return _atom();
  }

  _F _atom() {
    _ws();
    if (_eat('(')) {
      final f = _expr();
      if (!_eat(')')) throw FormatException('Missing ")"', src, i);
      return f;
    }
    final start = i;
    if (i < src.length && RegExp(r'[0-9.]').hasMatch(src[i])) {
      while (i < src.length && RegExp(r'[0-9.eE]').hasMatch(src[i])) {
        i++;
      }
      final n = double.parse(src.substring(start, i));
      return (_) => n;
    }
    while (i < src.length && RegExp(r'[A-Za-z_0-9]').hasMatch(src[i])) {
      i++;
    }
    final name = src.substring(start, i);
    if (name.isEmpty) {
      throw FormatException('Unexpected end of expression', src, i);
    }
    if (_eat('(')) {
      final a = _expr();
      if (_eat(',')) {
        final b = _expr();
        if (!_eat(')')) throw FormatException('Missing ")"', src, i);
        final f =
            _fn2[name] ?? (throw FormatException('Unknown function $name'));
        return (v) => f(a(v), b(v));
      }
      if (!_eat(')')) throw FormatException('Missing ")"', src, i);
      final f = _fn1[name] ?? (throw FormatException('Unknown function $name'));
      return (v) => f(a(v));
    }
    if (name == 'pi') return (_) => math.pi;
    if (name == 'e') return (_) => math.e;
    return (v) => v[name] ?? 0;
  }
}
