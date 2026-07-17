// Melody doodle — a freehand contour quantised to one pentatonic note per beat
// and rendered to a real Score. The quantiser is pure, so most of this is a
// plain unit test; the widget test drives a real drag.

import 'package:comet_beat/features/games/composition/melody_doodle_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' show NoteElement, Score;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

MelodyDoodleTester _game(WidgetTester tester) =>
    tester.state<State<MelodyDoodleScreen>>(
      find.byType(MelodyDoodleScreen),
    ) as MelodyDoodleTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  group('doodleToColumns', () {
    const size = Size(80, 50); // 8 columns of 10px, 5 rows of 10px
    List<int?> quantise(List<Offset> points, [Size box = size]) =>
        doodleToColumns(points, box, columns: 8, rows: 5);

    test('an untouched box is all rests', () {
      expect(quantise(const []), List<int?>.filled(8, null));
    });

    test('the top of the box is row 0 (the highest note)', () {
      // One point in column 0, near the top.
      expect(quantise(const [Offset(5, 1)]).first, 0);
    });

    test('the bottom of the box is the lowest row', () {
      expect(quantise(const [Offset(5, 49)]).first, 4);
    });

    test('a column averages its points rather than taking the last', () {
      // Two points in column 0: the very top and the very bottom → the middle.
      expect(
        quantise(const [Offset(5, 0), Offset(5, 50)]).first,
        2,
        reason: 'averaged to the middle row',
      );
    });

    test('only the crossed columns sound; the rest stay rests', () {
      // Points in columns 0 and 7 only.
      final cols = quantise(const [Offset(5, 5), Offset(75, 5)]);
      expect(cols[0], isNotNull);
      expect(cols[7], isNotNull);
      expect(cols.sublist(1, 7), everyElement(isNull));
    });

    test('points are clamped inside the box (no out-of-range rows)', () {
      final cols = quantise(const [Offset(-10, -10), Offset(999, 999)]);
      expect(cols.first, 0);
      expect(cols.last, 4);
    });

    test('a zero-size box is all rests (no divide-by-zero)', () {
      final cols = quantise(const [Offset(1, 1)], Size.zero);
      expect(cols, hasLength(8));
      expect(cols, everyElement(isNull));
    });
  });

  testWidgets('drawing a line makes notes and enables Play', (tester) async {
    await pumpGame(tester, const MelodyDoodleScreen());
    await tester.pump(); // let the canvas report its size

    final game = _game(tester);
    expect(game.columns, everyElement(isNull), reason: 'starts empty');
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final play = find.widgetWithText(FilledButton, l10n.myMelodyPlay);
    expect(tester.widget<FilledButton>(play).onPressed, isNull);

    // Drag a line across the canvas.
    final canvas = find.byKey(const ValueKey('melody-doodle-canvas'));
    await tester.drag(canvas, const Offset(300, 0), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      game.columns.any((r) => r != null),
      isTrue,
      reason: 'the drag left notes behind',
    );
    // Those notes are real notation.
    expect(game.score, isA<Score>());
    expect(
      game.score.measures.expand((m) => m.elements).whereType<NoteElement>(),
      isNotEmpty,
    );
    // Play is now live.
    expect(tester.widget<FilledButton>(play).onPressed, isNotNull);
  });
}
