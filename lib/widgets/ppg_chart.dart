import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Real-time PPG waveform chart with gradient fill.
class PpgChart extends StatelessWidget {
  final List<double> data;
  final int maxPoints;
  final Color lineColor;
  final double height;

  const PpgChart({
    super.key,
    required this.data,
    this.maxPoints = 150,
    this.lineColor = const Color(0xFFff6b6b),
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF1a1a2e).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          size: Size.infinite,
          painter: _PpgPainter(
            data: data,
            maxPoints: maxPoints,
            lineColor: lineColor,
          ),
        ),
      ),
    );
  }
}

class _PpgPainter extends CustomPainter {
  final List<double> data;
  final int maxPoints;
  final Color lineColor;

  _PpgPainter({
    required this.data,
    required this.maxPoints,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) {
      _drawEmptyState(canvas, size);
      return;
    }

    // Draw grid lines
    _drawGrid(canvas, size);

    // Normalize data to fit chart
    final displayData = data.length > maxPoints
        ? data.sublist(data.length - maxPoints)
        : data;

    if (displayData.length < 2) return;

    final minVal = displayData.reduce(math.min);
    final maxVal = displayData.reduce(math.max);
    final range = maxVal - minVal;
    if (range < 0.001) return;

    final padding = range * 0.1;
    final adjMin = minVal - padding;
    final adjMax = maxVal + padding;
    final adjRange = adjMax - adjMin;

    // Build path
    final path = Path();
    final fillPath = Path();

    final stepX = size.width / (maxPoints - 1);
    final startOffset = maxPoints - displayData.length;

    for (int i = 0; i < displayData.length; i++) {
      final x = (startOffset + i) * stepX;
      final y = size.height - ((displayData[i] - adjMin) / adjRange) * size.height * 0.85 - size.height * 0.075;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        // Smooth curve using cubic bezier
        final prevX = (startOffset + i - 1) * stepX;
        final prevY = size.height - ((displayData[i - 1] - adjMin) / adjRange) * size.height * 0.85 - size.height * 0.075;
        final controlX1 = prevX + (x - prevX) * 0.5;
        final controlX2 = x - (x - prevX) * 0.5;

        path.cubicTo(controlX1, prevY, controlX2, y, x, y);
        fillPath.cubicTo(controlX1, prevY, controlX2, y, x, y);
      }
    }

    // Close fill path
    final lastX = (startOffset + displayData.length - 1) * stepX;
    fillPath.lineTo(lastX, size.height);
    fillPath.close();

    // Draw gradient fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.3),
          lineColor.withValues(alpha: 0.05),
          lineColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // Draw line with glow effect
    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.4)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawPath(path, glowPaint);

    // Draw main line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);

    // Draw leading dot
    if (displayData.isNotEmpty) {
      final lastY = size.height - ((displayData.last - adjMin) / adjRange) * size.height * 0.85 - size.height * 0.075;
      final dotPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(lastX, lastY), 4, dotPaint);

      final dotGlow = Paint()
        ..color = lineColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(lastX, lastY), 6, dotGlow);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;

    // Horizontal lines
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical lines
    for (int i = 1; i < 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Place finger on camera',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.3),
          fontSize: 14,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _PpgPainter oldDelegate) {
    return oldDelegate.data.length != data.length ||
        (data.isNotEmpty && oldDelegate.data.isNotEmpty && oldDelegate.data.last != data.last);
  }
}
