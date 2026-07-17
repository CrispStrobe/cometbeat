// lib/core/services/audio_service.dart
//
// Plays synthesized pitches/chords/sequences (core/audio/synth.dart) via
// audioplayers. Playback failures are swallowed: audio is juice, never a
// requirement — tests and platforms without audio must not break.

import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  AudioPlayer? _player;

  /// The voice used for pitched notes/chords/sequences (not the retro SFX).
  /// Wired from the instrument setting in main.dart.
  Instrument instrument = Instrument.piano;

  /// Master sound switch, mirrored from [SettingsService.soundOn] in main.dart.
  /// When false, every `_play` below is a no-op — the whole app goes quiet with
  /// one flag. The mic (a separate plugin) is unaffected. On by default.
  bool soundOn = true;

  /// Route synthesized playback to the loud **speaker** (not the earpiece).
  /// Called once at startup and again after microphone capture: on iOS/Android
  /// the `record` plugin flips the shared audio session to record/earpiece and
  /// can leave it there, which makes the app sound silent afterwards. Re-routing
  /// to the speaker restores audible playback. Best-effort — audio is juice, so
  /// failures (and the web, which has no such session) are swallowed.
  Future<void> configurePlaybackRoute() async {
    if (kIsWeb) return;
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(route: AudioContextConfigRoute.speaker).build(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[AUDIO] setAudioContext unavailable: $e');
    }
  }

  Uint8List _wav(List<Segment> segments) =>
      renderWav(segments, timbre: timbreFor(instrument));

  Future<void> _play(Uint8List wav) async {
    if (!soundOn) return; // master mute (SettingsService.soundOn)
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      if (kIsWeb) {
        // BytesSource is not supported by the web implementation; a data
        // URI plays fine in the browser's audio element.
        await player
            .play(UrlSource('data:audio/wav;base64,${base64Encode(wav)}'));
      } else {
        await player.play(BytesSource(wav, mimeType: 'audio/wav'));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AUDIO] playback unavailable: $e');
    }
  }

  Future<void> playMidiNote(int midi, {int ms = 700}) => _play(
        _wav([
          (freqs: [midiToFrequency(midi)], ms: ms),
        ]),
      );

  /// A metronome tick ([accent]ed on the downbeat). Used by the play-along
  /// count-in.
  Future<void> playTick({bool accent = false}) =>
      _play(renderSfxTick(accent: accent));

  Future<void> playMidiChord(List<int> midis, {int ms = 1200}) => _play(
        _wav([(freqs: midis.map(midiToFrequency).toList(), ms: ms)]),
      );

  /// Arpeggio (bottom-up), then the block chord.
  Future<void> playArpeggioThenChord(List<int> midis) {
    final freqs = midis.map(midiToFrequency).toList();
    return _play(
      _wav([
        for (final f in freqs) (freqs: [f], ms: 400),
        (freqs: freqs, ms: 1200),
      ]),
    );
  }

  /// A short melodic phrase at a given tempo ([noteMs] per note) and dynamic
  /// level ([gain], 0..1) — the audio behind Dynamics & Tempo Charades.
  Future<void> playPhrase(
    List<int> midis, {
    int noteMs = 400,
    double gain = 1.0,
  }) =>
      _play(
        renderWav(
          [
            for (final m in midis) (freqs: [midiToFrequency(m)], ms: noteMs),
          ],
          timbre: timbreFor(instrument),
          gain: gain,
        ),
      );

  /// Sequential melody of (midi, ms) notes.
  Future<void> playSequence(List<(int, int)> notes) => _play(
        _wav([
          for (final (midi, ms) in notes)
            (freqs: [midiToFrequency(midi)], ms: ms),
        ]),
      );

  /// Plays a timed sequence of chords: each entry is `(midi pitches, ms)`. An
  /// **empty pitch list renders as a rest** (silence), so a full score timeline
  /// — notes, chords and rests, each at its own tempo-scaled duration — plays as
  /// one gap-accurate WAV. Backs the Workshop's score playback.
  Future<void> playTimedChords(List<(List<int>, int)> events) => _play(
        _wav([
          for (final (midis, ms) in events)
            if (ms > 0) (freqs: midis.map(midiToFrequency).toList(), ms: ms),
        ]),
      );

  /// Plays several parts **at once** (multi-part score playback). Each part is a
  /// timed-chord list like [playTimedChords]; every part starts together at t=0
  /// (its rests are silent segments), so parts of different lengths stay aligned.
  /// Parts are rendered to raw samples with the current [instrument] voice and
  /// combined with [mixStems] (per-stem unit-peak × gain → tanh soft-knee), so
  /// adding or muting a part never pumps the overall level. An empty [parts]
  /// list, or all-empty parts, is a silent no-op.
  Future<void> playMixedTimedChords(List<List<(List<int>, int)>> parts) {
    if (!soundOn) return Future.value(); // rendering is wasted while muted
    final timbre = timbreFor(instrument);
    final stems = <MixStem>[];
    var totalSamples = 0;
    for (final events in parts) {
      final segments = <Segment>[
        for (final (midis, ms) in events)
          if (ms > 0) (freqs: midis.map(midiToFrequency).toList(), ms: ms),
      ];
      if (segments.isEmpty) continue;
      final samples = renderSegmentsRaw(segments, timbre: timbre);
      if (samples.length > totalSamples) totalSamples = samples.length;
      stems.add((samples: samples, gain: 1.0));
    }
    if (stems.isEmpty) return Future.value();
    return _play(wavBytes(mixStems(stems, totalSamples: totalSamples)));
  }

  /// Sequential chords (e.g. a cadence), [ms] each.
  Future<void> playChordSequence(List<List<int>> chords, {int ms = 900}) =>
      _play(
        _wav([
          for (final midis in chords)
            (freqs: midis.map(midiToFrequency).toList(), ms: ms),
        ]),
      );

  /// Functional ear training: play a context cadence (e.g. I–IV–V–I), a short
  /// silent gap, then the target chord held longer so it stands out. An empty
  /// [Segment] renders as silence, which separates the target audibly.
  Future<void> playCadenceThenTarget(
    List<List<int>> cadence,
    List<int> target, {
    int cadenceMs = 620,
    int gapMs = 420,
    int targetMs = 1300,
  }) =>
      _play(
        _wav([
          for (final midis in cadence)
            (freqs: midis.map(midiToFrequency).toList(), ms: cadenceMs),
          (freqs: const <double>[], ms: gapMs),
          (freqs: target.map(midiToFrequency).toList(), ms: targetMs),
        ]),
      );

  /// Plays a note of [beats] quarter-beats with an audible pulse on each beat —
  /// a tick blended with the tone, re-articulated every beat, so the child can
  /// count "1–2–3" along with the sounding note.
  Future<void> playCountedNote(int beats, {int beatMs = 550}) {
    final note = midiToFrequency(67);
    final tick = midiToFrequency(84);
    return _play(
      _wav([
        for (var b = 0; b < beats; b++) ...[
          (freqs: [note, tick], ms: 70),
          (freqs: [note], ms: beatMs - 70),
        ],
      ]),
    );
  }

  /// Demonstrates a note/rest length: a note sustains a tone for [beats] beats;
  /// a rest frames [beats] beats of silence between two soft ticks. Used by the
  /// Symbol Quiz to make "how long is this?" audible.
  Future<void> playNoteLength(double beats, {required bool isRest}) {
    const beatMs = 480;
    final ms = (beats * beatMs).round().clamp(120, 4000);
    if (isRest) {
      return _play(
        _wav([
          (freqs: [midiToFrequency(84)], ms: 80),
          (freqs: const <double>[], ms: ms),
          (freqs: [midiToFrequency(84)], ms: 80),
        ]),
      );
    }
    return _play(
      _wav([
        (freqs: [midiToFrequency(69)], ms: ms),
      ]),
    );
  }

  // Retro feedback SFX, rendered once and cached.
  static Uint8List? _correctWav;
  static Uint8List? _wrongWav;
  static Uint8List? _fanfareWav;

  Future<void> playCorrect() => _play(_correctWav ??= renderSfxCorrect());

  Future<void> playWrong() => _play(_wrongWav ??= renderSfxWrong());

  Future<void> playFanfare() => _play(_fanfareWav ??= renderSfxFanfare());

  /// Stops whatever is currently sounding. Used by hold-to-play games so a note
  /// rings only while the pad is held.
  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (e) {
      if (kDebugMode) debugPrint('[AUDIO] stop unavailable: $e');
    }
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
