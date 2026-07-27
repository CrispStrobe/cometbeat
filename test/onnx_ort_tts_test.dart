// onnxFfi TTS backend (Piper VITS over native ONNX Runtime): everything that
// does NOT need libonnxruntime is unit-tested here — the phoneme→input shaping,
// the backend's fallback/no-op when ORT/model is unavailable, and the full
// speak→WAV→play path via an injected synth seam. Real ORT inference is device-
// only (no libonnxruntime under `flutter test`), so those bits are gated: the
// unavailable-path tests exercise exactly that "no native lib" branch.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/onnx_ort_tts.dart';
import 'package:comet_beat/core/audio/tts/onnx_ort_tts_backend.dart';
import 'package:comet_beat/core/audio/tts/piper/piper_voice_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OnnxOrtTtsSynth.buildInputs (pure shaping, no ORT)', () {
    test('shapes input (int64), input_lengths (int64), scales (float32)', () {
      final ins = OnnxOrtTtsSynth.buildInputs([1, 10, 0, 2]);
      expect(ins.keys, containsAll(['input', 'input_lengths', 'scales']));

      final input = ins['input']!;
      expect(input.int64, isTrue);
      expect(input.data, [1, 10, 0, 2]);
      expect(input.shape, [1, 4]);

      final lengths = ins['input_lengths']!;
      expect(lengths.int64, isTrue);
      expect(lengths.data, [4]);
      expect(lengths.shape, [1]);

      final scales = ins['scales']!;
      expect(scales.int64, isFalse);
      expect(scales.data, [0.667, 1.0, 0.8]);
      expect(scales.shape, [3]);
    });

    test('scales pass through custom VITS values', () {
      final ins = OnnxOrtTtsSynth.buildInputs(
        [1, 2],
        noiseScale: 0.5,
        lengthScale: 1.5,
        noiseW: 0.9,
      );
      expect(ins['scales']!.data, [0.5, 1.5, 0.9]);
    });

    test('custom tensor names are honoured', () {
      final ins = OnnxOrtTtsSynth.buildInputs(
        [1, 2],
        inputName: 'x',
        inputLengthsName: 'xlen',
        scalesName: 'sc',
      );
      expect(ins.keys, containsAll(['x', 'xlen', 'sc']));
    });
  });

  group('OnnxOrtTtsBackend — unavailable path (no libonnxruntime)', () {
    test('supported() is false when native ORT is not loadable', () async {
      final backend = _backend(ortAvailable: false);
      expect(await backend.supported(), isFalse);
    });

    test('isAvailable() is false without ORT even if a model file exists',
        () async {
      final tmp = Directory.systemTemp.createTempSync('onnx_tts_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      _stageVoice(tmp, 'en');
      final backend = _backend(cacheDir: tmp.path, ortAvailable: false);
      expect(await backend.isAvailable(), isFalse);
    });

    test('speak is a silent no-op when ORT is unavailable', () async {
      var plays = 0;
      final backend = _backend(
        ortAvailable: false,
        play: (_) async => plays++,
        // Would return audio if it ever ran — proves the ORT gate short-circuits.
        synthesize: (_) => OnnxTtsResult(Float32List.fromList([0.5]), 16000),
      );
      await backend.speak('hello', langCode: 'en');
      expect(plays, 0);
    });

    test('speak is a no-op when the voice is not cached (never downloads)',
        () async {
      final tmp = Directory.systemTemp.createTempSync('onnx_tts_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      var plays = 0;
      var synthCalls = 0;
      final backend = _backend(
        cacheDir: tmp.path,
        ortAvailable: true,
        play: (_) async => plays++,
        synthesize: (_) {
          synthCalls++;
          return OnnxTtsResult(Float32List.fromList([0.5]), 16000);
        },
      );
      await backend.speak('hello', langCode: 'en');
      expect(synthCalls, 0); // no cached model → synth never invoked
      expect(plays, 0);
    });
  });

  group('OnnxOrtTtsBackend — speak path via injected synth (no ORT lib)', () {
    test('cached voice + fake synth → plays a valid WAV at the voice rate',
        () async {
      final tmp = Directory.systemTemp.createTempSync('onnx_tts_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      _stageVoice(tmp, 'de');

      Uint8List? played;
      OnnxTtsRequest? seen;
      final backend = _backend(
        cacheDir: tmp.path,
        ortAvailable: true,
        play: (wav) async => played = wav,
        synthesize: (req) {
          seen = req;
          // 100 samples of non-silent float PCM.
          return OnnxTtsResult(
            Float32List.fromList(
              List<double>.generate(100, (i) => (i - 50) / 50.0),
            ),
            22050,
          );
        },
      );

      await backend.speak('Guten Tag', langCode: 'de-DE');

      expect(seen, isNotNull);
      expect(seen!.lang, 'de'); // locale tag normalised to base language
      expect(seen!.text, 'Guten Tag');
      expect(seen!.modelPath, endsWith('.onnx'));
      expect(played, isNotNull);
      expect(String.fromCharCodes(played!.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(played!.sublist(8, 12)), 'WAVE');
      expect(played!.length, 44 + 100 * 2); // PCM16 payload
    });

    test('blank text never invokes the synth', () async {
      final tmp = Directory.systemTemp.createTempSync('onnx_tts_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      _stageVoice(tmp, 'en');
      var synthCalls = 0;
      final backend = _backend(
        cacheDir: tmp.path,
        ortAvailable: true,
        synthesize: (_) {
          synthCalls++;
          return OnnxTtsResult(Float32List.fromList([0.1]), 16000);
        },
      );
      await backend.speak('   ', langCode: 'en');
      expect(synthCalls, 0);
    });

    test('a null synth result (bad decode) does not play', () async {
      final tmp = Directory.systemTemp.createTempSync('onnx_tts_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      _stageVoice(tmp, 'en');
      var plays = 0;
      final backend = _backend(
        cacheDir: tmp.path,
        ortAvailable: true,
        play: (_) async => plays++,
        synthesize: (_) => null,
      );
      await backend.speak('hi', langCode: 'en');
      expect(plays, 0);
    });

    test('isAvailable() true once ORT is loadable and a voice is cached',
        () async {
      final tmp = Directory.systemTemp.createTempSync('onnx_tts_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      _stageVoice(tmp, 'en');
      final backend = _backend(cacheDir: tmp.path, ortAvailable: true);
      expect(await backend.isAvailable(), isTrue);
    });
  });
}

OnnxOrtTtsBackend _backend({
  String? cacheDir,
  required bool ortAvailable,
  Future<void> Function(Uint8List wav)? play,
  OnnxTtsResult? Function(OnnxTtsRequest req)? synthesize,
}) =>
    OnnxOrtTtsBackend(
      store: PiperVoiceStore(cacheDirOverride: cacheDir),
      play: play ?? (_) async {},
      ortAvailable: () => ortAvailable,
      synthesize: synthesize,
    );

/// Write placeholder `.onnx` + `.onnx.json` for [lang]'s bundled voice so the
/// backend's cache check passes. Content is never parsed (the synth is faked).
void _stageVoice(Directory dir, String lang) {
  final store = PiperVoiceStore(cacheDirOverride: dir.path);
  store.modelFile(lang).writeAsBytesSync(List<int>.filled(16, 0));
  store.configFile(lang).writeAsStringSync('{"audio":{"sample_rate":16000}}');
}
