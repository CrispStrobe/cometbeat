// Custom Loop Mixer harmonies (LM-UX7) — the pure encode/decode.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/features/games/composition/custom_progressions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encode/decode round-trips a custom progression', () {
    final ps = [
      const Progression('x', [
        ChordDegree.i,
        ChordDegree.v,
        ChordDegree.vi,
        ChordDegree.iv,
      ]),
    ];
    final decoded = decodeCustomProgressions(encodeCustomProgressions(ps));
    expect(decoded, hasLength(1));
    expect(decoded.first.degrees, ps.first.degrees);
    expect(decoded.first.id, 'custom-0'); // ids re-assigned by position
  });

  test('multiple progressions and stable ids', () {
    final ps = [
      const Progression('a', [ChordDegree.i, ChordDegree.iv]),
      const Progression('b', [ChordDegree.vi, ChordDegree.v, ChordDegree.i]),
    ];
    final decoded = decodeCustomProgressions(encodeCustomProgressions(ps));
    expect(decoded.map((p) => p.id), ['custom-0', 'custom-1']);
    expect(decoded[1].degrees, hasLength(3));
  });

  test('malformed input never throws and is skipped', () {
    expect(decodeCustomProgressions(null), isEmpty);
    expect(decodeCustomProgressions(''), isEmpty);
    expect(decodeCustomProgressions('garbage;9,9,9;;'), isEmpty);
    // A valid entry among junk survives. Names, not ordinals.
    final ok = decodeCustomProgressions('nope;i,v');
    expect(ok, hasLength(1));
    expect(ok.first.degrees, [ChordDegree.i, ChordDegree.v]);
  });

  test('degrees round-trip by NAME, so enum insertions cannot rewrite them',
      () {
    const p = Progression('x', [ChordDegree.i, ChordDegree.v]);
    final encoded = encodeCustomProgressions([p]);
    // The wire format is names — the ordinals it used to write silently
    // re-read as different chords when ii/iii were inserted into the enum.
    expect(encoded, 'i,v');
    expect(decodeCustomProgressions(encoded).first.degrees, p.degrees);
  });

  test('legacy numeric entries still load rather than being dropped', () {
    final legacy = decodeCustomProgressions('0,3');
    expect(legacy, hasLength(1));
    expect(legacy.first.degrees, [
      ChordDegree.values[0],
      ChordDegree.values[3],
    ]);
  });
}
