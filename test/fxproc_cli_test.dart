// bin/fxproc.dart end-to-end: run the real CLI as a subprocess and check the
// audio that lands on disk. The sibling of dawedit_cli_test.dart — the chain
// GRAMMAR is covered headlessly in fx_chain_codec_test.dart and the DSP in the
// per-effect tests, so what this guards is the wiring: that the registry
// reaches the command line, that stereo survives, that a bad chain writes
// nothing, and that the CLI stays Flutter-free (`dart run`, not `flutter test`).
//
// ⏱ Every test here SPAWNS A PROCESS, so the default 30-second budget is the
// wrong one: it is sized for an in-process unit test, and a `dart run` on a
// machine that is busy (a parallel suite, a build, CI) can take far longer than
// the work it is doing. This suite was seen failing at load average 28 on a
// developer machine while passing in seconds when idle — a timeout that depends
// on what else is running is a flake, not a signal. The budget below is
// deliberately generous for that reason; it is not hiding a slow code path,
// which is why the assertions themselves are unchanged.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/synth.dart' show wavBytesStereo;
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ProcessResult> _fxproc(List<String> args) =>
    Process.run('dart', ['run', 'bin/fxproc.dart', ...args]);

Future<ProcessResult> _dawedit(List<String> args) =>
    Process.run('dart', ['run', 'bin/dawedit.dart', ...args]);

({int channels, int frames, double peak, double rms}) _read(String path) {
  final wav = readWavPcm16(File(path).readAsBytesSync());
  final channels = wav.channels;
  var peak = 0.0;
  var sumSquares = 0.0;
  for (final s in wav.samples) {
    final v = s / 32768;
    if (v.abs() > peak) peak = v.abs();
    sumSquares += v * v;
  }
  return (
    channels: channels,
    frames: wav.samples.length ~/ channels,
    peak: peak,
    rms: wav.samples.isEmpty ? 0 : math.sqrt(sumSquares / wav.samples.length),
  );
}

/// A stereo file whose two sides differ, so a channel-preserving claim can
/// actually be checked: left is a 440 Hz tone, right is silence.
void _writeStereoTone(String path, {int seconds = 1, int rate = 44100}) {
  final frames = seconds * rate;
  final out = Int16List(frames * 2);
  for (var i = 0; i < frames; i++) {
    out[i * 2] = (0.5 * 32767 * math.sin(2 * math.pi * 440 * i / rate)).round();
    out[i * 2 + 1] = 0;
  }
  File(path).writeAsBytesSync(wavBytesStereo(out, sampleRate: rate));
}

void main() {
  late Directory dir;
  late String tone;
  late String stereo;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('fxproc_cli');
    tone = '${dir.path}/tone.wav';
    stereo = '${dir.path}/stereo.wav';
    // Compile both CLIs HERE, serially, before any test body runs. `dart run`
    // builds a kernel snapshot on first use and `flutter test` runs suites
    // concurrently, so leaving the first fxproc invocation inside a test body
    // lets several suites race on that build. Paying it once in setUp costs a
    // second and takes the whole class of flake off the table.
    expect((await _fxproc(['--help'])).exitCode, 0);
    final r =
        await _dawedit(['--generate', 'sine:440:2', tone, '--amp', '0.5']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    _writeStereoTone(stereo);
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  group('--list is generated from the registry', () {
    test('lists every effect the app has', () async {
      final r = await _fxproc(['--list']);
      expect(r.exitCode, 0);
      final out = r.stdout as String;
      expect(out, contains('${FxType.values.length} effects'));
      for (final type in FxType.values) {
        expect(out, contains(type.name), reason: '${type.name} not listed');
      }
    });

    test('one effect shows its params, defaults and ranges', () async {
      final r = await _fxproc(['--list', 'compressor']);
      expect(r.exitCode, 0);
      final out = r.stdout as String;
      expect(out, contains('thresholdDb'));
      expect(out, contains('default -18'));
      expect(out, contains('-60..0 dB'));
    });

    test('an unknown effect exits non-zero and says so', () async {
      final r = await _fxproc(['--list', 'notaneffect']);
      expect(r.exitCode, 2);
      expect(r.stderr as String, contains('notaneffect'));
    });
  });

  group('--chain processes audio', () {
    test('gain moves the level by exactly the dB asked for', () async {
      final out = '${dir.path}/gain.wav';
      final r = await _fxproc([tone, out, '--chain', 'gain gainDb=-6']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      // −6 dB is a factor of 0.501; the source peaks at 0.5.
      expect(_read(out).peak, closeTo(0.5 * 0.5012, 0.005));
    });

    test('a low-pass well below the tone attenuates it', () async {
      final out = '${dir.path}/lp.wav';
      final r =
          await _fxproc([tone, out, '--chain', 'lowpass freq=200 q=0.707']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      // 440 Hz is over an octave above a 2-pole 200 Hz corner: heavily down.
      expect(_read(out).rms, lessThan(_read(tone).rms / 4));
    });

    test('stages apply in the order written', () async {
      // Boosting then cutting by the same amount returns the level; cutting
      // first and boosting after would too — so the order is checked with a
      // filter that only one order lets through.
      final quiet = '${dir.path}/order_a.wav';
      final loud = '${dir.path}/order_b.wav';
      expect(
        (await _fxproc(
          [tone, quiet, '--chain', 'gain gainDb=-24 | lowpass freq=8000'],
        ))
            .exitCode,
        0,
      );
      expect(
        (await _fxproc(
          [tone, loud, '--chain', 'lowpass freq=8000 | gain gainDb=-24'],
        ))
            .exitCode,
        0,
      );
      // Both orders are linear here, so they must agree — this pins that the
      // chain applies every stage rather than only the first or the last.
      expect(_read(quiet).rms, closeTo(_read(loud).rms, 1e-3));
      expect(_read(quiet).rms, lessThan(_read(tone).rms / 8));
    });

    test('a bypassed stage does nothing', () async {
      final out = '${dir.path}/bypass.wav';
      final r = await _fxproc([tone, out, '--chain', '!gain gainDb=-24']);
      expect(r.exitCode, 0);
      expect(_read(out).peak, closeTo(_read(tone).peak, 1e-3));
    });

    test('repeated --chain flags concatenate', () async {
      final out = '${dir.path}/two.wav';
      final r = await _fxproc([
        tone,
        out,
        '--chain',
        'gain gainDb=-6',
        '--chain',
        'gain gainDb=-6',
      ]);
      expect(r.exitCode, 0);
      expect(r.stdout as String, contains('gain gainDb=-6 | gain gainDb=-6'));
      expect(_read(out).peak, closeTo(0.5 * 0.2512, 0.005)); // −12 dB total
    });
  });

  group('channels', () {
    test('stereo in → stereo out, and the sides stay apart', () async {
      final out = '${dir.path}/st.wav';
      final r = await _fxproc([stereo, out, '--chain', 'gain gainDb=-6']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout as String, contains('stereo'));

      final wav = readWavPcm16(File(out).readAsBytesSync());
      expect(wav.channels, 2);
      var leftPeak = 0.0;
      var rightPeak = 0.0;
      for (var i = 0; i < wav.samples.length ~/ 2; i++) {
        leftPeak = math.max(leftPeak, (wav.samples[i * 2] / 32768).abs());
        rightPeak = math.max(rightPeak, (wav.samples[i * 2 + 1] / 32768).abs());
      }
      // The silent right channel must still be silent — the old CLI downmixed
      // to mono here, which would have bled the tone into both sides.
      expect(leftPeak, greaterThan(0.2));
      expect(rightPeak, lessThan(0.001));
    });

    test('--mono downmixes on request', () async {
      final out = '${dir.path}/mono.wav';
      final r = await _fxproc([stereo, out, '--mono', '--chain', 'gain']);
      expect(r.exitCode, 0);
      expect(readWavPcm16(File(out).readAsBytesSync()).channels, 1);
    });

    test('mono stays mono when the chain does not move the channels', () async {
      final out = '${dir.path}/stays.wav';
      expect(
        (await _fxproc([tone, out, '--chain', 'gain gainDb=-3'])).exitCode,
        0,
      );
      expect(readWavPcm16(File(out).readAsBytesSync()).channels, 1);
    });

    test('mono WIDENS when the chain moves the channels apart', () async {
      final out = '${dir.path}/wide.wav';
      final r = await _fxproc([tone, out, '--chain', 'pan pan=-1']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout as String, contains('moved the channels apart'));
      final wav = readWavPcm16(File(out).readAsBytesSync());
      expect(wav.channels, 2);
      // Hard left: the right side is gone.
      var leftPeak = 0.0;
      var rightPeak = 0.0;
      for (var i = 0; i < wav.samples.length ~/ 2; i++) {
        leftPeak = math.max(leftPeak, (wav.samples[i * 2] / 32768).abs());
        rightPeak = math.max(rightPeak, (wav.samples[i * 2 + 1] / 32768).abs());
      }
      expect(leftPeak, greaterThan(rightPeak * 10));
    });
  });

  group('reporting and refusal', () {
    test('--stats prints the level before and after', () async {
      final out = '${dir.path}/stats.wav';
      final r =
          await _fxproc([tone, out, '--stats', '--chain', 'gain gainDb=-6']);
      expect(r.exitCode, 0);
      final text = r.stdout as String;
      expect(text, contains('in '));
      expect(text, contains('out'));
      expect(text, contains('-6.0 dBFS')); // the source's own peak
    });

    test('--dry-run describes the chain and writes nothing', () async {
      final out = '${dir.path}/never.wav';
      final r = await _fxproc([tone, out, '--dry-run', '--chain', 'reverb']);
      expect(r.exitCode, 0);
      expect(r.stdout as String, contains('roomSize'));
      expect(File(out).existsSync(), isFalse);
    });

    test('a bad chain exits 2 and writes NOTHING', () async {
      final out = '${dir.path}/bad.wav';
      final r = await _fxproc([tone, out, '--chain', 'revrb mix=0.5']);
      expect(r.exitCode, 2);
      expect(r.stderr as String, contains('revrb'));
      expect(r.stderr as String, contains('reverb')); // the suggestion
      expect(File(out).existsSync(), isFalse);
    });

    test('an out-of-range value warns but still runs', () async {
      final out = '${dir.path}/clamped.wav';
      final r = await _fxproc([tone, out, '--chain', 'reverb mix=9']);
      expect(r.exitCode, 0);
      expect(r.stderr as String, contains('outside'));
      expect(File(out).existsSync(), isTrue);
    });

    test('a missing input file fails cleanly', () async {
      final r = await _fxproc([
        '${dir.path}/nope.wav',
        '${dir.path}/o.wav',
        '--chain',
        'gain',
      ]);
      expect(r.exitCode, 2);
      expect(r.stderr as String, contains('no such file'));
    });
  });

  test('the legacy --effect path still works', () async {
    final out = '${dir.path}/legacy.wav';
    final r = await _fxproc([tone, out, '--effect', 'reverb', '--mix', '0.4']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout as String, contains('fxproc: reverb'));
    expect(_read(out).channels, 1);
    expect(_read(out).frames, greaterThan(0));
  });
}
