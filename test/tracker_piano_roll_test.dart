// WS-T4 — one channel as a piano roll.
//
// A tracker cell says a note STARTS and says nothing about when it stops, so
// where a note ENDS is the entire logic of this view. Getting it wrong is
// invisible in a picture and obvious in a test, which is why the computation is
// a pure function and why these tests are arithmetic over it rather than
// screenshots.

import 'dart:async';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/composition/tracker_piano_roll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// A channel of [rows] empty cells, so each test can place only what it means.
List<TrackerCell> _empty(int rows) =>
    List.generate(rows, (_) => const TrackerCell());

List<TrackerCell> _withNote(
  List<TrackerCell> cells,
  int row,
  int midi, {
  int instrument = 0,
}) {
  final out = [...cells];
  out[row] = TrackerCell(midi: midi, instrument: instrument);
  return out;
}

List<TrackerCell> _withKeyOff(List<TrackerCell> cells, int row) {
  final out = [...cells];
  out[row] = const TrackerCell(keyOff: true);
  return out;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BeatBridge.instance.clear();
    MelodyBridge.instance.clear();
  });

  group('where a note ends', () {
    test('a lone note runs to the end of the pattern', () {
      // Nothing stops it, so it sounds for the rest of what we can see.
      final notes = rollNotesFor(_withNote(_empty(16), 4, 60));
      expect(notes, hasLength(1));
      expect(notes.single.startRow, 4);
      expect(notes.single.endRow, 16);
      expect(notes.single.midi, 60);
    });

    test('the NEXT note ends the one before it', () {
      // A tracker channel is monophonic: the new note takes the voice. Drawing
      // them overlapping would show a chord that never sounds.
      var cells = _withNote(_empty(16), 0, 60);
      cells = _withNote(cells, 8, 64);
      final notes = rollNotesFor(cells);
      expect(notes, hasLength(2));
      expect(notes.first.endRow, 8);
      expect(notes.last.startRow, 8);
      expect(notes.last.endRow, 16);
    });

    test('a key-off ends it and starts nothing', () {
      final cells = _withKeyOff(_withNote(_empty(16), 2, 60), 6);
      final notes = rollNotesFor(cells);
      expect(notes, hasLength(1));
      expect(notes.single.endRow, 6);
    });

    test('a key-off with nothing sounding is not a note', () {
      expect(rollNotesFor(_withKeyOff(_empty(8), 3)), isEmpty);
    });

    test('the same pitch re-struck is TWO notes, not one long one', () {
      // The onset is the musical event. Merging them would erase the rhythm,
      // which is the thing this view exists to show.
      var cells = _withNote(_empty(8), 0, 60);
      cells = _withNote(cells, 4, 60);
      final notes = rollNotesFor(cells);
      expect(notes, hasLength(2));
      expect(notes.first.endRow, 4);
    });

    test('notes on consecutive rows each stay visible', () {
      // A zero-length run cannot be drawn; each onset must still be one row.
      var cells = _withNote(_empty(4), 0, 60);
      cells = _withNote(cells, 1, 62);
      cells = _withNote(cells, 2, 64);
      final notes = rollNotesFor(cells);
      expect(notes, hasLength(3));
      for (final note in notes) {
        expect(note.endRow, greaterThan(note.startRow), reason: '${note.midi}');
      }
    });
  });

  group('degenerate input', () {
    test('an empty channel has no notes', () {
      expect(rollNotesFor(_empty(64)), isEmpty);
      expect(rollNotesFor(const []), isEmpty);
    });

    test('a note on the very last row still gets a length', () {
      final notes = rollNotesFor(_withNote(_empty(8), 7, 60));
      expect(notes, hasLength(1));
      expect(notes.single.endRow, 8);
    });
  });

  group('the pitch range', () {
    test('it spans the notes with air above and below', () {
      var cells = _withNote(_empty(8), 0, 60);
      cells = _withNote(cells, 4, 67);
      final range = rollRange(rollNotesFor(cells))!;
      expect(range.lowMidi, lessThan(60));
      expect(range.highMidi, greaterThan(67));
    });

    test('a single pitch still gets a drawable range', () {
      // Without padding this would be one lane tall and unreadable.
      final range = rollRange(rollNotesFor(_withNote(_empty(8), 0, 60)))!;
      expect(range.highMidi - range.lowMidi, greaterThanOrEqualTo(4));
    });

    test('no notes means no range — the caller says so instead of drawing', () {
      // An empty grid reads as broken; "no notes on this channel" does not.
      expect(rollRange(const []), isNull);
    });
  });

  group('it carries the instrument through', () {
    test('each run keeps the instrument its onset named', () {
      var cells = _withNote(_empty(8), 0, 60, instrument: 3);
      cells = _withNote(cells, 4, 62, instrument: 7);
      final notes = rollNotesFor(cells);
      expect(notes.first.instrument, 3);
      expect(notes.last.instrument, 7);
    });
  });

  group('the door is offered', () {
    // A view no screen opens is not a feature.
    testWidgets('the roll opens on the cursor\'s channel and shows notes',
        (tester) async {
      await pumpGame(tester, const AdvancedTrackerScreen());
      // Never pumpAndSettle: continuous ticker.
      await tester.pump();
      final game = tester.state<State<AdvancedTrackerScreen>>(
        find.byType(AdvancedTrackerScreen),
      ) as AdvancedTrackerTester;

      game.setNote(0, 0, 60);
      game.setNote(0, 8, 67);
      game.moveCursor(0, 0);
      await tester.pump();

      unawaited(game.openPianoRoll());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Channel 1'), findsOneWidget);
      expect(find.byType(TrackerPianoRoll), findsOneWidget);
      // It found the notes rather than falling through to the empty state.
      expect(find.textContaining('No notes'), findsNothing);
    });

    testWidgets('an empty channel says so rather than drawing a blank grid',
        (tester) async {
      // An empty grid reads as broken software.
      await pumpGame(tester, const AdvancedTrackerScreen());
      await tester.pump();
      final game = tester.state<State<AdvancedTrackerScreen>>(
        find.byType(AdvancedTrackerScreen),
      ) as AdvancedTrackerTester;
      game.moveCursor(0, 0);
      await tester.pump();

      unawaited(game.openPianoRoll());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('No notes'), findsOneWidget);
    });
  });
}
