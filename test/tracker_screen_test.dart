// Tracker (Sandbox skin) — drives the grid via the TrackerTester seam (audio is
// a no-op in the headless binding — the assertions are on the placed notes, the
// play state and the selected channel).

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/crisp_dsp/voice_fx.dart';
import 'package:klang_universum/core/audio/tracker_engine.dart'
    show TrackerEffect;
import 'package:klang_universum/features/games/composition/tracker_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

TrackerTester _game(WidgetTester tester) =>
    tester.state<State<TrackerScreen>>(find.byType(TrackerScreen))
        as TrackerTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('placing a note starts the groove; clearing stops it',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    expect(game.noteCount, 0);
    expect(game.isPlaying, isFalse);

    game.tapCell(0, 0);
    await tester.pump();
    expect(game.noteCount, 1);
    expect(game.isPlaying, isTrue);

    game.clearAll();
    await tester.pump();
    expect(game.noteCount, 0);
    expect(game.isPlaying, isFalse);
  });

  testWidgets('tapping the same cell twice toggles the note off',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    game.tapCell(2, 3);
    await tester.pump();
    expect(game.noteCount, 1);

    game.tapCell(2, 3);
    await tester.pump();
    expect(game.noteCount, 0);
  });

  testWidgets('each instrument tab edits its own channel', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    expect(game.channelIds.length, greaterThanOrEqualTo(2));
    expect(game.selectedChannel, 0);

    game.tapCell(0, 0); // channel 0
    game.selectChannel(1);
    await tester.pump();
    expect(game.selectedChannel, 1);

    game.tapCell(1, 1); // channel 1
    await tester.pump();
    // Two notes total, one per channel — switching tabs didn't move a note.
    expect(game.noteCount, 2);
  });

  testWidgets('the Clear button empties the pattern', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    game.tapCell(0, 0);
    game.tapCell(1, 2);
    await tester.pump();
    expect(game.noteCount, 2);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(game.noteCount, 0);
    expect(game.isPlaying, isFalse);
  });

  testWidgets('a recorded voice makes the voice channel playable',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    expect(game.channelIds, contains('voice'));
    expect(game.hasVoiceRecording, isFalse);

    // Inject a synthetic clip in place of a real mic recording.
    final raw = Float64List(4410);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = sin(2 * pi * 220 * i / 44100);
    }
    game.injectRecording(raw, VoiceEffect.chipmunk);
    await tester.pump();

    expect(game.hasVoiceRecording, isTrue);
    expect(game.selectedChannel, game.channelIds.indexOf('voice'));

    game.tapCell(0, 0);
    await tester.pump();
    expect(game.noteCount, 1);
    expect(game.isPlaying, isTrue);
  });

  testWidgets('the notation panel renders the pattern as a score',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    expect(game.notationVisible, isFalse);

    game.tapCell(0, 0);
    game.tapCell(2, 4);
    game.toggleNotation();
    await tester.pump();

    expect(game.notationVisible, isTrue);
    expect(tester.takeException(), isNull); // StaffView built cleanly
  });

  testWidgets('loading the demo tune fills the melody channel', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    expect(game.noteCount, 0);

    game.importDemo();
    await tester.pump();

    expect(game.noteCount, 4); // C D E G
    expect(game.selectedChannel, 0); // melody
    expect(game.isPlaying, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the instrument picker re-voices the selected channel',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    expect(game.selectedInstrumentId, 'piano'); // melody default

    game.tapCell(0, 0); // give it a note so the mix changes
    await tester.pump();

    game.setInstrument('laser');
    await tester.pump();
    expect(game.selectedInstrumentId, 'laser');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the drums channel uses a 3-row drum grid', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    final drums = game.channelIds.indexOf('drums');
    expect(drums, greaterThanOrEqualTo(0));

    game.selectChannel(drums);
    await tester.pump();
    expect(game.pitchRows, 3); // hat / snare / kick

    game.tapCell(2, 0); // bottom row (kick), step 0
    await tester.pump();
    expect(game.noteCount, 1);
    expect(game.isPlaying, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('importing a song book tune fills the melody channel',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    game.importSong('alle_meine_entchen');
    await tester.pump();

    // Its opening bar landed on the grid.
    expect(game.noteCount, greaterThan(0));
    expect(game.selectedChannel, 0); // melody
    expect(tester.takeException(), isNull);
  });

  testWidgets('pattern slots hold separate patterns and play as a song',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    expect(game.slotCount, greaterThanOrEqualTo(2));
    expect(game.currentSlot, 0);
    expect(game.songHasContent, isFalse);

    game.tapCell(0, 0); // note in slot A
    await tester.pump();
    expect(game.songHasContent, isTrue);

    game.selectSlot(1); // switch to slot B — its own (empty) pattern
    await tester.pump();
    expect(game.currentSlot, 1);
    expect(game.noteCount, 0); // B is empty; A's note was saved away

    game.tapCell(1, 2); // note in slot B
    await tester.pump();

    game.selectSlot(0); // back to A — its note is restored
    await tester.pump();
    expect(game.noteCount, 1);

    game.playSong(); // A then B, chained
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the order-list defines a custom song sequence', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    expect(game.songOrder, isEmpty);

    game.tapCell(0, 0); // slot A has a note
    game.selectSlot(1);
    game.tapCell(1, 2); // slot B has a note
    await tester.pump();

    // Build the order A B A explicitly.
    game.selectSlot(0);
    game.addToOrder(0);
    game.addToOrder(1);
    game.addToOrder(0);
    await tester.pump();
    expect(game.songOrder, [0, 1, 0]);

    game.playSong();
    await tester.pump();
    expect(game.songOrder, [0, 1, 0]); // order preserved
    expect(tester.takeException(), isNull);

    game.clearOrder();
    await tester.pump();
    expect(game.songOrder, isEmpty);
  });

  testWidgets('setting a per-note effect sticks', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    game.tapCell(0, 0); // melody (additive) note
    await tester.pump();
    expect(game.effectAt(0), TrackerEffect.none);

    game.setNoteEffect(0, 0, TrackerEffect.vibrato);
    await tester.pump();
    expect(game.effectAt(0), TrackerEffect.vibrato);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press toggles a note soft (dynamics)', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    game.tapCell(0, 0);
    await tester.pump();
    expect(game.isSoft(0, 0), isFalse);

    game.toggleAccent(0, 0);
    await tester.pump();
    expect(game.isSoft(0, 0), isTrue);

    game.toggleAccent(0, 0);
    await tester.pump();
    expect(game.isSoft(0, 0), isFalse);
    expect(tester.takeException(), isNull);
  });
}
