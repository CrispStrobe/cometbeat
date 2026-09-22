// tool/pool_workers_ab.dart
//
// A/B harness for the `onnx_runtime_dart` isolate GEMM pool — the ONE knob
// `OnnxModel.parallelize(workers: N, poolConv: true)` exposes, measured rather
// than guessed. Answers two separate questions with the same runs:
//
//   1. Is the pool worth it at all?     (arm 0 vs the rest)
//   2. How many workers?                (arm 2 vs 4 vs 6 — the `autoPoolWorkers`
//                                        cap in crepe_model_store.dart)
//
// ⚠ Measurement rules, deliberately hard-coded so a result can't be produced by
// a sloppier protocol:
//
//   · ONE ARM PER PROCESS. Isolate pools, JIT/AOT state and the allocator all
//     carry over inside a process, so two arms in one process measure the
//     order they ran in.
//   · THE FIRST RUN OF EACH ARM IS DISCARDED (cold: page cache, model file,
//     first-touch of the weight pages).
//   · MEDIAN, NOT MEAN, of at least three remaining runs. One descheduled run
//     on a shared machine moves a mean and not a median.
//   · OUTPUT EQUALITY IS CHECKED, not assumed. The pool splits each Conv/MatMul
//     by output band and concatenates — a pure scheduling change — so anything
//     other than byte-identical output is a BUG, not a tradeoff. Arms that
//     disagree are reported and the harness exits non-zero.
//
// Usage:
//   dart run tool/pool_workers_ab.dart --model basicpitch --bin <aot-exe> \
//       [--wav bench.wav] [--seconds 20] [--arms 0,2,4,6] [--runs 4]
//
//   --model basicpitch   bin/transcribe_basicpitch.dart --workers N  (Basic Pitch)
//   --model crepe        bin/transcribe_crepe.dart      --workers N  (CREPE-tiny)
//
// `--bin` should be the AOT executable (`dart build cli --target …`), not
// `dart run`: the JIT's warm-up inflates compute relative to the pool's
// per-conv message copy, which biases the comparison towards the pool. The app
// ships AOT, so AOT is what the numbers should describe.
//
// The benchmark WAV is synthesised here (a four-chord piano-ish progression) so
// no audio fixture has to live in the repo.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

Future<int> main(List<String> args) async {
  String opt(String flag, String fallback) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final model = opt('--model', 'basicpitch');
  final bin = opt('--bin', '');
  final wav = opt('--wav', 'pool_ab_bench.wav');
  final seconds = double.parse(opt('--seconds', '20'));
  final arms = opt('--arms', '0,2,4,6').split(',').map(int.parse).toList();
  final runs = int.parse(opt('--runs', '4'));

  if (bin.isEmpty || !File(bin).existsSync()) {
    stderr.writeln('usage: dart run tool/pool_workers_ab.dart --model '
        'basicpitch|crepe --bin <aot-exe> [--wav f.wav] [--seconds 20] '
        '[--arms 0,2,4,6] [--runs 4]');
    stderr.writeln('--bin must point at an existing executable (got "$bin")');
    return 64;
  }
  if (runs < 4) {
    stderr.writeln('--runs must be >= 4 (one cold run discarded, median of '
        'at least three)');
    return 64;
  }

  if (!File(wav).existsSync()) {
    File(wav).writeAsBytesSync(_synthWav(seconds));
    stderr.writeln('synthesised $wav (${seconds}s, 44100 Hz mono)');
  }

  stderr.writeln('host: ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion} · '
      '${Platform.numberOfProcessors} logical processors');
  stderr.writeln('model: $model · arms: $arms · runs/arm: $runs '
      '(1 discarded) · one process per run');

  final results = <int, List<int>>{};
  final outputs = <int, String>{};
  var mismatch = false;

  for (final workers in arms) {
    final times = <int>[];
    for (var r = 0; r < runs; r++) {
      final res = await _runOnce(model: model, bin: bin, wav: wav, w: workers);
      if (res == null) {
        stderr.writeln('arm $workers run $r FAILED — aborting');
        return 70;
      }
      // Discard the cold run.
      if (r > 0) times.add(res.ms);
      // Keep the LAST warm output for the equality check (any warm run will
      // do — if they differed between runs of one arm that is itself a bug,
      // which the per-run check below catches).
      final prev = outputs[workers];
      if (prev != null && prev != res.json) {
        stderr.writeln('arm $workers: output differs BETWEEN RUNS of the same '
            'arm — non-determinism independent of the pool');
        mismatch = true;
      }
      outputs[workers] = res.json;
      stderr.writeln('  arm $workers run $r: ${res.ms} ms'
          '${r == 0 ? '  (cold — discarded)' : ''}');
    }
    results[workers] = times;
  }

  // ── Output equality ───────────────────────────────────────────────────────
  final baselineArm = arms.contains(0) ? 0 : arms.first;
  final baseline = outputs[baselineArm]!;
  stdout.writeln();
  stdout.writeln('### Output equality (vs arm $baselineArm)');
  stdout.writeln();
  stdout.writeln('| workers | result |');
  stdout.writeln('|---|---|');
  for (final w in arms) {
    final same = outputs[w] == baseline;
    if (!same) mismatch = true;
    stdout.writeln('| $w | ${same ? 'IDENTICAL' : '**DIFFERS — BUG**'} |');
  }
  stdout.writeln();
  stdout.writeln('Compared: the full JSON note list '
      '(`midi`, `onMs`, `offMs`, `confidence` at full double precision), '
      '${_noteCount(baseline)} notes.');

  // ── Timings ───────────────────────────────────────────────────────────────
  final base = _median(results[baselineArm]!);
  stdout.writeln();
  stdout.writeln('### ${Platform.operatingSystem} · '
      '${Platform.numberOfProcessors} logical processors · $model');
  stdout.writeln();
  stdout.writeln('| workers | median ms | all warm runs | speedup |');
  stdout.writeln('|---|---|---|---|');
  for (final w in arms) {
    final t = results[w]!;
    final med = _median(t);
    final sp = med == 0 ? '—' : '${(base / med).toStringAsFixed(2)}×';
    stdout.writeln('| $w | **$med** | ${t.join(', ')} | $sp |');
  }
  stdout.writeln();
  stdout.writeln('Spread within each arm is the honest error bar: a difference '
      'between two arms smaller than the within-arm spread is noise.');

  return mismatch ? 1 : 0;
}

/// One arm, one process. Returns the self-reported inference time (the CLI
/// prints `elapsed_ms N` on stderr, excluding model load and WAV decode) and
/// the JSON note list from stdout.
Future<({int ms, String json})?> _runOnce({
  required String model,
  required String bin,
  required String wav,
  required int w,
}) async {
  final args = switch (model) {
    // CREPE: the RAW pitch track, so the timing is inference and not the
    // note-HMM segmentation that follows it (constant across arms, but it
    // would dilute the ratio being measured).
    'crepe' => [wav, '--workers', '$w', '--f0', '--json'],
    _ => [wav, '--workers', '$w', '--json'],
  };
  final p =
      await Process.run(bin, args, stdoutEncoding: utf8, stderrEncoding: utf8);
  if (p.exitCode != 0) {
    stderr.writeln(p.stderr);
    return null;
  }
  final m = RegExp(r'elapsed_ms (\d+)').firstMatch(p.stderr as String);
  if (m == null) {
    stderr.writeln('no `elapsed_ms` line on stderr:\n${p.stderr}');
    return null;
  }
  return (ms: int.parse(m.group(1)!), json: (p.stdout as String).trim());
}

int _median(List<int> xs) {
  final s = [...xs]..sort();
  if (s.isEmpty) return 0;
  return s.length.isOdd
      ? s[s.length ~/ 2]
      : ((s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2).round();
}

int _noteCount(String json) {
  try {
    return (jsonDecode(json) as List).length;
  } on Object {
    return -1;
  }
}

/// A four-chord piano-ish progression — three voices, five harmonics, an
/// exponential decay. Polyphonic (so Basic Pitch has real work to do) and
/// deterministic (so the equality check means something).
Uint8List _synthWav(double seconds) {
  const sr = 44100;
  final n = (sr * seconds).round();
  final buf = Float64List(n);
  const prog = [
    [60, 64, 67],
    [57, 60, 64],
    [53, 57, 60],
    [55, 59, 62],
  ];
  const harmonics = [1.0, 0.45, 0.22, 0.12, 0.06];
  const chordSeconds = 1.0;
  final chords = (seconds / chordSeconds).floor();
  for (var c = 0; c < chords; c++) {
    final start = (c * chordSeconds * sr).round();
    for (final midi in prog[c % prog.length]) {
      final f = 440.0 * math.pow(2, (midi - 69) / 12);
      final len = math.min((chordSeconds * 1.6 * sr).round(), n - start);
      for (var k = 0; k < len; k++) {
        final t = k / sr;
        var s = 0.0;
        for (var h = 0; h < harmonics.length; h++) {
          s += harmonics[h] * math.sin(2 * math.pi * f * (h + 1) * t);
        }
        buf[start + k] += math.exp(-3.0 * t) * s * 0.12;
      }
    }
  }
  var peak = 0.0;
  for (final x in buf) {
    peak = math.max(peak, x.abs());
  }
  final scale = peak == 0 ? 0.0 : 0.9 / peak;

  final bytes = BytesBuilder();
  void str(String s) => bytes.add(s.codeUnits);
  void u32(int v) => bytes
      .add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) => bytes
      .add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
  final data = Uint8List(n * 2);
  final dv = ByteData.view(data.buffer);
  for (var i = 0; i < n; i++) {
    dv.setInt16(
      i * 2,
      (buf[i] * scale * 32767).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  str('RIFF');
  u32(36 + data.length);
  str('WAVE');
  str('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(sr);
  u32(sr * 2); // byte rate
  u16(2); // block align
  u16(16); // bits
  str('data');
  u32(data.length);
  bytes.add(data);
  return bytes.takeBytes();
}
