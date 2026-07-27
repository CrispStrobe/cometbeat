// German grapheme-to-phoneme (g2p_de.dart). Exact IPA depends on the bundled
// lexicon, so words are tested by properties; the sentence path's injectable
// [lookup] is a clean seam with exact behaviour.
import 'package:comet_beat/core/audio/tts/g2p/g2p_de.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('wordToIpaDe', () {
    test('empty in → empty out', () {
      expect(wordToIpaDe(''), '');
    });

    test('is deterministic', () {
      expect(wordToIpaDe('Musik'), wordToIpaDe('Musik'));
    });

    test('a real German word yields a non-empty transcription', () {
      expect(wordToIpaDe('Hallo'), isNotEmpty);
      expect(wordToIpaDe('Musik'), isNotEmpty);
    });

    test('an umlaut / ß word never throws', () {
      expect(() => wordToIpaDe('Größe'), returnsNormally);
      expect(() => wordToIpaDe('Mädchen'), returnsNormally);
    });
  });

  group('textToIpaDe', () {
    test('transcribes a multi-word sentence non-emptily', () {
      expect(textToIpaDe('Guten Tag'), isNotEmpty);
    });

    test('the lookup hook overrides a word and defers on null', () {
      final ipa = textToIpaDe(
        'foo bar',
        lookup: (w) => w == 'foo' ? 'XOVERRIDEX' : null,
      );
      // 'foo' used the hook; 'bar' fell through to the built-in rules.
      expect(ipa, contains('XOVERRIDEX'));
      expect(ipa, contains(wordToIpaDe('bar')));
    });

    test('is deterministic', () {
      expect(textToIpaDe('Guten Morgen'), textToIpaDe('Guten Morgen'));
    });
  });
}
