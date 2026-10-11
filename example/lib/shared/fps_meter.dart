import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Frames-per-second counter based on a ticker (works on every platform,
/// including the web where frame timings are not reported).
class FpsMeter extends StatefulWidget {
  const FpsMeter({super.key, this.extra});

  /// Additional lines shown under the FPS value.
  final List<String> Function()? extra;

  @override
  State<FpsMeter> createState() => _FpsMeterState();
}

class _FpsMeterState extends State<FpsMeter>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick)..start();
  Duration _windowStart = Duration.zero;
  Duration _last = Duration.zero;
  int _frames = 0;
  double _fps = 0;
  double _worstMs = 0;
  double _windowWorst = 0;

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1000;
    _last = elapsed;
    if (dt > _windowWorst) _windowWorst = dt;
    _frames++;
    final window = elapsed - _windowStart;
    if (window >= const Duration(milliseconds: 500)) {
      setState(() {
        _fps = _frames * 1e6 / window.inMicroseconds;
        _worstMs = _windowWorst;
      });
      _frames = 0;
      _windowWorst = 0;
      _windowStart = elapsed;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _fps >= 55
        ? Colors.greenAccent
        : (_fps >= 30 ? Colors.amberAccent : Colors.redAccent);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_fps.toStringAsFixed(0)} FPS',
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text('worst frame ${_worstMs.toStringAsFixed(1)} ms'),
              ...?widget.extra?.call().map(Text.new),
            ],
          ),
        ),
      ),
    );
  }
}
