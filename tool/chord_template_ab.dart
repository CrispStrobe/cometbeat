// tool/chord_template_ab.dart
//
// A/Bs a candidate ChordDetector vocabulary against the shipped one.
//
//   dart run tool/chord_template_ab.dart          # summary
//   dart run tool/chord_template_ab.dart --detail # per-quality rows
//
// WHY THIS EXISTS. Extending the chord vocabulary looks like free progress and is
// not: the templates are BINARY pitch-class vectors matched by cosine, so every
// template added is another chance to confuse one chord for another. A bigger set
// can be strictly worse. The `BB-X2` card therefore requires the extension to be
// measured, and this is the measurement.
//
// WHAT IT MEASURES. For every quality in the candidate set, at all 12 roots, in
// three voicings (close, spread over two octaves, and first inversion), it
// synthesises the chord through `synth.dart` — the same renderer the existing
// chroma tests use, so the numbers are comparable to that gate — and asks the
// detector to name it. Three scores per set:
//
//   exact   the top candidate is the right root AND the right quality
//   root    the top candidate has the right root, whatever the quality
//   top3    the right (root, quality) is anywhere in the top three
//
// `root` matters on its own: the backing-band use (BB-X5) grades a player against
// the chord that is SOUNDING, and a chord named `C6` where `Am7` was meant still
// has the right notes. `exact` is what a chart-from-audio pass (BB-X2) needs.
//
// ⚠️ Read the collision report at the end before believing a drop in `exact`.
// Some pairs are the SAME pitch-class set — C6 and Am7 are literally the same
// four notes — so no amount of template work can separate them from a chromagram
// alone, and an `exact` miss on one of those is not an error the detector could
// have avoided.

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart' show renderSegments;

const int _windowSize = 4096;

double _freq(int midi) => 440.0 * math.pow(2.0, (midi - 69) / 12.0);

/// One window of the middle of a rendered chord — the same shape
/// `test/chroma_analysis_test.dart` uses, so results are comparable.
Float64List _window(List<int> midis) {
  final samples = renderSegments([(freqs: midis.map(_freq).toList(), ms: 600)]);
  final start = (samples.length - _windowSize) ~/ 2;
  final out = Float64List(_windowSize);
  for (var i = 0; i < _windowSize; i++) {
    out[i] = samples[start + i] / 32768.0;
  }
  return out;
}

/// The three voicings each chord is tested in. A detector that only handles
/// close position in one octave is not usable on real audio.
List<List<int>> _voicingsOf(int rootMidi, List<int> intervals) {
  final close = [for (final i in intervals) rootMidi + i];
  final spread = <int>[
    rootMidi,
    for (final i in intervals.skip(1)) rootMidi + i + 12,
  ];
  // First inversion: the root goes up an octave, so the third is in the bass.
  final inverted = <int>[
    for (final i in intervals.skip(1)) rootMidi + i,
    rootMidi + 12,
  ]..sort();
  return [close, spread, inverted];
}

class _Score {
  int trials = 0;
  int exact = 0;
  int root = 0;
  int top3 = 0;
  double get exactPct => trials == 0 ? 0 : 100 * exact / trials;
  double get rootPct => trials == 0 ? 0 : 100 * root / trials;
  double get top3Pct => trials == 0 ? 0 : 100 * top3 / trials;
}

/// Runs [templates] over the whole grid and returns the totals plus a per-quality
/// breakdown.
({_Score total, Map<String, _Score> byQuality}) measure(
  List<ChordTemplate> templates, {
  required List<ChordTemplate> vocabulary,
}) {
  final detector = ChordDetector(templates: templates);
  final total = _Score();
  final byQuality = <String, _Score>{};

  for (final t in vocabulary) {
    final q = byQuality.putIfAbsent(t.suffix, _Score.new);
    for (var rootPc = 0; rootPc < 12; rootPc++) {
      // C3..B3 as the root register, where a guitar/piano chord actually sits.
      final rootMidi = 48 + rootPc;
      for (final midis in _voicingsOf(rootMidi, t.intervals)) {
        final reading = detector.analyze(_window(midis));
        total.trials++;
        q.trials++;
        if (!reading.hasChord) continue;
        final top = reading.candidates.first;
        final rootOk = top.rootPc == rootPc;
        final exactOk = rootOk && top.suffix == t.suffix;
        final inTop3 = reading.candidates
            .any((c) => c.rootPc == rootPc && c.suffix == t.suffix);
        if (rootOk) {
          total.root++;
          q.root++;
        }
        if (exactOk) {
          total.exact++;
          q.exact++;
        }
        if (inTop3) {
          total.top3++;
          q.top3++;
        }
      }
    }
  }
  return (total: total, byQuality: byQuality);
}

/// Template pairs whose pitch-class sets are IDENTICAL, and therefore
/// indistinguishable from a chromagram no matter what the detector does.
List<String> collisions(List<ChordTemplate> templates) {
  Set<int> pcs(int root, ChordTemplate t) =>
      {for (final i in t.intervals) (root + i) % 12};
  final out = <String>[];
  final seen = <String>{};
  for (var rootA = 0; rootA < 12; rootA++) {
    for (final a in templates) {
      for (var rootB = 0; rootB < 12; rootB++) {
        for (final b in templates) {
          if (rootA == rootB && a.suffix == b.suffix) continue;
          final sa = pcs(rootA, a);
          final sb = pcs(rootB, b);
          if (sa.length != sb.length || !sa.containsAll(sb)) continue;
          final names = [
            '${_pcName(rootA)}${a.suffix}',
            '${_pcName(rootB)}${b.suffix}',
          ]..sort();
          final key = names.join(' = ');
          if (seen.add(key)) out.add(key);
        }
      }
    }
  }
  return out..sort();
}

const _names = [
  'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B', //
];
String _pcName(int pc) => _names[pc];

void main(List<String> args) {
  final detail = args.contains('--detail');

  // The shipped vocabulary.
  const shipped = kChordTemplates;

  // The candidate: the shipped eight plus the qualities a jazz/pop chart needs.
  // Deliberately NOT every quality `ChordSpec` can express — a chromagram has 12
  // numbers in it, and past a certain density every template matches everything.
  const candidate = <ChordTemplate>[
    ...kChordTemplates,
    ChordTemplate('m7b5', [0, 3, 6, 10]),
    ChordTemplate('dim7', [0, 3, 6, 9]),
    ChordTemplate('6', [0, 4, 7, 9]),
    ChordTemplate('m6', [0, 3, 7, 9]),
    ChordTemplate('sus2', [0, 2, 7]),
    ChordTemplate('mMaj7', [0, 3, 7, 11]),
    ChordTemplate('9', [0, 4, 7, 10, 14]),
    ChordTemplate('m9', [0, 3, 7, 10, 14]),
    ChordTemplate('maj9', [0, 4, 7, 11, 14]),
  ];

  // Each set is measured over BOTH vocabularies, because the two questions are
  // different: "did adding templates break the chords we already handled?" and
  // "can the bigger set name the new chords at all?".
  final oldOnOld = measure(shipped, vocabulary: shipped);
  final newOnOld = measure(candidate, vocabulary: shipped);
  final newOnNew = measure(candidate, vocabulary: candidate);

  void row(String label, _Score s) {
    stdout.writeln(
      '${label.padRight(34)} '
      'exact ${s.exactPct.toStringAsFixed(1).padLeft(5)}%  '
      'root ${s.rootPct.toStringAsFixed(1).padLeft(5)}%  '
      'top3 ${s.top3Pct.toStringAsFixed(1).padLeft(5)}%  '
      '(n=${s.trials})',
    );
  }

  stdout.writeln('=== REGRESSION: the 8 shipped qualities ===');
  row('shipped set (baseline)', oldOnOld.total);
  row('candidate set', newOnOld.total);
  final dExact = newOnOld.total.exactPct - oldOnOld.total.exactPct;
  final dRoot = newOnOld.total.rootPct - oldOnOld.total.rootPct;
  stdout.writeln('  delta: exact ${dExact >= 0 ? '+' : ''}'
      '${dExact.toStringAsFixed(1)}pp  '
      'root ${dRoot >= 0 ? '+' : ''}${dRoot.toStringAsFixed(1)}pp');

  stdout.writeln(
    '\n=== COVERAGE: all ${candidate.length} candidate qualities ===',
  );
  row('candidate set', newOnNew.total);

  if (detail) {
    stdout.writeln('\n=== per quality (candidate set) ===');
    newOnNew.byQuality.forEach((suffix, s) {
      row('  "${suffix.isEmpty ? 'maj' : suffix}"', s);
    });
    stdout.writeln('\n=== per quality, shipped 8, before → after ===');
    oldOnOld.byQuality.forEach((suffix, before) {
      final after = newOnOld.byQuality[suffix]!;
      stdout.writeln(
        '  ${(suffix.isEmpty ? 'maj' : suffix).padRight(8)} '
        'exact ${before.exactPct.toStringAsFixed(0)}% → '
        '${after.exactPct.toStringAsFixed(0)}%   '
        'root ${before.rootPct.toStringAsFixed(0)}% → '
        '${after.rootPct.toStringAsFixed(0)}%',
      );
    });
  }

  final collided = collisions(candidate);
  stdout.writeln('\n=== identical pitch-class sets in the candidate vocabulary '
      '(${collided.length}) ===');
  stdout
      .writeln('These CANNOT be told apart from a chromagram. An `exact` miss');
  stdout.writeln('on one of them is not a detector error.');
  for (final c in collided.take(20)) {
    stdout.writeln('  $c');
  }
  if (collided.length > 20) {
    stdout.writeln('  … and ${collided.length - 20} more');
  }
}
