// lib/core/audio/transcription/stems.dart
//
// Stem-assembly glue for a WHOLE-SONG transcription. Source separation (W-SEP)
// splits a mix into stems; this routes each stem to the right engine and
// assembles a multi-part score — the jump from "transcribe a solo" to
// "transcribe a song". Pure Dart: the separator is INJECTED (like the neural
// transcriber), so this builds and tests NOW with synthetic stems, and W-SEP
// only has to provide the separation.
//
//   vocals       → monophonic (a single melodic voice)
//   bass         → monophonic (bass clef falls out of chooseClef)
//   other/accomp → the router's choice (usually neural → chords)
//   drums        → W-DRUMS (a percussion hit list, alongside the pitched score)
//
// Each pitched stem is engraved with correct key/accidentals/clef (respell +
// chooseClef) against ONE shared rhythm grid (from the drums stem if present, so
// every part lines up), then collected into a MultiPartScore.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/beat_grid.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/drums.dart';
import 'package:comet_beat/core/audio/transcription/metre.dart';
import 'package:comet_beat/core/audio/transcription/notation.dart';
import 'package:comet_beat/core/audio/transcription/rhythm.dart';
import 'package:comet_beat/core/audio/transcription/route.dart';
import 'package:comet_beat/core/audio/transcription/transcribe.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore, Score;

/// Separated stems (any may be absent). Each is mono audio at the song's rate.
typedef Stems = ({
  Float64List? vocals,
  Float64List? bass,
  Float64List? drums,
  Float64List? other,
});

/// A source separator (e.g. Demucs / Open-Unmix), injected by the caller so this
/// file never depends on the native model. W-SEP provides one.
typedef Separator = Future<Stems> Function(Float64List mono, int sampleRate);

/// A whole-song transcription: the pitched parts as a [score] (null when no
/// pitched stem was present) with their [partNames], plus the [drums] hits.
typedef StemTranscription = ({
  MultiPartScore? score,
  List<String> partNames,
  List<DrumHit> drums,
});

/// Route + engrave each present stem and assemble a multi-part score.
Future<StemTranscription> transcribeStems(
  Stems stems, {
  int sampleRate = 44100,
  NeuralTranscriber? neural,
  F0Estimator? f0,
  BeatGrid? beats,
}) async {
  // One shared grid so every part aligns; the drums carry the clearest beat.
  final beatSource = stems.drums ?? stems.bass ?? stems.other ?? stems.vocals;
  final detected = beatSource == null
      ? (bpm: 0.0, beatMs: const <double>[], onsetMs: const <double>[])
      : detectRhythm(beatSource, sampleRate: sampleRate);
  // A beat tracker's grid (beat-this), when there is one, replaces the
  // estimated beats and tempo; the note onsets still come from the audio.
  final tracked = beats != null && beats.beatMs.length >= 2;
  final RhythmGrid grid = tracked
      ? (bpm: beats.bpm, beatMs: beats.beatMs, onsetMs: detected.onsetMs)
      : detected;
  // Its downbeats also say how long a bar is, which onset timing alone can
  // only guess (estimateMeter cannot tell 2/4 from 4/4).
  final barBeats = tracked ? beats.beatsPerBar : null;
  final beatsPerBar =
      barBeats != null && barBeats >= 2 && barBeats <= 7 ? barBeats : null;
  // ...and where bar 1 starts: the beats before the first downbeat are an
  // upbeat. Only with a tracked bar length — a phase without a period means
  // nothing.
  final pickupBeats =
      tracked && beatsPerBar != null ? pickupBeatsOf(beats, beatsPerBar) : 0;

  final parts = <Score>[];
  final names = <String>[];

  Future<void> addPart(
    Float64List? mono,
    String name, {
    TranscriptionEngine? force,
  }) async {
    if (mono == null) return;
    parts.add(
      await _stemToScore(
        mono,
        grid,
        sampleRate,
        neural: neural,
        f0: f0,
        force: force,
        beatsPerBar: beatsPerBar,
        pickupBeats: pickupBeats,
      ),
    );
    names.add(name);
  }

  // Melody on top, accompaniment, then bass at the bottom.
  await addPart(stems.vocals, 'Vocals', force: TranscriptionEngine.monophonic);
  await addPart(stems.other, 'Accompaniment'); // router's choice → chords
  await addPart(stems.bass, 'Bass', force: TranscriptionEngine.monophonic);

  final drums = stems.drums == null
      ? const <DrumHit>[]
      : transcribeDrums(stems.drums!, sampleRate: sampleRate);

  return (
    score: parts.isEmpty ? null : MultiPartScore(parts),
    partNames: names,
    drums: drums,
  );
}

/// Transcribe a whole [mono] song: separate it (if a [separator] is given) and
/// assemble a multi-part score; with no separator, transcribe the mix as one
/// part so the call still works before W-SEP lands.
Future<StemTranscription> transcribeSong(
  Float64List mono, {
  Separator? separator,
  int sampleRate = 44100,
  NeuralTranscriber? neural,
  F0Estimator? f0,
  BeatGrid? beats,
}) async {
  if (separator == null) {
    return transcribeStems(
      (vocals: null, bass: null, drums: null, other: mono),
      sampleRate: sampleRate,
      neural: neural,
      f0: f0,
      beats: beats,
    );
  }
  final stems = await separator(mono, sampleRate);
  return transcribeStems(
    stems,
    sampleRate: sampleRate,
    neural: neural,
    f0: f0,
    beats: beats,
  );
}

Future<Score> _stemToScore(
  Float64List mono,
  RhythmGrid grid,
  int sampleRate, {
  NeuralTranscriber? neural,
  F0Estimator? f0,
  TranscriptionEngine? force,
  int? beatsPerBar,
  int pickupBeats = 0,
}) async {
  final routed = await transcribeAuto(
    mono,
    sampleRate: sampleRate,
    neural: neural,
    f0: f0,
    forceEngine: force,
  );
  final raw = transcribeToScore(
    routed.notes,
    grid,
    beatsPerBar: beatsPerBar ?? estimateMeter(grid).beatsPerBar,
    pickupBeats: pickupBeats,
    clef: chooseClef(routed.notes),
  );
  return respell(raw, fifths: estimateKey(routed.notes).fifths);
}
