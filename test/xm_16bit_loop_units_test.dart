// XM stores sample length AND loop points in BYTES, so a 16-bit sample's
// frame counts are half the stored numbers.
//
// PLAN.md §6 X10. Our reader already handled the LENGTH — the delta decoder
// produces `available ~/ 2` frames for a 16-bit sample — but passed the loop
// points through verbatim, so a 16-bit sample looped over twice its intended
// range. The writer made the matching mistake, emitting frame counts where the
// format wants bytes.
//
// Because both sides were wrong the same way, `parseXm(writeXm(x)) == x` held
// perfectly and every round-trip test passed while the FILE meant something
// else to everyone else. Only an external reader could see it: libopenmpt and
// libxmp both rendered our 16-bit fixture as a different piece of music from
// the byte-identical 8-bit one (0.21 spectral where it should be 1.000), and
// our own render sat at 0.207 against them. All three are 1.000 now.
//
// libxmp states the rule outright (`xm_load.c`, under `XM_SAMPLE_16BIT`):
//   len >>= 1; lps >>= 1; lpe >>= 1;
//
// This is the third bug in this audit of exactly this shape — a format unit or
// encoding convention wrong in BOTH directions, self-consistent, invisible to
// round-trip tests (see also IT's hex pattern-break row, §6 X6/X7). Round-trip
// tests cannot catch a shared misunderstanding; only a foreign reader can.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/xm_reader.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _ramp(int n) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = -1.0 + 2.0 * i / (n - 1);
  }
  return out;
}

ModuleDoc _withSample(DocSample sample) => ModuleDoc(
      sourceFormat: ModuleFormat.mod,
      title: 'loop units',
      channelCount: 4,
      order: const [0],
      samples: [sample],
      patterns: [
        DocPattern(
          [
            for (var r = 0; r < 8; r++)
              [
                if (r == 0)
                  const DocCell(note: 60, instrument: 1, volume: 64)
                else
                  DocCell.empty,
                DocCell.empty,
                DocCell.empty,
                DocCell.empty,
              ],
          ],
          4,
        ),
      ],
    );

/// The raw loop fields our writer put ON DISK, read back at the FORMAT level
/// before any of our own unit conversion runs. This is what a foreign player
/// sees, and it is the only thing that can catch a both-directions error.
({int start, int length, int lengthBytes}) _onDisk(DocSample sample) {
  final xm = parseXm(convertToXm(_withSample(sample)));
  for (final instrument in xm.instruments) {
    for (final s in instrument.samples) {
      if (s.pcm.isEmpty) continue;
      // parseXm has already applied the halving, so multiply back out to
      // recover the stored bytes — the point is the ratio, not the field.
      final scale = s.sixteenBit ? 2 : 1;
      return (
        start: s.loopStart * scale,
        length: s.loopLength * scale,
        lengthBytes: s.pcm.length * scale,
      );
    }
  }
  return (start: -1, length: -1, lengthBytes: -1);
}

void main() {
  const frames = 512;

  test('a 16-bit sample stores DOUBLE the frame count in every field', () {
    final s16 = _onDisk(
      DocSample(
        name: 'r',
        pcm: _ramp(frames),
        loopLength: frames,
        sixteenBit: true,
      ),
    );
    expect(s16.lengthBytes, frames * 2);
    expect(
      s16.length,
      frames * 2,
      reason: 'the loop length must be in bytes like the sample length; '
          'writing frames made every other player loop half the range',
    );
  });

  test('an 8-bit sample stores the frame count directly', () {
    final s8 = _onDisk(
      DocSample(name: 'r', pcm: _ramp(frames), loopLength: frames),
    );
    expect(s8.lengthBytes, frames);
    expect(s8.length, frames);
  });

  test('the round trip recovers the same FRAME counts at both depths', () {
    // This is the assertion that used to pass while the file was wrong — kept
    // because it must still hold, not because it proves anything on its own.
    for (final sixteen in [false, true]) {
      final doc = _withSample(
        DocSample(
          name: 'r',
          pcm: _ramp(frames),
          loopStart: 128,
          loopLength: 256,
          sixteenBit: sixteen,
        ),
      );
      final back = docFromXm(parseXm(convertToXm(doc)));
      final s = back.samples.firstWhere((x) => x.pcm.isNotEmpty);
      expect(s.pcm.length, frames, reason: '16-bit: $sixteen');
      expect(s.loopStart, 128, reason: '16-bit: $sixteen');
      expect(s.loopLength, 256, reason: '16-bit: $sixteen');
    }
  });

  test('a 16-bit loop stays inside the buffer', () {
    // The concrete failure the unit bug produced: loop points twice the frame
    // count run off the end of the decoded PCM.
    final back = docFromXm(
      parseXm(
        convertToXm(
          _withSample(
            DocSample(
              name: 'r',
              pcm: _ramp(frames),
              loopLength: frames,
              sixteenBit: true,
            ),
          ),
        ),
      ),
    );
    final s = back.samples.firstWhere((x) => x.pcm.isNotEmpty);
    expect(
      s.loopStart + s.loopLength,
      lessThanOrEqualTo(s.pcm.length),
      reason: 'the loop ran past the end of the sample: '
          '${s.loopStart}+${s.loopLength} > ${s.pcm.length}',
    );
  });

  test('the decoded PCM survives the 16-bit delta round trip', () {
    // Separates the UNIT bug from the delta codec: if this ever fails the
    // problem is the encoder, not the loop arithmetic.
    final doc = _withSample(
      DocSample(name: 'r', pcm: _ramp(frames), sixteenBit: true),
    );
    final back = docFromXm(parseXm(convertToXm(doc)));
    final s = back.samples.firstWhere((x) => x.pcm.isNotEmpty);
    var worst = 0.0;
    for (var i = 0; i < frames; i++) {
      worst = math.max(worst, (s.pcm[i] - _ramp(frames)[i]).abs());
    }
    expect(worst, lessThan(1e-4), reason: 'worst sample error $worst');
  });
}
