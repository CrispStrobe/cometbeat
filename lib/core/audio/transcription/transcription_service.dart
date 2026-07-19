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
import 'package:comet_beat/core/audio/transcription/metre.dart';
import 'package:comet_beat/core/audio/transcription/rhythm.dart';
import 'package:comet_beat/core/audio/transcription/route.dart';
import 'package:comet_beat/core/audio/transcription/transcribe.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Score;

/// The outcome of transcribing a recording: the engraved [score], the [notes] it
/// was built from (each carries a `confidence` a UI can surface), which [engine]
/// the router chose, the [probe] that decided, the detected [bpm], and the
/// estimated [meter] (beats-per-bar → the score's time signature).
typedef TranscriptionResult = ({
  Score score,
  List<NoteEvent> notes,
  TranscriptionEngine engine,
  InputProbe probe,
  double bpm,
  Meter meter,
});

/// Transcribe [wavBytes] (a PCM16 WAV, any channel count / sample rate) into a
/// Score. The router picks monophonic vs neural from the audio; pass [neural] to
/// enable the neural engine (native + model present), [forceEngine] to override
/// the probe (a user toggle), and [a4] for the tuning reference.
///
/// Never throws on empty/degenerate audio — returns an empty-measure Score.
Future<TranscriptionResult> transcribeRecording(
  Uint8List wavBytes, {
  double a4 = 440,
  NeuralTranscriber? neural,
  TranscriptionEngine? forceEngine,
}) async {
  final wav = readWavPcm16(wavBytes);
  final mono = wavToMonoFloat(wav);
  final routed = await transcribeAuto(
    mono,
    sampleRate: wav.sampleRate,
    a4: a4,
    neural: neural,
    forceEngine: forceEngine,
  );
  final grid = detectRhythm(mono, sampleRate: wav.sampleRate);
  final meter = estimateMeter(grid);
  final score = transcribeToScore(
    routed.notes,
    grid,
    beatsPerBar: meter.beatsPerBar,
  );
  return (
    score: score,
    notes: routed.notes,
    engine: routed.engine,
    probe: routed.probe,
    bpm: grid.bpm,
    meter: meter,
  );
}
