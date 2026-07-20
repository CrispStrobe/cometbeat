// Live Looper "Perform" (S1) — stack/mute/undo/redo layers + a summed mix.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/beat_capture.dart' show BeatFrame;
import 'package:comet_beat/core/audio/loop_engine.dart' show PatternCell;
import 'package:comet_beat/core/services/live_voice.dart' show LiveVoiceMode;
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/composition/perform_screen.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

PerformTester _perform(WidgetTester tester) =>
    tester.state<State<PerformScreen>>(find.byType(PerformScreen))
        as PerformTester;

Widget _wrap(Widget home) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      // The shared keyboard's note-name labels read SettingsService (as in the
      // real app); provide a default one so the play-in panel builds.
      home: ChangeNotifierProvider(
        create: (_) => SettingsService(),
        child: home,
      ),
    );

double _peak(List<double> x) =>
    x.fold(0.0, (m, v) => v.abs() > m ? v.abs() : m);

bool _same(Float64List a, Float64List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-9) return false;
  }
  return true;
}

void main() {
  setUp(MelodyBridge.instance.clear);

  testWidgets('shares a melody layer out and loads a shared tune in',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    expect(p.hasMelodyLayer, isFalse);
    expect(p.canLoadSharedMelody, isFalse);

    // A tune another mode published (C-E-G, then a rest).
    MelodyBridge.instance.publish(
      SharedMelody(
        cells: const <PatternCell>[
          (midis: [60], steps: 2),
          (midis: [64], steps: 2),
          (midis: [67], steps: 4),
          (midis: null, steps: 8),
        ],
        tempoBpm: 100,
        source: 'loopmixer',
      ),
    );
    expect(p.canLoadSharedMelody, isTrue);

    // Pull it in — it becomes a melodic layer that sounds.
    p.loadSharedMelody();
    await tester.pump();
    expect(p.layerCount, 1);
    expect(p.hasMelodyLayer, isTrue);
    expect(_peak(p.debugMix()), greaterThan(0.0));

    // Share it back out — round-trips through the bridge (source looper).
    MelodyBridge.instance.clear();
    p.shareMelody();
    final shared = MelodyBridge.instance.current;
    expect(shared, isNotNull);
    expect(shared!.source, 'looper');
    expect(shared.isEmpty, isFalse);
  });

  testWidgets('stack layers, mute/undo/redo, and the mix reflects it',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    expect(p.layerCount, 0);
    expect(p.debugMix().every((v) => v == 0), isTrue); // silence when empty

    p.addSeed('beat');
    await tester.pump();
    p.addSeed('bass');
    await tester.pump();
    expect(p.layerCount, 2);
    expect(_peak(p.debugMix()), greaterThan(0.0)); // the jam makes sound

    // Muting a layer changes the mix; unmuting restores it.
    final full = _peak(p.debugMix());
    p.toggleMute(0);
    await tester.pump();
    expect(p.isMuted(0), isTrue);
    final muted = _peak(p.debugMix());
    expect(muted, lessThan(full)); // one layer removed → quieter/different
    p.toggleMute(0);
    await tester.pump();
    expect(p.isMuted(0), isFalse);

    // Undo drops the newest layer; redo brings it back.
    p.undoLayer();
    await tester.pump();
    expect(p.layerCount, 1);
    expect(p.canRedo, isTrue);
    p.redoLayer();
    await tester.pump();
    expect(p.layerCount, 2);

    // Clear wipes everything.
    p.clearAll();
    await tester.pump();
    expect(p.layerCount, 0);
    expect(p.canUndo, isFalse);
  });

  testWidgets('play-in a melody becomes a new layer', (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.startPlayIn();
    await tester.pump();
    expect(p.isPlayingIn, isTrue);

    // Tap a little C-major run.
    for (final midi in [60, 64, 67, 72]) {
      p.playInNote(midi);
    }
    p.finishPlayIn();
    await tester.pump();

    expect(p.isPlayingIn, isFalse);
    expect(p.layerCount, 1); // the played melody is now a layer
    expect(p.layerLabel(0), 'melody');
    expect(_peak(p.debugMix()), greaterThan(0.0)); // and it makes sound

    // Cancel discards without adding a layer.
    p.startPlayIn();
    p.playInNote(62);
    p.cancelPlayIn();
    await tester.pump();
    expect(p.layerCount, 1); // still just the first melody
  });

  testWidgets('play-in a beat via pads becomes a new layer', (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.startPlayInBeat();
    await tester.pump();
    expect(p.isPlayingIn, isTrue);

    // Tap a little kick/snare/hat pattern.
    for (final pad in ['kick', 'hat', 'snare', 'hat']) {
      p.playInPad(pad);
    }
    p.finishPlayIn();
    await tester.pump();

    expect(p.isPlayingIn, isFalse);
    expect(p.layerCount, 1);
    expect(p.layerLabel(0), 'beat');
    expect(_peak(p.debugMix()), greaterThan(0.0)); // the beat sounds

    // A melody tap while in beat mode is ignored (wrong mode).
    p.startPlayInBeat();
    p.playInNote(60); // ignored
    p.cancelPlayIn();
    await tester.pump();
    expect(p.layerCount, 1); // nothing added
  });

  testWidgets('scenes snapshot active layers; launch + arm reapply them',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.addSeed('beat');
    p.addSeed('bass');
    p.addSeed('chords');
    await tester.pump();
    expect(p.layerCount, 3);

    // Scene A = all three on.
    p.saveScene();
    // Scene B = just the beat (mute bass + chords, snapshot, then restore).
    p.toggleMute(1);
    p.toggleMute(2);
    p.saveScene();
    p.toggleMute(1);
    p.toggleMute(2);
    await tester.pump();

    expect(p.sceneCount, 2);
    expect(p.sceneActiveCount(0), 3);
    expect(p.sceneActiveCount(1), 1);

    // Launch scene B → only the beat is unmuted.
    p.launchScene(1);
    await tester.pump();
    expect(p.isMuted(0), isFalse);
    expect(p.isMuted(1), isTrue);
    expect(p.isMuted(2), isTrue);

    // Launch scene A → all back on.
    p.launchScene(0);
    await tester.pump();
    expect([p.isMuted(0), p.isMuted(1), p.isMuted(2)], everyElement(isFalse));

    // Arm queues without applying; launchArmed applies + clears.
    p.armScene(1);
    await tester.pump();
    expect(p.armedScene, 1);
    expect(p.isMuted(1), isFalse); // not applied yet
    p.launchArmed();
    await tester.pump();
    expect(p.armedScene, isNull);
    expect(p.isMuted(1), isTrue); // scene B applied
    expect(p.isMuted(2), isTrue);

    // Arm again toggles off.
    p.armScene(0);
    p.armScene(0);
    await tester.pump();
    expect(p.armedScene, isNull);

    // Remove a scene.
    p.removeScene(0);
    await tester.pump();
    expect(p.sceneCount, 1);
  });

  testWidgets('bounce builds My-Samples clips (whole mix + per active layer)',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.addSeed('beat');
    p.addSeed('bass');
    await tester.pump();

    // Whole loop → one clip that carries sound.
    final mix = p.debugBounce('Perf');
    expect(mix.length, 1);
    expect(mix.first, isA<SampleClip>());
    expect(mix.first.name, 'Perf');
    expect(mix.first.pcm.isNotEmpty, isTrue);
    expect(_peak(mix.first.pcm.toList()), greaterThan(0.0));

    // Per layer → one clip per ACTIVE layer.
    expect(p.debugBounce('Perf', perLayer: true).length, 2);

    // Muting a layer drops it from the per-layer bounce.
    p.toggleMute(0);
    await tester.pump();
    expect(p.debugBounce('Perf', perLayer: true).length, 1);

    // Nothing playing → nothing to bounce.
    p.clearAll();
    await tester.pump();
    expect(p.debugBounce('Perf'), isEmpty);
    expect(p.debugBounce('Perf', perLayer: true), isEmpty);
  });

  testWidgets('sample voice plays pitched + records a melody in that sound',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    final sample = Float64List(4410)..fillRange(0, 4410, 0.5);
    p.setSampleVoice(sample, baseMidi: 60, name: 'meow');
    await tester.pump();
    expect(p.hasSampleVoice, isTrue);
    expect(p.voiceName, 'meow');

    // Pitch: at the base note = original length; an octave up = half as long.
    expect(p.debugPitched(60).length, 4410);
    final octaveUp = p.debugPitched(72);
    expect(octaveUp.length, 2205);
    expect(_peak(octaveUp.toList()), greaterThan(0.0));

    // Recording a melody now uses the sample → a non-silent 'melody' layer.
    p.startPlayIn();
    for (final m in [60, 64, 67]) {
      p.playInNote(m);
    }
    p.finishPlayIn();
    await tester.pump();
    expect(p.layerCount, 1);
    expect(p.layerLabel(0), 'melody');
    expect(_peak(p.debugMix().toList()), greaterThan(0.0));

    // Clearing the voice returns to the synth.
    p.clearSampleVoice();
    await tester.pump();
    expect(p.hasSampleVoice, isFalse);
    expect(p.debugPitched(60), isEmpty);
  });

  testWidgets('pad voices: a pad plays your own sound in the beat layer',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    expect(p.hasPadVoice('kick'), isFalse);
    // Synth kick starts at ~0 (a sine's first sample).
    expect(p.debugBeat([('kick', 0)])[0].abs(), lessThan(0.05));

    // Assign a constant sample → the beat renders THAT sound at the hit.
    final sample = Float64List(2205)..fillRange(0, 2205, 0.5);
    p.setPadVoice('kick', sample, name: 'boom');
    await tester.pump();
    expect(p.hasPadVoice('kick'), isTrue);
    expect(p.padVoiceName('kick'), 'boom');
    expect(p.debugBeat([('kick', 0)])[0], greaterThan(0.3));

    // Clearing returns the synth drum.
    p.clearPadVoice('kick');
    await tester.pump();
    expect(p.hasPadVoice('kick'), isFalse);
    expect(p.debugBeat([('kick', 0)])[0].abs(), lessThan(0.05));
  });

  testWidgets('groove setup: tempo + key change the seeds, lock once building',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    expect(p.bpm, 120);
    expect(p.keyShift, 0);
    expect(p.canSetup, isTrue);

    final bassC = p.debugSeed('bass');
    expect(bassC.length, 88200); // one bar at 120 bpm

    // Key change transposes the seed (same length, different waveform).
    p.setKey(7); // G
    await tester.pump();
    expect(p.keyShift, 7);
    final bassG = p.debugSeed('bass');
    expect(bassG.length, 88200);
    expect(_same(bassC, bassG), isFalse);

    // Tempo change re-sizes the bar.
    p.setTempo(100);
    await tester.pump();
    expect(p.bpm, 100);
    expect(p.debugSeed('bass').length, 105840); // one bar at 100 bpm

    // Adding a layer locks setup; further tempo/key changes are ignored.
    p.addSeed('beat');
    await tester.pump();
    expect(p.canSetup, isFalse);
    p.setTempo(120);
    p.setKey(0);
    expect(p.bpm, 100);
    expect(p.keyShift, 7);
  });

  testWidgets('sing/beatbox capture converts frames into a layer',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    const totalMs = 2000; // one bar at 120 bpm
    expect(p.isCapturing, isFalse);

    // A sung line: two held (pentatonic) pitches across the bar.
    final samples = <(double, int?)>[
      for (var t = 0; t < totalMs; t += 20)
        (t.toDouble(), t < totalMs ~/ 2 ? 60 : 64),
    ];
    p.addSungLayer(samples, totalMs: totalMs);
    await tester.pump();
    expect(p.layerCount, 1);
    expect(p.layerLabel(0), 'melody');
    expect(_peak(p.debugMix().toList()), greaterThan(0.0));

    // A beatboxed pattern: four loud onsets over the bar.
    final frames = <BeatFrame>[
      for (var t = 0; t < totalMs; t += 20)
        (
          ms: t.toDouble(),
          rms: (t % 500 == 0) ? 0.8 : 0.0001,
          zcr: (t % 500 == 0) ? 0.05 : 0.0,
          pitchedLow: t % 500 == 0,
        ),
    ];
    p.addBeatboxLayer(frames, totalMs: totalMs);
    await tester.pump();
    expect(p.layerCount, 2);
    expect(p.layerLabel(1), 'beat');
    expect(_peak(p.debugMix().toList()), greaterThan(0.0));

    // Nothing captured → no layer added.
    p.addSungLayer(const [], totalMs: totalMs);
    p.addBeatboxLayer(const [], totalMs: totalMs);
    await tester.pump();
    expect(p.layerCount, 2);
  });

  testWidgets('transport reports loop position while running, resets on stop',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    // Stopped: no playhead.
    expect(p.loopProgress, 0.0);
    expect(p.currentBeat, -1);

    // Playing: the clock runs → a live position (at/after the downbeat).
    p.addSeed('beat');
    p.play();
    await tester.pump();
    expect(p.isPlaying, isTrue);
    expect(p.currentBeat, inInclusiveRange(0, 3));
    expect(p.loopProgress, inInclusiveRange(0.0, 1.0));

    // Stop resets the transport.
    p.stop();
    await tester.pump();
    expect(p.loopProgress, 0.0);
    expect(p.currentBeat, -1);
  });

  testWidgets('multi-bar loop length: captures span the loop, seeds tile',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    expect(p.bars, 1);
    // A seed is always one bar.
    expect(p.debugSeed('bass').length, 88200);

    // Choose a 4-bar loop (while empty).
    p.setLoopBars(4);
    await tester.pump();
    expect(p.bars, 4);
    expect(p.debugSeed('bass').length, 88200); // seed stays one bar

    // A played-in melody now spans the whole 4-bar loop.
    p.startPlayIn();
    for (final m in [60, 64, 67, 72]) {
      p.playInNote(m);
    }
    p.finishPlayIn();
    await tester.pump();
    expect(p.layerCount, 1);
    expect(_peak(p.debugMix().toList()), greaterThan(0.0));
    // The mix runs the full 4 bars (88200 * 4).
    expect(p.debugMix().length, 88200 * 4);

    // Length locks once a layer exists.
    p.setLoopBars(1);
    expect(p.bars, 4);
  });

  testWidgets('export gates on having a mix; the exported mix carries sound',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    expect(p.canExport, isFalse); // nothing to export yet

    p.addSeed('beat');
    await tester.pump();
    expect(p.canExport, isTrue);
    // The export content carries sound.
    expect(_peak(p.debugMix().toList()), greaterThan(0.0));

    // Muting the only layer leaves nothing to export.
    p.toggleMute(0);
    await tester.pump();
    expect(p.canExport, isFalse);
  });

  testWidgets('per-layer volume changes the mix; the drop ducks + releases',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.addSeed('beat');
    await tester.pump();
    final full = _peak(p.debugMix().toList());
    expect(full, greaterThan(0.0));
    expect(p.layerGain(0), 1.0);

    // Turning a layer down quiets the mix; silencing it drops out entirely.
    p.setLayerGain(0, 0.0);
    await tester.pump();
    expect(p.layerGain(0), 0.0);
    expect(_peak(p.debugMix().toList()), lessThan(full));
    p.setLayerGain(0, 1.0);
    await tester.pump();

    // The drop ducks the whole mix, then a boundary release slams it back.
    p.play();
    expect(p.masterLevel, 1.0);
    expect(p.isDropped, isFalse);
    p.drop();
    await tester.pump();
    expect(p.isDropped, isTrue);
    expect(p.masterLevel, lessThan(1.0));
    p.releaseDrop();
    await tester.pump();
    expect(p.isDropped, isFalse);
    expect(p.masterLevel, 1.0);
  });

  testWidgets('scene-chain plays scenes in order and wraps', (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.addSeed('beat');
    p.addSeed('bass');
    await tester.pump();

    // Scene A = both on; scene B = beat only.
    p.saveScene();
    p.toggleMute(1);
    p.saveScene();
    p.toggleMute(1);
    await tester.pump();
    expect(p.sceneCount, 2);

    // Start the chain → scene A applied, both on.
    p.play();
    p.playChain();
    await tester.pump();
    expect(p.isChaining, isTrue);
    expect(p.chainPos, 0);
    expect(p.isMuted(1), isFalse);

    // A boundary advances to scene B (beat only).
    p.advanceChain();
    await tester.pump();
    expect(p.chainPos, 1);
    expect(p.isMuted(1), isTrue);

    // Next boundary wraps back to scene A.
    p.advanceChain();
    await tester.pump();
    expect(p.chainPos, 0);
    expect(p.isMuted(1), isFalse);

    // A manual launch overrides + stops the chain.
    p.launchScene(1);
    await tester.pump();
    expect(p.isChaining, isFalse);
    expect(p.isMuted(1), isTrue);
  });

  testWidgets('swing shifts off-beats; straight is unchanged; locks on build',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    expect(p.swing, 0.0);
    final straight = p.debugSeed('beat');

    // Swing moves the off-beat hats → a different waveform (same length).
    p.setSwing(0.5);
    await tester.pump();
    expect(p.swing, 0.5);
    final swung = p.debugSeed('beat');
    expect(swung.length, straight.length);
    expect(_same(straight, swung), isFalse);

    // Straight again reproduces the original render exactly.
    p.setSwing(0.0);
    await tester.pump();
    expect(_same(straight, p.debugSeed('beat')), isTrue);

    // Locks once a layer is baked.
    p.setSwing(0.5);
    p.addSeed('beat');
    await tester.pump();
    p.setSwing(0.0);
    expect(p.swing, 0.5);
  });

  testWidgets('play-in voices cache note WAVs; a voice change invalidates',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    // A synth note builds a WAV and caches it (same instance on re-tap).
    final a = p.debugNoteWav(60);
    expect(a.isNotEmpty, isTrue);
    expect(identical(p.debugNoteWav(60), a), isTrue);
    // A different note is a different cache entry.
    expect(identical(p.debugNoteWav(67), a), isFalse);

    // Setting a sample voice invalidates the cache → notes rebuild from it.
    p.setSampleVoice(
      Float64List(4410)..fillRange(0, 4410, 0.5),
      baseMidi: 60,
      name: 'x',
    );
    await tester.pump();
    final b = p.debugNoteWav(60);
    expect(identical(b, a), isFalse);
    expect(b.isNotEmpty, isTrue);
    expect(identical(p.debugNoteWav(60), b), isTrue); // re-cached
  });

  testWidgets('accent captures velocity: soft taps render quieter than loud',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    expect(p.accent, 1.0);

    // Play a soft beat.
    p.setAccent(0.55);
    await tester.pump();
    expect(p.accent, 0.55);
    p.startPlayInBeat();
    for (final d in ['kick', 'snare', 'hat', 'kick']) {
      p.playInPad(d);
    }
    p.finishPlayIn();
    await tester.pump();
    final soft = _peak(p.debugMix().toList());

    // Same beat, loud.
    p.clearAll();
    p.setAccent(1.5);
    await tester.pump();
    p.startPlayInBeat();
    for (final d in ['kick', 'snare', 'hat', 'kick']) {
      p.playInPad(d);
    }
    p.finishPlayIn();
    await tester.pump();
    final loud = _peak(p.debugMix().toList());

    expect(loud, greaterThan(soft)); // velocity made it louder
  });

  testWidgets('audio-path toggle switches mode; degrades to classic for now',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    // Default is Auto, and with no real-time engine built yet it degrades.
    expect(p.liveMode, LiveVoiceMode.auto);
    expect(p.isRealtimeActive, isFalse);

    // The kid can force Classic or Real-time; both are safe (Real-time still
    // falls back until the engine lands in R2).
    p.setLiveMode(LiveVoiceMode.classic);
    await tester.pump();
    expect(p.liveMode, LiveVoiceMode.classic);
    expect(p.isRealtimeActive, isFalse);

    p.setLiveMode(LiveVoiceMode.realtime);
    await tester.pump();
    expect(p.liveMode, LiveVoiceMode.realtime);
    expect(p.isRealtimeActive, isFalse); // graceful degrade
  });

  testWidgets('LL1: layers carry a symbolic pattern (seed + played-in)',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    // A seed beat has the drum pattern behind it (kick on 1 & 3, etc.).
    p.addSeed('beat');
    await tester.pump();
    final beat = p.debugLayerCells(0);
    expect(beat, isNotEmpty);
    expect(beat, contains((2, 0))); // kick lane, step 0
    expect(beat, contains((2, 8))); // kick lane, step 8 (beat 3)
    expect(beat, contains((1, 4))); // snare lane, step 4 (beat 2)

    // A played-in melody's cells carry the actual pitches (row = midi).
    p.startPlayIn();
    for (final m in [60, 64, 67]) {
      p.playInNote(m);
    }
    p.finishPlayIn();
    await tester.pump();
    final melody = p.debugLayerCells(1);
    expect(melody.map((c) => c.$1), containsAll([60, 64, 67]));
  });

  testWidgets('LL2: tapping a beat/melody cell toggles it and re-renders',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.addSeed('beat');
    await tester.pump();
    expect(p.debugLayerCells(0), contains((2, 0))); // seed kick at step 0

    // Beat: toggling an ON cell removes it; an empty cell adds it.
    p.toggleCell(0, 2, 0);
    await tester.pump();
    expect(p.debugLayerCells(0), isNot(contains((2, 0))));
    p.toggleCell(0, 2, 1);
    await tester.pump();
    expect(p.debugLayerCells(0), contains((2, 1)));
    expect(_peak(p.debugMix().toList()), greaterThan(0.0));

    // Melody: a played-in note can be removed, and a new diatonic note added.
    p.startPlayIn();
    p.playInNote(60); // C4
    p.finishPlayIn();
    await tester.pump();
    expect(p.debugLayerCells(1), contains((60, 0)));
    p.toggleCell(1, 60, 0); // remove it
    await tester.pump();
    expect(p.debugLayerCells(1), isNot(contains((60, 0))));
    p.toggleCell(1, 67, 4); // add G4 at step 4
    await tester.pump();
    expect(p.debugLayerCells(1), contains((67, 4)));
    expect(_peak(p.debugMix().toList()), greaterThan(0.0));
  });

  testWidgets('play/stop toggles and does not crash without audio',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.play(); // no layers yet → stays stopped
    expect(p.isPlaying, isFalse);

    p.addSeed('melody');
    await tester.pump();
    p.play();
    expect(p.isPlaying, isTrue);
    p.stop();
    expect(p.isPlaying, isFalse);
  });
}
