import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/sing_melody.dart';
import 'package:flutter_test/flutter_test.dart';

/// A "sung" line: three half-second notes with a little vibrato.
Float64List _line(List<int> midi, int sr) {
  final per = sr ~/ 2;
  final x = Float64List(per * midi.length);
  var phase = 0.0;
  for (var n = 0; n < midi.length; n++) {
    final hz = 440 * math.pow(2, (midi[n] - 69) / 12);
    for (var i = 0; i < per; i++) {
      final t = i / sr;
      final f = hz * (1 + 0.004 * math.sin(2 * math.pi * 5.5 * t));
      phase += 2 * math.pi * f / sr;
      x[n * per + i] = 0.5 * math.sin(phase) + 0.15 * math.sin(2 * phase);
    }
  }
  return x;
}

void main() {
  test('finds the sung notes on a background isolate (pure-Dart engine)',
      () async {
    const sr = 44100;
    final line = _line([60, 64, 67], sr);
    // The UI isolate must stay free: count event-loop turns while it runs.
    var turns = 0;
    var running = true;
    Future<void> ticker() async {
      while (running) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        turns++;
      }
    }

    final tick = ticker();
    final result = await singMelody(line, sr, useCrepe: false);
    running = false;
    await tick;

    expect(result.engine, SingF0Engine.dio);
    expect(result.notes.map((n) => n.midi).toList(), [60, 64, 67]);
    expect(turns, greaterThan(3), reason: 'the calling isolate kept running');
  });
}
