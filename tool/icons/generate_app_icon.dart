// Generates the launcher PNGs from the in-app HTBizLogo painter.
// Run with: flutter test tool/icons/generate_app_icon.dart
//
// This is a generator, not a test. It lived in test/ and so ran on every
// `flutter test`, rewriting the committed PNGs below as a side effect — which
// is why the launcher icons kept showing up as modified in git.
//
// Outputs:
//   assets/icon/app_icon.png             — full 1024x1024 logo
//   assets/icon/app_icon_foreground.png  — 1024x1024 foreground (palm disc only)
//   assets/icon/app_icon_background.png  — 1024x1024 solid Haiti blue background

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _haitiBlue = Color(0xFF00209F);
const _haitiRed = Color(0xFFD21034);
const _haitiGold = Color(0xFFE8A838);

void _paintFullLogo(Canvas canvas, double s) {
  // Top half blue, bottom half red
  canvas.drawRect(Rect.fromLTWH(0, 0, s, s / 2), Paint()..color = _haitiBlue);
  canvas.drawRect(
      Rect.fromLTWH(0, s / 2, s, s / 2), Paint()..color = _haitiRed);

  // Center white disc + palm
  final c = Offset(s / 2, s / 2);
  final r = s * 0.32;
  canvas.drawCircle(c, r, Paint()..color = Colors.white);
  _paintPalm(canvas, c, r);

  // Gold ring
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..color = _haitiGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.018,
  );
}

void _paintForeground(Canvas canvas, double s) {
  // Adaptive icon foreground: just the disc + palm centered, no flag bg
  final c = Offset(s / 2, s / 2);
  final r = s * 0.32;
  canvas.drawCircle(c, r, Paint()..color = Colors.white);
  _paintPalm(canvas, c, r);
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..color = _haitiGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.018,
  );
}

void _paintPalm(Canvas canvas, Offset c, double r) {
  final trunkPaint = Paint()
    ..color = const Color(0xFF6B3F1B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.18
    ..strokeCap = StrokeCap.round;

  final trunk = Path()
    ..moveTo(c.dx + r * 0.05, c.dy + r * 0.7)
    ..quadraticBezierTo(
      c.dx - r * 0.1,
      c.dy + r * 0.2,
      c.dx + r * 0.05,
      c.dy - r * 0.15,
    );
  canvas.drawPath(trunk, trunkPaint);

  final frondPaint = Paint()
    ..color = const Color(0xFF1E8449)
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.13
    ..strokeCap = StrokeCap.round;

  final top = Offset(c.dx + r * 0.05, c.dy - r * 0.18);
  final fronds = <List<Offset>>[
    [
      top,
      Offset(c.dx - r * 0.55, c.dy - r * 0.55),
      Offset(c.dx - r * 0.85, c.dy - r * 0.35)
    ],
    [
      top,
      Offset(c.dx - r * 0.2, c.dy - r * 0.75),
      Offset(c.dx - r * 0.15, c.dy - r * 1.0)
    ],
    [
      top,
      Offset(c.dx + r * 0.35, c.dy - r * 0.75),
      Offset(c.dx + r * 0.55, c.dy - r * 0.95)
    ],
    [
      top,
      Offset(c.dx + r * 0.6, c.dy - r * 0.35),
      Offset(c.dx + r * 0.95, c.dy - r * 0.15)
    ],
    [
      top,
      Offset(c.dx + r * 0.45, c.dy + r * 0.0),
      Offset(c.dx + r * 0.85, c.dy + r * 0.2)
    ],
    [
      top,
      Offset(c.dx - r * 0.4, c.dy - r * 0.25),
      Offset(c.dx - r * 0.7, c.dy + r * 0.05)
    ],
  ];
  for (final f in fronds) {
    final p = Path()..moveTo(f[0].dx, f[0].dy);
    p.quadraticBezierTo(f[1].dx, f[1].dy, f[2].dx, f[2].dy);
    canvas.drawPath(p, frondPaint);
  }

  canvas.drawCircle(
    Offset(c.dx + r * 0.05, c.dy - r * 0.25),
    r * 0.18,
    Paint()..color = _haitiGold.withValues(alpha: 0.6),
  );
}

Future<void> _renderToFile(
  String relativePath,
  void Function(Canvas, double) painter, {
  int size = 1024,
  Color? background,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
  );
  if (background != null) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = background,
    );
  }
  painter(canvas, size.toDouble());
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(relativePath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate launcher icon PNGs from HTBizLogo painter', () async {
    await _renderToFile('assets/icon/app_icon.png', _paintFullLogo);
    await _renderToFile(
      'assets/icon/app_icon_foreground.png',
      _paintForeground,
    );
    await _renderToFile(
      'assets/icon/app_icon_background.png',
      (canvas, s) {},
      background: _haitiBlue,
    );
  });
}
