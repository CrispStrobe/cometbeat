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
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/audio_compare.dart';
import 'support/reference_players.dart';

/// Opt-in, like the other A/B harness: this shells out to up to three external
/// renderers per fixture and cannot survive a parallel whole-suite run.
const _abRaw = String.fromEnvironment('OPENMPT_AB');
final _ab = _abRaw.isNotEmpty && _abRaw != '0';

/// A reference sitting at least this far from centre is making a PAN claim,
/// even if it never moves — see the note at the gate.
const double _kPanOffCentreFloor = 0.2;

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

/// How far the reference PAN trajectory must travel before we gate on it.
///
/// Same guard as the envelope's dynamic-range floor and for the same reason: a
/// render that never moves across the stereo field has a flat trajectory, and
/// Pearson between two flat signals is noise. 0.2 of the full −1..+1 span is
/// well below what any real pan effect does (panbrello alone travels ~1.0) and
/// well above the wobble a centred render shows.
const double _kPanTravelFloor = 0.2;

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
  // ⚠️ **The pan column REPORTS but does not GATE.** `offenders` below takes
  // spectral and envelope gaps only, so a pan row marked `<-- OUTSIDE` is
  // information, not a failure. That is deliberate for now and worth knowing
  // before reading the output: 26 MOD rows currently show a pan gap of ~0.16,
  // and it is one finding, not 26 — see below.
  //
  // ⬜ **MOD stereo SEPARATION is an open preference, not a bug.** ProTracker
  // pans channels hard LRRL, and every player softens that by taste because
  // hard panning is fatiguing on headphones. Measured on `fx/vibrato.mod`:
  // openmpt renders channel 0 at −0.500 and we render it at −0.661, and the two
  // references AGREE with each other (spread ±0.00). So we are outside a
  // consensus, on a number that is a listening choice rather than a
  // correctness one — the same shape as `authenticSlides`. Deciding it (match
  // the references, keep ours, or expose it) is an owner's call; until then the
  // pan column will show ~0.16 on every MOD row.
  //
  // (The four volume-column fixtures lived here. A cell's volume became
  // `noteVolume`, a 0..1 per-note multiplier, while `Axy` slid the 0..64
  // CHANNEL volume still sitting at its default 64 — so a slide UP from a quiet
  // note began already clamped and did nothing, which is why only the UP
  // fixtures failed while the DOWN ones, starting at the default, passed.
  //
  // Fixed by routing the column to the channel volume under tracker profiles
  // and leaving our own authoring on the multiplier
  // (`ReplayProfile.volumeColumnIsChannelVolume`). All four read 1.000 spectral
  // / 0.95 envelope now. ⚠️ The field still means two things — the honest split
  // changes `TrackerCell`, which is ON-DISK — so this buys the behaviour
  // without a migration and leaves the split for a format version bump.)
  // FT2 `T00` — a tremor with BOTH nibbles zero — eventually kills the channel
  // in FastTracker II, and we keep playing.
  //
  // The tremor RULE is not the problem here, and that is worth stating because
  // the number looks like it is. Rendered tick by tick, our gate matches
  // openmpt CHARACTER FOR CHARACTER for the first 136 ticks, and the per-tick
  // levels agree to within 2%. Then both references go silent and stay silent
  // while our note plays on to the end of the pattern — 40 ticks of sound
  // against 40 ticks of nothing, which is the whole of the envelope gap.
  //
  // ⚠️ Isolated by measuring the last audible tick of every fixture, ours and
  // theirs: this is the ONLY one where they part (them 136, us 176; every other
  // fixture in both engines runs to ~180). So it is specific to FT2 with a zero
  // parameter, not a general tail or fadeout difference.
  //
  // libxmp's own note points at the mechanism — "Tremor likely just overwrites
  // the channel volume in FT2" — i.e. FT2's tremor writes the channel volume
  // rather than gating a copy of it, so a degenerate parameter can leave the
  // channel latched at zero. Confirming that needs its own fixture and a look
  // at what FT2 does to `volume` proper; it is NOT what the tremor counter fix
  // was about, and the S3M/IT rows of this same fixture pass at 0.96 envelope,
  // which is what it was added to settle. PLAN.md §6.
  'tremor_I00.xm',
  // (NNA note-fade and note-off were listed here at 0.874 / 0.952. The dispatch
  // fix made them reachable and the once-only fix below made them right; all
  // five NNA fixtures pass, so the entries are gone. What they recorded is kept
  // in PLAN.md §6 because the DIAGNOSIS is the reusable part: the fadeout
  // arithmetic measured exactly right at the call site while the render still
  // piled voices up, because a released or faded voice stayed in the voice list
  // and every later note pushed its release moment forward again. The rate was
  // never wrong; the moment kept moving.)
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

/// Our own render of [path], keeping both channels.
({Float64List left, Float64List right}) _ourStereo(String path) =>
    wavToStereoPcm(
      songFromModuleBytes(File(path).readAsBytesSync()).renderSongWav(),
    );

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
  // `env/` is XM+IT volume/pan envelopes and fadeout — the shaping layer, which
  // MOD and S3M do not have at all. ⚠️ Those fixtures are the least independent
  // in the suite: an envelope is a SHAPE, so a writer that encodes it wrongly
  // produces a file both references read the same wrong way, agree on, and that
  // our replayer reads back — the error cancels and this sweep goes green.
  // `envelope_shape_test.dart` guards that separately by checking the reference
  // render against ARITHMETIC (a ramp of a known tick length).
  // `nna/` is IT new-note actions — cut/continue/off/fade, the part of the IT
  // model that makes a channel polyphonic. IT only: XM has no NNA and MOD/S3M
  // have no instruments, so this is the one set with only two references.
  // `stereo/` is IT stereo SAMPLES — the last unmeasured thing in the sample
  // layer, and the one a mono downmix is structurally blind to. Hard-left and
  // hard-right fixtures plus a mono control, so a dropped payload reads as
  // "identical to the control" rather than as a subtle difference.
  for (final name in ['fx', 'flow', 'sample', 'fmt', 'env', 'nna', 'stereo']) {
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
        // The PAN trajectory, on the same relative baseline. Everything above
        // downmixes to mono and is therefore blind to stereo placement — which
        // is how panbrello ran six times too fast while reading 1.000 spectral
        // and 0.93 envelope.
        final refStereo = await renderAllReferencesStereo(path);
        final ourStereo = _ourStereo(path);
        var refPan = 1.0;
        for (var i = 0; i < refStereo.length; i++) {
          for (var j = i + 1; j < refStereo.length; j++) {
            final c = panCorrelation(
              refStereo[i].left,
              refStereo[i].right,
              refStereo[j].left,
              refStereo[j].right,
            );
            if (c < refPan) refPan = c;
          }
        }
        var ourPan = 1.0;
        for (final r in refStereo) {
          final c =
              panCorrelation(ourStereo.left, ourStereo.right, r.left, r.right);
          if (c < ourPan) ourPan = c;
        }
        final panTravelled = refStereo.isEmpty
            ? 0.0
            : panTravel(refStereo.first.left, refStereo.first.right);
        // ⚠️ A signal that SITS hard to one side is as much a pan claim as one
        // that MOVES, and gating on travel alone missed it. The stereo-sample
        // fixtures are hard left and hard right from their first sample, so
        // their travel is zero — they sailed through on nothing but the
        // spectral comparison, which downmixes to mono and is amplitude-
        // invariant, i.e. it cannot tell "tone left, silence right" from a mono
        // tone at all. Three fixtures built to be unmissable, and the gate
        // missed them. (The `setpan` fixtures gate because their note starts
        // CENTRED and then moves — which is why this went unnoticed.)
        final refOffCentre = refStereo.isEmpty
            ? 0.0
            : refStereo
                .map((r) => meanPanPosition(r.left, r.right).abs())
                .reduce(math.max);
        final panGated = refStereo.length >= 2 &&
            (panTravelled >= _kPanTravelFloor ||
                refOffCentre >= _kPanOffCentreFloor);

        // MEAN POSITION is what the gate actually rides on. Correlation
        // degenerates on anything near-constant — two references measuring the
        // same STATIC pan correlated at −1.00 with each other — whereas a mean
        // is in pan units and directly interpretable. It is also what made the
        // set-pan bug obvious: 0.00 against 0.485.
        final ourMean = meanPanPosition(ourStereo.left, ourStereo.right);
        var refMeanSpread = 0.0;
        var worstMeanGap = 0.0;
        for (var i = 0; i < refStereo.length; i++) {
          final mi = meanPanPosition(refStereo[i].left, refStereo[i].right);
          for (var j = i + 1; j < refStereo.length; j++) {
            final mj = meanPanPosition(refStereo[j].left, refStereo[j].right);
            refMeanSpread = math.max(refMeanSpread, (mi - mj).abs());
          }
          worstMeanGap = math.max(worstMeanGap, (ourMean - mi).abs());
        }
        // Same relative baseline as everywhere else: beat the references'
        // own disagreement, plus the standard slack.
        final panGap = worstMeanGap - refMeanSpread;

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
        final panOver = panGated && panGap > _kMaxExcessDeviation;
        final failing = over || envOver || panOver;
        final which = [
          if (over) 'spectral',
          if (envOver) 'envelope',
          if (panOver) 'pan',
        ].join('+');
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
        final panCol = panGated
            ? 'pan ±${refMeanSpread.toStringAsFixed(2)}/${worstMeanGap.toStringAsFixed(2)} '
                'r${refPan.toStringAsFixed(2)}/${ourPan.toStringAsFixed(2)}'
            : 'pan  --  ';
        print('  ${name.padRight(24)} refs ${refAgree.toStringAsFixed(3)} · '
            'ours ${ourWorst.toStringAsFixed(3)} · '
            'gap ${gap.toStringAsFixed(3)} · '
            '$envCol · $panCol · '
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
