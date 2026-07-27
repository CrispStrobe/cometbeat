// narration_key.dart — the pure key logic shared by the bake tool and the
// runtime lookup. A key computed at bake time must match the key looked up at
// runtime on every platform (VM/web/wasm), so the normalisation has to be
// exact and total.
import 'package:comet_beat/core/audio/tts/narration_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeNarration', () {
    test('trims and collapses every run of whitespace to one space', () {
      expect(normalizeNarration('  hello   world  '), 'hello world');
      expect(normalizeNarration('a\t\tb'), 'a b');
      expect(normalizeNarration('line one\n  line two'), 'line one line two');
    });

    test('leaves already-clean text untouched', () {
      expect(normalizeNarration('hello world'), 'hello world');
      expect(normalizeNarration(''), '');
    });

    test('whitespace-only collapses to empty', () {
      expect(normalizeNarration('   \n\t '), '');
    });
  });

  group('narrationLang', () {
    test('takes the primary subtag, lower-cased', () {
      expect(narrationLang('en-US'), 'en');
      expect(narrationLang('de_DE'), 'de');
      expect(narrationLang('pt-BR'), 'pt');
      expect(narrationLang('EN'), 'en');
    });

    test('a bare language code is returned as-is (lower-cased)', () {
      expect(narrationLang('de'), 'de');
    });
  });

  group('narrationKey', () {
    test('is "<lang>|<normalized text>"', () {
      expect(narrationKey('Hello', 'en-US'), 'en|Hello');
      expect(narrationKey('Hallo', 'de_DE'), 'de|Hallo');
    });

    test('formatting-equivalent inputs produce the SAME key', () {
      // The whole point: a stray double space at bake time must not miss at
      // runtime.
      expect(
        narrationKey('  Guten   Tag ', 'de'),
        narrationKey('Guten Tag', 'de-DE'),
      );
    });

    test('is a plain string, never a numeric hash', () {
      // A VM-side int hash would not survive the web's 53-bit ints; the key
      // must stay human-readable text.
      final key = narrationKey('Twinkle', 'en');
      expect(key, 'en|Twinkle');
      expect(int.tryParse(key), isNull);
    });

    test('text and language are distinguishable (no collision across the bar)',
        () {
      expect(narrationKey('a|b', 'en'), 'en|a|b');
      expect(narrationKey('a', 'en') == narrationKey('', 'en|a'), isFalse);
    });
  });
}
