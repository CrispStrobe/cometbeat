// tool/hybrid_chord_eval.dart
//
// Option C: let each path do the job it is actually good at.
//
//   COMET_ACCEPT_LICENSES=CC-BY-NC-SA-4.0 \
//     dart run tool/hybrid_chord_eval.dart <dir-with-wav-and-jams>
//
// THE HYPOTHESIS. Measured separately on the same audio, the two paths fail in
// opposite places. BTC gets the ROOT right 95.8% of the time but its head has
// only 25 classes, so it can never say anything but major or minor — useless for
// a chart that needs m7b5 or maj7. Our chroma matcher can express those, but its
// dominant failure is ROOT confusion: it hears E flat as its fifth B flat, or A
// flat as its relative minor F minor, because guitar voicings double roots and
// fifths and the low root's harmonics reinforce them.
//
// So: take the root from BTC, and let chroma choose the quality among ONLY the
// templates rooted there. Chroma stops doing the thing it is bad at, and the
// entire root-confusion error class disappears by construction.
//
// ⚠️ LICENCE. BTC weights are CC-BY-NC-SA-4.0 — NON-COMMERCIAL. This is
// evaluation, scoped by an env var, and it proves nothing about shippability:
// a hybrid built on NC weights inherits the NC. What it CAN do is tell us how
// much quality accuracy a good root is worth, which is a design fact that
// survives whatever weights we end up owning.

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
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

/// Harte quality → our template suffix, or null if no template expresses it.
String? _suffix(String quality) => switch (quality.split('(').first) {
      'maj' || '' => '',
      'min' => 'm',
      'maj7' => 'maj7',
      'min7' => 'm7',
      '7' => '7',
      'sus4' => 'sus4',
      'dim' => 'dim',
      'aug' => 'aug',
      'hdim7' => 'm7b5',
      'dim7' => 'dim7',
      'maj6' => '6',
      'min6' => 'm6',
      _ => null,
    };

String? _majminOf(String? suffix) => switch (suffix) {
      '' || 'maj7' || '6' || '7' || '9' || 'maj9' => 'maj',
      'm' || 'm7' || 'm6' || 'm9' || 'mMaj7' => 'min',
      _ => null,
    };

class _T {
  double w = 0, root = 0, majmin = 0, exact = 0;
  String pct(double v) =>
      w == 0 ? '  n/a' : '${(100 * v / w).toStringAsFixed(1)}%';
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: hybrid_chord_eval.dart <dir>');
    exit(2);
  }
  final wavs = Directory(args.first)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('_mic.wav'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final bundle = await HarmonyModelStore().load();

  // The hybrid gets the FULL vocabulary. Its earlier harm was root confusion,
  // which is exactly what BTC now removes — so the extra qualities may finally
  // pay off. That is the second thing this measures.
  const rich = <ChordTemplate>[
    ...kChordTemplates,
    ChordTemplate('m7b5', [0, 3, 6, 10]),
    ChordTemplate('dim7', [0, 3, 6, 9]),
    ChordTemplate('6', [0, 4, 7, 9]),
    ChordTemplate('m6', [0, 3, 7, 9]),
  ];
  final plain = ChordDetector();
  final richDet = ChordDetector(templates: rich);

  final btc = _T(), chroma = _T(), hybrid8 = _T(), hybridRich = _T();
  // Sweep the simplicity prior rather than guessing one value.
  final biased = <double, _T>{
    for (final v in [0.02, 0.05, 0.10, 0.20]) v: _T(),
  };

  for (final wavFile in wavs) {
    final jamsFile =
        File(wavFile.path.replaceAll(RegExp(r'_mic\.wav$'), '.jams'));
    if (!jamsFile.existsSync()) continue;

    final wav = readWavPcm16(wavFile.readAsBytesSync());
    final mono = Float64List(wav.samples.length ~/ wav.channels);
    for (var i = 0; i < mono.length; i++) {
      mono[i] = wav.samples[i * wav.channels] / 32768.0;
    }
    final est = estimateChords(
      mono,
      model: bundle.model,
      cqt: bundle.cqt,
      sampleRate: wav.sampleRate,
      keepNoChord: true,
    );

    final jams =
        jsonDecode(jamsFile.readAsStringSync()) as Map<String, dynamic>;
    final anns = (jams['annotations'] as List)
        .cast<Map<String, dynamic>>()
        .where((a) => a['namespace'] == 'chord')
        .toList();
    if (anns.isEmpty) continue;
    final ref = (anns.last['data'] as List).cast<Map<String, dynamic>>();

    for (final obs in ref) {
      final value = (obs['value'] as String?) ?? '';
      if (!value.contains(':')) continue;
      final pc = _rootPc(value.split(':').first);
      final suffix = _suffix(value.split(':')[1].split('/').first);
      if (pc == null || suffix == null) continue;
      final refMm = _majminOf(suffix);
      if (refMm == null) continue;
      final time = (obs['time'] as num).toDouble();
      final dur = (obs['duration'] as num).toDouble();
      if (dur < 0.5) continue;

      // ── BTC's answer at the segment midpoint ──
      final mid = (time + dur / 2) * 1000;
      ChordEvent? at;
      for (final e in est) {
        if (mid >= e.onMs && mid < e.offMs) {
          at = e;
          break;
        }
      }
      final btcRoot = at?.rootPc;
      final btcMm = at == null
          ? null
          : (at.quality == 'maj'
              ? 'maj'
              : (at.quality == 'min' ? 'min' : null));

      btc.w += dur;
      if (btcRoot == pc) btc.root += dur;
      if (btcRoot == pc && btcMm == refMm) btc.majmin += dur;
      // BTC structurally cannot name anything but maj/min.
      if (btcRoot == pc && btcMm == refMm && (suffix == '' || suffix == 'm')) {
        btc.exact += dur;
      }

      // ── the smoothed chroma over the same segment ──
      const win = 8192, votes = 9;
      final windows = <Float64List>[];
      for (var k = 0; k < votes; k++) {
        final atS = time + dur * (k + 0.5) / votes;
        final start = ((atS * wav.sampleRate).round()) - win ~/ 2;
        if (start < 0 || start + win >= mono.length) continue;
        windows.add(Float64List.sublistView(mono, start, start + win));
      }
      if (windows.isEmpty) continue;

      List<double> smooth(ChordDetector d) {
        final sm = ChordSmoother(d, mode: ChordSmoothing.meanChroma);
        ChordReading? out;
        for (final w in windows) {
          out = sm.add(d.analyze(w));
        }
        return out?.chroma ?? List<double>.filled(12, 0);
      }

      // chroma alone
      final cChroma = smooth(plain);
      final cCand = plain.matchChroma(cChroma);
      chroma.w += dur;
      if (cCand.isNotEmpty) {
        final top = cCand.first;
        if (top.rootPc == pc) chroma.root += dur;
        if (top.rootPc == pc && _majminOf(top.suffix) == refMm) {
          chroma.majmin += dur;
        }
        if (top.rootPc == pc && top.suffix == suffix) chroma.exact += dur;
      }

      // ── the HYBRID: BTC's root, chroma's quality among templates on it ──
      // [simplicity] biases toward the plainer chord: a richer template must
      // beat the simplest one by this margin to be chosen. The hybrid's failure
      // mode is over-predicting extensions — calling a plain major a major
      // seventh — so this is the one knob that could rescue it.
      void doHybrid(ChordDetector d, _T t, {double simplicity = 0}) {
        t.w += dur;
        if (btcRoot == null || btcRoot < 0) return;
        final cands = d.matchChroma(smooth(d));
        final onRoot = cands.where((c) => c.rootPc == btcRoot).toList();
        if (onRoot.isEmpty) return;
        var best = onRoot.first;
        if (simplicity > 0) {
          // The simplest quality on this root, and how far behind it is.
          const simple = ['', 'm'];
          final plainest = onRoot.where((c) => simple.contains(c.suffix));
          if (plainest.isNotEmpty) {
            final p = plainest.reduce((a, b) => a.score >= b.score ? a : b);
            if (best.score - p.score < simplicity) best = p;
          }
        }
        if (btcRoot == pc) t.root += dur;
        if (btcRoot == pc && _majminOf(best.suffix) == refMm) t.majmin += dur;
        if (btcRoot == pc && best.suffix == suffix) t.exact += dur;
      }

      doHybrid(plain, hybrid8);
      doHybrid(richDet, hybridRich);
      for (final e in biased.entries) {
        doHybrid(richDet, e.value, simplicity: e.key);
      }
    }
  }

  void row(String label, _T t) => stdout.writeln(
        '  ${label.padRight(26)} root ${t.pct(t.root).padLeft(6)}   '
        'majmin ${t.pct(t.majmin).padLeft(6)}   '
        'FULL QUALITY ${t.pct(t.exact).padLeft(6)}',
      );

  stdout.writeln('=== Option C: BTC root + chroma quality ===');
  stdout.writeln('  (duration-weighted, performed annotation, '
      '${btc.w.toStringAsFixed(0)}s)\n');
  row('chroma alone', chroma);
  row('BTC alone', btc);
  row('hybrid (8 templates)', hybrid8);
  row('hybrid (12 templates)', hybridRich);
  for (final e in biased.entries) {
    row('hybrid +simplicity ${e.key}', e.value);
  }
  stdout.writeln('\n  NB "FULL QUALITY" requires the exact quality — maj7 as '
      'maj7, not as maj.\n  BTC alone can only ever score there on plain '
      'maj/min, by construction.');
}
