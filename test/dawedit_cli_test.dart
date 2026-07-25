// bin/dawedit.dart end-to-end: run the real CLI as a subprocess and check the
// audio that lands on disk. This is the guard on the CLI *wiring* — the edit
// maths itself is covered headlessly in daw_edits_test.dart. It also proves the
// edit path stays Flutter-free: `dart run` (not `flutter test`) executes it.

import 'dart:io';

import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ProcessResult> _dawedit(List<String> args) =>
    Process.run('dart', ['run', 'bin/dawedit.dart', ...args]);

/// Peak sample magnitude (0..1) of a written WAV, channel-interleaved.
double _peakOf(String path) {
  final wav = readWavPcm16(File(path).readAsBytesSync());
  var peak = 0.0;
  for (final s in wav.samples) {
    final a = (s / 32768).abs();
    if (a > peak) peak = a;
  }
  return peak;
}

double _durationMsOf(String path) {
  final wav = readWavPcm16(File(path).readAsBytesSync());
  return wav.samples.length / wav.channels * 1000 / wav.sampleRate;
}

void main() {
  late Directory dir;
  late String tone;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('dawedit_cli');
    tone = '${dir.path}/tone.wav';
    // A 2 s sine at a known level — every case below starts from this.
    final r =
        await _dawedit(['--generate', 'sine:440:2', tone, '--amp', '0.25']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  test('--generate writes a real WAV at the requested level', () {
    expect(File(tone).existsSync(), isTrue);
    expect(_durationMsOf(tone), closeTo(2000, 1));
    expect(_peakOf(tone), closeTo(0.25, 0.01));
  });

  test('--stats reports peak and RMS of a sine (RMS = peak/sqrt2)', () async {
    final r = await _dawedit([tone, '--stats']);
    expect(r.exitCode, 0);
    final out = r.stdout as String;
    expect(out, contains('peak 0.2500'));
    expect(out, contains('-12.0 dBFS'));
    expect(out, contains('RMS 0.1768')); // 0.25 / sqrt(2)
    expect(out, contains('clipped 0'));
  });

  test('--normalize then --amplify chain in the order given', () async {
    final out = '${dir.path}/chain.wav';
    final r = await _dawedit([tone, out, '--normalize', '--amplify', '-6']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    // 0.98 normalized, then -6 dB → 0.98 * 0.5012.
    expect(_peakOf(out), closeTo(0.4912, 0.002));
  });

  test('--crop keeps only the marked window', () async {
    final out = '${dir.path}/crop.wav';
    final r = await _dawedit([tone, out, '--crop', '500:1500']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(_durationMsOf(out), closeTo(1000, 2));
    expect(_peakOf(out), closeTo(0.25, 0.01)); // untouched audio
  });

  test('--silence blanks the range WITHOUT shortening the file', () async {
    final out = '${dir.path}/silence.wav';
    final r = await _dawedit([tone, out, '--silence', '500:1500']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    // The hole stays a hole: nothing ripples left, so the file is still 2 s.
    expect(_durationMsOf(out), closeTo(2000, 2));

    // Sample a WINDOW, not a point: a single sample of a sine can legitimately
    // be zero (at 440 Hz, 100 ms in is exactly 44 cycles — a zero crossing).
    final wav = readWavPcm16(File(out).readAsBytesSync());
    int peakOver(int fromMs, int toMs) {
      var peak = 0;
      final from = fromMs * wav.sampleRate ~/ 1000;
      final to = toMs * wav.sampleRate ~/ 1000;
      for (var i = from; i < to && i < wav.samples.length; i++) {
        if (wav.samples[i].abs() > peak) peak = wav.samples[i].abs();
      }
      return peak;
    }

    expect(peakOver(700, 1300), 0); // inside the hole: real silence
    expect(peakOver(0, 400), greaterThan(1000)); // head kept
    expect(peakOver(1600, 2000), greaterThan(1000)); // tail kept, in place
  });

  test('--silence at the head then --trim-silence restores the audio',
      () async {
    final blanked = '${dir.path}/head.wav';
    final trimmed = '${dir.path}/trimmed.wav';
    expect((await _dawedit([tone, blanked, '--silence', '0:500'])).exitCode, 0);
    expect(_durationMsOf(blanked), closeTo(2000, 2)); // head blanked, not cut

    final r = await _dawedit([blanked, trimmed, '--trim-silence']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains('cut 500.0 ms off the front'));
    expect(_durationMsOf(trimmed), closeTo(1500, 2));
    expect(_peakOf(trimmed), closeTo(0.25, 0.01));
  });

  test('an unknown option fails loudly instead of being ignored', () async {
    final r = await _dawedit([tone, '--bogus']);
    expect(r.exitCode, 2);
    expect(r.stderr, contains('Unknown option'));
  });

  test('no output path leaves the input untouched and warns', () async {
    final before = File(tone).lengthSync();
    final r = await _dawedit([tone, '--normalize']);
    expect(r.exitCode, 0);
    expect(r.stderr, contains('edits were not written'));
    expect(File(tone).lengthSync(), before);
  });
}
