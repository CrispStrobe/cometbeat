// scaledStarScore — grade stars by the fraction of a variable-length chart hit
// (so a Song Book song of any length scores fairly against a fixed bracket),
// producing a starScore that yields the right star under `scoreToStars`.

import 'package:comet_beat/core/audio/play_along.dart';
import 'package:comet_beat/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bracket = [1, 9, 13]; // the shipped 'sing_along' bracket

  // The starScore maps back to the intended star under scoreToStars.
  int starsFor(int hits, int total) => scoreToStars(
        'sing_along',
        scaledStarScore(hits, total, bracket),
        hits > 0,
      );

  test('≥90% hit → 3 stars, at any length', () {
    expect(starsFor(9, 10), 3); // 90%
    expect(starsFor(40, 40), 3); // 100%, long song
    expect(starsFor(19, 20), 3); // 95%
  });

  test('70–89% hit → 2 stars', () {
    expect(starsFor(7, 10), 2); // 70%
    expect(starsFor(30, 40), 2); // 75%
    expect(starsFor(17, 20), 2); // 85%
  });

  test('any hit below 70% → 1 star', () {
    expect(starsFor(1, 10), 1);
    expect(starsFor(13, 40), 1); // 33% — used to be a false 3★ on the raw count
    expect(starsFor(6, 10), 1); // 60%
  });

  test('no hits → 0 stars (and total 0 is safe)', () {
    expect(starsFor(0, 10), 0);
    expect(scaledStarScore(0, 0, bracket), 0);
    expect(scaledStarScore(5, 0, bracket), 0);
  });

  test('the raw-count bug this fixes: 13 hits of a 40-note song', () {
    // Against the raw bracket, 13 hits => 3★ (13 >= 13). Scaled, 13/40 = 33% => 1★.
    expect(
      scoreToStars('sing_along', 13, true),
      3,
      reason: 'the old behaviour',
    );
    expect(starsFor(13, 40), 1, reason: 'the fixed behaviour');
  });
}
