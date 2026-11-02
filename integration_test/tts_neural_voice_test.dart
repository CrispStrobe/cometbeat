// On-device integration test for NEURAL narration, in the REAL sandboxed app:
// libcrispasr loads from the app's lookup cascade, the voice lives in the
// CONTAINER's ~/.cache/crispasr, and a sentence is spoken through the same
// TtsService path the lesson sheet uses. Headless `flutter test` reaches none
// of that (no sandbox, no bundled lib).
//
// Run (macOS):
//   flutter test integration_test/tts_neural_voice_test.dart -d macos
// Also exercise the in-app DOWNLOAD (≈31 MB Thorsten) when it is missing:
//   … --dart-define=TTS_DOWNLOAD=1
//
// Skips cleanly (with the reason) when libcrispasr cannot load here, or when
// the voice is not downloaded and TTS_DOWNLOAD is off.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/crispasr_voice_runtime.dart';
import 'package:comet_beat/core/audio/tts/neural_voice_catalog.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:comet_beat/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

const _download = String.fromEnvironment('TTS_DOWNLOAD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a German lesson sentence is spoken by Thorsten (neural)',
    (tester) async {
      await app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      final tts =
          tester.element(find.byType(MaterialApp).first).read<TtsService>();
      final thorsten = neuralVoiceById('piper-de-thorsten-medium')!;

      final why = await tester.runAsync(tts.neuralUnavailableReason);
      debugPrint('[tts-it] HOME=${Platform.environment['HOME']} '
          'engine=${why ?? 'ok'}');
      if (why != null) {
        markTestSkipped('neural engine unavailable here: $why');
        return;
      }

      await tester.runAsync(tts.refreshInstalled);
      if (!tts.isInstalledCached(thorsten.id)) {
        if (_download.isEmpty || _download == '0') {
          markTestSkipped('Thorsten not downloaded (pass TTS_DOWNLOAD=1)');
          return;
        }
        final sw = Stopwatch()..start();
        final ok = await tester.runAsync(() => tts.downloadVoice(thorsten));
        debugPrint('[tts-it] download ok=$ok in ${sw.elapsed} '
            'error=${tts.downloadError(thorsten.id)}');
        expect(ok, isTrue, reason: tts.downloadError(thorsten.id));
      }

      // 1. Through the app's TtsService, lesson scope, explicit choice.
      await tester.runAsync(
        () => tts.setVoiceChoice(
          'de',
          thorsten.id,
          scope: NarrationScope.lesson,
        ),
      );
      final sw = Stopwatch()..start();
      await tester.runAsync(
        () => tts.speak(
          'Eine Viertelnote dauert einen Schlag.',
          locale: const Locale('de'),
          scope: NarrationScope.lesson,
        ),
      );
      debugPrint('[tts-it] speak took ${sw.elapsed}; '
          'voice=${tts.lastNeuralVoice?.id} fallback=${tts.lastFallback?.detail}');
      expect(tts.lastFallback, isNull, reason: tts.lastFallback?.detail);
      expect(tts.lastNeuralVoice?.id, thorsten.id);

      // 2. The same runtime, capturing the WAV: real, non-silent speech.
      Uint8List? wav;
      final rt = CrispAsrVoiceRuntime(play: (w) async => wav = w);
      sw.reset();
      await tester.runAsync(
        () => rt.speak(thorsten, 'Die halbe Note dauert zwei Schläge.'),
      );
      rt.dispose();
      expect(wav, isNotNull);
      final pcm = Int16List.sublistView(wav!, 44);
      var peak = 0;
      for (final s in pcm) {
        if (s.abs() > peak) peak = s.abs();
      }
      // Keep the clip (container tmp) for an optional ASR round-trip check.
      final out = File('${Directory.systemTemp.path}/tts_it_thorsten.wav')
        ..writeAsBytesSync(wav!);
      debugPrint('[tts-it] fresh runtime: ${sw.elapsed}; wav ${wav!.length} '
          'B, peak $peak → ${out.path}');
      expect(pcm.length, greaterThan(16000));
      expect(peak, greaterThan(1000));

      // Leave the user's preference as it was.
      await tester.runAsync(
        () => tts.setVoiceChoice('de', null, scope: NarrationScope.lesson),
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
