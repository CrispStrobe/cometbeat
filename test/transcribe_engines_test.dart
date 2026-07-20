// resolveEngines maps the config + availability to concrete injected engines:
// picks a backend only when the config wants it AND it's installed, otherwise
// falls back to pure-Dart (null). F0 has two neural backends — ONNX CREPE (runs
// on web too) and CrispASR ggml CREPE (native only).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/features/games/transcribe/transcribe_engines.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<NoteEvent>> _fakeNeural(Float64List m, int sr) async => const [];
Future<PitchTrack> _fakeF0(Float64List m, int sr) async => const [];

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

  test('nothing installed → both null (pure-Dart)', () async {
    final e = await resolveEngines(
      cfg,
      isWeb: false,
      loadNeural: ({bool download = false}) async => null,
      loadRmvpe: ({bool download = false}) async => null,
      loadCrepeGgml: ({bool download = false}) async => null,
      loadCrepeOnnx: ({bool download = false}) async => null,
    );
    expect(e.neural, isNull);
    expect(e.f0, isNull);
  });

  test('a user "on-device" F0 choice ignores the installed CREPE', () async {
    final e = await resolveEngines(
      cfg.copyWith(backends: {TranscriptionStep.f0: Backend.pureDart}),
      isWeb: false,
      loadNeural: ({bool download = false}) async => _fakeNeural,
      loadCrepeOnnx: ({bool download = false}) async => _fakeF0,
    );
    expect(e.f0, isNull); // forced pure-Dart
    expect(e.neural, isNotNull); // poly still auto
  });

  test('web can use ONNX CREPE but never the ggml (FFI) one', () async {
    final e = await resolveEngines(
      cfg,
      isWeb: true,
      loadNeural: ({bool download = false}) async => _fakeNeural,
      loadCrepeGgml: ({bool download = false}) async => _fakeF0,
      loadCrepeOnnx: ({bool download = false}) async => _fakeF0,
    );
    expect(e.f0, isNotNull); // ONNX CREPE is fine on web
    expect(e.neural, isNotNull);
  });

  test('the CrispASR ggml CREPE stub is null until the package ships pitch()',
      () async {
    expect(await loadCrispasrCrepeF0(), isNull);
  });
}
