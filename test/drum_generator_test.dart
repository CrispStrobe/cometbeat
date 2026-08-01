import 'package:comet_beat/core/harmony/drum_generator.dart';
import 'package:comet_beat/core/harmony/style_library.dart';
import 'package:comet_beat/core/harmony/style_spec.dart';
import 'package:flutter_test/flutter_test.dart';

/// The kit.
///
/// The three assertions that matter are the renderer constraints, because they
/// are the ones that produce a WRONG SOUND rather than a wrong note: no voice
/// twice at one instant (the renderer sums, so that is a comb filter), no open
/// hat where a real kit would choke it (the loader has no `off_by`), and no
/// voice index outside the order-locked palette.
RolePattern grooveOf(String styleId, int level) =>
    styleFor(styleId).levelAt(level).roles[StyleRole.drums]!;

DrumContext ctx({
  int bar = 0,
  double beats = 4,
  bool phrase = false,
  bool section = false,
  bool last = false,
}) =>
    DrumContext(
      barIndex: bar,
      beats: beats,
      isPhraseEnd: phrase,
      isSectionEnd: section,
      isLastBar: last,
    );

void main() {
  group('renderer constraints', () {
    test('never the same voice twice at the same instant', () {
      // midi_render.dart SUMS every zone covering a key+velocity, so a doubled
      // voice is N× louder and comb-filtered, not emphasised.
      for (final style in kStyles) {
        for (var level = 0; level < style.levels.length; level++) {
          final pattern = style.levelAt(level).roles[StyleRole.drums];
          if (pattern == null) continue;
          for (final phrase in [false, true]) {
            final bar = generateDrumBar(
              pattern: pattern,
              context: ctx(phrase: phrase),
            );
            final keys = bar.map((h) => '${h.voice}@${h.beat}').toList();
            expect(
              keys.toSet(),
              hasLength(keys.length),
              reason: '${style.id} level $level phrase=$phrase doubled a voice',
            );
          }
        }
      }
    });

    test('DIFFERENT voices at the same instant are allowed', () {
      // The swing ride and hat both land on beat 1, and that is correct — the
      // dedupe key must be the pair, not the beat.
      final bar = generateDrumBar(
        pattern: grooveOf('swing', 1),
        context: ctx(),
      );
      final onBeatOne = bar.where((h) => h.beat == 1).toList();
      expect(onBeatOne.length, greaterThan(1));
      expect(
        onBeatOne.map((h) => h.voice).toSet(),
        hasLength(onBeatOne.length),
      );
    });

    test('every voice index is inside the order-locked palette', () {
      // `enum Drum` has 12 values and its ordinal IS a MIDI note downstream.
      for (final style in kStyles) {
        for (var level = 0; level < style.levels.length; level++) {
          final pattern = style.levelAt(level).roles[StyleRole.drums];
          if (pattern == null) continue;
          for (final hit in generateDrumBar(
            pattern: pattern,
            context: ctx(phrase: true, section: true),
          )) {
            expect(hit.voice, inInclusiveRange(0, 11), reason: style.id);
          }
        }
      }
    });

    test('an open hat only lands where nothing follows it in the bar', () {
      // There is no hi-hat choke: an open hat mid-bar rings through the closed
      // hats after it.
      for (final style in kStyles) {
        for (var level = 0; level < style.levels.length; level++) {
          final pattern = style.levelAt(level).roles[StyleRole.drums];
          if (pattern == null) continue;
          final bar = generateDrumBar(
            pattern: pattern,
            context: ctx(phrase: true, section: true),
          );
          for (final open in bar.where((h) => h.voice == kDrumOpenHat)) {
            final laterHats = bar.where(
              (h) => h.voice == kDrumHat && h.beat > open.beat,
            );
            expect(
              laterHats,
              isEmpty,
              reason: '${style.id} level $level: a closed hat follows an '
                  'open one, which will not choke it',
            );
          }
        }
      }
    });
  });

  group('fills', () {
    test('a fill lands at a phrase end and nowhere else', () {
      final pattern = grooveOf('rock', 2);
      final plain = generateDrumBar(pattern: pattern, context: ctx());
      final filled =
          generateDrumBar(pattern: pattern, context: ctx(bar: 7, phrase: true));
      // Compare CONTENT, not length: two different bars can happen to have the
      // same number of hits, which made the first version of this assertion
      // pass for the wrong reason.
      expect(
        filled.map((h) => '${h.voice}@${h.beat}').toList(),
        isNot(plain.map((h) => '${h.voice}@${h.beat}').toList()),
      );

      // Toms are the fill's signature; the groove has none.
      bool hasToms(List<DrumHit> bar) => bar.any(
            (h) =>
                h.voice == kDrumTom ||
                h.voice == kDrumHighTom ||
                h.voice == kDrumLowTom,
          );
      expect(hasToms(plain), isFalse);
      expect(hasToms(filled), isTrue);
    });

    test('a fill keeps the first half of the bar', () {
      // A whole bar of fill is a solo. The bar must still belong to the phrase.
      final pattern = grooveOf('rock', 2);
      final filled =
          generateDrumBar(pattern: pattern, context: ctx(phrase: true));
      expect(filled.any((h) => h.beat < 2 && h.voice == kDrumKick), isTrue);
    });

    test('a fill rises into the downbeat that follows', () {
      final filled = generateDrumBar(
        pattern: grooveOf('rock', 2),
        context: ctx(phrase: true),
      );
      final second = filled.where((h) => h.beat >= 2).toList();
      expect(second.first.velocity, lessThan(second.last.velocity));
    });

    test('the fill shape varies with the bar, deterministically', () {
      final pattern = grooveOf('rock', 2);
      String shapeAt(int bar) => generateDrumBar(
            pattern: pattern,
            context: ctx(bar: bar, phrase: true),
          ).where((h) => h.beat >= 2).map((h) => h.voice).join(',');

      // Different phrases fill differently. These bar numbers are the REAL
      // ones — fills land at 8-bar phrase ends, so every index here is
      // congruent mod 4, which is exactly what a naive `% 4` cannot vary.
      expect(
        {shapeAt(7), shapeAt(15), shapeAt(23), shapeAt(31)},
        hasLength(greaterThan(1)),
      );
      // …but the same bar always fills the same way.
      expect(shapeAt(7), shapeAt(7));
    });

    test('a section end is marked, and marked LAST in the bar', () {
      final bar = generateDrumBar(
        pattern: grooveOf('rock', 2),
        context: ctx(phrase: true, section: true),
      );
      final open = bar.where((h) => h.voice == kDrumOpenHat);
      expect(open, hasLength(1));
      expect(open.single.beat, 3.5);
    });
  });

  group('the ends of the piece', () {
    test('the last bar is a crash, not a groove that stops', () {
      final bar = generateDrumBar(
        pattern: grooveOf('rock', 3),
        context: ctx(last: true),
      );
      expect(bar.map((h) => h.voice), contains(kDrumCrash));
      expect(bar.every((h) => h.beat == 0), isTrue);
    });

    test('a count-in accents the downbeat', () {
      final bar = countInBar(4);
      expect(bar, hasLength(4));
      expect(bar.first.velocity, greaterThan(bar[1].velocity));
      expect(bar.map((h) => h.beat), [0, 1, 2, 3]);
    });

    test('a count-in follows the meter', () {
      expect(countInBar(3), hasLength(3));
    });
  });

  group('meter', () {
    test('a 4/4 pattern is truncated to a 3/4 bar, not overrun', () {
      final bar = generateDrumBar(
        pattern: grooveOf('rock', 2),
        context: ctx(beats: 3),
      );
      expect(bar, isNotEmpty);
      for (final hit in bar) {
        expect(hit.beat, lessThan(3));
      }
    });

    test('a fill fits a short bar too', () {
      final bar = generateDrumBar(
        pattern: grooveOf('rock', 2),
        context: ctx(beats: 2, phrase: true),
      );
      for (final hit in bar) {
        expect(hit.beat, lessThan(2));
      }
    });

    test('a zero-length bar is silent rather than a crash', () {
      expect(
        generateDrumBar(pattern: grooveOf('rock', 2), context: ctx(beats: 0)),
        isEmpty,
      );
    });
  });

  test('no drums at a level is a legitimate arrangement, not a gap', () {
    // Level 0 of several styles is bass and comp only.
    expect(generateDrumBar(pattern: null, context: ctx()), isEmpty);
  });

  test('hits come out in time order', () {
    final bar = generateDrumBar(
      pattern: grooveOf('swing', 2),
      context: ctx(phrase: true),
    );
    for (var i = 1; i < bar.length; i++) {
      expect(bar[i].beat, greaterThanOrEqualTo(bar[i - 1].beat));
    }
  });
}
