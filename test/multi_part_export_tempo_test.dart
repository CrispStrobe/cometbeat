// Regression: multiPartToMidi (and the scoreToMidi it wraps) must export at the
// score's NOTATED tempo, not a fixed 120 BPM. A ♩=60 piece used to come out at
// double speed because no caller passed quarterBpm and the writer ignored
// Score.tempo.

import 'package:comet_beat/core/notation/multi_part_export.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether [haystack] contains [needle] as a contiguous subsequence.
bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

void main() {
  test('exports each part at its notated tempo, not a fixed 120', () {
    final part = Score.simple(
      notes: 'c4:q d4 e4 f4',
      timeSignature: TimeSignature.fourFour,
      tempo: const Tempo(60),
    );
    final midi = multiPartToMidi(MultiPartScore([part]));
    // ♩ = 60 → 1_000_000 µs/quarter = 0x0F4240.
    expect(_contains(midi, [0xFF, 0x51, 0x03, 0x0F, 0x42, 0x40]), isTrue);
    // And definitely NOT the old 120-BPM value (0x07A120).
    expect(_contains(midi, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]), isFalse);
  });

  test('an explicit quarterBpm still overrides the score tempo', () {
    final part = Score.simple(notes: 'c4:q', tempo: const Tempo(60));
    final midi = multiPartToMidi(MultiPartScore([part]), quarterBpm: 120);
    expect(_contains(midi, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]), isTrue);
  });

  test('a tempo-less score still defaults to 120', () {
    final midi = multiPartToMidi(
      MultiPartScore([Score.simple(notes: 'c4:q')]),
    );
    expect(_contains(midi, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]), isTrue);
  });
}
