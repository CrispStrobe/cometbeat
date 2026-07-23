// Tracker (Sandbox skin) — drives the grid via the TrackerTester seam (audio is
// a no-op in the headless binding — the assertions are on the placed notes, the
// play state and the selected channel).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/loop_engine.dart' show PatternCell;
import 'package:comet_beat/core/audio/mod/mod.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show parseAnyModule;
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerCell, TrackerChannelEffect, TrackerEffect;
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:comet_beat/features/games/composition/tracker_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        Clef,
        Measure,
        NoteDuration,
        NoteElement,
        Pitch,
        RestElement,
        Score,
        StaffView,
        Step,
        scoreFromMidi;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

TrackerTester _game(WidgetTester tester) =>
    tester.state<State<TrackerScreen>>(find.byType(TrackerScreen))
        as TrackerTester;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BeatBridge.instance.clear();
    MelodyBridge.instance.clear();
  });

  testWidgets('offers a one-tap starter groove on an empty tracker',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    expect(game.noteCount, 0);
    expect(
        find.byKey(const ValueKey('tracker-starter-groove')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tracker-starter-groove')));
    await tester.pump();

    expect(game.noteCount, greaterThan(0));
    expect(find.byKey(const ValueKey('tracker-starter-groove')), findsNothing);
  });

  testWidgets('shares the drum channel out and loads a shared beat in',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    // A shared beat another mode published (kick+hat on 0, snare on 4).
    List<bool> row(List<int> hits) =>
        [for (var i = 0; i < 16; i++) hits.contains(i)];
    BeatBridge.instance.publish(
      SharedBeat(
        rows: {
          Drum.kick: row([0, 8]),
          Drum.hat: row([0, 2, 4, 6, 8, 10, 12, 14]),
          Drum.snare: row([4, 12]),
        },
        tempoBpm: 120,
      ),
    );
    expect(game.canLoadSharedBeat, isTrue);
    expect(game.noteCount, 0);

    // Pull it in — drums land in the beginner percussion channel (simplified).
    game.loadSharedBeat();
    await tester.pump();
    expect(game.noteCount, greaterThan(0));

    // Share the drum channel back out — round-trips through the bridge.
    BeatBridge.instance.clear();
    game.shareBeat();
    final shared = BeatBridge.instance.current;
    expect(shared, isNotNull);
    expect(shared!.source, 'tracker');
    expect(shared.isEmpty, isFalse);
  });

  testWidgets('shares the melody channel out and loads a shared tune in',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    // A shared tune (C-D-E-G, then a rest) another mode published.
    MelodyBridge.instance.publish(
      SharedMelody(
        cells: const <PatternCell>[
          (midis: [60], steps: 2),
          (midis: [62], steps: 2),
          (midis: [64], steps: 2),
          (midis: [67], steps: 2),
          (midis: null, steps: 8),
        ],
        tempoBpm: 120,
        source: 'loopmixer',
      ),
    );
    expect(game.canLoadSharedMelody, isTrue);
    expect(game.noteCount, 0);

    // Pull it in — notes land on the melodic channel at their onsets.
    game.loadSharedMelody();
    await tester.pump();
    expect(game.noteCount, 4);

    // Share the melody channel back out — round-trips through the bridge.
    MelodyBridge.instance.clear();
    game.shareMelody();
    final shared = MelodyBridge.instance.current;
    expect(shared, isNotNull);
    expect(shared!.source, 'tracker');
    expect(shared.isEmpty, isFalse);
  });

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

  testWidgets('promotes the groove to an Advanced song (lossless)',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    game.selectChannel(0);
    game.tapCell(0, 0); // a note in slot A
    game.tapCell(2, 4);
    await tester.pump();

    final song = game.debugPromoteToSong();
    // The band + a pattern per slot carry over.
    expect(song.channels.length, game.channelIds.length);
    expect(song.patterns.length, game.slotCount);
    // Slot A's notes survive in the promoted song.
    final notes = song.patterns
        .expand((p) => p.cells)
        .expand((col) => col)
        .where((c) => c.midi != null)
        .length;
    expect(notes, 2);
    // The order lists the non-empty slot (A) so it actually plays.
    expect(song.order, contains(0));
  });

  testWidgets('an Advanced song hands down onto the kid grid (snapped)',
      (tester) async {
    final song = TrackerSong(); // default band, 32 rows
    song.engine.setCell(0, 0, const TrackerCell(midi: 61)); // chromatic C#
    song.engine.setCell(0, 8, const TrackerCell(midi: 67)); // G

    await pumpGame(tester, TrackerScreen(initialSong: song));
    final game = _game(tester);
    await tester.pump(); // let the post-frame notice fire

    // Downsample maps rows 0 and 8 (of 32) onto steps 0 and 2 -> two notes.
    expect(game.noteCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide range opens three octaves of pitch rows', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    game.selectChannel(0); // a pitched channel

    final narrow = game.pitchRows;
    expect(game.wideRange, isFalse);

    game.setWideRange(true);
    await tester.pump();
    expect(game.wideRange, isTrue);
    expect(game.pitchRows, narrow * 3); // low + mid + high octaves

    // A note on a top (high-octave) row — only reachable in wide mode — lands.
    game.tapCell(0, 0);
    await tester.pump();
    expect(game.noteCount, 1);

    game.setWideRange(false);
    await tester.pump();
    expect(game.pitchRows, narrow);
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

  testWidgets('the score view shows a staff per pitched channel',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    game.tapCell(0, 0); // melody
    game.selectChannel(game.channelIds.indexOf('bass'));
    game.tapCell(0, 0); // bass
    game.toggleNotation();
    await tester.pump();

    // One staff for melody, one for bass — the multi-part view.
    expect(find.byType(StaffView), findsNWidgets(2));
    expect(tester.takeException(), isNull);
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

  testWidgets('a MOD imports into the tracker and re-exports', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    // A tiny 1-channel module with a note on row 0.
    final rows = List.generate(64, (_) => <ModCell>[const ModCell()]);
    rows[0] = [const ModCell(sample: 1, period: 428)];
    final mod = ModModule(
      channelCount: 1,
      samples: [
        ModSample(name: 's', pcm: Int8List.fromList([0, 50, -50])),
        for (var i = 1; i < 31; i++) ModSample.empty(),
      ],
      order: const [0],
      patterns: [ModPattern(rows)],
    );

    game.importModModule(mod);
    await tester.pump();
    expect(game.noteCount, greaterThan(0)); // the note landed on the grid

    // Export re-parses as a valid module (round-trips through the codec).
    final back = parseMod(game.exportModBytes());
    expect(back.channelCount, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('exports the groove to all four module formats (sample-kept)',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    game.selectChannel(0);
    game.tapCell(0, 0); // place a note so there's something to export
    await tester.pump();

    for (final fmt in ['mod', 'xm', 's3m', 'it']) {
      final bytes = game.exportModuleBytes(fmt);
      expect(bytes.isNotEmpty, isTrue, reason: '$fmt export produced bytes');
      // It re-parses through the module hub and keeps at least one sample.
      final doc = parseAnyModule(bytes);
      expect(doc.samples, isNotEmpty, reason: '$fmt kept a sample');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('saves the groove to the Song Book as a multi-part score',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    final songs = UserSongsService();

    // Nothing placed yet → nothing saved.
    expect(game.debugSaveToSongBook(songs), isFalse);
    expect(songs.songs, isEmpty);

    // Place a note, then save → one Song Book entry, real notation.
    game.tapCell(0, 0);
    await tester.pump();
    expect(game.debugSaveToSongBook(songs), isTrue);
    expect(songs.songs.length, 1);
    expect(songs.songs.single.score.measures, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('imports a non-MOD module tune (.it) via importModuleBytes',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    // A real .it golden — reaches the grid through the hub converter, not the
    // MOD-only path (which the file picker used to be restricted to).
    final bytes = File('test/fixtures/golden.it').readAsBytesSync();
    game.importModuleBytes(bytes);
    await tester.pump();

    expect(game.noteCount, greaterThan(0)); // the .it note landed on the grid
    expect(tester.takeException(), isNull);
  });

  testWidgets('MIDI imports and exports (the MIDI↔MOD hub)', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    // A tiny score (a C–E chord + rests), as if parsed from a MIDI file.
    const score = Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement(
            pitches: [Pitch(Step.c), Pitch(Step.e)],
            duration: NoteDuration.quarter,
          ),
          RestElement(NoteDuration.quarter),
          RestElement(NoteDuration.half),
        ]),
      ],
    );

    game.importMidiScore(score);
    await tester.pump();
    expect(game.noteCount, greaterThan(0)); // chord split across channels

    final midi = game.exportMidiBytes();
    expect(midi.isNotEmpty, isTrue);
    // The export must carry actual notes, not just a header (scoreToMidi drops
    // notes without ids — regression guard for that).
    final back = scoreFromMidi(midi);
    expect(
      back.measures.any((m) => m.elements.any((e) => e is NoteElement)),
      isTrue,
      reason: 'exported MIDI should round-trip with notes',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ABC imports and exports (the Score bridge)', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    // A one-bar ABC melody — imports onto the (pentatonic) grid.
    game.importAbcText('X:1\nL:1/8\nK:C\nCDEG z4 |\n');
    await tester.pump();
    expect(game.noteCount, greaterThan(0));

    final abc = game.exportAbcText();
    expect(abc, contains('X:')); // a valid ABC tune header
    expect(abc, contains('K:'));
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

  testWidgets('the selected channel effect can be set and cleared',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    expect(game.channelEffects, isEmpty);
    game.setChannelEffects(
      const [TrackerChannelEffect.reverb, TrackerChannelEffect.delay],
    );
    await tester.pump();
    expect(
      game.channelEffects,
      [TrackerChannelEffect.reverb, TrackerChannelEffect.delay],
    );

    game.setChannelEffects(const []);
    await tester.pump();
    expect(game.channelEffects, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the swing toggle turns the groove swing on and off',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    expect(game.swingOn, isFalse);
    game.setSwing(true);
    await tester.pump();
    expect(game.swingOn, isTrue);
    game.setSwing(false);
    await tester.pump();
    expect(game.swingOn, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the voice speed control time-stretches a recorded clip',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    final raw = Float64List(4000);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = sin(2 * pi * 220 * i / 44100);
    }

    // As-recorded (1.0) keeps the length.
    game.setVoiceStretch(1.0);
    await tester.pump();
    game.injectRecording(raw, VoiceEffect.normal);
    await tester.pump();
    expect(game.voiceSampleLength, raw.length);

    // Slower (1.5) yields a longer sample (pitch preserved by WSOLA).
    game.setVoiceStretch(1.5);
    await tester.pump();
    game.injectRecording(raw, VoiceEffect.normal);
    await tester.pump();
    expect(game.voiceStretch, 1.5);
    expect(game.voiceSampleLength, closeTo(raw.length * 1.5, 2048));
    expect(tester.takeException(), isNull);
  });
}
