// REAL end-to-end synthesis through libcrispasr + the on-disk Kokoro model.
// Skips automatically when the native lib / model aren't present (CI, other
// machines), so it never fails a clean checkout — it's the macOS dev proof that
// the Dart FFI → ggml → PCM path works, not a portable unit test.
//
// Point it at your build with env overrides if the defaults don't match:
//   COMET_CRISPASR_LIB, COMET_KOKORO_MODEL, COMET_KOKORO_VOICE_DE
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/tts/crispasr_tts_backend.dart';
import 'package:comet_beat/core/audio/tts/kokoro_model_store.dart';
import 'package:crispasr/crispasr.dart';
import 'package:flutter_test/flutter_test.dart';

String _env(String k, String fallback) =>
    Platform.environment[k]?.isNotEmpty == true
        ? Platform.environment[k]!
        : fallback;

void main() {
  final lib = _env(
    'COMET_CRISPASR_LIB',
    '/Users/christianstrobele/code/CrispASR/build/src/libcrispasr.dylib',
  );
  final model = _env(
    'COMET_KOKORO_MODEL',
    '/Users/christianstrobele/code/lego/brickwright-tts-demo/kokoro.gguf',
  );
  final voiceDe = _env(
    'COMET_KOKORO_VOICE_DE',
    '/Users/christianstrobele/Documents/models/whisper_cpp/kokoro-voice-df_eva.gguf',
  );

  // The native backend needs the locale voice pack as well as the base model.
  // A developer machine can have the first two files from an earlier setup
  // without the voice, so treat that as an unavailable smoke-test fixture.
  final present =
      File(lib).existsSync() && File(model).existsSync() && File(voiceDe).existsSync();

  test('the kokoro registry resolves to the published download URL', () {
    if (!File(lib).existsSync()) {
      // ignore: avoid_print
      print('SKIP: libcrispasr not on this machine — dev-only smoke.');
      return;
    }
    final dylib = DynamicLibrary.open(lib);
    final entry = registryLookup('kokoro', lib: dylib);
    expect(entry, isNotNull, reason: 'kokoro missing from the registry');
    expect(entry!.filename, 'kokoro-82m-q8_0.gguf');
    expect(entry.url, contains('huggingface.co/cstr'));
    // The en voice resolves; the de voice URL derives from the same repo.
    final af =
        registryLookupByFilename('kokoro-voice-af_heart.gguf', lib: dylib);
    expect(af?.url, contains('kokoro-voices-GGUF'));
  });

  test(
    'kokoro synthesises real German audio through the FFI backend',
    () {
      if (!present) {
        // ignore: avoid_print
        print('SKIP: libcrispasr/model/de voice not on this machine — dev-only smoke.');
        return;
      }
      final pcm = synthesizeKokoroPcm16(
        KokoroSynthRequest(
          libPath: lib,
          modelPath: model,
          voicePath: File(voiceDe).existsSync() ? voiceDe : null,
          text: 'Ein gleichmäßiger Puls ist der Herzschlag der Musik.',
        ),
      );

      expect(pcm, isNotNull, reason: 'synthesis returned null');
      expect(
        pcm!.length,
        greaterThan(24000), // > 1 s @ 24 kHz
        reason: 'suspiciously short audio',
      );
      var peak = 0;
      for (final s in pcm) {
        final a = s.abs();
        if (a > peak) peak = a;
      }
      expect(peak, greaterThan(2000), reason: 'audio is essentially silent');

      // The WAV wrapper the app plays.
      final wav = wavBytes(pcm, sampleRate: 24000);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(wav.length, 44 + pcm.length * 2);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // The full APP path: the real KokoroModelStore (no overrides) resolves the lib
  // from ~/.cache/crispasr, finds the cached model, and CrispAsrTtsBackend
  // synthesises + hands a WAV to the play sink — exactly what the running macOS
  // app does when the HD-voice tile is on. Skips unless the cache is populated
  // (run tool/bundle_macos_tts.sh first), so it's a dev proof, not a CI test.
  test(
    'the real store + backend narrate end-to-end from ~/.cache/crispasr',
    () async {
      final store = KokoroModelStore(); // no overrides → CrispASR cache dir
      if (!await store.isReady()) {
        // ignore: avoid_print
        print('SKIP: ~/.cache/crispasr not populated — run '
            'tool/bundle_macos_tts.sh + fetch the model.');
        return;
      }
      expect(await store.supported(), isTrue);

      Uint8List? played;
      final backend = CrispAsrTtsBackend(
        store: store,
        play: (wav) async => played = wav,
      );
      await backend.speak(
        'Guten Tag! Dies ist die natürliche Stimme von CometBeat.',
        langCode: 'de-DE',
      );

      expect(played, isNotNull, reason: 'nothing was synthesised/played');
      expect(String.fromCharCodes(played!.sublist(0, 4)), 'RIFF');
      expect(played!.length, greaterThan(44 + 24000 * 2)); // > 1 s of audio

      // Write it out so a human can listen (afplay) — proof it really works.
      final out = File(
        '${Directory.systemTemp.path}/cometbeat_tts_realstore.wav',
      )..writeAsBytesSync(played!);
      // ignore: avoid_print
      print('WROTE ${out.path} (${played!.length} bytes)');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
