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

/// Whether [midi] is anywhere in the pattern.
///
/// ⚠️ This exists instead of comparing `noteCount`, and the difference is the
/// whole reason the count-in pair used to be flaky. The screen's playhead runs
/// on a REAL `Stopwatch` (it is the clock the transport follows), while
/// `tester.pump(duration)` only advances FAKE time — so the row a note records
/// to is a function of how long the widget build actually took in wall-clock,
/// modulo the pattern length. Measured on one machine it was row 22 with a cold
/// build and row 2 with a warm one, and on CI it landed on row 0.
///
/// Row 0 is where these tests seed their reference note, and a record there
/// OVERWRITES rather than adds (`copyWith` on the existing cell, deliberately),
/// so `noteCount` stayed 1 and the "kept" test failed `Expected: <2>`. The
/// mirror bug was worse: the count-in test asserts the count is UNCHANGED,
/// which a wrong write to the cursor cell also satisfies — a silent false pass.
///
/// Asking whether the PITCH is present answers what both tests actually mean,
/// and does not care which row the wall-clock picked.
bool _hasNote(AdvancedTrackerTester game, int midi) {
  for (var c = 0; c < game.channelCount; c++) {
    for (var r = 0; r < game.rows; r++) {
      if (game.noteAt(c, r) == midi) return true;
    }
  }
  return false;
}

/// Every note in the pattern, whatever row or channel it landed on.
///
/// ⚠️ The wall-clock lesson: the Tracker's playhead runs on a REAL `Stopwatch`
/// while `tester.pump(duration)` moves only FAKE time, so the row a recorded
/// note lands on is whatever the build happened to take. Asserting on the
/// PITCH holds regardless; asserting on a row — or on a count that an
/// overwrite also satisfies — does not.
List<int> _notesIn(AdvancedTrackerTester game) => [
      for (var channel = 0; channel < game.channelCount; channel++)
        for (var row = 0; row < game.rows; row++)
          if (game.noteAt(channel, row) case final midi?) midi,
    ];

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
    // ⚠️ And the PITCHES, not only the count. A count that stays put is also
    // satisfied by a wrong write that OVERWRITES an occupied cell — the false
    // pass @daw-ux found in the sibling test here. Naming the notes says what
    // is meant and cannot be satisfied by an accident.
    expect(_notesIn(game), isNot(contains(60)));
    expect(_notesIn(game), isNot(contains(62)));
  });

  group('how long a note was held', () {
    testWidgets('releasing writes a key-off, so the note has a LENGTH', (
      tester,
    ) async {
      // Without it every recorded note runs until the next one on its channel,
      // and a staccato stab is indistinguishable from a held pad.
      await pumpGame(tester, const AdvancedTrackerScreen());
      final game = _game(tester);
      game.setNote(0, 0, 48);
      game.togglePlay();
      game.toggleRecord();
      game.moveCursor(1, 0);
      await _playing(tester);

      _noteOn(game, 60);
      await _settle(tester);
      final row = [
        for (var r = 0; r < game.rows; r++)
          if (game.noteAt(1, r) == 60) r,
      ].single;

      _noteOff(game, 60);
      await _settle(tester);
      game.stop();
      await tester.pump();

      final cuts = [
        for (var r = 0; r < game.rows; r++)
          if (game.isNoteCutAt(1, r)) r,
      ];
      expect(cuts, isNotEmpty, reason: 'the release was recorded');
      expect(
        cuts.single,
        isNot(row),
        reason:
            'a key-off in the note own row would cancel it before it sounds',
      );
    });

    testWidgets('a release does not delete a note played after it', (
      tester,
    ) async {
      // By the time you let go, the next note may already be recorded where the
      // cut would land — cutting there would delete a note you played to end
      // one you had already finished.
      await pumpGame(tester, const AdvancedTrackerScreen());
      final game = _game(tester);
      game.setNote(0, 0, 48);
      game.togglePlay();
      game.toggleRecord();
      game.moveCursor(1, 0);
      await _playing(tester);

      _noteOn(game, 60);
      await _settle(tester);
      // Fill every row of the channel, so wherever the cut would go there is a
      // note already.
      for (var r = 0; r < game.rows; r++) {
        game.setNote(1, r, 72);
      }
      _noteOff(game, 60);
      await _settle(tester);
      game.stop();
      await tester.pump();

      for (var r = 0; r < game.rows; r++) {
        expect(game.noteAt(1, r), 72, reason: 'row $r survived');
        expect(game.isNoteCutAt(1, r), isFalse);
      }
    });

    testWidgets('a release outside a record pass writes nothing', (
      tester,
    ) async {
      // Letting go after you stopped recording must not edit the pattern.
      await pumpGame(tester, const AdvancedTrackerScreen());
      final game = _game(tester);
      _noteOn(game, 60);
      await _settle(tester);
      final before = game.noteCount;
      _noteOff(game, 60);
      await _settle(tester);
      expect(game.noteCount, before);
      // The specific thing this is about: no key-off was written anywhere, on
      // any channel — a cut on a channel nobody looked at is still a cut.
      for (var channel = 0; channel < game.channelCount; channel++) {
        for (var r = 0; r < game.rows; r++) {
          expect(game.isNoteCutAt(channel, r), isFalse, reason: '$channel/$r');
        }
      }
    });
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
    // Same wall-clock hazard as the count-in pair (see `_hasNote`): if the
    // playhead happened to sit on row 0 these would overwrite the seeded note
    // instead of adding cells, and a count-based assertion would go red for a
    // reason that has nothing to do with undo. The last note played is the one
    // nothing can overwrite — a release never writes over a note.
    expect(_hasNote(game, 65), isTrue, reason: 'it recorded');

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
      game.togglePlay();
      game.toggleRecord();
      await _playing(tester);
      expect(game.isCountingIn, isTrue);

      _noteOn(game, 60);
      await _settle(tester);
      expect(_hasNote(game, 60), isFalse, reason: 'heard, but not kept');
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
      game.togglePlay();
      game.toggleRecord();
      await _playing(tester);
      expect(game.isCountingIn, isFalse);

      _noteOn(game, 60);
      await _settle(tester);
      expect(_hasNote(game, 60), isTrue, reason: 'no count-in gates it');
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
