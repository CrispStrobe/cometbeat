// StreamingMixer — the pure streaming pipeline (§C-1a core). No audio hardware:
// pull blocks from a looping buffer through the live filter and assert the
// stream matches the loop, wraps seamlessly, and stays block-continuous.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/streaming_mixer.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _tone(double freq, {int samples = 4096, double amp = 0.5}) {
  final out = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    out[i] = amp * math.sin(2 * math.pi * freq * i / 44100);
  }
  return out;
}

double _rms(Float64List x) {
  var s = 0.0;
  for (final v in x) {
    s += v * v;
  }
  return math.sqrt(s / x.length);
}

void main() {
  test('an empty loop is rejected', () {
    expect(() => StreamingMixer(Float64List(0)), throwsArgumentError);
  });

  test('bypassed, the stream is the loop wrapped', () {
    final mixer = StreamingMixer(Float64List.fromList([0, 1, 2, 3]));
    final out = mixer.pull(6); // filter is transparent at cutoff 0
    expect(out.toList(), [0, 1, 2, 3, 0, 1]);
    expect(mixer.position, 2, reason: 'position wrapped past the end');
  });

  test('streaming in blocks equals one big pull (block-continuous)', () {
    final loop = _tone(2000);
    final whole = (StreamingMixer(loop)..setCutoff(-0.5)).pull(10000);

    final blocked = StreamingMixer(loop)..setCutoff(-0.5);
    final sink = BufferedSink();
    blocked.stream(sink, 10000, blockSize: 333);
    final got = sink.samples;

    expect(got.length, whole.length);
    for (var i = 0; i < whole.length; i++) {
      expect(got[i], closeTo(whole[i], 1e-12), reason: 'sample $i');
    }
  });

  test('a low-pass on the stream attenuates a high-tone loop', () {
    final high = _tone(7000);
    final dry = _rms(StreamingMixer(high).pull(high.length));
    final wet =
        _rms((StreamingMixer(high)..setCutoff(-0.85)).pull(high.length));
    expect(wet, lessThan(0.35 * dry), reason: 'highs cut by the low-pass');
  });

  test('setLoop preserves the play phase by default', () {
    final mixer = StreamingMixer(Float64List.fromList([0, 1, 2, 3, 4, 5]))
      ..pull(4); // position now 4
    mixer.setLoop(Float64List.fromList([9, 9, 9, 9, 9, 9]));
    expect(mixer.position, 4, reason: 'phase kept');
    mixer.setLoop(Float64List.fromList([7, 7]), preservePhase: false);
    expect(mixer.position, 0);
  });
}
