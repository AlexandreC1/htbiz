import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htbiz/widgets/business_stats_grid.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('dashboard stats fit a small phone at text scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
        data: MediaQueryData(
            size: const Size(320, 900), textScaler: TextScaler.linear(scale)),
        child: const Scaffold(
            body: SingleChildScrollView(
                child: Padding(
          padding: EdgeInsets.all(16),
          child: BusinessStatsGrid(stats: [
            BusinessStat(Icons.store, '12', 'Vos entreprises'),
            BusinessStat(Icons.reviews, '120', 'Nombre total d’avis'),
            BusinessStat(Icons.star, '4.5', 'Note moyenne'),
            BusinessStat(Icons.favorite, '40', 'Favoris'),
          ]),
        ))),
      )));
      expect(tester.takeException(), isNull);
      expect(find.text('Nombre total d’avis'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });
  }
}
