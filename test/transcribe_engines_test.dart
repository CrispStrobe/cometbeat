// resolveEngines maps the config + availability to concrete injected engines:
// picks a backend only when the config wants it AND it's installed, otherwise
// falls back to pure-Dart (null). F0 has two neural backends — ONNX CREPE (runs
// on web too) and CrispASR ggml CREPE (native only).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/harmony.dart'
    show ChordEvent;
import 'package:comet_beat/features/games/transcribe/transcribe_engines.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<NoteEvent>> _fakeNeural(Float64List m, int sr) async => const [];
Future<PitchTrack> _fakeF0(Float64List m, int sr) async => const [];
Future<List<ChordEvent>> _fakeChords(Float64List m, int sr) async => const [];

void main() {
  const cfg = TranscriptionEngineConfig();

  test(
      'auto, native, ggml CREPE present → it wins for F0; Basic Pitch for poly',
      () async {
    final e = await resolveEngines(
      cfg,
      isWeb: false,
      loadNeural: ({bool download = false}) async => _fakeNeural,
      loadCrepeGgml: ({bool download = false}) async => _fakeF0,
      loadCrepeOnnx: ({bool download = false}) async => _fakeF0,
    );
    expect(e.neural, isNotNull);
    expect(e.f0, isNotNull);
  });

  test('auto, only ONNX CREPE present → ONNX for F0', () async {
    final e = await resolveEngines(
      cfg,
      isWeb: false,
      loadNeural: ({bool download = false}) async => null,
      loadCrepeGgml: ({bool download = false}) async => null,
      loadRmvpe: ({bool download = false}) async => null,
      loadCrepeOnnx: ({bool download = false}) async => _fakeF0,
    );
    expect(e.f0, isNotNull);
    expect(e.neural, isNull);
  });

  test('RMVPE is preferred over CREPE for the ONNX F0 backend', () async {
    var rmvpeUsed = false;
    Future<PitchTrack> rmvpe(Float64List m, int sr) async {
      rmvpeUsed = true;
      return const [];
    }

    final e = await resolveEngines(
      cfg,
      isWeb: false,
      loadNeural: ({bool download = false}) async => null,
      loadRmvpe: ({bool download = false}) async => rmvpe,
      loadCrepeOnnx: ({bool download = false}) async => _fakeF0,
    );
    expect(e.f0, isNotNull);
    await e.f0!(Float64List(0), 44100); // the chosen estimator is RMVPE
    expect(rmvpeUsed, isTrue);
  });

  test('nothing installed → neural null, F0 = pure-Dart DIO', () async {
    final e = await resolveEngines(
      cfg,
      isWeb: false,
      loadNeural: ({bool download = false}) async => null,
      loadRmvpe: ({bool download = false}) async => null,
      loadCrepeGgml: ({bool download = false}) async => null,
      loadCrepeOnnx: ({bool download = false}) async => null,
    );
    expect(e.neural, isNull); // no built-in polyphonic engine
    expect(e.f0, isNotNull); // the model-free WORLD DIO F0 always resolves
    await e.f0!(Float64List(0), 44100); // and is callable
  });

  test('a user "on-device" F0 choice ignores the installed CREPE', () async {
    // ⚠️ Every loader is stubbed, including the ones this case does not care
    // about. `resolveEngines` PROBES EVERY RUNTIME for every step regardless of
    // the config, so an unstubbed loader is a live call into the real model
    // manager. This test stubbed only two, and the rest reached the filesystem
    // (and the download path) — fast enough to pass on a developer machine at
    // ~6 s, and slow enough on a shared CI runner to blow the 30 s budget. It
    // was the only red in an otherwise green CI run, and it failed on a
    // TIMEOUT rather than an assertion, which is the tell.
    //
    // Its siblings above already stub `loadRmvpe`/`loadCrepeGgml` for the same
    // reason; this one had simply been missed.
    final e = await resolveEngines(
      cfg.copyWith(backends: {TranscriptionStep.f0: Backend.pureDart}),
      isWeb: false,
      loadNeural: ({bool download = false}) async => _fakeNeural,
      loadCrepeOnnx: ({bool download = false}) async => _fakeF0,
      loadRmvpe: ({bool download = false}) async => _fakeF0,
      loadCrepeGgml: ({bool download = false}) async => _fakeF0,
      loadHarmony: ({bool download = false}) async => _fakeChords,
      loadF0OnnxFfi: ({bool download = false}) async => null,
      loadNeuralOnnxFfi: ({bool download = false}) async => null,
      loadChordsOnnxFfi: ({bool download = false}) async => null,
      loadPianoGgml: ({bool download = false}) async => null,
    );
    expect(e.f0, isNotNull); // forced pure-Dart → WORLD DIO, not CREPE
    await e.f0!(Float64List(0), 44100); // DIO runs (no model, no download)
    expect(e.neural, isNotNull); // poly still auto
  });

  test('web can use ONNX CREPE but never the ggml (FFI) one', () async {
    // Same reason as the stubs above: unstubbed loaders are live calls into the
    // real model manager. This one was not failing, but it was the second
    // slowest test in the file at ~3 s, which is the same defect with more
    // headroom rather than a different one.
    final e = await resolveEngines(
      cfg,
      isWeb: true,
      loadNeural: ({bool download = false}) async => _fakeNeural,
      loadCrepeGgml: ({bool download = false}) async => _fakeF0,
      loadCrepeOnnx: ({bool download = false}) async => _fakeF0,
      loadRmvpe: ({bool download = false}) async => _fakeF0,
      loadHarmony: ({bool download = false}) async => _fakeChords,
    );
    expect(e.f0, isNotNull); // ONNX CREPE is fine on web
    expect(e.neural, isNotNull);
  });

  test('a neural chords choice → the chord estimator when installed', () async {
    final e = await resolveEngines(
      cfg.copyWith(backends: {TranscriptionStep.chords: Backend.onnx}),
      isWeb: false,
      loadNeural: ({bool download = false}) async => null,
      loadRmvpe: ({bool download = false}) async => null,
      loadCrepeOnnx: ({bool download = false}) async => null,
      loadCrepeGgml: ({bool download = false}) async => null,
      loadHarmony: ({bool download = false}) async => _fakeChords,
    );
    expect(e.chords, isNotNull);
  });

  test('chords stay null when harmony is absent', () async {
    final e = await resolveEngines(
      cfg.copyWith(backends: {TranscriptionStep.chords: Backend.onnx}),
      isWeb: false,
      loadNeural: ({bool download = false}) async => null,
      loadRmvpe: ({bool download = false}) async => null,
      loadCrepeOnnx: ({bool download = false}) async => null,
      loadCrepeGgml: ({bool download = false}) async => null,
      loadHarmony: ({bool download = false}) async => null,
    );
    expect(e.chords, isNull);
  });

  test('native-ORT FFI F0 is used when present (and beats pure-Dart ONNX)',
      () async {
    var ffiUsed = false;
    Future<PitchTrack> ffiF0(Float64List m, int sr) async {
      ffiUsed = true;
      return const [];
    }

    final e = await resolveEngines(
      cfg,
      isWeb: false,
      loadNeural: ({bool download = false}) async => null,
      loadRmvpe: ({bool download = false}) async => null,
      loadCrepeOnnx: ({bool download = false}) async =>
          _fakeF0, // pure-Dart onnx
      loadF0OnnxFfi: ({bool download = false}) async => ffiF0, // native-ORT FFI
    );
    expect(e.f0, isNotNull);
    await e.f0!(Float64List(0), 44100);
    expect(ffiUsed, isTrue, reason: 'native-ORT FFI beats pure-Dart ONNX');
  });

  test('ggml piano is used for polyphony when present', () async {
    var pianoUsed = false;
    Future<List<NoteEvent>> piano(Float64List m, int sr) async {
      pianoUsed = true;
      return const [];
    }

    final e = await resolveEngines(
      cfg,
      isWeb: false,
      loadNeural: ({bool download = false}) async => _fakeNeural, // onnx BP
      loadPianoGgml: ({bool download = false}) async => piano, // ggml
    );
    expect(e.neural, isNotNull);
    await e.neural!(Float64List(0), 44100);
    expect(pianoUsed, isTrue, reason: 'ggml piano beats ONNX Basic Pitch');
  });

  test('runtimes null unless configured/present', () async {
    // CrispASR CREPE is wired via the CLI but env-gated: null without a
    // CRISPASR_BIN + GGUF, so it's null on CI/dev by default.
    expect(await loadCrispasrCrepeF0(), isNull);
    expect(await loadCrispasrPiano(), isNull);
    expect(await loadOnnxFfiF0(), isNull);
    expect(await loadOnnxFfiNeural(), isNull);
    expect(await loadOnnxFfiChords(), isNull);
  });
}
