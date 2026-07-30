// tool/guitarset_chord_eval.dart
//
// The chord detector's first encounter with REAL AUDIO.
//
//   dart run tool/guitarset_chord_eval.dart <dir-with-wav-and-jams>
//
// Everything the detector has been measured on so far was synthesised by our own
// renderer, which is a rigged exam: the same code makes the sound and knows the
// answer, there is no room, no pick noise, no bleed, no human timing. This runs
// it on GuitarSet — real guitarists, a real microphone, CC BY 4.0, recorded FOR
// the dataset so axis 2 is clean, and already held in our Tier-A JAMS corpus.
//
// It exists to settle one open question. The synthetic grid says a bigger chord
// vocabulary REGRESSES accuracy (-4.2pp for four extra qualities, -10.8pp for
// nine). But that grid excludes the very chords the extension exists to catch, so
// it flatters the shipped set: a half-diminished it cannot name is not counted
// against it. Real annotated audio does not have that blind spot.
//
// GuitarSet ships two chord annotations per take. The FIRST is the instructed
// progression (`D#:maj`), the SECOND what was actually played, in full Harte
// syntax with extensions and inversions (`D#:sus2(7)/1`, `G#:maj6(*5)/1`). We
// score against the instructed one — it is the fair target for a maj/min
// vocabulary — and report how often the performed label carries a quality no
// template set can express, which bounds what any of this can achieve.

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

const _pcNames = [
  'C',
  'C#',
  'D',
  'Eb',
  'E',
  'F',
  'F#',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];
String _pcName(int pc) => _pcNames[pc];

/// Harte root spelling → pitch class.
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

/// A Harte quality reduced to the suffix our templates use, or null when no
/// template set here can express it.
String? _suffix(String quality) {
  final q = quality.split('(').first;
  return switch (q) {
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
}

class _Pair {
  final _Tally instructed = _Tally();
  final _Tally performed = _Tally();
}

class _Tally {
  int n = 0, root = 0, exact = 0;
  double get rootPct => n == 0 ? 0 : 100 * root / n;
  double get exactPct => n == 0 ? 0 : 100 * exact / n;
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: guitarset_chord_eval.dart <dir>');
    exit(2);
  }
  final dir = Directory(args.first);
  final wavs = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('_mic.wav'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  const sets = <String, List<ChordTemplate>>{
    'shipped 8': kChordTemplates,
    'modest +4': [
      ...kChordTemplates,
      ChordTemplate('m7b5', [0, 3, 6, 10]),
      ChordTemplate('dim7', [0, 3, 6, 9]),
      ChordTemplate('6', [0, 4, 7, 9]),
      ChordTemplate('m6', [0, 3, 7, 9]),
    ],
    'full +9': [
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
    ],
  };

  final tallies = {for (final k in sets.keys) k: _Tally()};
  final smoothed = <String, _Pair>{
    for (final k in sets.keys)
      for (final sm in ChordSmoothing.values) '$k|${sm.name}': _Pair(),
  };
  final performedTallies = {for (final k in sets.keys) k: _Tally()};
  final detectors = {
    for (final e in sets.entries) e.key: ChordDetector(templates: e.value),
  };
  var segments = 0, unexpressible = 0, files = 0;
  final performedQualities = <String, int>{};

  for (final wav in wavs) {
    final jamsFile = File(wav.path.replaceAll(RegExp(r'_mic\.wav$'), '.jams'));
    if (!jamsFile.existsSync()) continue;
    files++;

    final data = readWavPcm16(wav.readAsBytesSync());
    final jams =
        jsonDecode(jamsFile.readAsStringSync()) as Map<String, dynamic>;
    final chordAnns = (jams['annotations'] as List)
        .cast<Map<String, dynamic>>()
        .where((a) => a['namespace'] == 'chord')
        .toList();
    if (chordAnns.isEmpty) continue;

    // First = instructed progression; last = what was actually played.
    final instructed =
        (chordAnns.first['data'] as List).cast<Map<String, dynamic>>();
    final performed =
        (chordAnns.last['data'] as List).cast<Map<String, dynamic>>();
    for (final o in performed) {
      final v = (o['value'] as String?) ?? '';
      final q = v.contains(':') ? v.split(':')[1].split('/').first : '';
      performedQualities[q.split('(').first] =
          (performedQualities[q.split('(').first] ?? 0) + 1;
      if (_suffix(q) == null) unexpressible++;
    }

    // 🔴 Score against BOTH annotations. The instructed progression is what the
    // player was ASKED to play; the performed annotation is what actually came
    // out of the guitar, and only the second is ground truth for a detector
    // listening to the audio. Scoring detection against the instruction
    // penalises the detector for correctly hearing the maj7 voicing the player
    // chose over the plain maj that was written down.
    final annotations = <List<Map<String, dynamic>>>[instructed, performed];
    for (var annIndex = 0; annIndex < annotations.length; annIndex++) {
      final ann = annotations[annIndex];
      for (final obs in ann) {
        final value = (obs['value'] as String?) ?? '';
        if (!value.contains(':')) continue;
        final pc = _rootPc(value.split(':').first);
        final suffix = _suffix(value.split(':')[1].split('/').first);
        if (pc == null || suffix == null) continue;

        final time = (obs['time'] as num).toDouble();
        final dur = (obs['duration'] as num).toDouble();
        if (dur < 0.5) continue;

        // 🔴 VOTE OVER THE SEGMENT, do not sample one window. A single window is
        // the worst case for a per-frame detector: it can land on a re-strum, a
        // rest or the decay tail. Real chord recognition smooths over time — BTC
        // gives its transformer 108 frames of context for exactly this reason —
        // so measuring one window would have scored our sampling as much as the
        // detector.
        const win = 8192; // BB-H1: the bass needs this; chroma is unaffected
        const votes = 9;
        final windows = <Float64List>[];
        for (var k = 0; k < votes; k++) {
          final at = time + dur * (k + 0.5) / votes;
          final start = ((at * data.sampleRate).round() * data.channels) -
              win * data.channels ~/ 2;
          if (start < 0 || start + win * data.channels >= data.samples.length) {
            continue;
          }
          final w = Float64List(win);
          for (var i = 0; i < win; i++) {
            w[i] = data.samples[start + i * data.channels] / 32768.0;
          }
          windows.add(w);
        }
        if (windows.isEmpty) continue;
        final mono = windows[windows.length ~/ 2];
        if (annIndex == 1) segments++;
        if (segments <= 8 && annIndex == 1) {
          var rms = 0.0;
          for (final v in mono) {
            rms += v * v;
          }
          rms = math.sqrt(rms / mono.length);
          final r = detectors['shipped 8']!.analyze(mono);
          final got =
              r.hasChord ? r.candidates.first.toString() : 'SILENT/none';
          stdout.writeln('  probe: want ${_pcName(pc)}$suffix  got $got  '
              'rms=${rms.toStringAsFixed(4)}  energy=${r.energy.toStringAsExponential(1)}  '
              'sr=${data.sampleRate} ch=${data.channels}');
        }

        for (final entry in detectors.entries) {
          // Compare the smoothing strategies head to head on the same frames.
          for (final sm in ChordSmoothing.values) {
            final smoother = ChordSmoother(entry.value, mode: sm);
            ChordReading? out;
            for (final w in windows) {
              out = smoother.add(entry.value.analyze(w));
            }
            final st = smoothed['${entry.key}|${sm.name}']!;
            (annIndex == 0 ? st.instructed : st.performed).n++;
            if (out != null && out.hasChord) {
              final c = out.candidates.first;
              final t2 = annIndex == 0 ? st.instructed : st.performed;
              if (c.rootPc == pc) t2.root++;
              if (c.rootPc == pc && c.suffix == suffix) t2.exact++;
            }
          }

          final ballot = <String, int>{};
          for (final w in windows) {
            final r = entry.value.analyze(w);
            if (!r.hasChord) continue;
            final c = r.candidates.first;
            final key = '${c.rootPc}|${c.suffix}';
            ballot[key] = (ballot[key] ?? 0) + 1;
          }
          final t = (annIndex == 0 ? tallies : performedTallies)[entry.key]!;
          t.n++;
          if (entry.key == 'shipped 8' && annIndex == 1 && t.n <= 5) {
            final top = ballot.values.isEmpty
                ? 0
                : ballot.values.reduce((a, b) => a > b ? a : b);
            stdout.writeln('  vote: ${windows.length} windows -> '
                '${ballot.length} distinct answers, winner had $top');
          }
          if (ballot.isEmpty) continue;
          final winner = ballot.entries.reduce((a, b) {
            if (b.value != a.value) return b.value > a.value ? b : a;
            return a.key.compareTo(b.key) <= 0 ? a : b; // deterministic
          }).key;
          final gotPc = int.parse(winner.split('|')[0]);
          final gotSuffix = winner.split('|')[1];
          if (gotPc == pc) t.root++;
          if (gotPc == pc && gotSuffix == suffix) t.exact++;
        }
      }
    }
  }

  stdout.writeln('=== GuitarSet — REAL audio, $files takes, '
      '$segments annotated chord segments ===');
  stdout.writeln('--- scored against the INSTRUCTED progression '
      '(what the player was asked to play) ---');
  for (final k in sets.keys) {
    final t = tallies[k]!;
    stdout.writeln('  ${k.padRight(12)} '
        'exact ${t.exactPct.toStringAsFixed(1).padLeft(5)}%   '
        'root ${t.rootPct.toStringAsFixed(1).padLeft(5)}%   (n=${t.n})');
  }

  stdout.writeln('\n=== scored against the PERFORMED annotation '
      '(what the guitar actually played — the real ground truth) ===');
  for (final k in sets.keys) {
    final t = performedTallies[k]!;
    stdout.writeln('  ${k.padRight(12)} '
        'exact ${t.exactPct.toStringAsFixed(1).padLeft(5)}%   '
        'root ${t.rootPct.toStringAsFixed(1).padLeft(5)}%   (n=${t.n})');
  }

  stdout.writeln('\n=== SMOOTHING head to head '
      '(9 frames, scored against the performed annotation) ===');
  for (final k in sets.keys) {
    for (final sm in ChordSmoothing.values) {
      final t = smoothed['$k|${sm.name}']!.performed;
      stdout.writeln('  ${k.padRight(11)} ${sm.name.padRight(13)} '
          'exact ${t.exactPct.toStringAsFixed(1).padLeft(5)}%   '
          'root ${t.rootPct.toStringAsFixed(1).padLeft(5)}%');
    }
  }

  stdout.writeln('\n=== what was actually PLAYED (performed annotation) ===');
  final sorted = performedQualities.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted.take(12)) {
    final mark =
        _suffix(e.key) == null ? '  ← no template can express this' : '';
    stdout.writeln(
      '  ${e.key.padRight(10)} ${e.value.toString().padLeft(4)}$mark',
    );
  }
  final totalPerf = performedQualities.values.fold(0, (a, b) => a + b);
  stdout.writeln('\n  $unexpressible of $totalPerf performed labels '
      '(${(100 * unexpressible / totalPerf).toStringAsFixed(1)}%) name a quality '
      'no template set here can express.');
}
