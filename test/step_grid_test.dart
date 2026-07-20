// The shared step-grid / mini piano-roll widget.

import 'package:comet_beat/shared/widgets/step_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('read-only grid builds and paints its cells', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 320,
          child: StepGridView(
            cells: [StepCell(2, 0), StepCell(1, 4)],
            steps: 16,
            percussive: true,
          ),
        ),
      ),
    );
    expect(find.byType(StepGridView), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('percussive tap reports the lane and step', (tester) async {
    int? row, step;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 320,
          child: StepGridView(
            cells: const [],
            steps: 8,
            percussive: true,
            onToggle: (r, s) {
              row = r;
              step = s;
            },
          ),
        ),
      ),
    );
    // Tap the top-left cell → hat lane (row 0), step 0.
    await tester.tapAt(
        tester.getTopLeft(find.byType(StepGridView)) + const Offset(4, 4));
    expect(row, 0);
    expect(step, 0);
  });

  testWidgets('melodic tap maps the y-row to a melodyRows pitch',
      (tester) async {
    int? row;
    const rows = [60, 62, 64, 65, 67, 69, 71, 72]; // C major octave
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 320,
          child: StepGridView(
            cells: const [],
            steps: 8,
            melodyRows: rows,
            onToggle: (r, s) => row = r,
          ),
        ),
      ),
    );
    // The very top row is the highest pitch (72).
    await tester.tapAt(
      tester.getTopLeft(find.byType(StepGridView)) + const Offset(4, 2),
    );
    expect(row, 72);
  });
}
