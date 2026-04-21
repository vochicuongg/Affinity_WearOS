// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — waveform_painter.dart
//  Real-time amplitude bar visualiser for the circular Wear OS screen.
//
//  Layout: N symmetrical vertical bars centred horizontally.
//  Each bar is drawn top-and-bottom from the horizontal midline.
//  Inactive bars are dimmed; the newest bar is full opacity + glow colour.
//  The history length determines how many bars are visible.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:math' as math;

import 'package:flutter/material.dart';

// ── WaveformData (immutable snapshot passed to the painter) ───────────────────

class WaveformData {
  const WaveformData({
    required this.amplitudes,
    required this.isActive,
    this.accentColor = const Color(0xFFE8305A),
  });

  /// List of normalised amplitude values in [0..1]. Newest is last.
  final List<double> amplitudes;

  /// Whether recording/playback is currently in progress.
  final bool isActive;

  /// Colour used for the active bars.
  final Color accentColor;

  WaveformData copyWith({
    List<double>? amplitudes,
    bool? isActive,
    Color? accentColor,
  }) =>
      WaveformData(
        amplitudes:  amplitudes  ?? this.amplitudes,
        isActive:    isActive    ?? this.isActive,
        accentColor: accentColor ?? this.accentColor,
      );
}

// ── WaveformPainter ───────────────────────────────────────────────────────────

class WaveformPainter extends CustomPainter {
  const WaveformPainter({required this.data});
  final WaveformData data;

  static const int _maxBars = 32;
  static const double _barWidth  = 3.0;
  static const double _barGap    = 2.0;
  static const double _minHeight = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.amplitudes.isEmpty) return;

    final cx = size.width  / 2;
    final cy = size.height / 2;

    // Circular clipping so bars don't overflow the round watch bezel
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: size.width, height: size.height),
        Radius.circular(size.width / 2),
      ),
    );

    final amps = data.amplitudes.length > _maxBars
        ? data.amplitudes.sublist(data.amplitudes.length - _maxBars)
        : data.amplitudes;

    final totalW  = amps.length * (_barWidth + _barGap) - _barGap;
    final startX  = cx - totalW / 2;
    final maxBarH = cy * 0.75; // bar can be at most 75% of half-height

    for (var i = 0; i < amps.length; i++) {
      final amp     = amps[i];
      final barH    = math.max(_minHeight, amp * maxBarH);
      final x       = startX + i * (_barWidth + _barGap);
      final progress = i / amps.length; // 0 = oldest, 1 = newest

      // Opacity fades from 0.25 (oldest) to 1.0 (newest)
      final opacity = data.isActive
          ? 0.25 + 0.75 * progress
          : 0.15 + 0.35 * progress;

      final paint = Paint()
        ..color = data.accentColor.withValues(alpha: opacity)
        ..strokeWidth = _barWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      // Glow on the latest bar
      if (i == amps.length - 1 && data.isActive) {
        final glowPaint = Paint()
          ..color = data.accentColor.withValues(alpha: 0.25)
          ..strokeWidth = _barWidth * 3
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawLine(
          Offset(x + _barWidth / 2, cy - barH),
          Offset(x + _barWidth / 2, cy + barH),
          glowPaint,
        );
      }

      // Draw symmetrical bar (top + bottom from centre)
      canvas.drawLine(
        Offset(x + _barWidth / 2, cy - barH),
        Offset(x + _barWidth / 2, cy + barH),
        paint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) =>
      oldDelegate.data.amplitudes != data.amplitudes ||
      oldDelegate.data.isActive   != data.isActive;
}

// ── WaveformWidget (stateless, wraps CustomPaint) ─────────────────────────────

class WaveformWidget extends StatelessWidget {
  const WaveformWidget({
    super.key,
    required this.data,
    this.width  = 160,
    this.height = 60,
  });

  final WaveformData data;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:  width,
      height: height,
      child: CustomPaint(painter: WaveformPainter(data: data)),
    );
  }
}
