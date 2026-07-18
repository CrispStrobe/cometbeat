// starterBeatHits — the pure "starter module" pattern generator.

import 'package:comet_beat/features/library/starter_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a 3-channel, 16-row backbeat: pulse, backbeat, hats', () {
    final hits = starterBeatHits(channels: 3, rows: 16); // quarter=4, eighth=2

    List<int> rowsOn(int ch) =>
        hits.where((h) => h.channel == ch).map((h) => h.row).toList()..sort();

    expect(rowsOn(0), [0, 4, 8, 12]); // downbeat pulse (every beat)
    expect(rowsOn(1), [4, 12]); // backbeat (beats 2 & 4)
    expect(rowsOn(2), [0, 2, 4, 6, 8, 10, 12, 14]); // eighth hats
  });

  test('adapts to fewer channels (no channel it does not have)', () {
    final hits = starterBeatHits(channels: 1, rows: 16);
    expect(hits.every((h) => h.channel == 0), isTrue);
    expect(hits.map((h) => h.row).toList()..sort(), [0, 4, 8, 12]);
  });

  test('degenerate inputs yield nothing', () {
    expect(starterBeatHits(channels: 0, rows: 16), isEmpty);
    expect(starterBeatHits(channels: 4, rows: 0), isEmpty);
  });

  test('never emits a hit outside the grid', () {
    final hits = starterBeatHits(channels: 4, rows: 13);
    expect(hits.every((h) => h.row >= 0 && h.row < 13), isTrue);
    expect(hits.every((h) => h.channel >= 0 && h.channel < 4), isTrue);
  });
}
