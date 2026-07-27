// chord_quality.dart — the shared Harte ↔ symbol ↔ intervals vocabulary. Pure
// tables + total fallbacks, so every branch is exactly testable.
import 'package:comet_beat/features/games/songs/import/chord_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('intervalsForSuffix', () {
    test('known suffixes voice exactly', () {
      expect(intervalsForSuffix(''), [0, 4, 7]); // major triad
      expect(intervalsForSuffix('m'), [0, 3, 7]); // minor triad
      expect(intervalsForSuffix('m7'), [0, 3, 7, 10]);
      expect(intervalsForSuffix('maj7'), [0, 4, 7, 11]);
      expect(intervalsForSuffix('m7b5'), [0, 3, 6, 10]);
      expect(intervalsForSuffix('dim7'), [0, 3, 6, 9]);
      expect(intervalsForSuffix('9'), [0, 4, 7, 10, 14]);
    });

    test('an unknown minor-ish suffix falls back to a minor triad', () {
      expect(intervalsForSuffix('m13'), [0, 3, 7]);
      expect(intervalsForSuffix('min-something'), [0, 3, 7]);
    });

    test('unknown major-ish / other suffixes fall back to a major triad', () {
      expect(intervalsForSuffix('maj13'), [0, 4, 7]); // maj, not minor
      expect(intervalsForSuffix('13'), [0, 4, 7]);
      expect(intervalsForSuffix('weird'), [0, 4, 7]);
    });
  });

  group('suffixForHarteQuality', () {
    test('exact vocabulary maps', () {
      expect(suffixForHarteQuality('maj'), '');
      expect(suffixForHarteQuality('min'), 'm');
      expect(suffixForHarteQuality('min7'), 'm7');
      expect(suffixForHarteQuality('maj7'), 'maj7');
      expect(suffixForHarteQuality('hdim7'), 'm7b5');
      expect(suffixForHarteQuality('minmaj7'), 'mMaj7');
      expect(suffixForHarteQuality('9'), '9');
    });

    test('unknown qualities reduce to the nearest base', () {
      expect(suffixForHarteQuality('minmaj'), 'mMaj7');
      expect(suffixForHarteQuality('hdim'), 'm7b5');
      expect(suffixForHarteQuality('dim9'), 'dim');
      expect(suffixForHarteQuality('aug7'), 'aug');
      expect(suffixForHarteQuality('sus'), 'sus4');
      expect(suffixForHarteQuality('maj11'), ''); // maj checked before m
      expect(suffixForHarteQuality('min11'), 'm');
      expect(suffixForHarteQuality('11'), ''); // dominant extension → major
    });

    test('surrounding whitespace is tolerated', () {
      expect(suffixForHarteQuality('  min7 '), 'm7');
    });
  });

  test('harteQualityForSuffix inverts the vocabulary, unknown → maj', () {
    expect(harteQualityForSuffix('m7'), 'min7');
    expect(harteQualityForSuffix(''), 'maj');
    expect(harteQualityForSuffix('m7b5'), 'hdim7');
    expect(harteQualityForSuffix('nope'), 'maj');
  });

  test('every vocabulary entry round-trips symbol ↔ Harte', () {
    for (final q in chordQualities) {
      expect(
        suffixForHarteQuality(q.harte.first),
        q.suffix,
        reason: 'Harte ${q.harte.first} → suffix',
      );
      expect(
        harteQualityForSuffix(q.suffix),
        q.harte.first,
        reason: 'suffix ${q.suffix} → Harte',
      );
    }
  });

  group('splitChordSymbol', () {
    test('separates root (with accidentals) from quality suffix', () {
      expect(splitChordSymbol('C'), (root: 'C', suffix: ''));
      expect(splitChordSymbol('C#m7'), (root: 'C#', suffix: 'm7'));
      expect(splitChordSymbol('Bbmaj7'), (root: 'Bb', suffix: 'maj7'));
    });

    test('lower-case root letter is normalised to upper case', () {
      expect(splitChordSymbol('am'), (root: 'A', suffix: 'm'));
    });

    test('trims and rejects a symbol with no root letter', () {
      expect(splitChordSymbol('  D7 '), (root: 'D', suffix: '7'));
      expect(splitChordSymbol('7'), isNull);
      expect(splitChordSymbol(''), isNull);
      expect(splitChordSymbol('xyz'), isNull);
    });
  });
}
