// Superseded by tool/icons/generate_app_icon.dart, which produces the
// foreground and background layers this one does not.
//
// Kept for reference only. It hangs: pumpAndSettle() never settles here, so as
// a member of the test suite it timed out after ten minutes on every run.
// Run deliberately, if at all:  flutter test tool/icons/generate_icon_legacy.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htbiz/widgets/htbiz_logo.dart';

void main() {
  testWidgets('Generate app icon PNG from HTBizLogo', (tester) async {
    // Build the logo widget inside a RepaintBoundary
    final key = GlobalKey();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: const SizedBox(
              width: 1024,
              height: 1024,
              child: HTBizLogo(size: 1024),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Capture to image
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    expect(byteData, isNotNull);

    final bytes = byteData!.buffer.asUint8List();

    // Write icon files
    final iconFile = File('assets/icon/app_icon.png');
    iconFile.writeAsBytesSync(bytes);

    final fgFile = File('assets/icon/app_icon_foreground.png');
    fgFile.writeAsBytesSync(bytes);

    // ignore: avoid_print
    print('Generated app_icon.png: ${bytes.length} bytes');
  });
}
