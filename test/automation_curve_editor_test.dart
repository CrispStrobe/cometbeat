// The drawable automation curve. The point of this widget is that DRAGGING
// changes the data, so that's what's tested — not that it renders.

import 'package:comet_beat/core/audio/daw_timeline.dart'
    show DawAutomationPoint;
import 'package:comet_beat/features/games/composition/automation_curve_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pump an editor 400x160 logical px, spanning 0..1000 ms and 0..2.
Future<List<DawAutomationPoint>> _pump(
  WidgetTester tester,
  List<DawAutomationPoint> initial, {
  double min = 0,
  double max = 2,
}) async {
  var points = initial;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: StatefulBuilder(
              builder: (context, setState) => AutomationCurveEditor(
                points: points,
                min: min,
                max: max,
                timeMax: 1000,
                onChanged: (next) => setState(() => points = next),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return points;
}

/// Where the editor draws a point, in global coordinates.
Offset _at(
  WidgetTester tester,
  double ms,
  double value, {
  double min = 0,
  double max = 2,
}) {
  final box = tester.getRect(find.byType(AutomationCurveEditor));
  return Offset(
    box.left + ms / 1000 * box.width,
    box.top + (1 - (value - min) / (max - min)) * box.height,
  );
}

void main() {
  testWidgets('dragging a handle changes its time and value', (tester) async {
    var points = [
      const DawAutomationPoint(ms: 0, value: 1),
      const DawAutomationPoint(ms: 1000, value: 1),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: StatefulBuilder(
                builder: (context, setState) => AutomationCurveEditor(
                  points: points,
                  min: 0,
                  max: 2,
                  timeMax: 1000,
                  onChanged: (next) => setState(() => points = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Grab the first handle (0 ms, value 1 → left edge, vertical centre) and
    // drag it down: the value must fall.
    final from = _at(tester, 0, 1);
    await tester.dragFrom(from, const Offset(0, 40));
    await tester.pumpAndSettle();

    expect(points, hasLength(2));
    expect(points.first.value, lessThan(1));
    expect(points.first.value, greaterThanOrEqualTo(0));
  });

  testWidgets('a tap on empty canvas adds a point there', (tester) async {
    var points = [
      const DawAutomationPoint(ms: 0, value: 1),
      const DawAutomationPoint(ms: 1000, value: 1),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: StatefulBuilder(
                builder: (context, setState) => AutomationCurveEditor(
                  points: points,
                  min: 0,
                  max: 2,
                  timeMax: 1000,
                  onChanged: (next) => setState(() => points = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(_at(tester, 500, 0.5));
    await tester.pumpAndSettle();

    expect(points, hasLength(3));
    // Inserted in time order, at roughly where it was tapped.
    expect(points[1].ms, closeTo(500, 40));
    expect(points[1].value, closeTo(0.5, 0.15));
    expect(points[0].ms, lessThanOrEqualTo(points[1].ms));
    expect(points[1].ms, lessThanOrEqualTo(points[2].ms));
  });

  testWidgets('a long press removes a handle, but never below two',
      (tester) async {
    var points = [
      const DawAutomationPoint(ms: 0, value: 1),
      const DawAutomationPoint(ms: 500, value: 0.5),
      const DawAutomationPoint(ms: 1000, value: 1),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: StatefulBuilder(
                builder: (context, setState) => AutomationCurveEditor(
                  points: points,
                  min: 0,
                  max: 2,
                  timeMax: 1000,
                  onChanged: (next) => setState(() => points = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.longPressAt(_at(tester, 500, 0.5));
    await tester.pumpAndSettle();
    expect(points, hasLength(2));

    // A curve needs at least two points, so further removal is refused.
    await tester.longPressAt(_at(tester, 0, 1));
    await tester.pumpAndSettle();
    expect(points, hasLength(2));
  });

  testWidgets('a drag is clamped to the axes', (tester) async {
    var points = [
      const DawAutomationPoint(ms: 500, value: 1),
      const DawAutomationPoint(ms: 1000, value: 1),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: StatefulBuilder(
                builder: (context, setState) => AutomationCurveEditor(
                  points: points,
                  min: 0,
                  max: 2,
                  timeMax: 1000,
                  onChanged: (next) => setState(() => points = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Yank the first handle far past the top-left corner.
    await tester.dragFrom(_at(tester, 500, 1), const Offset(-900, -900));
    await tester.pumpAndSettle();

    for (final p in points) {
      expect(p.ms, inInclusiveRange(0, 1000));
      expect(p.value, inInclusiveRange(0, 2));
    }
  });

  testWidgets('renders an empty point list without throwing', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(AutomationCurveEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
