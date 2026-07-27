// English grapheme-to-phoneme (g2p_en.dart) — text → IPA, pure Dart. The exact
// IPA of a lexicon word depends on the bundled dictionary, so the word path is
// tested by properties (total, deterministic, case-insensitive); the ARPABET→
// IPA converter has fixed context rules (stress reductions, T-flapping,
// linking-ɹ) that are asserted exactly.
import 'package:comet_beat/core/audio/tts/g2p/g2p_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('arpabetToIpa — context-free stress reductions', () {
    test('empty phone list → empty IPA', () {
      expect(arpabetToIpa(const []), '');
    });

    test('unstressed AH is a schwa', () {
      expect(arpabetToIpa(const ['AH0']), 'ə');
    });

    test('unstressed IH/IY/UW reduce', () {
      expect(arpabetToIpa(const ['IH0']), 'ɪ');
      expect(arpabetToIpa(const ['IY0']), 'i');
      expect(arpabetToIpa(const ['UW0']), 'ʊ');
    });

    test('ER is stress-dependent: ˈɜː when stressed, ɚ when not', () {
      expect(arpabetToIpa(const ['ER1']), 'ˈɜː');
      expect(arpabetToIpa(const ['ER0']), 'ɚ');
    });
  });

  group('arpabetToIpa — context rules', () {
    test('T between a vowel and an unstressed vowel flaps to ɾ', () {
      // AE1 · T · AH0 — the "batter/data" flap.
      expect(arpabetToIpa(const ['AE1', 'T', 'AH0']), contains('ɾ'));
    });

    test('T does NOT flap before a stressed vowel', () {
      expect(arpabetToIpa(const ['AE1', 'T', 'AH1']), isNot(contains('ɾ')));
    });

    test('ER before a vowel gets a linking ɹ', () {
      expect(arpabetToIpa(const ['ER1', 'AH0']), contains('ɹ'));
    });

    test('unknown ARPABET tokens are skipped, not crashed', () {
      expect(arpabetToIpa(const ['ZZZ', 'AH0']), 'ə');
    });
  });

  group('wordToIpaEn', () {
    test('empty in → empty out (total function)', () {
      expect(wordToIpaEn(''), '');
    });

    test('is deterministic', () {
      expect(wordToIpaEn('hello'), wordToIpaEn('hello'));
    });

    test('is case-insensitive', () {
      expect(wordToIpaEn('Hello'), wordToIpaEn('hello'));
      expect(wordToIpaEn('CAT'), wordToIpaEn('cat'));
    });

    test('a real word yields a non-empty transcription', () {
      expect(wordToIpaEn('music'), isNotEmpty);
      expect(wordToIpaEn('cat'), isNotEmpty);
    });

    test('an all-consonant nonsense string never throws', () {
      expect(() => wordToIpaEn('brrght'), returnsNormally);
    });
  });
}
