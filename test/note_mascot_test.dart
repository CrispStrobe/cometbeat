// The note mascot renders in every mood and animates on a mood change without
// throwing (the geometry is best eyeballed live; this guards the plumbing).

import 'package:comet_beat/shared/widgets/note_mascot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mood in NoteMascotMood.values) {
    testWidgets('renders in $mood mood', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: NoteMascot(mood: mood))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NoteMascot), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reacts to a mood change (idle -> happy) without throwing',
      (tester) async {
    Widget app(NoteMascotMood m) =>
        MaterialApp(home: Scaffold(body: Center(child: NoteMascot(mood: m))));

    await tester.pumpWidget(app(NoteMascotMood.idle));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(NoteMascotMood.happy)); // triggers the hop
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
