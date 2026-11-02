// lib/features/games/explain/dynamics_demo.dart
//
// Plays dynamic levels one after another (a short repeated note per level, at
// the level's MusicTerm.gain) and publishes WHICH level is sounding right now,
// so the explanation card's loudness ladder lights up in step with the sound.
//
// One WAV is rendered (each note peak-normalized then scaled by its gain — the
// same trick as the crescendo ear game), so the levels are gap-accurate and a
// single `playWavBytes` call plays them; the timers only drive the highlight.

import 'dart:async';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/explain/music_terms.dart';
import 'package:flutter/foundation.dart';

class DynamicsDemo {
  /// The dynamic level currently sounding (null = silent).
  final ValueNotifier<MusicTerm?> sounding = ValueNotifier(null);

  final List<Timer> _timers = [];

  /// Plays [levels] in order after [lead] (leaving room for the answer blip),
  /// [notesPerLevel] notes of [noteMs] each on MIDI [midi].
  void play(
    AudioService audio,
    List<MusicTerm> levels, {
    int midi = 67,
    int notesPerLevel = 2,
    int noteMs = 240,
    Duration lead = const Duration(milliseconds: 250),
  }) {
    stop();
    if (levels.isEmpty) return;
    final timbre = timbreFor(audio.instrument);
    final pcm = <int>[];
    for (final level in levels) {
      for (var n = 0; n < notesPerLevel; n++) {
        pcm.addAll(
          renderSegments(
            [
              (freqs: [midiToFrequency(midi)], ms: noteMs),
            ],
            timbre: timbre,
            gain: level.gain,
          ),
        );
      }
    }
    final wav = wavBytes(Int16List.fromList(pcm));
    final levelMs = notesPerLevel * noteMs;
    _timers.add(Timer(lead, () => audio.playWavBytes(wav)));
    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      _timers.add(
        Timer(
          lead + Duration(milliseconds: i * levelMs),
          () => sounding.value = level,
        ),
      );
    }
    _timers.add(
      Timer(
        lead + Duration(milliseconds: levels.length * levelMs),
        () => sounding.value = null,
      ),
    );
  }

  /// Cancels any pending highlight steps (the sound itself is a single clip
  /// and is cut by the next sound the game plays).
  void stop() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    sounding.value = null;
  }

  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    sounding.dispose();
  }
}
