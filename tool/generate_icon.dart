// ignore_for_file: avoid_print
import 'dart:io';
// dart:ui is imported twice on purpose: unprefixed for the plain value types
// (Color, Rect, Paint...), and aliased for the names this script already
// qualifies (ui.Canvas, ui.Gradient). Without the unprefixed import every one
// of those types is undefined and `flutter analyze` fails on this file.
import 'dart:ui';
import 'dart:ui' as ui;

/// Brand palette — must match lib/widgets/htbiz_logo.dart
const Color oceanDeep = Color(0xFF0E3A5C);
const Color oceanMid = Color(0xFF1B4F72);
const Color tealAccent = Color(0xFF0E8A7E);
const Color goldAccent = Color(0xFFE8A838);
const Color goldHighlight = Color(0xFFF6C65B);

Color _white(double alpha) => Color.fromRGBO(255, 255, 255, alpha);
Color _black(double alpha) => Color.fromRGBO(0, 0, 0, alpha);

void _paint(ui.Canvas canvas, double w, double h) {
  final rect = Rect.fromLTWH(0, 0, w, h);

  // 1) Rounded-rect clip (26% radius like the widget)
  final radius = w * 0.26;
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
  canvas.clipRRect(rrect);

  // 2) Base gradient
  final basePaint = Paint()
    ..shader = ui.Gradient.linear(
      Offset.zero,
      const Offset(1, 1), // will be overridden by matrix
      [oceanDeep, oceanMid, tealAccent, goldAccent],
      [0.0, 0.45, 0.75, 1.0],
    );
  // Recreate with proper coordinates
  basePaint.shader = ui.Gradient.linear(
    Offset.zero,
    Offset(w, h),
    [oceanDeep, oceanMid, tealAccent, goldAccent],
    [0.0, 0.45, 0.75, 1.0],
  );
  canvas.drawRect(rect, basePaint);

  // 3) Radial highlight top-left
  final hlCenter = Offset(w * 0.2, h * 0.2);
  final highlight = Paint()
    ..shader = ui.Gradient.radial(
      hlCenter,
      w * 1.1,
      [_white(0.28), _white(0.0)],
    );
  canvas.drawRect(rect, highlight);

  // 4) Diagonal sheen
  final sheen = Paint()
    ..shader = ui.Gradient.linear(
      Offset.zero,
      Offset(w, h),
      [_white(0.0), _white(0.08), _white(0.0)],
      [0.35, 0.5, 0.65],
    );
  canvas.drawRect(rect, sheen);

  // 5) "H" monogram
  _drawMonogram(canvas, w, h);

  // 6) Storefront bar
  _drawStorefrontBar(canvas, w, h);

  // 7) Inner border
  final border = Paint()
    ..color = _white(0.12)
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * 0.012;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.02, h * 0.02, w - w * 0.04, h - h * 0.04),
      Radius.circular(radius * 0.88),
    ),
    border,
  );
}

void _drawMonogram(ui.Canvas canvas, double w, double h) {
  final cx = w / 2;
  final cy = h / 2;
  final hWidth = w * 0.44;
  final hHeight = h * 0.44;
  final strokeW = w * 0.10;
  final left = cx - hWidth / 2;
  final right = cx + hWidth / 2;
  final top = cy - hHeight / 2;
  final bottom = cy + hHeight / 2;

  final outlinePaint = Paint()
    ..color = _black(0.18)
    ..style = PaintingStyle.fill;

  final fillPaint = Paint()
    ..shader = ui.Gradient.linear(
      Offset(left, top),
      Offset(left, bottom),
      [goldHighlight, goldAccent],
    );

  final leftBar = RRect.fromRectAndRadius(
    Rect.fromLTWH(left, top, strokeW, hHeight),
    Radius.circular(strokeW * 0.35),
  );
  final rightBar = RRect.fromRectAndRadius(
    Rect.fromLTWH(right - strokeW, top, strokeW, hHeight),
    Radius.circular(strokeW * 0.35),
  );
  final crossbar = RRect.fromRectAndRadius(
    Rect.fromLTWH(
      left + strokeW * 0.2,
      cy - strokeW * 0.45,
      hWidth - strokeW * 0.4,
      strokeW * 0.9,
    ),
    Radius.circular(strokeW * 0.35),
  );

  // Shadow pass
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

void _drawStorefrontBar(ui.Canvas canvas, double w, double h) {
  final barWidth = w * 0.50;
  final barHeight = h * 0.045;
  final left = (w - barWidth) / 2;
  final top = h * 0.74;

  final bar = RRect.fromRectAndRadius(
    Rect.fromLTWH(left, top, barWidth, barHeight),
    Radius.circular(barHeight * 0.5),
  );

  final paint = Paint()
    ..shader = ui.Gradient.linear(
      Offset(left, top),
      Offset(left + barWidth, top),
      [
        goldAccent.withValues(alpha: 0.0),
        goldHighlight,
        goldAccent.withValues(alpha: 0.0),
      ],
    );
  canvas.drawRRect(bar, paint);
}

Future<void> main() async {
  const size = 1024.0;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

  _paint(canvas, size, size);

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

  if (byteData == null) {
    print('ERROR: Failed to encode image');
    exit(1);
  }

  final bytes = byteData.buffer.asUint8List();

  // Write main icon
  File('assets/icon/app_icon.png').writeAsBytesSync(bytes);
  print('Wrote assets/icon/app_icon.png (${bytes.length} bytes)');

  // Also write foreground (same image for adaptive icons)
  File('assets/icon/app_icon_foreground.png').writeAsBytesSync(bytes);
  print('Wrote assets/icon/app_icon_foreground.png');

  exit(0);
}
