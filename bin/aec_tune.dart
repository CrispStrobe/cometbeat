// bin/aec_tune.dart
//
// The automatic AEC tuner: given the self-tuning Valin rate, the filter already
// picks its own step at runtime — but the rate control itself introduced a few
// constants that ARE still hand-picked (rateGamma, rateBeta0, rateMuMax; the
// paper leaves gamma/beta0 unspecified). This tool tunes exactly those, the
// "surviving constants", automatically: it builds a ground-truth corpus, then
// runs separable CMA-ES to maximize a domain objective (note-survival + SI-SDR)
// over them, and prints the config it found next to the untuned baseline.
//
// This is the whole loop the earlier tuning FLAGS made possible, closed:
//   corpus (known ground truth) → optimizer → scored AecTuning.
//
//   dart run bin/aec_tune.dart                 # synthetic, default budget
//   dart run bin/aec_tune.dart --evals 400 --rooms 4 --seed 7
//   dart run bin/aec_tune.dart --rir-dir <dir> --cello-dir <dir>   # real acoustics
//   dart run bin/aec_tune.dart --nonlin tanh --drive 3            # nonlinear echo
//
// --nonlin <clip|tanh> adds a loudspeaker nonlinearity to the echo (the AEC
// Challenge's Hammerstein model): it first reports what the distortion COSTS and
// whether a residual-suppression stage recovers it, then tunes on the nonlinear
// corpus. --drive sets the distortion amount.
//
// Honesty: a synthetic/parametric corpus (or a MODELLED nonlinearity) is only as
// real as the model; measured RIRs + real cello (--rir-dir/--cello-dir) and, for
// true speaker/mic nonlinearity, a real device capture are the upgrades — the
// tuner code doesn't change. CLI-only (out of the app).

import 'dart:io';
import 'dart:math';

import 'package:comet_beat/core/audio/aec_offline.dart';

import 'aec_tune/cmaes.dart';
import 'aec_tune/corpus.dart';
import 'aec_tune/objective.dart';

// Each tuned parameter, with the bounds the optimizer's unbounded search maps
// into via a logistic squash — so CMA-ES can't propose e.g. a negative gamma.
class _Param {
  const _Param(this.name, this.lo, this.hi, this.initial);
  final String name;
  final double lo;
  final double hi;
  final double initial;
}

const _params = <_Param>[
  _Param('rateGamma', 0.01, 0.5, 0.1),
  _Param('rateBeta0', 0.005, 0.3, 0.05),
  _Param('rateMuMax', 0.1, 1.0, 0.5),
];

double _logistic(double z) => 1 / (1 + exp(-z));
double _logit(double p) => log(p / (1 - p));

/// Map an unbounded vector to a bounded [AecTuning] (adaptiveRate on).
AecTuning _toTuning(List<double> z) {
  double bounded(int i) {
    final p = _params[i];
    return p.lo + (p.hi - p.lo) * _logistic(z[i]);
  }

  return AecTuning(
    adaptiveRate: true,
    rateGamma: bounded(0),
    rateBeta0: bounded(1),
    rateMuMax: bounded(2),
  );
}

/// The unbounded start point that maps to each param's initial value.
List<double> _initialZ() => List<double>.generate(_params.length, (i) {
      final p = _params[i];
      final frac = (p.initial - p.lo) / (p.hi - p.lo);
      return _logit(frac.clamp(1e-6, 1 - 1e-6));
    });

void main(List<String> argv) {
  final args = _parse(argv);
  final strs = _parseStr(argv);
  final evals = args['evals'] ?? 300;
  final rooms = args['rooms'] ?? 4;
  final seed = args['seed'] ?? 20260717;
  final rirDir = strs['rir-dir'];
  final celloDir = strs['cello-dir'];
  final loudspeaker = _loudspeaker(strs['nonlin']);
  final drive = double.tryParse(strs['drive'] ?? '') ?? 2.0;

  List<AecScenario> build(Loudspeaker ls) {
    if (rirDir != null && celloDir != null) {
      return buildCorpusFromAssets(
        rirDir: rirDir,
        celloDir: celloDir,
        seed: seed,
        loudspeaker: ls,
        drive: drive,
      );
    }
    return buildCorpus(rooms: rooms, seed: seed, loudspeaker: ls, drive: drive);
  }

  final where = (rirDir != null && celloDir != null)
      ? 'REAL-acoustics (rir=$rirDir, cello=$celloDir)'
      : 'synthetic (rooms=$rooms)';

  // When a loudspeaker nonlinearity is requested, first quantify what it COSTS
  // and whether a residual-suppression stage recovers it — before tuning.
  if (loudspeaker != Loudspeaker.linear) {
    stderr.writeln('Nonlinearity comparison on the $where corpus '
        '($loudspeaker, drive=$drive):');
    final linCorpus = build(Loudspeaker.linear);
    final nlCorpus = build(loudspeaker);
    const adaptive = AecTuning(adaptiveRate: true);
    final lin = scoreTuning(adaptive, linCorpus);
    final nl = scoreTuning(adaptive, nlCorpus);
    final nlRes = scoreTuning(adaptive, nlCorpus, residualSuppress: true);
    stderr.writeln('  linear echo           : $lin');
    stderr.writeln('  nonlinear echo        : $nl   '
        '(distortion costs ${_d(nl.meanSiSdr - lin.meanSiSdr)} dB SI-SDR)');
    stderr.writeln('  nonlinear echo + RES  : $nlRes   '
        '(residual recovers ${_d(nlRes.meanSiSdr - nl.meanSiSdr)} dB)');
    stderr.writeln('Now tuning the rate on the NONLINEAR corpus…');
  }

  stderr.writeln('Building $where corpus (seed=$seed)…');
  final corpus = build(loudspeaker);
  stderr.writeln('${corpus.length} scenarios.');

  // Baselines: the untuned adaptive rate, and the old fixed-mu default, so the
  // report says what the tuning bought over BOTH.
  final baselineAdaptive =
      scoreTuning(const AecTuning(adaptiveRate: true), corpus);
  final baselineFixed = scoreTuning(const AecTuning(), corpus);
  stderr.writeln('baseline fixed-mu   : $baselineFixed');
  stderr.writeln('baseline adaptive   : $baselineAdaptive');

  stderr.writeln('Tuning rateGamma/rateBeta0/rateMuMax with CMA-ES '
      '($evals evals)…');
  var calls = 0;
  final result = cmaesMinimize(
    (z) {
      calls += 1;
      // CMA-ES minimizes; we maximize the score.
      return -scoreTuning(_toTuning(z), corpus).score;
    },
    initialMean: _initialZ(),
    sigma0: 1.0,
    maxEvals: evals,
    rng: Random(seed),
  );

  final tuned = _toTuning(result.best);
  final tunedScore = scoreTuning(tuned, corpus);
  stderr.writeln('…$calls evaluations, ${result.generations} generations.');
  stderr.writeln();
  stderr.writeln('tuned               : $tunedScore');
  stderr.writeln('  vs adaptive base  : '
      '${_delta(tunedScore, baselineAdaptive)}');
  stderr.writeln('  vs fixed-mu base  : ${_delta(tunedScore, baselineFixed)}');
  stderr.writeln();
  stderr.writeln('tuned parameters:');
  stderr.writeln('  rateGamma  = ${tuned.rateGamma.toStringAsFixed(4)}');
  stderr.writeln('  rateBeta0  = ${tuned.rateBeta0.toStringAsFixed(4)}');
  stderr.writeln('  rateMuMax  = ${tuned.rateMuMax.toStringAsFixed(4)}');
  // stdout carries the machine-usable one-liner (the AecTuning.describe form).
  stdout.writeln('adaptiveRate '
      'rateGamma=${tuned.rateGamma.toStringAsFixed(4)} '
      'rateBeta0=${tuned.rateBeta0.toStringAsFixed(4)} '
      'rateMuMax=${tuned.rateMuMax.toStringAsFixed(4)}');
}

/// Map the --nonlin flag to a loudspeaker model.
Loudspeaker _loudspeaker(String? name) {
  switch (name) {
    case 'clip':
    case 'hardclip':
      return Loudspeaker.hardClip;
    case 'tanh':
    case 'sigmoid':
      return Loudspeaker.sigmoid;
    default:
      return Loudspeaker.linear;
  }
}

/// Signed dB string.
String _d(double x) => '${x >= 0 ? '+' : ''}${x.toStringAsFixed(1)}';

String _delta(ObjectiveResult tuned, ObjectiveResult base) {
  final ds = tuned.score - base.score;
  final dSdr = tuned.meanSiSdr - base.meanSiSdr;
  final dNote = (tuned.noteSurvival - base.noteSurvival) * 100;
  return '${ds >= 0 ? '+' : ''}${ds.toStringAsFixed(2)} score '
      '(${dSdr >= 0 ? '+' : ''}${dSdr.toStringAsFixed(1)} dB SI-SDR, '
      '${dNote >= 0 ? '+' : ''}${dNote.toStringAsFixed(0)}% notes)';
}

Map<String, int> _parse(List<String> argv) {
  final out = <String, int>{};
  for (var i = 0; i < argv.length - 1; i++) {
    final a = argv[i];
    if (a.startsWith('--')) {
      final v = int.tryParse(argv[i + 1]);
      if (v != null) out[a.substring(2)] = v;
    }
  }
  return out;
}

Map<String, String> _parseStr(List<String> argv) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length - 1; i++) {
    final a = argv[i];
    if (a.startsWith('--') && !argv[i + 1].startsWith('--')) {
      out[a.substring(2)] = argv[i + 1];
    }
  }
  return out;
}
