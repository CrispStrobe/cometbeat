// One effect per fixture, measured against every reference player present.
//
// This is the instrument PLAN.md §6 X1 was built around and X2/X3/X4 keep
// using. `effects.mod` runs four commands on four channels at once, so when it
// drifts you learn "the effects are a bit off" and nothing more. Each fixture
// under `test/fixtures/fx/` sounds ONE command on ONE channel, so a number here
// names the bug.
//
// The bar is not a constant. Two correct replayers never agree perfectly, and
// how far apart they land depends entirely on the material — so each fixture
// reports the WORST pairwise agreement among the references alongside our own
// worst deviation from any of them. A gap near zero means we sit inside the
// spread of the independent implementations, which is the most that can be
// asked of a fourth one.
//
// It PRINTS rather than asserts per effect, deliberately: the sweep is a
// measuring instrument for whoever is working the ladder, and pinning every
// effect to a threshold would turn each reference-player upgrade into a red
// suite. The single assertion at the end is the one that matters — no fixture
// may deviate MORE than the references deviate from each other by a wide
// margin, which is what a real replayer bug looks like.
//
// The fixtures are ours (`tool/make_effect_fixtures.dart`), so they are safe to
// commit — unlike the corpus modules the other harness wants.
//
// RUN:
//   flutter test --dart-define=OPENMPT_AB=1 \
//     test/tracker_effect_reference_sweep_test.dart
//
//   # and again with the period-accurate pitch model, to compare:
//   flutter test --dart-define=OPENMPT_AB=1 --dart-define=PORTA_PERIOD=1 \
//     --dart-define=PAULA_CLOCK=1 test/tracker_effect_reference_sweep_test.dart

// The whole point of this file is to report measurements to a human reading
// stdout, so print is the tool, not a lint to route around.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_replayer.dart'
    show kPortaPeriodAccurate;
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/audio_compare.dart';
import 'support/reference_players.dart';

/// Opt-in, like the other A/B harness: this shells out to up to three external
/// renderers per fixture and cannot survive a parallel whole-suite run.
const _abRaw = String.fromEnvironment('OPENMPT_AB');
final _ab = _abRaw.isNotEmpty && _abRaw != '0';

/// How far past the references' own disagreement we allow ourselves to sit.
///
/// A deliberate constant, and the honest way to read it is "the gate rides the
/// material, with a fixed allowance on top". If a fixture ever makes the
/// references disagree wildly the gate goes slack with them — the safe failure
/// direction (never a false red), not a free lunch.
const double _kMaxExcessDeviation = 0.10;

/// Fixtures whose deviation is a KNOWN, deliberate consequence of the default
/// pitch model, and which are therefore reported but not gated unless
/// `PORTA_PERIOD=1` selects the hardware model.
///
/// ProTracker slides the PERIOD by a fixed step; we slide the PITCH by a fixed
/// number of semitones, which can only match at one starting note. That is a
/// documented design choice awaiting the maintainer's call (PLAN.md §6 X1), not
/// a bug someone forgot — so the sweep must not go red just for running in the
/// shipped configuration. Under the gate these drop to ~1.000 and are held to
/// the same bar as everything else.
///
/// Note what is NOT in this list: vibrato and `6xy`. They also bend pitch, and
/// they pass in BOTH configurations, because their residual turned out to be a
/// doubled LFO rate rather than the pitch model (§6 X2).
/// Fixtures pinned to a KNOWN, DIAGNOSED, unfixed defect — reported every run
/// and flagged in the output, but not failing the suite.
///
/// **Currently empty, and that is the point.** It held `mem_porta_up` and
/// `mem_porta_down` while ProTracker's per-command effect memory was diagnosed
/// but unfixed (0.270 and 0.531 against three engines agreeing at 1.000). When
/// the fix landed the sweep printed "KNOWN OPEN now passing? drop the
/// exemption" on both, which is what this list is for: an exemption that
/// announces its own obsolescence instead of quietly outliving the bug.
const _kKnownOpenDefects = <String>{
  // PLAN.md §6 X9. Two measured, format-SPECIFIC portamento gaps that the
  // fine-slide routing did not close. They are listed rather than skipped so
  // the numbers print every run, and the flag inverts to "now passing? drop the
  // exemption" the moment someone fixes one.
  //
  // IT plain porta (0.683 / 0.544 where S3M is 1.000 for the same command):
  // most likely IT's LINEAR frequency slides — IT files carry a linear-slides
  // flag and libopenmpt honours it, while we slide the period. That would also
  // explain why IT's FINE porta is perfect: once-per-row steps are small enough
  // for the two curves to agree.
  //
  // S3M fine porta (0.857 / 0.828 where IT is 1.000): S3M-specific scaling. The
  // extra-fine variant sits at 0.987 — a quarter of the step and roughly a
  // quarter of the error — which points at a constant factor rather than a
  // wrong mechanism.
  'porta_down_Exx.it',
  'porta_up_Fxx.it',
  'fine_porta_down_EFx.s3m',
  'fine_porta_up_FFx.s3m',
};

const _kPeriodModelDependent = {
  'porta_up',
  'porta_down',
  'tone_porta',
  'tonevol_5xy',
};

double _worstPairwise(List<Float64List> pcms) {
  var worst = 1.0;
  for (var i = 0; i < pcms.length; i++) {
    for (var j = i + 1; j < pcms.length; j++) {
      final s = spectralSimilarity(pcms[i], pcms[j]);
      if (s < worst) worst = s;
    }
  }
  return worst;
}

/// Our own render of [path], as mono PCM.
Float64List _ourPcm(String path) => wavToMonoPcm(
      songFromModuleBytes(File(path).readAsBytesSync()).renderSongWav(),
    );

void main() {
  if (!_ab) {
    test(
      'effect reference sweep',
      () {},
      skip: 'opt-in: pass --dart-define=OPENMPT_AB=1',
    );
    return;
  }

  // Three fixture sets: `fx/` is one EFFECT per file (all MOD, since the effect
  // set is ProTracker's), `flow/` is one order-list SHAPE per file emitted into
  // all four formats, and `sample/` is one property of the PLAYBACK layer per
  // file (all XM — MOD samples are 8-bit forward-loop only, so a MOD fixture
  // cannot exercise ping-pong or 16-bit at all). `fmt/` is one S3M/IT LETTER
  // command per file — the effects MOD has no encoding for, so nothing in `fx/`
  // can reach them. The flow set is what catches a per-format encoding
  // difference — the same song written four ways must render to the same thing,
  // and the references agree on that even where the formats encode it
  // differently.
  const extensions = ['.mod', '.xm', '.s3m', '.it'];
  final fixtures = <String>[];
  for (final name in ['fx', 'flow', 'sample', 'fmt']) {
    final dir = Directory('test/fixtures/$name');
    if (!dir.existsSync()) continue;
    fixtures.addAll(
      dir
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => extensions.any(p.endsWith)),
    );
  }
  fixtures.sort();

  test(
    'every effect fixture stays inside the reference spread',
    () async {
      expect(
        fixtures,
        isNotEmpty,
        reason: 'no fixtures — run `dart run tool/make_effect_fixtures.dart` '
            'and `dart run tool/make_flow_fixtures.dart` first',
      );

      final offenders = <String>[];
      print('\n  effect fixture sweep '
          '(refs = worst pairwise agreement, ours = worst vs any reference)\n');

      for (final path in fixtures) {
        // Keep the extension in the label: `break_row16.it` and
        // `break_row16.mod` are the SAME song and must be told apart, since
        // the whole point of the flow set is comparing them.
        final name = path.split('/').last;
        final stem = name.substring(0, name.lastIndexOf('.'));
        final refs = await renderAllReferences(path);
        if (refs.length < 2) {
          print('  ${name.padRight(24)} skipped — '
              'only ${refs.length} reference');
          continue;
        }

        final ours = _ourPcm(path);
        final refAgree = _worstPairwise(refs);
        var ourWorst = 1.0;
        for (final r in refs) {
          final s = spectralSimilarity(ours, r);
          if (s < ourWorst) ourWorst = s;
        }
        final gap = refAgree - ourWorst;
        final knownOpen = _kKnownOpenDefects.contains(name);
        final exempt = knownOpen ||
            (!kPortaPeriodAccurate && _kPeriodModelDependent.contains(stem));
        final over = gap > _kMaxExcessDeviation;
        final flag = !over
            ? (knownOpen
                ? '  <-- KNOWN OPEN now passing? drop the exemption'
                : '')
            : knownOpen
                ? '  <-- KNOWN OPEN defect — see _kKnownOpenDefects'
                : exempt
                    ? '  (semitone pitch model — set PORTA_PERIOD=1)'
                    : '  <-- OUTSIDE';
        // The DURATION rides along, because a flow bug shows up there first
        // and most bluntly: a break landing on the wrong row plays a different
        // NUMBER of rows, which the spectral number only sees indirectly.
        final ourSec = ours.length / kReferenceSampleRate;
        final refSec = refs.first.length / kReferenceSampleRate;
        print('  ${name.padRight(24)} refs ${refAgree.toStringAsFixed(3)} · '
            'ours ${ourWorst.toStringAsFixed(3)} · '
            'gap ${gap.toStringAsFixed(3)} · '
            '${ourSec.toStringAsFixed(2)}s vs ${refSec.toStringAsFixed(2)}s '
            '(${refs.length} engines)$flag');
        if (over && !exempt) {
          offenders.add('$name (gap ${gap.toStringAsFixed(3)})');
        }
      }
      print('');

      expect(
        offenders,
        isEmpty,
        reason: 'these effects deviate from the reference players by much more '
            'than the references deviate from each other, which is what a '
            'replayer bug looks like: ${offenders.join(", ")}',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
