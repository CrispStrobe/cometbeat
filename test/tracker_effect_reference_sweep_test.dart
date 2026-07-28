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

/// How much the references must agree about an ENVELOPE before we gate on it.
const double _kEnvelopeFloor = 0.5;

/// How much the reference envelope must actually MOVE before we gate on it.
///
/// A sustained note has a near-flat envelope, and Pearson correlation between
/// two near-flat signals is dominated by whatever ripple each render happens to
/// have — high between two references that share it, low against a third
/// implementation, and meaningless in both cases. Gating on that produced false
/// reds on pure PITCH fixtures, where the envelope is not the effect under test.
///
/// So the gate also requires the reference envelope to span a real dynamic
/// range: a loud-to-quiet ratio of at least this much between its 90th and 10th
/// percentile. A fade, a cut or a tremolo clears it easily; a held note does
/// not, and is reported without being gated.
const double _kEnvelopeDynamicRange = 1.6;

/// The 90th/10th percentile ratio of [pcm]'s loudness envelope — "does this
/// render actually get louder and quieter".
double _envelopeDynamicRange(Float64List pcm) {
  final env = rmsEnvelope(pcm);
  if (env.length < 8) return 1;
  final sorted = Float64List.fromList(env)..sort();
  final lo = sorted[(sorted.length * 0.1).floor()];
  final hi = sorted[(sorted.length * 0.9).floor()];
  if (lo <= 1e-9) return hi <= 1e-9 ? 1 : double.infinity;
  return hi / lo;
}

/// Fixtures pinned to a KNOWN, DIAGNOSED, unfixed defect — reported every run
/// and flagged in the output, but not failing the suite.
///
/// The flag inverts to "now passing? drop the exemption" the moment one is
/// fixed, so an exemption announces its own obsolescence rather than quietly
/// outliving the bug. It has already retired four entries that way.
const _kKnownOpenDefects = <String>{
  // The VOLUME COLUMN does not set the channel volume. A cell's volume becomes
  // `noteVolume`, a 0..1 per-note multiplier, while `Axy` slides `volume`, the
  // 0..64 CHANNEL volume still sitting at its default 64 — so a slide UP from a
  // quiet note starts already clamped and does nothing. Diagnosed by the
  // asymmetry: the DOWN fixtures start at 64, the default, and pass.
  //
  // Not fixed here because `TrackerCell.volume` is shared with the app's own
  // authoring (Loop Mixer ghost notes use it as a multiplier), so making it set
  // the channel volume changes song semantics, not just import. PLAN.md §6.
  'volslide_up_Dx0.s3m',
  'volslide_up_Dx0.it',
  'fine_volslide_up_DxF.s3m',
  'fine_volslide_up_DxF.it',
  // (S3M fine and extra-fine porta were listed here at 0.857 / 0.828 / 0.19-env,
  // attributed to "a constant scale factor". That guess was wrong. Fine porta
  // bypassed PitchDomain entirely and always bent LINEARLY — right for XM/IT,
  // wrong for MOD/S3M — so the split was by DOMAIN, not by scale. All three
  // read 1.000 now and the entries are gone.)
};

// `_kPeriodModelDependent` used to live here: the four portamento fixtures were
// exempt whenever the `PORTA_PERIOD` gate was off, because the shipped default
// was the musical model and they could not match a hardware reference under it.
// Both the gate and the exemption are gone — MOD/S3M now bend the period by
// default, so those fixtures are held to the same bar as everything else and
// pass at 1.000. The remaining preference is a user setting, and a setting is
// not a reason to stop measuring the default.

/// The worst pairwise ENVELOPE agreement among the references.
///
/// Spectral similarity is a cosine of magnitude spectra and is therefore
/// amplitude-INVARIANT: it cannot see a volume effect at all. That blind spot
/// hid tremolo's depth being 4x too shallow while the fixture read 0.999 (§6
/// X2), and it is why every `Dxy` volume-slide fixture reads 1.000 without that
/// being evidence of anything (§6 X9).
///
/// Envelope correlation is Pearson over the RMS envelope — scale-invariant but
/// SHAPE-sensitive, which is exactly what a fade is. A slide that runs four
/// times too fast has a different shape and shows up here even though the
/// spectrum is untouched.
double _worstPairwiseEnvelope(List<Float64List> pcms) {
  var worst = 1.0;
  for (var i = 0; i < pcms.length; i++) {
    for (var j = i + 1; j < pcms.length; j++) {
      final e = envelopeCorrelation(pcms[i], pcms[j]);
      if (e < worst) worst = e;
    }
  }
  return worst;
}

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

        // The ENVELOPE, on the same relative baseline. Gated only where the
        // references AGREE on an envelope shape (`_kEnvelopeFloor`): a steady
        // note has a flat envelope, and Pearson over two flat signals is
        // meaningless, so demanding agreement there would be noise, not a test.
        final refEnv = _worstPairwiseEnvelope(refs);
        var ourEnvWorst = 1.0;
        for (final r in refs) {
          final e = envelopeCorrelation(ours, r);
          if (e < ourEnvWorst) ourEnvWorst = e;
        }
        final envGap = refEnv - ourEnvWorst;
        final envRange = _envelopeDynamicRange(refs.first);
        final envGated =
            refEnv >= _kEnvelopeFloor && envRange >= _kEnvelopeDynamicRange;
        final gap = refAgree - ourWorst;
        final knownOpen = _kKnownOpenDefects.contains(name);
        final exempt = knownOpen;
        final over = gap > _kMaxExcessDeviation;
        final envOver = envGated && envGap > _kMaxExcessDeviation;

        // One status per row, covering BOTH metrics. Two earlier versions of
        // this got it wrong in opposite directions: "now passing" once looked
        // only at the spectral gap and told me to drop exemptions whose
        // ENVELOPE was still failing, and a known-open entry failing only on
        // the envelope printed no flag at all — silently the thing the list
        // exists to keep visible.
        final failing = over || envOver;
        final which = over && envOver
            ? 'spectral+envelope'
            : over
                ? 'spectral'
                : 'envelope';
        final String flag;
        if (knownOpen) {
          flag = failing
              ? '  <-- KNOWN OPEN ($which) — see _kKnownOpenDefects'
              : '  <-- KNOWN OPEN now passing? drop the exemption';
        } else if (!failing) {
          flag = '';
        } else if (exempt) {
          flag = '  (semitone pitch model — set PORTA_PERIOD=1)';
        } else {
          flag = '  <-- OUTSIDE ($which)';
        }
        const envFlag = '';
        // The DURATION rides along, because a flow bug shows up there first
        // and most bluntly: a break landing on the wrong row plays a different
        // NUMBER of rows, which the spectral number only sees indirectly.
        final ourSec = ours.length / kReferenceSampleRate;
        final refSec = refs.first.length / kReferenceSampleRate;
        final envCol = envGated
            ? 'env ${refEnv.toStringAsFixed(2)}/${ourEnvWorst.toStringAsFixed(2)}'
            : 'env  --  ';
        print('  ${name.padRight(24)} refs ${refAgree.toStringAsFixed(3)} · '
            'ours ${ourWorst.toStringAsFixed(3)} · '
            'gap ${gap.toStringAsFixed(3)} · '
            '$envCol · '
            '${ourSec.toStringAsFixed(2)}s vs ${refSec.toStringAsFixed(2)}s '
            '(${refs.length} engines)$flag$envFlag');
        if (over && !exempt) {
          offenders.add('$name (gap ${gap.toStringAsFixed(3)})');
        } else if (envOver && !exempt) {
          offenders.add('$name (ENVELOPE gap ${envGap.toStringAsFixed(3)})');
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
