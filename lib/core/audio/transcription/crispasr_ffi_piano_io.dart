// Native CrispASR ggml NOTE-EVENT transcription (CrispasrSession.pianoNotes,
// crispasr 0.8.17+): resample the mono audio to the model's OWN rate, run the
// model, map its PianoNoteWithProgram records onto our NoteEvent contract —
// MT3's per-note General MIDI instrument included. dart:io only.
// Null when the ggml runtime/model isn't available here → the resolver falls
// back to the pure-Dart onnx Basic Pitch.
//
// THREE models share this one seam. `crispasr_session_piano` is the same C
// entry point for piano-transcription, Basic Pitch and MT3 alike (its `pcm_16k`
// parameter name is historical), so [CrispasrNoteModel] is a choice of MODEL,
// not a third code path. What differs between them is the registry key and the
// native sample rate — and the rate is ASKED FOR, never assumed:
// `pianoSampleRate` returns 22050 for basic-pitch, 16000 for the other two, and
// 0 when the opened backend has no piano arm at all, which is exactly the
// capability probe we want.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_session_io.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart'
    show CrispasrNoteModel, CrispasrNoteModelInfo;
import 'package:comet_beat/core/audio/transcription/route.dart'
    show NeuralTranscriber;
// For the CrispasrSession type; hide the PitchFrame that collides with ours.
import 'package:crispasr/crispasr.dart' hide PitchFrame;

// PianoNote's numeric fields cross the session seam as `num` (a cross-file
// record-inference quirk), so pin them to the NoteEvent field types here.
int _i(Object? v) => (v as num).toInt();
double _d(Object? v) => (v as num).toDouble();

/// A program from the C ABI, clamped to what [NoteEvent.program] promises:
/// -1, 0..127, or 128. Anything else (a future ABI, a corrupt read) becomes
/// [gmProgramUnknown] rather than being passed on as a GM program it is not.
int _program(Object? v) {
  final p = (v as num).toInt();
  return (p >= 0 && p <= gmProgramPercussion) ? p : gmProgramUnknown;
}

/// A CrispASR-FFI note-event [NeuralTranscriber] for [model], or null when that
/// model / the ggml lib isn't available. [download] fetches the GGUF if not
/// cached — the caller gates that, because MT3 and piano-transcription are tens
/// of megabytes (see [CrispasrNoteModelInfo.needsExplicitDownloadConsent]).
Future<NeuralTranscriber?> loadCrispasrPianoFfi({
  bool download = false,
  CrispasrNoteModel model = CrispasrNoteModel.auto,
}) async {
  // registryLookup + cacheDir + cacheEnsureFile, via the shared opener — no
  // hand-rolled URLs. Null for: no libcrispasr, a build without this backend
  // registered, or "not cached and we were told not to download".
  final CrispasrSession? session =
      openCrispasrSession(model.registryBackend, download: download);
  if (session == null) return null;
  // Ask the model its rate; 0 means this session has no piano arm (or the
  // dylib predates the API), in which case there is nothing to fall through to
  // but null — and dividing by it would hand resampleLinear an infinite ratio.
  final int target;
  try {
    target = session.pianoSampleRate;
  } on Object {
    session.close();
    return null;
  }
  if (target <= 0) {
    session.close();
    return null;
  }
  return (Float64List mono, int sampleRate) async {
    if (mono.isEmpty) return const <NoteEvent>[];
    final at =
        sampleRate == target ? mono : resampleLinear(mono, sampleRate / target);
    final pcm = Float32List(at.length);
    for (var i = 0; i < at.length; i++) {
      pcm[i] = at[i].toDouble();
    }
    try {
      // PianoNoteWithProgram {midi, onMs, offMs, velocity, program} → our
      // NoteEvent, program included.
      final events = <NoteEvent>[];
      for (final n in session.pianoNotesWithPrograms(pcm)) {
        // velocity is a loudness estimate, not a confidence — use it as a 0–1
        // strength proxy (documented; better than a flat constant).
        //
        // `pianoNotesWithPrograms` is the unconditional call: against a dylib
        // predating `crispasr_session_piano_note_programs`, or against
        // piano-transcription / basic-pitch, it returns -1 for every program
        // rather than throwing or probing. So the -1 arriving here means
        // exactly what NoteEvent.program's sentinel means, whichever of the
        // three models is loaded, and there is no capability branch to get
        // wrong. Only MT3 fills it in.
        final NoteEvent e = (
          midi: _i(n.midi),
          onMs: _d(n.onMs),
          offMs: _d(n.offMs),
          confidence: (_d(n.velocity) / 127).clamp(0.0, 1.0).toDouble(),
          program: _program(n.program),
        );
        events.add(e);
      }
      return events;
    } catch (_) {
      return const <NoteEvent>[];
    }
  };
}
