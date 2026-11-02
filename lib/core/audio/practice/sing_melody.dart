// lib/core/audio/practice/sing_melody.dart
//
// The sung melody of a separated vocal stem, found OFF the UI isolate.
//
// A whole song's vocal stem is minutes of audio: F0 + note segmentation over a
// 4-minute track measured ~36 s, which on the UI isolate is a frozen screen.
// Everything here therefore runs inside one [Isolate.run], and the F0 engine
// is opened INSIDE it — an FFI session or ONNX handle cannot cross isolates.
//
// Engine: CREPE via CrispASR's ggml FFI when its model is already cached (the
// same engine the transcription framework prefers), else WORLD DIO — the
// pure-Dart, model-free F0 the framework falls back to. No download is ever
// started from here.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/contracts.dart'
    show NoteEvent;
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_pitch.dart'
    show crispasrFfiCrepeF0;
import 'package:comet_beat/core/audio/transcription/dio.dart' show dioEstimator;
import 'package:comet_beat/core/audio/transcription/route.dart'
    show transcribeMonophonic;

/// Which F0 engine [singMelody] used.
enum SingF0Engine { crepe, dio }

/// The notes of [mono] (a vocal stem at [sampleRate]), computed on a
/// background isolate. [useCrepe] false forces the pure-Dart engine.
Future<({List<NoteEvent> notes, SingF0Engine engine})> singMelody(
  Float64List mono,
  int sampleRate, {
  bool useCrepe = true,
}) =>
    Isolate.run(() => _singMelody(mono, sampleRate, useCrepe));

Future<({List<NoteEvent> notes, SingF0Engine engine})> _singMelody(
  Float64List mono,
  int sampleRate,
  bool useCrepe,
) async {
  final crepe = useCrepe ? await crispasrFfiCrepeF0() : null;
  final notes = await transcribeMonophonic(
    mono,
    sampleRate: sampleRate,
    f0: crepe ?? dioEstimator(),
  );
  return (
    notes: notes,
    engine: crepe == null ? SingF0Engine.dio : SingF0Engine.crepe,
  );
}
