// WS-T7 — playing notes INTO the pattern, from the MIDI seam.
//
// Live record already existed here (a typed note lands at the sounding row).
// What did not was any way to PLAY into it: the pads (WS-X5 3b) had no host
// anywhere in the app, and the screen's own piano emits `onKeyTap` — a tap,
// which has no duration and so can never be a chord held together.
//
// `pattern_record_test.dart` covers the decisions (which row, which channels,
// the count-in, one undo per pass) as pure functions. This covers the join:
// that a MIDI note actually reaches the pattern, and that the three defects the
// old path had are gone.
//
// ⚠️ Never `pumpAndSettle` here — the playhead Ticker never stops, so it hangs.

import 'package:comet_beat/core/midi/midi_input.dart';
import 'package:comet_beat/core/services/transport_service.dart';
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/game_test_support.dart';

AdvancedTrackerTester _game(WidgetTester tester) =>
    tester.state<State<AdvancedTrackerScreen>>(
      find.byType(AdvancedTrackerScreen),
    ) as AdvancedTrackerTester;

void _noteOn(AdvancedTrackerTester game, int note, {int velocity = 100}) =>
    game.debugMidiInput.send(
      MidiMessage(kind: MidiMessageKind.noteOn, data1: note, data2: velocity),
    );

void _noteOff(AdvancedTrackerTester game, int note) => game.debugMidiInput.send(
      MidiMessage(kind: MidiMessageKind.noteOff, data1: note),
    );

/// The screen delivers MIDI through a stream, so a send needs a turn of the
/// event loop before the pattern has changed.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Let the playhead come alive before playing into it.
///
/// ⚠️ Worth knowing: the row is `-1` until the Ticker has run at least once
/// with the clock going, and live record needs a real row — so a note sent in
/// the same frame as `togglePlay` lands at the CURSOR, not the playhead, and a
/// test that skips this passes for the wrong reason.
Future<void> _playing(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('a played note reaches the pattern', (tester) async {
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    final before = game.noteCount;

    _noteOn(game, 60);
    await _settle(tester);

    expect(game.noteCount, before + 1);
  });

  testWidgets('not recording, a played note goes in at the cursor', (
    tester,
  ) async {
    // The pads are an instrument as well as a recorder: with the transport
    // stopped they enter notes exactly as typing does.
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.moveCursor(1, 4);
    await tester.pump();

    _noteOn(game, 62);
    await _settle(tester);

    expect(game.noteAt(1, 4), 62);
  });

  testWidgets('⚠️ a CHORD spreads across channels instead of overwriting', (
    tester,
  ) async {
    // The defect this fixes: every note went to the cursor channel, so a triad
    // wrote one cell three times and two notes of it silently vanished.
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 48); // something to play, so the clock runs
    game.togglePlay();
    game.toggleRecord();
    game.moveCursor(0, 0);
    await _playing(tester);

    _noteOn(game, 60);
    _noteOn(game, 64);
    _noteOn(game, 67);
    await _settle(tester);
    game.stop();
    await tester.pump();

    // All three survive, lowest on the channel the player was on.
    final written = <int?>[
      for (var channel = 0; channel < 3; channel++)
        [
          for (var row = 0; row < game.rows; row++) game.noteAt(channel, row),
        ].firstWhere(
          (note) => note == 60 || note == 64 || note == 67,
          orElse: () => null,
        ),
    ];
    expect(written, [60, 64, 67]);
  });

  testWidgets('a release does not write anything', (tester) async {
    // Note-offs track what is held; only note-ons commit. (And a note-on with
    // velocity 0 IS a note-off — the trap the seam exists for.)
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    final before = game.noteCount;

    _noteOff(game, 60);
    // A note-ON at velocity 0 — which the standard says IS a note-off, and
    // which anything reading `kind` alone would happily record as a note.
    _noteOn(game, 62, velocity: 0);
    await _settle(tester);

    expect(game.noteCount, before);
  });

  testWidgets('a whole record pass is ONE undo', (tester) async {
    // It used to be one per note, and each entry snapshots the entire pattern
    // against an 80-entry cap — so a short jam evicted every earlier edit.
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.setNote(0, 0, 48);
    final afterSetup = game.noteCount;
    game.togglePlay();
    game.toggleRecord();
    await _playing(tester);

    for (final note in [60, 62, 64, 65]) {
      _noteOn(game, note);
      _noteOff(game, note);
      await _settle(tester);
    }
    game.stop();
    await tester.pump();
    expect(game.noteCount, greaterThan(afterSetup), reason: 'it recorded');

    game.undo();
    await tester.pump();
    expect(
      game.noteCount,
      afterSetup,
      reason: 'one undo takes back the whole take, not the last note',
    );
  });

  group('the count-in gates the writes', () {
    testWidgets('nothing is committed while it runs', (tester) async {
      // The Tracker's own clock is what the transport follows, so a count-in
      // cannot hold time back — the pattern keeps playing (you play along) and
      // nothing is kept until the count ends.
      final transport = TransportService()..countInBars = 2;
      await pumpGame(
        tester,
        const AdvancedTrackerScreen(),
        extraProviders: [
          ChangeNotifierProvider<TransportService>.value(value: transport),
        ],
      );
      final game = _game(tester);
      game.setNote(0, 0, 48);
      final before = game.noteCount;
      game.togglePlay();
      game.toggleRecord();
      await _playing(tester);
      expect(game.isCountingIn, isTrue);

      _noteOn(game, 60);
      await _settle(tester);
      expect(game.noteCount, before, reason: 'heard, but not kept');
      game.stop();
      await tester.pump();
    });

    testWidgets('with no count-in set, the first note is kept', (tester) async {
      // The default must not make recording feel broken.
      final transport = TransportService();
      await pumpGame(
        tester,
        const AdvancedTrackerScreen(),
        extraProviders: [
          ChangeNotifierProvider<TransportService>.value(value: transport),
        ],
      );
      final game = _game(tester);
      game.setNote(0, 0, 48);
      final before = game.noteCount;
      game.togglePlay();
      game.toggleRecord();
      await _playing(tester);
      expect(game.isCountingIn, isFalse);

      _noteOn(game, 60);
      await _settle(tester);
      expect(game.noteCount, before + 1);
      game.stop();
      await tester.pump();
    });
  });

  testWidgets('arming record tells the shared transport', (tester) async {
    // "From the transport" is the card: another surface showing record state
    // should not have to ask the Tracker.
    final transport = TransportService();
    await pumpGame(
      tester,
      const AdvancedTrackerScreen(),
      extraProviders: [
        ChangeNotifierProvider<TransportService>.value(value: transport),
      ],
    );
    final game = _game(tester);

    expect(transport.isRecordArmed, isFalse);
    game.toggleRecord();
    await tester.pump();
    expect(transport.isRecordArmed, isTrue);

    game.toggleRecord();
    await tester.pump();
    expect(transport.isRecordArmed, isFalse);
  });

  testWidgets('the screen still works with NO transport provided', (
    tester,
  ) async {
    // Every existing test mounts it without one, and the screen deliberately
    // tolerates that.
    await pumpGame(tester, const AdvancedTrackerScreen());
    final game = _game(tester);
    game.toggleRecord();
    await tester.pump();
    expect(game.isRecording, isTrue);
    _noteOn(game, 60);
    await _settle(tester);
    expect(game.noteCount, greaterThan(0));
  });
}
