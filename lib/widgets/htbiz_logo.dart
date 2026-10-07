import 'package:flutter/material.dart';

/// HTBIZ brand mark.
///
/// A flat gold "H" on deep ocean, with a crossbar that floats free of the
/// stems. Two colours, no gradients or effects. The geometry matches
/// generate_icon.js, which renders the launcher icons and splash images, so
/// change both together.
class HTBizLogo extends StatelessWidget {
  final double size;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? shadows;

  const HTBizLogo({
    super.key,
    this.size = 96,
    this.borderRadius,
    this.shadows,
  });

  static const Color oceanDeep = Color(0xFF0E3A5C);
  static const Color goldAccent = Color(0xFFE8A838);

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(size * 0.22);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: oceanDeep,
        borderRadius: radius,
        boxShadow: shadows,
      ),
      child: CustomPaint(
        size: Size(size, size),
        painter: const _HTBizLogoPainter(),
      ),
    );
  }
}

class _HTBizLogoPainter extends CustomPainter {
  const _HTBizLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;

    // Same fractions as generate_icon.js.
    final boxW = s * 0.46;
    final boxH = s * 0.42;
    final stem = s * 0.104;
    final bar = s * 0.09;
    final gap = s * 0.016;
    final corner = Radius.circular(s * 0.018);
    final left = (s - boxW) / 2;
    final top = (s - boxH) / 2;
    final barTop = s / 2 - bar / 2 - s * 0.008;

    final paint = Paint()..color = HTBizLogo.goldAccent;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, top, stem, boxH), corner),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(left + boxW - stem, top, stem, boxH), corner),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + stem + gap, barTop, boxW - 2 * (stem + gap), bar),
        corner,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HTBizLogoPainter oldDelegate) => false;
}
