// scoreToStars — the star-scoring contract every game funnels through. These
// lock the invariants (not one game's mapping): a result is always 0-3, a lost
// game is always 0, a win is monotonic non-decreasing in score, every
// registered threshold bracket produces the right star at its boundary, and an
// unknown game type falls back to 800/400.

import 'dart:math';

import 'package:comet_beat/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final gameTypes = [...kStarThresholds.keys, 'an_unregistered_game'];
  const probeScores = [
    -1000,
    -1,
    0,
    1,
    50,
    99,
    100,
    399,
    400,
    401,
    550,
    799,
    800,
    801,
    900,
    5000,
    1 << 30,
  ];

  test('a lost game is always 0 stars, whatever the score', () {
    for (final game in gameTypes) {
      for (final score in probeScores) {
        expect(
          scoreToStars(game, score, false),
          0,
          reason: '$game / $score should be 0 when unsuccessful',
        );
      }
    }
  });

  test('the result is always within 0..3', () {
    final rng = Random(7);
    for (var i = 0; i < 5000; i++) {
      final game =
          i.isEven ? gameTypes[rng.nextInt(gameTypes.length)] : 'unknown_$i';
      final score = rng.nextInt(4000) - 500; // includes negatives
      final stars = scoreToStars(game, score, rng.nextBool());
      expect(stars, inInclusiveRange(0, 3), reason: '$game / $score');
    }
  });

  test('a win is worth at least 1 star, even at score 0 or below', () {
    for (final game in gameTypes) {
      expect(scoreToStars(game, 0, true), 1, reason: '$game score 0');
      expect(scoreToStars(game, -5, true), 1, reason: '$game score -5');
    }
  });

  test('stars are monotonic non-decreasing in score for a won game', () {
    for (final game in gameTypes) {
      var previous = 0;
      for (var score = 0; score <= 6000; score += 25) {
        final stars = scoreToStars(game, score, true);
        expect(
          stars,
          greaterThanOrEqualTo(previous),
          reason: '$game dropped a star going up to score $score',
        );
        previous = stars;
      }
    }
  });

  test('each registered bracket earns its star exactly at the threshold', () {
    kStarThresholds.forEach((game, bracket) {
      final two = bracket[1], three = bracket[2];
      // Below the 2-star line is still a win → 1 star.
      expect(
        scoreToStars(game, two - 1, true),
        1,
        reason: '$game just below 2',
      );
      expect(scoreToStars(game, two, true), 2, reason: '$game at 2');
      expect(scoreToStars(game, three - 1, true), 2, reason: '$game below 3');
      expect(scoreToStars(game, three, true), 3, reason: '$game at 3');
      expect(
        scoreToStars(game, three + 1000, true),
        3,
        reason: '$game above 3',
      );
    });
  });

  test('an unknown game type uses the 800/400 fallback', () {
    const g = 'no_such_game';
    expect(scoreToStars(g, 399, true), 1);
    expect(scoreToStars(g, 400, true), 2);
    expect(scoreToStars(g, 799, true), 2);
    expect(scoreToStars(g, 800, true), 3);
  });
}
