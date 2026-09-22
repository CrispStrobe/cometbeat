// lib/core/audio/transcription/transcription_service.dart
//
// N2 — the app-facing orchestration for "transcribe a recording": WAV bytes → a
// crisp_notation Score, ready to open in the Song Book or Composition Workshop.
//
// Pure and web-safe: it wires the auto-router (route.dart) → rhythm (rhythm.dart)
// → the S5 engraver (transcribe.dart, which uses crisp_notation_core, not the
// Flutter barrel). The NEURAL engine is INJECTED as a [NeuralTranscriber] — this
// file never imports basic_pitch (which pulls dart:io), so it compiles on web,
// where the caller passes `neural: null` and the router uses the monophonic
// chain. The app supplies the real Basic Pitch transcriber on native when its
// model is present.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/harmony.dart'
    show ChordEstimator, ChordEvent;
import 'package:comet_beat/core/audio/transcription/metre.dart';
import 'package:comet_beat/core/audio/transcription/notation.dart';
import 'package:comet_beat/core/audio/transcription/rhythm.dart';
import 'package:comet_beat/core/audio/transcription/route.dart';
import 'package:comet_beat/core/audio/transcription/transcribe.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore, Score;

/// The outcome of transcribing a recording: the engraved [score], the [notes] it
/// was built from (each carries a `confidence` a UI can surface), which [engine]
/// the router chose, the [probe] that decided, the detected [bpm], the estimated
/// [meter] (beats-per-bar → the time signature), the [key], and any recognised
/// [chords] (empty unless a neural chord estimator was supplied).
///
/// [parts] is [score] split by instrument — one entry per distinct
/// [NoteEvent.program], each already re-spelled for the key. It is never
/// empty. With a single-instrument transcriber (every producer but MT3, all of
/// which report [gmProgramUnknown]) it holds exactly one part and [score] is
/// that part's score, so a caller that ignores [parts] sees no change. With MT3
/// it is how a multi-instrument take reaches the UI as more than one staff;
/// [multiPart] wraps it for the multi-part MusicXML writer.
typedef TranscriptionResult = ({
  Score score,
  List<TranscribedPart> parts,
  List<NoteEvent> notes,
  TranscriptionEngine engine,
  InputProbe probe,
  double bpm,
  Meter meter,
  KeyEstimate key,
  List<ChordEvent> chords,
});

/// Transcribe [wavBytes] (a PCM16 WAV, any channel count / sample rate) into a
/// Score. The router picks monophonic vs neural from the audio; pass [neural] to
/// enable the neural engine (native + model present), [forceEngine] to override
/// the probe (a user toggle), and [a4] for the tuning reference.
///
/// Never throws on empty/degenerate audio — returns an empty-measure Score.
/// Transcribe already-decoded mono PCM straight to a [Score] — the entry a DAW
/// clip (which holds its samples, not a WAV file) uses to get notes back from
/// audio. Same pipeline as [transcribeRecording] minus the WAV decode; defaults
/// to the pure-Dart monophonic engine so it always runs with no model download.
Future<Score> transcribePcmToScore(
  Float64List mono, {
  int sampleRate = 44100,
  double a4 = 440,
  NeuralTranscriber? neural,
  F0Estimator? f0,
  TranscriptionEngine? forceEngine = TranscriptionEngine.monophonic,
}) async {
  final routed = await transcribeAuto(
    mono,
    sampleRate: sampleRate,
    a4: a4,
    neural: neural,
    f0: f0,
    forceEngine: forceEngine,
  );
  final grid = detectRhythm(mono, sampleRate: sampleRate);
  final meter = estimateMeter(grid);
  final raw = transcribeToScore(
    routed.notes,
    grid,
    beatsPerBar: meter.beatsPerBar,
    clef: chooseClef(routed.notes),
  );
  return respell(raw, fifths: estimateKey(routed.notes).fifths);
}

Future<TranscriptionResult> transcribeRecording(
  Uint8List wavBytes, {
  double a4 = 440,
  NeuralTranscriber? neural,
  F0Estimator? f0,
  ChordEstimator? chordEstimator,
  TranscriptionEngine? forceEngine,
}) async {
  final wav = readWavPcm16(wavBytes);
  final mono = wavToMonoFloat(wav);
  final routed = await transcribeAuto(
    mono,
    sampleRate: wav.sampleRate,
    a4: a4,
    neural: neural,
    f0: f0,
    forceEngine: forceEngine,
  );
  final chords = chordEstimator == null
      ? const <ChordEvent>[]
      : await chordEstimator(mono, wav.sampleRate);
  final grid = detectRhythm(mono, sampleRate: wav.sampleRate);
  final meter = estimateMeter(grid);
  final raw = transcribeToScore(
    routed.notes,
    grid,
    beatsPerBar: meter.beatsPerBar,
    clef: chooseClef(routed.notes), // bass for a low line, else treble
  );
  // Detect the key and re-spell (B-flat, not A-sharp) + stamp the key signature.
  final key = estimateKey(routed.notes);
  final score = respell(raw, fifths: key.fifths);
  // Split by instrument. For every producer but MT3 this is one part holding
  // the whole take (all notes carry gmProgramUnknown), and its score is `score`
  // itself — the single-instrument path is untouched.
  final parts = [
    for (final part in transcribeToParts(
      routed.notes,
      grid,
      beatsPerBar: meter.beatsPerBar,
    ))
      (
        program: part.program,
        notes: part.notes,
        // Re-spell per part, so a transposing/low part is spelled in the key
        // rather than inheriting the whole take's accidentals by accident.
        score: respell(part.score, fifths: key.fifths),
      ),
  ];
  return (
    score: score,
    parts: parts,
    notes: routed.notes,
    engine: routed.engine,
    probe: routed.probe,
    bpm: grid.bpm,
    meter: meter,
    key: key,
    chords: chords,
  );
}

/// [TranscriptionResult.parts] as a [MultiPartScore] — what
/// `multiPartToMusicXml` takes, so a multi-instrument transcription exports as
/// one document with a `<part>` (and its own `<midi-program>`) per instrument
/// rather than one staff of piled-up chords.
MultiPartScore multiPart(TranscriptionResult result) =>
    MultiPartScore([for (final p in result.parts) p.score]);
