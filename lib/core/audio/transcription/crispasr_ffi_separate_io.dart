// Native CrispASR ggml source separation (CrispasrSession.separate, crispasr
// 0.8.17+; mini-bs-roformer from 0.8.50). Two consumers:
//
//   • whole-song TRANSCRIPTION — the mono [Separator] seam (stems.dart);
//   • the practice-stems PLAYER — [separateStereoCrispasr], which keeps the
//     stems in STEREO at the model's rate, because they are listened to.
//
// Separation of a song takes about as long as the song, so it never runs on the
// calling isolate: [Isolate.run] opens the session, separates and closes it.
// The session is a native handle and cannot cross isolates; the paths and the
// PCM can. dart:io only. Everything returns null when the lib or the model is
// not here, so callers fall back.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_session_io.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/separated_stem.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart'
    show Separator, Stems;
import 'package:crispasr/crispasr.dart' show CrispasrSession;

export 'package:comet_beat/core/audio/transcription/separated_stem.dart';

const Stems _empty = (vocals: null, bass: null, drums: null, other: null);

/// Whether [model] can run right now: the lib loads, the backend is registered
/// and its GGUF is cached (or, with [download], could be fetched). Cheap — it
/// does not load the model.
Future<bool> crispasrSeparatorAvailable(
  CrispasrSeparatorModel model, {
  bool download = false,
}) async =>
    crispasrModelPath(model.registryBackend, download: download) != null;

/// Split a stereo recording into stereo stems with [model], off the calling
/// isolate. [left]/[right] are at [sampleRate]; the stems come back at the
/// model's own rate (44.1 kHz for all three), which [SeparatedStem.sampleRate]
/// reports. Null when the model or lib is unavailable or separation fails.
Future<List<SeparatedStem>?> separateStereoCrispasr(
  Float32List left,
  Float32List right,
  int sampleRate, {
  CrispasrSeparatorModel model = CrispasrSeparatorModel.auto,
  bool download = false,
}) async {
  final backend = model.registryBackend;
  final modelPath = crispasrModelPath(backend, download: download);
  if (modelPath == null) return null;
  final libPath = crispasrLibPath();
  final cpuOnly = model.cpuOnly;
  return Isolate.run(() {
    CrispasrSession? session;
    try {
      session = _open(modelPath, libPath, backend, cpuOnly: cpuOnly);
      final sr = session.separateSampleRate;
      if (sr <= 0) return null;
      final l = _toRate(left, sampleRate, sr);
      final r = _toRate(right, sampleRate, sr);
      final n = l.length < r.length ? l.length : r.length;
      final inter = Float32List(n * 2);
      for (var i = 0; i < n; i++) {
        inter[2 * i] = l[i];
        inter[2 * i + 1] = r[i];
      }
      return [
        for (final s in session.separate(inter))
          SeparatedStem.fromInterleaved(s.name, s.pcm, sr),
      ];
    } catch (_) {
      return null;
    } finally {
      session?.close();
    }
  });
}

/// Opens the session, on the CPU when [cpuOnly] — falling back to a plain
/// open on a lib too old for `openWithParams`.
CrispasrSession _open(
  String modelPath,
  String libPath,
  String backend, {
  required bool cpuOnly,
}) {
  if (cpuOnly) {
    try {
      return CrispasrSession.openWithParams(
        modelPath,
        useGpu: false,
        libPath: libPath,
        backend: backend,
      );
    } on UnsupportedError {
      // fall through
    }
  }
  return CrispasrSession.open(modelPath, libPath: libPath, backend: backend);
}

Float32List _toRate(Float32List x, int from, int to) {
  if (from == to) return x;
  final f64 = Float64List(x.length);
  for (var i = 0; i < x.length; i++) {
    f64[i] = x[i];
  }
  final y = resampleLinear(f64, from / to);
  return Float32List.fromList(y);
}

/// A CrispASR-FFI [Separator] for whole-song transcription (mono in, mono stems
/// out at the input rate), or null when [model] is not available.
Future<Separator?> loadCrispasrFfiSeparator({
  bool download = false,
  CrispasrSeparatorModel model = CrispasrSeparatorModel.auto,
}) async {
  if (!await crispasrSeparatorAvailable(model, download: download)) {
    return null;
  }
  return (Float64List mono, int sampleRate) async {
    if (mono.isEmpty) return _empty;
    final m32 = Float32List(mono.length);
    for (var i = 0; i < mono.length; i++) {
      m32[i] = mono[i];
    }
    final stems = await separateStereoCrispasr(
      m32,
      m32,
      sampleRate,
      model: model,
      download: download,
    );
    if (stems == null) return _empty;
    Float64List? mono0(String name) {
      for (final s in stems) {
        if (s.name != name) continue;
        final m = s.mono();
        return s.sampleRate == sampleRate
            ? m
            : resampleLinear(m, s.sampleRate / sampleRate);
      }
      return null;
    }

    return (
      vocals: mono0('vocals'),
      bass: mono0('bass'),
      drums: mono0('drums'),
      // RoFormer labels its non-vocal stem 'instrumental'.
      other: mono0('other') ?? mono0('instrumental'),
    );
  };
}

/// Whether this device can run [model] at all (lib + registered backend),
/// downloaded or not.
bool crispasrSeparatorSupported(CrispasrSeparatorModel model) =>
    crispasrBackendRegistered(model.registryBackend);
