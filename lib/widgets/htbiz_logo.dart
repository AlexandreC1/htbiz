import 'package:flutter/material.dart';

/// HTBIZ brand mark.
///
/// Redesigned: no red, no flag split. Instead, a refined rounded-square
/// badge with a deep-ocean-to-gold gradient, a subtle inner glow, and a
/// stylized "H" monogram with a storefront underline — reading as a
/// trustworthy business directory brand.
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

  // Brand palette — ocean/teal -> gold, Haiti-inspired without the flag.
  static const Color oceanDeep = Color(0xFF0E3A5C);
  static const Color oceanMid = Color(0xFF1B4F72);
  static const Color tealAccent = Color(0xFF0E8A7E);
  static const Color goldAccent = Color(0xFFE8A838);
  static const Color goldHighlight = Color(0xFFF6C65B);

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(size * 0.26);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          size: Size(size, size),
          painter: _HTBizLogoPainter(),
        ),
      ),
    );
  }
}

class _HTBizLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);

    // 1) Base gradient — deep ocean in the top-left to a warm gold toward
    // the bottom-right, with a teal mid-stop for depth.
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          HTBizLogo.oceanDeep,
          HTBizLogo.oceanMid,
          HTBizLogo.tealAccent,
          HTBizLogo.goldAccent,
        ],
        stops: [0.0, 0.45, 0.75, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    // 2) Soft radial highlight in the top-left for dimension.
    final highlight = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.6, -0.6),
        radius: 1.1,
        colors: [
          Colors.white.withValues(alpha: 0.28),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, highlight);

    // 3) Subtle diagonal sheen across the middle.
    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.35, 0.5, 0.65],
      ).createShader(rect);
    canvas.drawRect(rect, sheen);

    // 4) Gold "H" monogram in the center.
    _drawMonogram(canvas, w, h);

    // 5) Storefront underline bar — reads as a shop awning / business cue.
    _drawStorefrontBar(canvas, w, h);

    // 6) Thin inner border for a minted look.
    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012;
    canvas.drawRect(
      Rect.fromLTWH(
          w * 0.02, h * 0.02, w - w * 0.04, h - h * 0.04),
      border,
    );
  }

  void _drawMonogram(Canvas canvas, double w, double h) {
    final cx = w / 2;
    final cy = h / 2;

    // Dimensions for the H
    final hWidth = w * 0.44;
    final hHeight = h * 0.44;
    final strokeW = w * 0.10;

    final left = cx - hWidth / 2;
    final right = cx + hWidth / 2;
    final top = cy - hHeight / 2;
    final bottom = cy + hHeight / 2;

    // Shadow / outline pass for legibility
    final outlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [HTBizLogo.goldHighlight, HTBizLogo.goldAccent],
      ).createShader(Rect.fromLTRB(left, top, right, bottom));

    // Left vertical
    final leftBar = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, strokeW, hHeight),
      Radius.circular(strokeW * 0.35),
    );
    // Right vertical
    final rightBar = RRect.fromRectAndRadius(
      Rect.fromLTWH(right - strokeW, top, strokeW, hHeight),
      Radius.circular(strokeW * 0.35),
    );
    // Crossbar
    final crossbar = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          left + strokeW * 0.2, cy - strokeW * 0.45,
          hWidth - strokeW * 0.4, strokeW * 0.9),
      Radius.circular(strokeW * 0.35),
    );

    // Draw outline (slightly offset to create subtle depth)
    final offset = strokeW * 0.06;
    canvas.save();
    canvas.translate(offset, offset);
    canvas.drawRRect(leftBar, outlinePaint);
    canvas.drawRRect(rightBar, outlinePaint);
    canvas.drawRRect(crossbar, outlinePaint);
    canvas.restore();

    // Fill
    canvas.drawRRect(leftBar, fillPaint);
    canvas.drawRRect(rightBar, fillPaint);
    canvas.drawRRect(crossbar, fillPaint);
  }

  void _drawStorefrontBar(Canvas canvas, double w, double h) {
    // A thin gold bar beneath the monogram suggesting a storefront awning.
    final barWidth = w * 0.50;
    final barHeight = h * 0.045;
    final left = (w - barWidth) / 2;
    final top = h * 0.74;

    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, barWidth, barHeight),
      Radius.circular(barHeight * 0.5),
    );
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          HTBizLogo.goldAccent.withValues(alpha: 0.0),
          HTBizLogo.goldHighlight,
          HTBizLogo.goldAccent.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(left, top, barWidth, barHeight));
    canvas.drawRRect(bar, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
