// Drumkit / BoomBox — the step beat-grid over a shared DrumRowsPattern.
// Audio is a no-op in the headless binding; assertions are on the grid + state.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/beat_capture.dart' show BeatFrame;
import 'package:comet_beat/core/audio/loop_engine.dart' show DrumRowsPattern;
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show SampleInstrument;
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart'
    show instrumentToJsonString;
import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/drums/drumkit_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

DrumkitTester _kit(WidgetTester tester) =>
    tester.state<State<DrumkitScreen>>(find.byType(DrumkitScreen))
        as DrumkitTester;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BeatBridge.instance.clear();
  });

  testWidgets('round-trip: seeds the grid from initialBeat + reflects edits',
      (tester) async {
    final seed = DrumRowsPattern({
      Drum.kick: List<bool>.filled(16, false)
        ..[0] = true
        ..[8] = true,
      Drum.snare: List<bool>.filled(16, false)..[4] = true,
    });
    await pumpGame(tester, DrumkitScreen(initialBeat: seed));
    final kit = _kit(tester);

    // The pads start from the incoming drums pattern.
    expect(kit.cellAt(Drum.kick, 0), isTrue);
    expect(kit.cellAt(Drum.kick, 8), isTrue);
    expect(kit.cellAt(Drum.snare, 4), isTrue);
    expect(kit.cellAt(Drum.kick, 1), isFalse);

    // Editing on the pads changes what a Done round-trip would return.
    kit.toggle(Drum.hat, 2);
    await tester.pump();
    expect(kit.cellAt(Drum.hat, 2), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press ghosts a pad hit; dynamics seed + round-trip + undo',
      (tester) async {
    // Seed with an accented kick — the ghost at step 0 travels in.
    final seed = DrumRowsPattern(
      {
        Drum.kick: List<bool>.filled(16, false)
          ..[0] = true
          ..[8] = true,
      },
      velocities: {
        Drum.kick: List<double>.filled(16, 1.0)..[0] = 0.45,
      },
    );
    await pumpGame(tester, DrumkitScreen(initialBeat: seed));
    final kit = _kit(tester);

    // The incoming ghost is seeded onto the pads.
    expect(kit.velocityAt(Drum.kick, 0), lessThan(1.0));
    expect(kit.velocityAt(Drum.kick, 8), 1.0);

    // Long-press cycles a normal hit → ghost and back.
    kit.cycleVelocity(Drum.kick, 8);
    await tester.pump();
    expect(kit.velocityAt(Drum.kick, 8), lessThan(1.0));

    // A Done round-trip carries BOTH ghosts back out.
    final out = kit.currentPattern;
    expect(out.velocities![Drum.kick]![0], lessThan(1.0));
    expect(out.velocities![Drum.kick]![8], lessThan(1.0));

    // Long-press an empty cell is a no-op.
    kit.cycleVelocity(Drum.snare, 3);
    await tester.pump();
    expect(kit.velocityAt(Drum.snare, 3), 1.0);

    // Undo reverts the last ghost edit (step 8 back to normal).
    kit.undo();
    await tester.pump();
    expect(kit.velocityAt(Drum.kick, 8), 1.0);
    expect(kit.velocityAt(Drum.kick, 0), lessThan(1.0)); // seeded ghost stays
    expect(tester.takeException(), isNull);
  });

  testWidgets('shares the beat to the bridge and loads a shared one back',
      (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);

    // Author a beat and publish it to the shared bridge.
    kit.toggle(Drum.kick, 0);
    kit.toggle(Drum.snare, 4);
    kit.setTempo(120);
    await tester.pump();
    kit.shareBeat();

    final shared = BeatBridge.instance.current!;
    expect(shared.rows[Drum.kick]![0], isTrue);
    expect(shared.rows[Drum.snare]![4], isTrue);
    expect(shared.tempoBpm, 120);
    expect(shared.source, 'drumkit');

    // Clear locally, then pull the shared beat back — it restores the grid.
    kit.clear();
    kit.setTempo(80);
    await tester.pump();
    expect(kit.hitCount, 0);

    expect(kit.canLoadSharedBeat, isTrue);
    kit.loadSharedBeat();
    await tester.pump();
    expect(kit.cellAt(Drum.kick, 0), isTrue);
    expect(kit.cellAt(Drum.snare, 4), isTrue);
    expect(kit.tempo, 120); // tempo came back too

    // Loading is undoable (it pushed an undo snapshot).
    expect(kit.canUndo, isTrue);
  });

  testWidgets('bars extend the grid, preserving hits', (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    expect(kit.steps, 16); // 2 bars by default
    expect(kit.bars, 2);

    kit.toggle(Drum.kick, 0);
    kit.toggle(Drum.snare, 15); // last step of the 2-bar grid
    await tester.pump();
    expect(kit.hitCount, 2);

    kit.setBars(4);
    await tester.pump();
    expect(kit.steps, 32);
    expect(kit.bars, 4);
    expect(kit.cellAt(Drum.kick, 0), isTrue); // hits preserved
    expect(kit.cellAt(Drum.snare, 15), isTrue);
    expect(kit.hitCount, 2); // the new bars are silent

    kit.setBars(2); // shrink back — truncates the (silent) extra bars
    await tester.pump();
    expect(kit.steps, 16);
    expect(kit.cellAt(Drum.kick, 0), isTrue);
    expect(kit.hitCount, 2);
  });

  testWidgets('a preset tiles across the extra bars', (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    kit.setBars(4);
    kit.debugLoadPreset(0); // Rock: kick on every downbeat
    await tester.pump();
    expect(kit.steps, 32);
    expect(kit.cellAt(Drum.kick, 0), isTrue);
    expect(kit.cellAt(Drum.kick, 16), isTrue); // the groove repeated, not blank
  });

  testWidgets('loading a preset fills the grid and is undoable',
      (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    expect(kit.hitCount, 0);

    kit.debugLoadPreset(0); // the first built-in groove
    await tester.pump();
    expect(kit.hitCount, greaterThan(0));
    expect(kit.canUndo, isTrue);

    kit.undo();
    await tester.pump();
    expect(kit.hitCount, 0); // undo restores the empty grid
  });

  testWidgets('a per-drum voice override swaps the sound and resets back',
      (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    expect(kit.drumVoiceOf(Drum.kick), isNull); // the built-in synth drum

    // A library instrument (as My-Instruments would supply).
    final pcm = Float64List.fromList([
      for (var i = 0; i < 400; i++) i % 40 < 20 ? 0.6 : -0.6,
    ]);
    final voice = SavedInstrument(
      name: 'Boom',
      json: instrumentToJsonString(SampleInstrument('boom', pcm)),
    );

    kit.debugSetDrumVoice(Drum.kick, voice);
    await tester.pump();
    expect(kit.drumVoiceOf(Drum.kick)?.name, 'Boom');

    // The beat still builds/plays with the override in place.
    kit.toggle(Drum.kick, 0);
    await tester.pump();
    expect(kit.hitCount, 1);
    expect(tester.takeException(), isNull);

    // Reset restores the synth drum.
    kit.debugSetDrumVoice(Drum.kick, null);
    await tester.pump();
    expect(kit.drumVoiceOf(Drum.kick), isNull);
  });

  testWidgets('per-drum voices travel with a shared beat', (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);

    final pcm = Float64List.fromList([
      for (var i = 0; i < 200; i++) i % 20 < 10 ? 0.5 : -0.5,
    ]);
    final voice = SavedInstrument(
      name: 'Boom',
      json: instrumentToJsonString(SampleInstrument('boom', pcm)),
    );
    kit.toggle(Drum.kick, 0);
    kit.debugSetDrumVoice(Drum.kick, voice);
    await tester.pump();
    kit.shareBeat();

    // Drop the voice locally, then load the shared beat — the voice comes back.
    kit.debugSetDrumVoice(Drum.kick, null);
    await tester.pump();
    expect(kit.drumVoiceOf(Drum.kick), isNull);

    kit.loadSharedBeat();
    await tester.pump();
    expect(kit.drumVoiceOf(Drum.kick)?.name, 'Boom');
  });

  testWidgets('an empty grid has nothing to share', (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    kit.shareBeat(); // no-op when empty
    expect(BeatBridge.instance.hasBeat, isFalse);
    expect(kit.canLoadSharedBeat, isFalse);
  });

  testWidgets('toggling grid cells builds the beat', (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    expect(kit.steps, 16);
    expect(kit.hitCount, 0);

    kit.toggle(Drum.kick, 0);
    kit.toggle(Drum.kick, 8);
    kit.toggle(Drum.snare, 4);
    await tester.pump();

    expect(kit.hitCount, 3);
    expect(kit.cellAt(Drum.kick, 0), isTrue);
    expect(kit.cellAt(Drum.kick, 8), isTrue);
    expect(kit.cellAt(Drum.snare, 4), isTrue);
    expect(kit.cellAt(Drum.hat, 0), isFalse);

    kit.toggle(Drum.kick, 0); // off again
    await tester.pump();
    expect(kit.hitCount, 2);
  });

  testWidgets('swing groove toggles and clamps to the musical range',
      (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    expect(kit.swing, 0); // straight by default

    kit.setSwing(0.4);
    await tester.pump();
    expect(kit.swing, 0.4);

    kit.setSwing(0.9); // above the musical ceiling → clamped
    expect(kit.swing, 0.6);

    kit.setSwing(0); // back to straight
    expect(kit.swing, 0);
  });

  testWidgets('undo/redo covers grid edits, record takes and clear',
      (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    expect(kit.canUndo, isFalse);

    // A grid edit is undoable.
    kit.toggle(Drum.kick, 0);
    await tester.pump();
    expect(kit.hitCount, 1);
    expect(kit.canUndo, isTrue);
    kit.undo();
    await tester.pump();
    expect(kit.hitCount, 0);
    expect(kit.canRedo, isTrue);
    kit.redo();
    await tester.pump();
    expect(kit.hitCount, 1);

    // A record take is one undo step (back to just the grid edit).
    kit.setTempo(120);
    kit.debugRecordTaps([
      (drum: Drum.snare, ms: 250),
      (drum: Drum.hat, ms: 500),
    ]);
    await tester.pump();
    expect(kit.hitCount, 3);
    kit.undo();
    await tester.pump();
    expect(kit.hitCount, 1); // the take is gone; the kick remains

    // Clear is undoable too.
    kit.clear();
    await tester.pump();
    expect(kit.hitCount, 0);
    kit.undo();
    await tester.pump();
    expect(kit.hitCount, 1);
  });

  testWidgets('play/stop + clear + tempo + pad tap do not crash',
      (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    kit.toggle(Drum.kick, 0);
    kit.setTempo(120);
    expect(kit.tempo, 120);

    kit.tapPad(Drum.snare); // one-shot audition (no-op audio)
    kit.togglePlay();
    await tester.pump();
    kit.stop();
    await tester.pump();
    expect(kit.isPlaying, isFalse);

    kit.clear();
    await tester.pump();
    expect(kit.hitCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap-to-record quantises loose taps onto the eighth grid',
      (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    kit.setTempo(120); // beatMs 500 → an eighth step is 250 ms
    await tester.pump();

    // Loose taps: kick on beats 1 & 2 (with a stray near-duplicate), snare on
    // the "and of 1". Loop-relative ms.
    kit.debugRecordTaps([
      (drum: Drum.kick, ms: 12), // → step 0
      (drum: Drum.kick, ms: 28), // near-dup → collapses onto step 0
      (drum: Drum.snare, ms: 258), // → step 1 (not over-quantised to the beat)
      (drum: Drum.kick, ms: 505), // → step 2
    ]);
    await tester.pump();

    expect(kit.cellAt(Drum.kick, 0), isTrue);
    expect(kit.cellAt(Drum.kick, 2), isTrue);
    expect(kit.cellAt(Drum.snare, 1), isTrue);
    // The stray double-kick collapsed → kick has just two hits.
    expect(kit.hitCount, 3);
    expect(kit.isRecording, isFalse);
  });

  testWidgets('beatbox capture classifies each hit and quantises onto the grid',
      (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    kit.setTempo(120); // beatMs 500 → eighth step 250 ms
    await tester.pump();

    // A quiet frame then a loud attack per hit (detectOnsets needs the rise).
    // kick @ 250 ms (low pitch), snare @ 1000 (mid zcr), hat @ 1500 (bright).
    kit.debugBeatboxFrames(const <BeatFrame>[
      (ms: 240, rms: 0.005, zcr: 0.0, pitchedLow: false),
      (ms: 250, rms: 0.30, zcr: 0.01, pitchedLow: true), // → kick, step 1
      (ms: 990, rms: 0.005, zcr: 0.0, pitchedLow: false),
      (ms: 1000, rms: 0.30, zcr: 0.45, pitchedLow: false), // → snare, step 4
      (ms: 1490, rms: 0.005, zcr: 0.0, pitchedLow: false),
      (ms: 1500, rms: 0.30, zcr: 0.67, pitchedLow: false), // → hat, step 6
    ]);
    await tester.pump();

    expect(kit.cellAt(Drum.kick, 1), isTrue);
    expect(kit.cellAt(Drum.snare, 4), isTrue);
    expect(kit.cellAt(Drum.hat, 6), isTrue);
    expect(kit.hitCount, 3);
    expect(kit.isListening, isFalse);
  });

  testWidgets('Send to Multitrack adds the beat as a DAW clip', (tester) async {
    final daw = DawService();
    await pumpGame(
      tester,
      const DrumkitScreen(),
      extraProviders: [ChangeNotifierProvider<DawService>.value(value: daw)],
    );
    final kit = _kit(tester);

    // Empty grid → nothing sent.
    kit.sendToDaw();
    expect(daw.clipCount, 0);

    kit.toggle(Drum.kick, 0);
    kit.toggle(Drum.snare, 4);
    await tester.pump();
    kit.sendToDaw();
    expect(daw.clipCount, 1);
    // The sent clip renders to real audio (a DrumSource over the beat).
    expect(daw.bake(), isNotEmpty);
  });

  testWidgets('the beat saves to the Song Book as a rhythm-line score',
      (tester) async {
    final songs = UserSongsService();
    await pumpGame(
      tester,
      const DrumkitScreen(),
      extraProviders: [
        ChangeNotifierProvider<UserSongsService>.value(value: songs),
      ],
    );
    final kit = _kit(tester);

    // Empty grid → nothing to save.
    expect(kit.debugMusicXml(), isNull);

    kit.toggle(Drum.kick, 0);
    kit.toggle(Drum.kick, 8);
    kit.toggle(Drum.hat, 4);
    await tester.pump();

    expect(songs.songs, isEmpty);
    final xml = kit.debugSaveToSongBook(songs);
    expect(xml, isNotNull);
    expect(xml, contains('<score-partwise'));
    expect(songs.songs, hasLength(1));
    expect(songs.songs.single.musicXml, contains('<score-partwise'));
  });
}
