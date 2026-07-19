// bin/sfont.dart — the SoundFont CLI. Its glue is thin; the testable core is the
// pure info-report + render helpers, exercised here on a real in-memory SF2 (the
// same fixture the sf2 parser tests use). Proves the CLI's parse -> extract
// instrument -> render pipeline works end to end without the app.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bin/sfont.dart';
import 'sf2_fixture.dart';

LoadedSoundFont _font() {
  const n = 4410;
  final pcm = Int16List(n);
  for (var i = 0; i < n; i++) {
    pcm[i] = (0.5 * 32767 * math.sin(2 * math.pi * 220 * i / 22050)).round();
  }
  final bytes = oneSampleSf2(
    pcm: pcm,
    sampleRate: 22050,
    rootKey: 57,
    loopStart: 100,
    loopEnd: n - 100,
  );
  return loadSoundFont(bytes);
}

void main() {
  test('majorScale is the right 8 notes from the root', () {
    expect(majorScale(60), [60, 62, 64, 65, 67, 69, 71, 72]);
  });

  test('info report lists the preset (bank:program, zones, name)', () {
    final report = sfontInfoReport(_font());
    expect(report, contains('1 preset(s)'));
    expect(report, contains('GMTest')); // the fixture preset name
    expect(report, contains('0:0')); // bank:program
  });

  test('render produces a valid, non-silent WAV', () {
    final wav = sfontRenderWav(_font(), 0, majorScale(60));
    // RIFF/WAVE container
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    // there is actual audio in the data chunk
    var peak = 0;
    for (var i = 44; i + 1 < wav.length; i += 2) {
      final s = wav.buffer.asByteData().getInt16(i, Endian.little).abs();
      if (s > peak) peak = s;
    }
    expect(peak, greaterThan(1000), reason: 'rendered audio is not silent');
  });

  test('a single note renders a shorter clip than the full scale', () {
    final one = sfontRenderWav(_font(), 0, [60]);
    final scale = sfontRenderWav(_font(), 0, majorScale(60));
    expect(one.length, lessThan(scale.length));
  });
}
