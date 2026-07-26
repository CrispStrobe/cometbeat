// End-to-end proof for the pure-Dart Kokoro TTS runner:
//   text → g2p phonemes → kokoroTokens → KokoroSynth (onnx_runtime_dart) → PCM.
//
// dart:io is used HERE (test only) to download/cache the model via the native
// KokoroModelStore. The runner LIB (`kokoro_synth.dart`) stays pure Dart.
//
// The model download (~154 MB) is gated: if the model/voice can't be obtained
// (offline CI), the e2e test PRINTS a skip and passes, so CI stays green. When
// present, it asserts the synthesized audio is NON-SILENT (RMS above a floor)
// and of plausible length (≥ 0.2 s @ 24 kHz).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/g2p/g2p_phonemizer.dart';
import 'package:comet_beat/core/audio/tts/kokoro/kokoro_model_store.dart';
import 'package:comet_beat/core/audio/tts/kokoro/kokoro_synth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

void main() {
  group('KokoroSynth pure helpers (no model)', () {
    test('voiceFromBytes reinterprets little-endian float32', () {
      final bd = ByteData(8)
        ..setFloat32(0, 1.5, Endian.little)
        ..setFloat32(4, -2.25, Endian.little);
      final v = KokoroSynth.voiceFromBytes(bd.buffer.asUint8List());
      expect(v, [1.5, -2.25]);
    });

    test('selectRefS indexes by unpadded token count, clamped', () {
      // 4 rows × styleDim 4 = 16 floats: row r filled with value r.
      final voice = Float32List(16);
      for (var r = 0; r < 4; r++) {
        for (var c = 0; c < 4; c++) {
          voice[r * 4 + c] = r.toDouble();
        }
      }
      final synth = KokoroSynth(_DummyModel(), styleDim: 4);
      // Pad-wrapped tokens [0, a, b, 0] → unpadded 2 → row 2.
      final ref = synth.selectRefS([0, 11, 12, 0], voice);
      expect(ref, [2, 2, 2, 2]);
      // Over-long clamps to the last row (3).
      final long = List<int>.filled(50, 7);
      expect(synth.selectRefS(long, voice), [3, 3, 3, 3]);
    });

    test('rms of a constant buffer', () {
      expect(
        KokoroSynth.rms(Float32List.fromList([0.5, -0.5, 0.5, -0.5])),
        closeTo(0.5, 1e-6),
      );
      expect(KokoroSynth.rms(Float32List(0)), 0);
    });
  });

  group('Kokoro end-to-end synthesis (gated on model download)', () {
    test(
      'text → phonemes → Kokoro → non-silent audio',
      () async {
        final store = KokoroModelStore();
        final modelFile = await store.ensureModel();
        final voiceFile = await store.ensureVoice();
        if (modelFile == null || voiceFile == null) {
          // ignore: avoid_print
          print('Kokoro model/voice unavailable (offline?) — skipping e2e. '
              'Expected model at ${store.modelFile().path}');
          return;
        }

        final synth =
            KokoroSynth(OnnxModel.fromBytes(modelFile.readAsBytesSync()));
        final voice = KokoroSynth.voiceFromBytes(voiceFile.readAsBytesSync());

        // English "hello".
        final enTokens = kokoroTokens('hello');
        expect(enTokens.first, 0);
        expect(enTokens.last, 0);
        final enPcm = synth.synthesize(enTokens, voice: voice);
        final enSec = enPcm.length / synth.sampleRate;
        final enRms = KokoroSynth.rms(enPcm);
        // ignore: avoid_print
        print('EN "hello": ${enPcm.length} samples '
            '(${enSec.toStringAsFixed(3)} s), RMS=${enRms.toStringAsFixed(5)}');
        expect(enPcm.length, greaterThanOrEqualTo(4800)); // ≥ 0.2 s @ 24 kHz
        expect(enRms, greaterThan(0.005)); // non-silent

        // German phrase (af_heart — Kokoro v1.0 has no German voice).
        final deTokens = kokoroTokens('guten morgen welt', lang: 'de');
        final dePcm = synth.synthesize(deTokens, voice: voice);
        final deSec = dePcm.length / synth.sampleRate;
        final deRms = KokoroSynth.rms(dePcm);
        // ignore: avoid_print
        print('DE "guten morgen welt": ${dePcm.length} samples '
            '(${deSec.toStringAsFixed(3)} s), RMS=${deRms.toStringAsFixed(5)}');
        expect(dePcm.length, greaterThanOrEqualTo(4800));
        expect(deRms, greaterThan(0.005));
        // Longer text → longer audio.
        expect(dePcm.length, greaterThan(enPcm.length));
      },
      timeout: const Timeout(Duration(minutes: 15)),
    );
  });
}

/// A stand-in [OnnxModel] for the pure-helper tests (never .run()). We only need
/// an instance to exercise [KokoroSynth.selectRefS]; construct a trivial valid
/// ONNX graph so `OnnxModel.fromBytes` succeeds without network.
class _DummyModel implements OnnxModel {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('dummy model: ${invocation.memberName}');
}
