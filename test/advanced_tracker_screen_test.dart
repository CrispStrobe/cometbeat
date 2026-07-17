// Advanced Tracker — drives the classic grid via the AdvancedTrackerTester seam
// (audio is a no-op in the headless binding — assertions are on placed notes,
// play state, track count and pattern length). Mirrors tracker_screen_test.dart.

import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

AdvancedTrackerTester _game(WidgetTester tester) =>
    tester.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('trackerNoteName renders classic tracker labels', (_) async {
    expect(trackerNoteName(60), 'C-4');
    expect(trackerNoteName(61), 'C#4');
    expect(trackerNoteName(69), 'A-4');
    expect(trackerNoteName(72), 'C-5');
  });

  testWidgets('placing a chromatic note starts playback; clearing empties',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    expect(game.noteCount, 0);
    expect(game.isPlaying, isFalse);

    game.togglePlay();
    await tester.pump();
    expect(game.isPlaying, isTrue);

    game.setNote(0, 5, 61); // C#4 — a chromatic note the kid grid can't place
    await tester.pump();
    expect(game.noteCount, 1);

    game.clearNote(0, 5);
    await tester.pump();
    expect(game.noteCount, 0);

    game.togglePlay();
    await tester.pump();
    expect(game.isPlaying, isFalse);
  });

  testWidgets('endless length: the pattern grows well past one bar',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    expect(game.rows, 32); // already 4x the Beginner grid's 8 steps
    game.setRows(128);
    await tester.pump();
    expect(game.rows, 128);

    // A note deep in the pattern is reachable — no 2-3 Takte ceiling.
    game.setNote(0, 120, 60);
    await tester.pump();
    expect(game.noteCount, 1);
  });

  testWidgets('endless tracks: add and remove channels', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    final before = game.channelCount;
    game.addTrack();
    await tester.pump();
    expect(game.channelCount, before + 1);

    // A note on the new track survives, and removing a different track keeps it.
    game.setNote(before, 0, 64);
    await tester.pump();
    expect(game.noteCount, 1);

    game.removeTrack(0);
    await tester.pump();
    expect(game.channelCount, before);
    expect(game.noteCount, 1); // the note moved down with its channel
  });

  testWidgets(
      'keyboard entry: a piano key types a note and advances the cursor',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    game.moveCursor(0, 4);
    await tester.pump();
    expect(game.cursorChannel, 0);
    expect(game.cursorRow, 4);

    // 'z' = C at the base octave (default octave 4 -> C4 = MIDI 60).
    game.typeKey('z');
    await tester.pump();
    expect(game.noteCount, 1);
    expect(game.octave, 4);
    // The cursor advanced by the default edit-step of 1.
    expect(game.cursorRow, 5);

    // 'q' = C one octave up (the upper keyboard row).
    game.typeKey('q');
    await tester.pump();
    expect(game.noteCount, 2);
    expect(game.cursorRow, 6);
  });

  testWidgets('per-track instrument can be reassigned', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    // Just assert the API drives without error and a subsequent note counts —
    // the instrument change itself is exercised in the engine tests.
    game.setChannelInstrument(0, 'flute');
    game.setNote(0, 0, 60);
    await tester.pump();
    expect(game.noteCount, 1);
  });

  testWidgets('multi-pattern: add, select and edit separate patterns',
      (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    expect(game.patternCount, 1);
    game.setNote(0, 0, 60); // pattern 0
    await tester.pump();

    game.addPattern(); // -> pattern 1, selected
    await tester.pump();
    expect(game.patternCount, 2);
    expect(game.currentPattern, 1);
    expect(game.noteCount, 0); // fresh pattern

    game.setNote(0, 0, 72); // pattern 1
    await tester.pump();
    expect(game.noteCount, 1);

    game.selectPattern(0);
    await tester.pump();
    expect(game.noteCount, 1); // pattern 0's note restored
  });

  testWidgets('order list + play song', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);

    game.setNote(0, 0, 60);
    game.addPattern(clone: true); // pattern 1 (index 1), selected
    await tester.pump();
    expect(game.patternCount, 2);

    // Order starts as [0]; append the current pattern (1) -> [0, 1].
    game.addToOrder(game.currentPattern);
    await tester.pump();
    expect(game.orderLength, 2);

    game.playSong();
    await tester.pump();
    expect(game.isSongPlaying, isTrue);

    game.togglePlay(); // stop
    await tester.pump();
    expect(game.isPlaying, isFalse);
    expect(game.isSongPlaying, isFalse);
  });
}
