// lib/core/services/audio_service.dart
//
// Plays synthesized pitches/chords/sequences (core/audio/synth.dart) via
// audioplayers. Playback failures are swallowed: audio is juice, never a
// requirement — tests and platforms without audio must not break.

import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:klang_universum/core/audio/synth.dart';

class AudioService {
  AudioPlayer? _player;

  Future<void> _play(Uint8List wav) async {
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
        renderWav([
          (freqs: [midiToFrequency(midi)], ms: ms),
        ]),
      );

  Future<void> playMidiChord(List<int> midis, {int ms = 1200}) => _play(
        renderWav([(freqs: midis.map(midiToFrequency).toList(), ms: ms)]),
      );

  /// Arpeggio (bottom-up), then the block chord.
  Future<void> playArpeggioThenChord(List<int> midis) {
    final freqs = midis.map(midiToFrequency).toList();
    return _play(
      renderWav([
        for (final f in freqs) (freqs: [f], ms: 400),
        (freqs: freqs, ms: 1200),
      ]),
    );
  }

  /// Sequential melody of (midi, ms) notes.
  Future<void> playSequence(List<(int, int)> notes) => _play(
        renderWav([
          for (final (midi, ms) in notes)
            (freqs: [midiToFrequency(midi)], ms: ms),
        ]),
      );

  /// Sequential chords (e.g. a cadence), [ms] each.
  Future<void> playChordSequence(List<List<int>> chords, {int ms = 900}) =>
      _play(
        renderWav([
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
        renderWav([
          for (final midis in cadence)
            (freqs: midis.map(midiToFrequency).toList(), ms: cadenceMs),
          (freqs: const <double>[], ms: gapMs),
          (freqs: target.map(midiToFrequency).toList(), ms: targetMs),
        ]),
      );

  // Retro feedback SFX, rendered once and cached.
  static Uint8List? _correctWav;
  static Uint8List? _wrongWav;
  static Uint8List? _fanfareWav;

  Future<void> playCorrect() => _play(_correctWav ??= renderSfxCorrect());

  Future<void> playWrong() => _play(_wrongWav ??= renderSfxWrong());

  Future<void> playFanfare() => _play(_fanfareWav ??= renderSfxFanfare());

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
