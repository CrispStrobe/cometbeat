// End-to-end proof for the pure-Dart Piper VITS runner:
//   text → our g2p IPA → piperPhonemeIds → PiperSynth (onnx_runtime_dart) → PCM.
//
// dart:io is used HERE (test only) to download/cache the CC0 voices via the
// native PiperVoiceStore. The runner + phonemizer LIBS stay pure Dart.
//
// The voice download (~63 MB each) is gated: if a voice can't be obtained
// (offline CI) the e2e test PRINTS a skip and passes. When present, it asserts
// the synthesized audio is NON-SILENT (RMS above a floor) and of plausible
// length, and prints the one-time render wall-clock.

import 'package:comet_beat/core/audio/tts/piper/piper_phonemes.dart';
import 'package:comet_beat/core/audio/tts/piper/piper_synth.dart';
import 'package:comet_beat/core/audio/tts/piper/piper_voice_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/slow_tests.dart';

void main() {
  group('Piper phonemes (pure)', () {
    const cfg = '{"audio":{"sample_rate":16000},'
        '"phoneme_id_map":{"_":[0],"^":[1],"\$":[2]," ":[3],'
        '"h":[10],"ɐ":[11],"l":[12],"ˈ":[13],"o":[14],"ʊ":[15]}}';

    test('phonemeIdMapFromJson + sampleRateFromJson', () {
      final m = phonemeIdMapFromJson(cfg);
      expect(m['^'], 1);
      expect(m['ʊ'], 15);
      expect(sampleRateFromJson(cfg), 16000);
    });

    test('piperPhonemeIds builds BOS + (phoneme,pad)* + EOS, drops unmapped',
        () {
      final m = phonemeIdMapFromJson(cfg);
      // "hello" → our g2p lexicon → IPA "hɐlˈoʊ" (all mapped above).
      final ids = piperPhonemeIds('hello', lang: 'en', phonemeIdMap: m);
      expect(ids, [1, 10, 0, 11, 0, 12, 0, 13, 0, 14, 0, 15, 0, 2]);
      expect(ids.first, 1); // BOS ^
      expect(ids.last, 2); // EOS $

      // A phoneme absent from the map is dropped (here drop 'l' id 12).
      final m2 = Map<String, int>.from(m)..remove('l');
      final ids2 = piperPhonemeIds('hello', lang: 'en', phonemeIdMap: m2);
      expect(ids2.contains(12), isFalse);
      expect(ids2.first, 1);
      expect(ids2.last, 2);
    });
  });

  group('Piper end-to-end synthesis (gated on voice download)', () {
    // Gated: see test/support/slow_tests.dart.
    if (!kRunModelE2e) {
      test(
        describeSkip('MODEL_E2E', 'Piper TTS inference'),
        () {},
      );
      return;
    }
    Future<void> runLang(String lang, String text) async {
      final store = PiperVoiceStore();
      final cfgJson = await store.loadConfigJson(lang);
      if (cfgJson == null) {
        // ignore: avoid_print
        print('Piper $lang voice unavailable (offline?) — skipping. '
            'Expected at ${store.modelFile(lang).path}');
        return;
      }
      final map = phonemeIdMapFromJson(cfgJson);
      final sr = sampleRateFromJson(cfgJson);
      final model = await store.loadModel(lang);
      final synth = PiperSynth(model, sampleRate: sr);
      final voice = PiperVoiceStore.voices[lang]!;

      final ids = piperPhonemeIds(text, lang: lang, phonemeIdMap: map);
      expect(ids.first, map['^']);
      expect(ids.last, map[r'$']);

      final sw = Stopwatch()..start();
      final pcm = synth.synthesize(ids);
      sw.stop();
      final sec = pcm.length / sr;
      final rms = PiperSynth.rms(pcm);
      // ignore: avoid_print
      print('$lang "${voice.base}" [${voice.license}] sr=$sr : '
          'ids=${ids.length} samples=${pcm.length} '
          'audio=${sec.toStringAsFixed(3)}s RMS=${rms.toStringAsFixed(5)} '
          'render=${sw.elapsedMilliseconds}ms');

      expect(pcm.length, greaterThanOrEqualTo(sr ~/ 5)); // ≥ 0.2 s
      expect(rms, greaterThan(0.005)); // non-silent
    }

    test(
      'English (kathleen CC0)',
      () async {
        await runLang('en', 'Hello, welcome to the music workshop.');
      },
      timeout: const Timeout(Duration(minutes: 15)),
    );

    test(
      'German (thorsten CC0)',
      () async {
        await runLang('de', 'Guten Morgen, willkommen in der Musikwerkstatt.');
      },
      timeout: const Timeout(Duration(minutes: 15)),
    );
  });
}
