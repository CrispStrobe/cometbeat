// REAL end-to-end synthesis through libcrispasr + whatever catalog voices are
// already in CrispASR's cache (~/.cache/crispasr): the actual worker isolate,
// session, phonemizer and WAV wrapping the app uses. Gated (MODEL_E2E) and
// self-skipping when the lib / a voice is absent, so it never fails a clean
// checkout — it is the dev-machine proof that every installed voice speaks.
//
//   flutter test test/crispasr_tts_smoke_test.dart --dart-define=MODEL_E2E=1
//
// Point it elsewhere with COMET_CRISPASR_LIB / CRISPASR_CACHE_DIR.
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/crispasr_voice_runtime.dart';
import 'package:comet_beat/core/audio/tts/kokoro_model_store.dart';
import 'package:comet_beat/core/audio/tts/neural_voice_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/slow_tests.dart';

void main() {
  if (!kRunModelE2e) {
    test(describeSkip('MODEL_E2E', 'real CrispASR voices'), () {});
    return;
  }

  final played = <Uint8List>[];
  final rt = CrispAsrVoiceRuntime(
    store: KokoroModelStore(),
    play: (wav) async => played.add(wav),
  );
  tearDownAll(rt.dispose);

  for (final voice in kNeuralVoices) {
    test(
      '${voice.id} speaks a non-silent sentence',
      () async {
        final why = await rt.unavailableReason();
        if (why != null) {
          markTestSkipped('libcrispasr not loadable: $why');
          return;
        }
        if (!await rt.isInstalled(voice)) {
          markTestSkipped('${voice.id} not in the CrispASR cache');
          return;
        }
        played.clear();
        await rt.speak(
          voice,
          voice.lang == 'de'
              ? 'Die Viertelnote dauert einen Schlag.'
              : 'A quarter note lasts one beat.',
        );
        expect(played, hasLength(1));
        final wav = played.single;
        final pcm = Int16List.sublistView(wav, 44);
        var peak = 0;
        for (final s in pcm) {
          if (s.abs() > peak) peak = s.abs();
        }
        expect(pcm.length, greaterThan(8000), reason: 'too short to be speech');
        expect(peak, greaterThan(1000), reason: 'silent output');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
