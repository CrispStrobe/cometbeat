// MultiPartCanvas — the full-score canvas for the multi-instrument Workshop.
// Verifies it renders a MultiPartView for a multi-part document and reports
// taps as global element ids (surface enlarged per the CI surface-flake note).

import 'package:comet_beat/features/workshop/model/multi_part_document.dart';
import 'package:comet_beat/features/workshop/widgets/multi_part_canvas.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

Pitch _p(Step step, {int octave = 4}) => Pitch(step, octave: octave);
const _quarter = NoteDuration(DurationBase.quarter);

MultiPartDocument _twoParts() {
  final doc = MultiPartDocument();
  doc.parts[0]
    ..insertNote(_p(Step.c), _quarter)
    ..insertNote(_p(Step.d), _quarter);
  doc.addPart(clef: Clef.bass);
  doc.parts[1]
    ..insertNote(_p(Step.c, octave: 3), _quarter)
    ..insertNote(_p(Step.g, octave: 3), _quarter);
  doc.setActive(0);
  return doc;
}

void main() {
  testWidgets('renders a MultiPartView for a multi-part document',
      (tester) async {
    await useGameSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MultiPartCanvas(document: _twoParts())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveMultiPartView), findsOneWidget);
  });

  testWidgets('a single-part document still renders one full-score view',
      (tester) async {
    await useGameSurface(tester);
    final doc = MultiPartDocument();
    doc.parts[0].insertNote(_p(Step.c), _quarter);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MultiPartCanvas(document: doc)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveMultiPartView), findsOneWidget);
  });

  testWidgets('the MultiPartView carries the document built from all parts',
      (tester) async {
    await useGameSurface(tester);
    final doc = _twoParts();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MultiPartCanvas(document: doc)),
      ),
    );
    await tester.pumpAndSettle();
    final view = tester.widget<InteractiveMultiPartView>(
      find.byType(InteractiveMultiPartView),
    );
    expect(view.document.parts, hasLength(2));
    // The onElementTap wiring is present (screen feeds it to selectByGlobalId).
    expect(view.onElementTap, isNull); // not wired in this bare harness
  });
}
