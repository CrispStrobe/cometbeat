// tool/symbolic_chord_eval.dart
//
// Symbolic notes → chords: how good is it, measured rather than assumed.
//
//   dart run tool/symbolic_chord_eval.dart <dir-with-jams>
//
// This is a DIFFERENT problem from audio chord recognition and it is worth not
// conflating them. Here the notes are already known — the question is only which
// chord a set of sounding pitches spells. It is the engine behind deriving charts
// from the 46k-score corpus (BB-X1) and behind explaining a chart's harmony
// (BB-X6), and it never touches a microphone.
//
// It is scored on the SAME GuitarSet takes, the SAME segments and the SAME
// MIREX-style majmin duration-weighted metric as the audio evaluations, so the
// numbers are directly comparable — but note the input differs: this reads
// GuitarSet's `note_midi` annotations (what was played, already transcribed)
// rather than the waveform. It therefore measures the symbolic reader's ceiling
// given PERFECT transcription, which is exactly the number BB-X1 needs, since
// there the notes come from a score and really are perfect.
//
// Four strategies are compared because the naive one is not the obvious winner:
//   all       every note sounding anywhere in the segment
//   midpoint  only what sounds at the segment's midpoint
//   weighted  duration-weighted pitch classes, strongest 3-4 kept
//   nct       `all`, retrying without one note when nothing matches

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart'
    show ChordAnalysis, Pitch, identifyChord;

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

String? _refSuffix(String q) => switch (q.split('(').first) {
      'maj' || '' => '',
      'min' => 'm',
      'maj7' => 'maj7',
      'min7' => 'm7',
      '7' => '7',
      'sus4' => 'sus4',
      'sus2' => 'sus2',
      'dim' => 'dim',
      'aug' => 'aug',
      'hdim7' => 'm7b5',
      'dim7' => 'dim7',
      'maj6' => '6',
      'min6' => 'm6',
      _ => null,
    };

String? _majmin(String? s) => switch (s) {
      '' || 'maj7' || '6' || '7' || '9' || 'maj9' => 'maj',
      'm' || 'm7' || 'm6' || 'm9' || 'mMaj7' => 'min',
      _ => null,
    };

class _T {
  double w = 0, root = 0, majmin = 0, exact = 0, named = 0;
  String p(double v) =>
      w == 0 ? ' n/a' : '${(100 * v / w).toStringAsFixed(1)}%';
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: symbolic_chord_eval.dart <dir>');
    exit(2);
  }
  final files = Directory(args.first)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.jams'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final res = {
    for (final k in ['all', 'midpoint', 'weighted', 'nct']) k: _T(),
  };
  var segments = 0;

  for (final f in files) {
    final jams = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final anns = (jams['annotations'] as List).cast<Map<String, dynamic>>();
    final chordAnns = anns.where((a) => a['namespace'] == 'chord').toList();
    final notes = <Map<String, dynamic>>[
      for (final a in anns)
        if (a['namespace'] == 'note_midi')
          ...(a['data'] as List).cast<Map<String, dynamic>>(),
    ];
    if (chordAnns.isEmpty || notes.isEmpty) continue;
    final ref = (chordAnns.last['data'] as List).cast<Map<String, dynamic>>();

    for (final obs in ref) {
      final value = (obs['value'] as String?) ?? '';
      if (!value.contains(':')) continue;
      final pc = _rootPc(value.split(':').first);
      final suffix = _refSuffix(value.split(':')[1].split('/').first);
      if (pc == null || suffix == null) continue;
      final refMm = _majmin(suffix);
      if (refMm == null) continue;
      final t0 = (obs['time'] as num).toDouble();
      final dur = (obs['duration'] as num).toDouble();
      if (dur < 0.5) continue;
      segments++;

      final t1 = t0 + dur, mid = t0 + dur / 2;
      final inSeg = notes.where((n) {
        final s = (n['time'] as num).toDouble();
        final e = s + (n['duration'] as num).toDouble();
        return e > t0 && s < t1;
      }).toList();
      if (inSeg.isEmpty) continue;

      int midiOf(Map<String, dynamic> n) => (n['value'] as num).round();

      final variants = <String, List<int>>{
        'all': inSeg.map(midiOf).toSet().toList()..sort(),
        'midpoint': inSeg
            .where((n) {
              final s = (n['time'] as num).toDouble();
              return s <= mid && s + (n['duration'] as num).toDouble() > mid;
            })
            .map(midiOf)
            .toSet()
            .toList()
          ..sort(),
      };

      // Duration-weighted pitch classes — the symbolic analogue of a chroma.
      final weight = <int, double>{};
      for (final n in inSeg) {
        final s = (n['time'] as num).toDouble();
        final e = s + (n['duration'] as num).toDouble();
        final overlap = (e < t1 ? e : t1) - (s > t0 ? s : t0);
        if (overlap <= 0) continue;
        final m = midiOf(n);
        weight[m] = (weight[m] ?? 0) + overlap;
      }
      final ranked = weight.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      variants['weighted'] = (ranked.take(4).map((e) => e.key).toList())
        ..sort();

      for (final entry in variants.entries) {
        _score(res[entry.key]!, entry.value, pc, suffix, refMm, dur);
      }
      // NCT variant: `all`, but drop one note if nothing matches.
      _score(res['nct']!, variants['all']!, pc, suffix, refMm, dur, nct: true);
    }
  }

  stdout.writeln('=== SYMBOLIC notes → chords (GuitarSet note_midi, '
      '$segments segments) ===\n');
  for (final e in res.entries) {
    final t = e.value;
    stdout.writeln('  ${e.key.padRight(9)} '
        'named ${t.p(t.named).padLeft(6)}   '
        'root ${t.p(t.root).padLeft(6)}   '
        'majmin ${t.p(t.majmin).padLeft(6)}   '
        'FULL ${t.p(t.exact).padLeft(6)}');
  }
  stdout.writeln('\n  "named" = a chord was identified at all. The others are '
      'over ALL segments,\n  so an unnamed segment counts against them — which '
      'is the honest denominator.');
  stdout.writeln('\n  for comparison, on the same segments from AUDIO:');
  stdout.writeln('    chroma            root  70.5%   majmin  69.2%');
  stdout.writeln('    BTC (neural)      root  95.8%   majmin  89.7%');
}

void _score(
  _T t,
  List<int> midis,
  int refPc,
  String refSuffix,
  String refMm,
  double dur, {
  bool nct = false,
}) {
  t.w += dur;
  ChordAnalysis? got = _identify(midis);
  if (got == null && nct && midis.length > 3) {
    // Drop each note in turn and take the first clean read — the same
    // one-non-chord-tone recovery `analyze()` performs on a score.
    for (var i = 0; i < midis.length; i++) {
      final without = [...midis]..removeAt(i);
      got = _identify(without);
      if (got != null) break;
    }
  }
  if (got == null) return;
  t.named += dur;
  final gotPc = (got.root.step.semitonesFromC + got.root.alter) % 12;
  final gotSuffix = got.type.suffix;
  if (gotPc == refPc) t.root += dur;
  if (gotPc == refPc && _majmin(gotSuffix) == refMm) t.majmin += dur;
  if (gotPc == refPc && gotSuffix == refSuffix) t.exact += dur;
}

ChordAnalysis? _identify(List<int> midis) {
  if (midis.length < 3) return null;
  return identifyChord([for (final m in midis) Pitch.fromMidi(m)]);
}
