import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:node_program_editor/node_program_editor.dart';

/// A small 8-bit image (1 = gray, 3 = RGB channels), pure Dart.
class VImage {
  VImage(this.width, this.height, this.channels, [Uint8List? data])
    : data = data ?? Uint8List(width * height * channels);

  final int width;
  final int height;
  final int channels;
  final Uint8List data;

  int get length => width * height;

  /// Gray copy (luma weights).
  VImage toGray([List<double> w = const [0.299, 0.587, 0.114]]) {
    if (channels == 1) return this;
    final out = VImage(width, height, 1);
    for (var i = 0; i < length; i++) {
      final v =
          data[i * 3] * w[0] + data[i * 3 + 1] * w[1] + data[i * 3 + 2] * w[2];
      out.data[i] = v.round().clamp(0, 255);
    }
    return out;
  }

  /// RGBA bytes for display.
  Uint8List toRgba() {
    final out = Uint8List(length * 4);
    for (var i = 0; i < length; i++) {
      if (channels == 1) {
        final v = data[i];
        out[i * 4] = v;
        out[i * 4 + 1] = v;
        out[i * 4 + 2] = v;
      } else {
        out[i * 4] = data[i * 3];
        out[i * 4 + 1] = data[i * 3 + 1];
        out[i * 4 + 2] = data[i * 3 + 2];
      }
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  /// Converts to a GPU image for previews.
  Future<ui.Image> toUiImage() {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      toRgba(),
      width,
      height,
      ui.PixelFormat.rgba8888,
      c.complete,
    );
    return c.future;
  }

  /// Decodes PNG / JPEG bytes (downscaled to [maxWidth]).
  static Future<VImage> decode(Uint8List bytes, {int maxWidth = 320}) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: maxWidth);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final rgba = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    final out = VImage(img.width, img.height, 3);
    for (var i = 0; i < out.length; i++) {
      out.data[i * 3] = rgba[i * 4];
      out.data[i * 3 + 1] = rgba[i * 4 + 1];
      out.data[i * 3 + 2] = rgba[i * 4 + 2];
    }
    img.dispose();
    return out;
  }

  /// PNG bytes (used to turn synthetic samples into [ImageRef]s).
  Future<Uint8List> toPng() async {
    final img = await toUiImage();
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bytes!.buffer.asUint8List();
  }
}

/// Synthetic test frames: no image assets needed.
abstract final class Samples {
  static const int w = 256, h = 192;

  static VImage generate(
    String pattern, {
    int seed = 1,
    double noise = 8,
    double brightness = 1,
    double jitter = 0,
  }) {
    final rnd = math.Random(seed);
    final img = VImage(w, h, 3);
    void px(int x, int y, num r, num g, num b) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      final i = (y * w + x) * 3;
      img.data[i] = (r * brightness).round().clamp(0, 255);
      img.data[i + 1] = (g * brightness).round().clamp(0, 255);
      img.data[i + 2] = (b * brightness).round().clamp(0, 255);
    }

    switch (pattern) {
      case 'Checkerboard':
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final on = ((x ~/ 32) + (y ~/ 32)).isEven;
            px(x, y, on ? 230 : 25, on ? 230 : 25, on ? 230 : 25);
          }
        }
      case 'Gradient':
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final v = 255 * x / w;
            final band = 40 * math.sin(y / 8);
            px(x, y, v, v + band, 255 - v);
          }
        }
      case 'Coins':
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            px(x, y, 40, 45, 55);
          }
        }
        for (var k = 0; k < 11; k++) {
          final cx = 20 + rnd.nextDouble() * (w - 40) + jitter;
          final cy = 20 + rnd.nextDouble() * (h - 40);
          final r = 10 + rnd.nextDouble() * 16;
          final shade = 150 + rnd.nextInt(90);
          for (var y = (cy - r).floor(); y <= cy + r; y++) {
            for (var x = (cx - r).floor(); x <= cx + r; x++) {
              final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
              if (d <= r) {
                final rim = d > r - 2 ? 0.8 : 1.0;
                px(x, y, shade * rim, shade * 0.85 * rim, shade * 0.5 * rim);
              }
            }
          }
        }
      default: // Parts on a conveyor.
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final light = 35 + 30 * x / w;
            px(x, y, light, light + 4, light + 10);
          }
        }
        const colors = [
          [230, 80, 60],
          [60, 200, 120],
          [80, 140, 240],
          [240, 200, 60],
        ];
        for (var k = 0; k < 9; k++) {
          final cx = 24 + (k % 3) * 80 + rnd.nextDouble() * 30 + jitter;
          final cy = 26 + (k ~/ 3) * 60 + rnd.nextDouble() * 18;
          final col = colors[rnd.nextInt(colors.length)];
          if (k.isEven) {
            final r = 12 + rnd.nextDouble() * 10;
            for (var y = (cy - r).floor(); y <= cy + r; y++) {
              for (var x = (cx - r).floor(); x <= cx + r; x++) {
                if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
                  px(x, y, col[0], col[1], col[2]);
                }
              }
            }
          } else {
            final hw = 10 + rnd.nextDouble() * 14,
                hh = 8 + rnd.nextDouble() * 10;
            for (var y = (cy - hh).floor(); y <= cy + hh; y++) {
              for (var x = (cx - hw).floor(); x <= cx + hw; x++) {
                px(x, y, col[0], col[1], col[2]);
              }
            }
          }
        }
    }
    if (noise > 0) {
      for (var i = 0; i < img.data.length; i++) {
        img.data[i] = (img.data[i] + (rnd.nextDouble() * 2 - 1) * noise)
            .round()
            .clamp(0, 255);
      }
    }
    return img;
  }
}

/// Image processing operators.
abstract final class Ops {
  static VImage blur(VImage src, double sigma) {
    if (sigma <= 0.01) return src;
    final r = (sigma * 3).ceil();
    final k = Float64List(2 * r + 1);
    var sum = 0.0;
    for (var i = -r; i <= r; i++) {
      sum += k[i + r] = math.exp(-(i * i) / (2 * sigma * sigma));
    }
    for (var i = 0; i < k.length; i++) {
      k[i] /= sum;
    }
    final w = src.width, h = src.height, c = src.channels;
    final tmp = Float64List(w * h * c);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        for (var ch = 0; ch < c; ch++) {
          var acc = 0.0;
          for (var i = -r; i <= r; i++) {
            final xx = (x + i).clamp(0, w - 1);
            acc += src.data[(y * w + xx) * c + ch] * k[i + r];
          }
          tmp[(y * w + x) * c + ch] = acc;
        }
      }
    }
    final out = VImage(w, h, c);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        for (var ch = 0; ch < c; ch++) {
          var acc = 0.0;
          for (var i = -r; i <= r; i++) {
            final yy = (y + i).clamp(0, h - 1);
            acc += tmp[(yy * w + x) * c + ch] * k[i + r];
          }
          out.data[(y * w + x) * c + ch] = acc.round().clamp(0, 255);
        }
      }
    }
    return out;
  }

  static VImage convolve(VImage src, Matrix kernel, {bool normalize = true}) {
    final g = src.toGray();
    final w = g.width, h = g.height;
    final kr = kernel.rows ~/ 2, kc = kernel.cols ~/ 2;
    var norm = 1.0;
    if (normalize) {
      final s = kernel.data.fold<double>(0, (a, b) => a + b);
      if (s.abs() > 1e-9) norm = s;
    }
    final out = VImage(w, h, 1);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var acc = 0.0;
        for (var j = 0; j < kernel.rows; j++) {
          final yy = (y + j - kr).clamp(0, h - 1);
          for (var i = 0; i < kernel.cols; i++) {
            final xx = (x + i - kc).clamp(0, w - 1);
            acc += g.data[yy * w + xx] * kernel.at(j, i);
          }
        }
        out.data[y * w + x] = (acc / norm).round().clamp(0, 255);
      }
    }
    return out;
  }

  static VImage lut(VImage src, List<ui.Offset> curve) {
    final table = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      table[i] = CurveParam.evaluate(curve, i.toDouble()).round().clamp(0, 255);
    }
    final out = VImage(src.width, src.height, src.channels);
    for (var i = 0; i < src.data.length; i++) {
      out.data[i] = table[src.data[i]];
    }
    return out;
  }

  static VImage threshold(VImage src, double lo, double hi, bool invert) {
    final g = src.toGray();
    final out = VImage(g.width, g.height, 1);
    for (var i = 0; i < g.length; i++) {
      final v = g.data[i];
      final on = v >= lo && v <= hi;
      out.data[i] = (on != invert) ? 255 : 0;
    }
    return out;
  }

  static VImage sobel(VImage src, double scale) {
    final g = src.toGray();
    final w = g.width, h = g.height;
    final out = VImage(w, h, 1);
    int at(int x, int y) => g.data[y.clamp(0, h - 1) * w + x.clamp(0, w - 1)];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final gx =
            -at(x - 1, y - 1) -
            2 * at(x - 1, y) -
            at(x - 1, y + 1) +
            at(x + 1, y - 1) +
            2 * at(x + 1, y) +
            at(x + 1, y + 1);
        final gy =
            -at(x - 1, y - 1) -
            2 * at(x, y - 1) -
            at(x + 1, y - 1) +
            at(x - 1, y + 1) +
            2 * at(x, y + 1) +
            at(x + 1, y + 1);
        out.data[y * w + x] = (math.sqrt(gx * gx + gy * gy) * scale / 4)
            .round()
            .clamp(0, 255);
      }
    }
    return out;
  }

  static VImage _minMax(VImage src, int size, bool max) {
    final g = src.toGray();
    final w = g.width, h = g.height, r = size ~/ 2;
    final tmp = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var v = max ? 0 : 255;
        for (var i = -r; i <= r; i++) {
          final p = g.data[y * w + (x + i).clamp(0, w - 1)];
          v = max ? math.max(v, p) : math.min(v, p);
        }
        tmp[y * w + x] = v;
      }
    }
    final out = VImage(w, h, 1);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var v = max ? 0 : 255;
        for (var i = -r; i <= r; i++) {
          final p = tmp[(y + i).clamp(0, h - 1) * w + x];
          v = max ? math.max(v, p) : math.min(v, p);
        }
        out.data[y * w + x] = v;
      }
    }
    return out;
  }

  static VImage morphology(VImage src, String op, int size) => switch (op) {
    'Erode' => _minMax(src, size, false),
    'Dilate' => _minMax(src, size, true),
    'Open' => _minMax(_minMax(src, size, false), size, true),
    _ => _minMax(_minMax(src, size, true), size, false),
  };

  static VImage crop(VImage src, ui.Rect r) {
    final x0 = r.left.round().clamp(0, src.width - 1);
    final y0 = r.top.round().clamp(0, src.height - 1);
    final x1 = r.right.round().clamp(x0 + 1, src.width);
    final y1 = r.bottom.round().clamp(y0 + 1, src.height);
    final out = VImage(x1 - x0, y1 - y0, src.channels);
    for (var y = y0; y < y1; y++) {
      final from = (y * src.width + x0) * src.channels;
      out.data.setRange(
        (y - y0) * out.width * src.channels,
        (y - y0 + 1) * out.width * src.channels,
        src.data,
        from,
      );
    }
    return out;
  }

  static List<int> histogram(VImage src) {
    final g = src.toGray();
    final bins = List<int>.filled(256, 0);
    for (final v in g.data) {
      bins[v]++;
    }
    return bins;
  }

  /// Connected components (4-connectivity) of a binary image.
  static List<ui.Rect> blobs(VImage binary, double minArea, double maxArea) {
    final g = binary.toGray();
    final w = g.width, h = g.height;
    final seen = Uint8List(w * h);
    final out = <ui.Rect>[];
    final stack = <int>[];
    for (var start = 0; start < w * h; start++) {
      if (seen[start] != 0 || g.data[start] < 128) continue;
      var area = 0, minX = w, minY = h, maxX = 0, maxY = 0;
      stack.add(start);
      seen[start] = 1;
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        area++;
        final x = p % w, y = p ~/ w;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        for (final q in [p - 1, p + 1, p - w, p + w]) {
          if (q < 0 || q >= w * h) continue;
          if ((q == p - 1 && x == 0) || (q == p + 1 && x == w - 1)) continue;
          if (seen[q] == 0 && g.data[q] >= 128) {
            seen[q] = 1;
            stack.add(q);
          }
        }
      }
      if (area >= minArea && area <= maxArea) {
        out.add(
          ui.Rect.fromLTRB(
            minX.toDouble(),
            minY.toDouble(),
            maxX + 1.0,
            maxY + 1.0,
          ),
        );
      }
    }
    return out;
  }

  /// RGB copy of [src] with [boxes] outlined.
  static VImage drawBoxes(VImage src, List<ui.Rect> boxes) {
    final base = src.channels == 3 ? src : _grayToRgb(src);
    final out = VImage(
      base.width,
      base.height,
      3,
      Uint8List.fromList(base.data),
    );
    void px(int x, int y) {
      if (x < 0 || y < 0 || x >= out.width || y >= out.height) return;
      final i = (y * out.width + x) * 3;
      out.data[i] = 255;
      out.data[i + 1] = 170;
      out.data[i + 2] = 0;
    }

    for (final b in boxes) {
      for (var x = b.left.toInt(); x < b.right; x++) {
        px(x, b.top.toInt());
        px(x, b.bottom.toInt() - 1);
      }
      for (var y = b.top.toInt(); y < b.bottom; y++) {
        px(b.left.toInt(), y);
        px(b.right.toInt() - 1, y);
      }
    }
    return out;
  }

  static VImage _grayToRgb(VImage g) {
    final out = VImage(g.width, g.height, 3);
    for (var i = 0; i < g.length; i++) {
      out.data[i * 3] = out.data[i * 3 + 1] = out.data[i * 3 + 2] = g.data[i];
    }
    return out;
  }

  static VImage colorize(VImage src, String map) {
    final g = src.toGray();
    final table = [
      for (var i = 0; i < 256; i++) ColorMapParam.sample(map, i / 255),
    ];
    final out = VImage(g.width, g.height, 3);
    for (var i = 0; i < g.length; i++) {
      final c = table[g.data[i]];
      out.data[i * 3] = (c.r * 255).round();
      out.data[i * 3 + 1] = (c.g * 255).round();
      out.data[i * 3 + 2] = (c.b * 255).round();
    }
    return out;
  }

  static double mean(VImage src) {
    final g = src.toGray();
    var s = 0;
    for (final v in g.data) {
      s += v;
    }
    return s / g.length;
  }
}
