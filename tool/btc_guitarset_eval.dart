// tool/btc_guitarset_eval.dart
//
// STEP ZERO of docs/BTC_TRAINING_HANDOVER.md, with the bar BB-H0 established:
// does the chord model we ALREADY HAVE clear 70.7% majmin on real audio?
//
//   COMET_ACCEPT_LICENSES=CC-BY-NC-SA-4.0 \
//     dart run tool/btc_guitarset_eval.dart <dir-with-wav-and-jams>
//
// ⚠️ LICENCE. The BTC weights are CC-BY-NC-SA-4.0 — NON-COMMERCIAL — and
// `model_license.dart` gates them. This is non-commercial EVALUATION, which that
// licence permits, and the acceptance is scoped to this process by an env var.
// Running it does not make the model shippable and weakens no gate.
//
// WHY IT MATTERS. Training a replacement is weeks of work whose entire
// justification is that the neural path is better. That has never been measured
// on our own evaluation set. If BTC does not clearly beat the chroma path's
// 70.7%, then the licence is not what blocks us and the plan needs rethinking
// before it starts rather than after.
//
// Scored EXACTLY like tool/guitarset_chord_eval.dart: MIREX-style majmin,
// duration-weighted, non-maj/min references excluded — otherwise the comparison
// would repeat the ruler mistake that made a 24% look like a catastrophe.

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/harmony.dart';
import 'package:comet_beat/core/audio/transcription/harmony_model_store.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

int? _rootPc(String s) {
  const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  if (s.isEmpty) return null;
  var pc = base[s[0].toUpperCase()];
  if (pc == null) return null;
  for (final ch in s.substring(1).split('')) {
    if (ch == '#') pc = pc! + 1;
    if (ch == 'b') pc = pc! - 1;
  }
  return (pc! % 12 + 12) % 12;
}

/// Harte quality → maj/min/null, the same reduction the chroma eval uses.
String? _majmin(String q) => switch (q.split('(').first) {
      'maj' || '' || 'maj7' || 'maj6' || '7' || '9' || 'maj9' => 'maj',
      'min' || 'min7' || 'min6' || 'min9' || 'minmaj7' => 'min',
      _ => null,
    };

/// BTC's `ChordEvent.quality` is literally `'maj'`, `'min'` or `'N'` — see
/// `chordFromIndex`. Reading it as `''` for major (as a first version of this did)
/// makes EVERY major chord score zero, which showed up as majmin 4.5% against
/// root 95.8% — a gap that large between root and quality is a bug in the
/// harness, not a property of the model.
String? _btcMajmin(String quality) => switch (quality) {
      'maj' => 'maj',
      'min' => 'min',
      _ => null, // 'N'
    };

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: btc_guitarset_eval.dart <dir>');
    exit(2);
  }
  final wavs = Directory(args.first)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('_mic.wav'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final bundle = await HarmonyModelStore().load();

  var weighted = 0.0, hit = 0.0, rootHit = 0.0;
  var segments = 0, files = 0;
  final sw = Stopwatch()..start();
  var audioSeconds = 0.0;

  for (final wavFile in wavs) {
    final jamsFile =
        File(wavFile.path.replaceAll(RegExp(r'_mic\.wav$'), '.jams'));
    if (!jamsFile.existsSync()) continue;
    files++;

    final wav = readWavPcm16(wavFile.readAsBytesSync());
    final mono = Float64List(wav.samples.length ~/ wav.channels);
    for (var i = 0; i < mono.length; i++) {
      mono[i] = wav.samples[i * wav.channels] / 32768.0;
    }
    audioSeconds += mono.length / wav.sampleRate;

    final est = estimateChords(
      mono,
      model: bundle.model,
      cqt: bundle.cqt,
      sampleRate: wav.sampleRate,
      keepNoChord: true,
    );

    final jams =
        jsonDecode(jamsFile.readAsStringSync()) as Map<String, dynamic>;
    final chordAnns = (jams['annotations'] as List)
        .cast<Map<String, dynamic>>()
        .where((a) => a['namespace'] == 'chord')
        .toList();
    if (chordAnns.isEmpty) continue;
    // The performed annotation: what the guitar actually played.
    final ref = (chordAnns.last['data'] as List).cast<Map<String, dynamic>>();

    for (final obs in ref) {
      final value = (obs['value'] as String?) ?? '';
      if (!value.contains(':')) continue;
      final pc = _rootPc(value.split(':').first);
      final refMm = _majmin(value.split(':')[1].split('/').first);
      if (pc == null || refMm == null) continue;
      final time = (obs['time'] as num).toDouble();
      final dur = (obs['duration'] as num).toDouble();
      if (dur < 0.5) continue;
      segments++;

      // The estimate covering the MIDPOINT of the reference segment — the same
      // sampling point the chroma eval uses, so the two are comparable.
      final mid = (time + dur / 2) * 1000;
      ChordEvent? at;
      for (final e in est) {
        if (mid >= e.onMs && mid < e.offMs) {
          at = e;
          break;
        }
      }
      weighted += dur;
      if (at == null) continue;
      if (at.rootPc == pc) rootHit += dur;
      if (at.rootPc == pc && _btcMajmin(at.quality) == refMm) hit += dur;
    }
  }
  sw.stop();

  final majmin = weighted == 0 ? 0.0 : 100 * hit / weighted;
  final root = weighted == 0 ? 0.0 : 100 * rootHit / weighted;
  stdout.writeln('=== BTC (neural, CC-BY-NC-SA weights) on GuitarSet ===');
  stdout.writeln('  $files takes, $segments maj/min segments, '
      '${weighted.toStringAsFixed(0)}s scored');
  stdout.writeln('  majmin ${majmin.toStringAsFixed(1)}%   '
      'root ${root.toStringAsFixed(1)}%');
  stdout.writeln('  inference: ${sw.elapsed.inSeconds}s for '
      '${audioSeconds.toStringAsFixed(0)}s of audio '
      '(RTF ${(sw.elapsedMilliseconds / 1000 / audioSeconds).toStringAsFixed(2)})');
  stdout
      .writeln('\n  the bar to beat (chroma, BB-H0): majmin 70.7%  root 71.4%');
  final delta = majmin - 70.7;
  stdout.writeln('  delta: ${delta >= 0 ? '+' : ''}'
      '${delta.toStringAsFixed(1)}pp majmin');
}
