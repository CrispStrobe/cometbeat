import 'package:comet_beat/core/harmony/style_library.dart';
import 'package:comet_beat/core/harmony/style_spec.dart';
import 'package:flutter_test/flutter_test.dart';

/// The style model, and the six styles built on it.
///
/// The validator is the point of this file: a malformed style must be caught
/// with the offending FIELD NAMED, rather than producing a bar that silently
/// overruns or a level that silently falls back — both of which sound like a
/// bug in the band rather than in the data.
StyleSpec styled({
  String id = 'x',
  double swing = 0,
  List<int> meters = const [4],
  (int, int) tempo = const (60, 200),
  List<StyleLevel> levels = const [],
}) =>
    StyleSpec(
      id: id,
      name: 'X',
      swing: swing,
      meters: meters,
      tempoRange: tempo,
      levels: levels.isEmpty
          ? const [
              StyleLevel(
                roles: {
                  StyleRole.comp: RolePattern(
                    hits: [StyleHit(voice: 0, beat: 0)],
                  ),
                },
              ),
            ]
          : levels,
    );

void main() {
  group('the built-in styles', () {
    test('all six validate', () {
      for (final style in kStyles) {
        expect(
          validateStyle(style),
          isEmpty,
          reason: '${style.id}: ${validateStyle(style).join('; ')}',
        );
      }
    });

    test('ids are unique', () {
      final ids = kStyles.map((s) => s.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every style covers all four intensity levels', () {
      // The intensity axis is how a last chorus lifts; a style with two levels
      // would silently flatten that.
      for (final style in kStyles) {
        expect(style.levels, hasLength(4), reason: style.id);
      }
    });

    test('intensity is monotone in how much is playing', () {
      // Not a musical law, but it IS what the axis promises: level 3 must not
      // be sparser than level 0, or "turn it up" turns it down.
      for (final style in kStyles) {
        final counts = [
          for (final level in style.levels)
            level.roles.values.fold<int>(0, (a, p) => a + p.hits.length),
        ];
        expect(counts.first, lessThanOrEqualTo(counts.last), reason: style.id);
      }
    });

    test('a bass role always carries a mode, and only the bass does', () {
      for (final style in kStyles) {
        for (final level in style.levels) {
          for (final entry in level.roles.entries) {
            if (entry.key == StyleRole.bass) {
              expect(entry.value.bassMode, isNotNull, reason: style.id);
            } else {
              expect(entry.value.bassMode, isNull, reason: style.id);
            }
          }
        }
      }
    });

    test('the waltz fits 3 and nothing else', () {
      final waltz = kStyles.firstWhere((s) => s.id == 'waltz');
      expect(waltz.fitsMeter(3), isTrue);
      expect(waltz.fitsMeter(4), isFalse);
    });

    test('swing is continuous, not a triplet switch', () {
      final swing = kStyles.firstWhere((s) => s.id == 'swing');
      expect(swing.swing, greaterThan(0));
      expect(
        swing.swing,
        lessThan(1),
        reason: 'full triplet is a hard shuffle, not medium swing',
      );
      expect(kStyles.firstWhere((s) => s.id == 'straight').swing, 0);
    });

    test('styleFor falls back rather than throwing on an unknown id', () {
      // A chart saved with a style a later build removed must still play.
      expect(styleFor('no-such-style').id, defaultStyle.id);
      expect(styleFor(null).id, defaultStyle.id);
      expect(styleFor('bossa').id, 'bossa');
    });

    test('levelAt clamps instead of throwing', () {
      final style = kStyles.first;
      expect(() => style.levelAt(-1), returnsNormally);
      expect(() => style.levelAt(99), returnsNormally);
      expect(style.levelAt(99), same(style.levels.last));
    });
  });

  group('the validator names the field', () {
    test('a hit past the end of the bar', () {
      final bad = styled(
        levels: const [
          StyleLevel(
            roles: {
              StyleRole.drums: RolePattern(
                hits: [
                  StyleHit(voice: 0, beat: 0),
                  StyleHit(voice: 0, beat: 4),
                ],
              ),
            },
          ),
        ],
      );
      final problems = validateStyle(bad);
      expect(problems, hasLength(1));
      expect(problems.single.field, 'levels[0].drums.hits[1].beat');
      expect(problems.single.detail, contains('4-beat bar'));
    });

    test('the LONGEST claimed meter is what constrains a pattern', () {
      // A pattern is written for the longest bar and truncated to the actual
      // one, so validating against the longest is what proves no hit is dead
      // code. A hit at beat 3 is legal in a style that claims 3/4 and 4/4 —
      // it simply does not sound in the 3/4 bars.
      final ok = styled(
        meters: const [3, 4],
        levels: const [
          StyleLevel(
            roles: {
              StyleRole.comp: RolePattern(hits: [StyleHit(voice: 0, beat: 3)]),
            },
          ),
        ],
      );
      expect(validateStyle(ok), isEmpty);

      final bad = styled(
        meters: const [3, 4],
        levels: const [
          StyleLevel(
            roles: {
              StyleRole.comp: RolePattern(hits: [StyleHit(voice: 0, beat: 4)]),
            },
          ),
        ],
      );
      expect(validateStyle(bad).single.detail, contains('4-beat bar'));
    });

    test('a bass role with no mode', () {
      final bad = styled(
        levels: const [
          StyleLevel(roles: {StyleRole.bass: RolePattern()}),
        ],
      );
      expect(validateStyle(bad).single.field, 'levels[0].bass');
      expect(validateStyle(bad).single.detail, contains('bassMode'));
    });

    test('a bassMode on a role that is not the bass', () {
      final bad = styled(
        levels: const [
          StyleLevel(
            roles: {StyleRole.comp: RolePattern(bassMode: BassMode.walking)},
          ),
        ],
      );
      expect(validateStyle(bad).single.field, 'levels[0].comp');
    });

    test('a level with no roles at all', () {
      final bad = styled(levels: const [StyleLevel(roles: {})]);
      expect(validateStyle(bad).single.field, 'levels[0]');
    });

    test('out-of-range velocity, negative beat, non-positive duration', () {
      final bad = styled(
        levels: const [
          StyleLevel(
            roles: {
              StyleRole.comp: RolePattern(
                hits: [
                  StyleHit(voice: 0, beat: -1),
                  StyleHit(voice: 0, beat: 1, velocity: 1.5),
                  StyleHit(voice: 0, beat: 2, duration: 0),
                  StyleHit(voice: -1, beat: 3),
                ],
              ),
            },
          ),
        ],
      );
      final fields = validateStyle(bad).map((p) => p.field).toList();
      expect(fields, contains('levels[0].comp.hits[0].beat'));
      expect(fields, contains('levels[0].comp.hits[1].velocity'));
      expect(fields, contains('levels[0].comp.hits[2].duration'));
      expect(fields, contains('levels[0].comp.hits[3].voice'));
    });

    test('header-level problems', () {
      expect(
        validateStyle(styled(id: '  ')).map((p) => p.field),
        contains('id'),
      );
      expect(
        validateStyle(styled(swing: 2)).map((p) => p.field),
        contains('swing'),
      );
      expect(
        validateStyle(styled(meters: const [])).map((p) => p.field),
        contains('meters'),
      );
      expect(
        validateStyle(styled(tempo: (200, 60))).map((p) => p.field),
        contains('tempoRange'),
      );
    });

    test('a style with no levels is rejected', () {
      const empty = StyleSpec(id: 'e', name: 'E', levels: []);
      expect(validateStyle(empty).map((p) => p.field), contains('levels'));
    });
  });
}
