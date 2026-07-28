// The envelope fixtures are the least independent in the audit, so they get a
// guard the rest of the suite does not need.
//
// PLAN.md §6. Every fixture under `test/fixtures/` is written by our own
// writer, and for an EFFECT that is tolerable: an effect is a byte, so if we
// write the wrong one the reference players do something visibly different and
// the sweep catches it. An ENVELOPE is a SHAPE. If our writer encodes the shape
// wrongly then both references read the same wrong shape, agree with each other
// perfectly, our replayer reads the same file back — and the sweep goes green
// while every real module still plays wrong. The error cancels.
//
// Two things close that hole, and both are here:
//
//   * **Arithmetic** (opt-in, needs openmpt123). The shapes are ramps whose
//     length in TICKS is known before anything is rendered — 24 ticks is four
//     rows at speed 6 — so the reference render can be checked against a number
//     rather than against us. Our writer cannot fake a number.
//   * **Cross-format agreement** (CI-able, no external players). XM and IT
//     encode a pan envelope differently — XM 0…64 with 32 centre, IT signed
//     −32…+32 with 0 centre — so the SAME authored `DocEnvelope` must survive
//     into both and come back meaning the same thing. It did not: the IT points
//     were copied through verbatim, so IT's centre arrived as hard LEFT. That
//     round-tripped perfectly (writer and reader agreed), which is why only a
//     cross-format comparison could see it.
//
// The second test needs no fixtures and no renderers, so it is the one that
// will still be running in a year.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/it_reader.dart';
import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/xm_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reference_players.dart';

const _abRaw = String.fromEnvironment('OPENMPT_AB');
final _ab = _abRaw.isNotEmpty && _abRaw != '0';

/// One tick at the fixtures' speed 6 / 125 BPM.
const _tickSeconds = 0.020;

Float64List _wave() {
  const n = 256;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = math.sin(2 * math.pi * i / n);
  }
  return out;
}

/// A doc carrying [pan] as its pan envelope, in the NEUTRAL convention
/// (0…64, 32 = centre) on both the sample (XM reads this) and the instrument
/// (IT reads this).
ModuleDoc _withPanEnvelope(DocEnvelope pan) {
  final wave = _wave();
  return ModuleDoc(
    sourceFormat: ModuleFormat.mod,
    title: 'pan env',
    channelCount: 4,
    order: const [0],
    samples: [
      DocSample(
        name: 's',
        pcm: wave,
        loopLength: wave.length,
        panEnvelope: pan,
      ),
    ],
    itInstruments: [
      DocInstrument(
        name: 's',
        panEnvelope: pan,
        keymap: List<int>.filled(120, 1),
      ),
    ],
    patterns: [
      DocPattern(
        [
          for (var r = 0; r < 8; r++)
            [
              if (r == 0)
                const DocCell(note: 60, instrument: 1, volume: 64)
              else
                DocCell.empty,
              DocCell.empty,
              DocCell.empty,
              DocCell.empty,
            ],
        ],
        4,
      ),
    ],
  );
}

/// The per-tick left/right balance of [wav]: −1 hard left … +1 hard right.
List<double> _balance(Uint8List wav) {
  final stereo = wavToStereoPcm(wav);
  final left = stereo.left, right = stereo.right;
  final tick = (kReferenceSampleRate * _tickSeconds).round();
  final out = <double>[];
  for (var t = 0; (t + 1) * tick <= left.length; t++) {
    var l = 0.0, r = 0.0;
    for (var i = t * tick; i < (t + 1) * tick; i++) {
      l += left[i].abs();
      r += right[i].abs();
    }
    out.add(l + r > 0 ? (r - l) / (l + r) : 0.0);
  }
  return out;
}

/// The per-tick level of [wav], normalised to its own peak.
List<double> _levels(Uint8List wav) {
  final pcm = wavToMonoPcm(wav);
  final tick = (kReferenceSampleRate * _tickSeconds).round();
  var peak = 0.0;
  for (final v in pcm) {
    peak = math.max(peak, v.abs());
  }
  if (peak == 0) return const [];
  final out = <double>[];
  for (var t = 0; (t + 1) * tick <= pcm.length; t++) {
    var s = 0.0;
    for (var i = t * tick; i < (t + 1) * tick; i++) {
      s += pcm[i].abs();
    }
    out.add(s / tick / peak);
  }
  return out;
}

void main() {
  group('cross-format: the same authored envelope must MEAN the same thing',
      () {
    // XM stores a pan envelope 0..64 centred at 32; IT stores it signed
    // -32..+32 centred at 0. The neutral model uses XM's convention, so the IT
    // reader has to shift. It did not, and because the IT WRITER made the
    // matching assumption the round trip was perfect — `docFromIt(convertToIt
    // (x)) == x` held while the file meant something else than the XM written
    // from the same source. Only comparing the two formats can see that.
    const cases = <String, DocEnvelope>{
      'left to right': DocEnvelope(
        points: [(0, 0), (24, 64)],
        enabled: true,
      ),
      'centred throughout': DocEnvelope(
        points: [(0, 32), (24, 32)],
        enabled: true,
      ),
      'right to left': DocEnvelope(
        points: [(0, 64), (24, 0)],
        enabled: true,
      ),
    };

    cases.forEach((name, authored) {
      test('$name survives into BOTH formats identically', () {
        final doc = _withPanEnvelope(authored);

        final viaXm = docFromXm(parseXm(convertToXm(doc)))
            .samples
            .firstWhere((s) => s.pcm.isNotEmpty)
            .panEnvelope;
        final viaIt = docFromIt(parseIt(convertToIt(doc)))
            .itInstruments
            .first
            .panEnvelope;

        expect(
          viaXm.points,
          authored.points,
          reason: 'XM is the convention the neutral model uses',
        );
        expect(
          viaIt.points,
          authored.points,
          reason: 'IT stores this signed around 0; reading it back verbatim '
              'made the neutral value mean 32 less than it says, so an IT '
              'centre arrived as hard LEFT',
        );
      });
    });

    test('and IT really does store it SIGNED on disk', () {
      // The other half of the statement above: the two tests together say the
      // encoding differs AND the meaning does not. Without this one, making
      // both readers agree by writing IT unsigned would also pass.
      final doc = _withPanEnvelope(
        const DocEnvelope(points: [(0, 32), (24, 64)], enabled: true),
      );
      final it = parseIt(convertToIt(doc));
      final points = it.instruments.first.panEnvelope.points;
      expect(
        points.first.$2,
        0,
        reason: 'neutral 32 is CENTRE, and IT spells centre as 0',
      );
      expect(
        points.last.$2,
        32,
        reason: 'neutral 64 is hard right, and IT spells that +32',
      );
    });
  });

  group('the reference render matches the ARITHMETIC, not just us', () {
    // Guards fixture independence: if our writer encoded the shape wrongly,
    // both references would still agree with each other and with us.
    Future<void> expectRampReachesFullAt(
      String fixture,
      int attackTicks,
    ) async {
      final path = 'test/fixtures/env/$fixture';
      if (!File(path).existsSync()) {
        markTestSkipped('missing $path — run tool/make_envelope_fixtures.dart');
        return;
      }
      final levels = _levels(await renderWithOpenMpt(path));
      expect(levels, isNotEmpty, reason: 'silent render');
      final peak = levels.reduce(math.max);
      final full = levels.indexWhere((v) => v >= 0.95 * peak);
      expect(
        full,
        closeTo(attackTicks, 2),
        reason: '$fixture was authored with a $attackTicks-tick attack; the '
            'reference reaches full level at tick $full',
      );
      expect(
        levels.first,
        lessThan(0.2 * peak),
        reason: 'a ramp must START quiet, or it is not the shape we wrote',
      );
    }

    test(
      'a 24-tick attack takes 24 ticks',
      () async {
        await expectRampReachesFullAt('env_vol_ramp.xm', 24);
        await expectRampReachesFullAt('env_vol_ramp.it', 24);
      },
      skip: !_ab,
    );

    test(
      'a 6-tick attack takes 6 — the SAME file with one number changed',
      () async {
        // Two lengths: a single ramp cannot distinguish "the envelope is
        // right" from "it is applied twice" or "the rate is fixed".
        await expectRampReachesFullAt('env_vol_fast.xm', 6);
        await expectRampReachesFullAt('env_vol_fast.it', 6);
      },
      skip: !_ab,
    );

    test(
      'the pan sweep really sweeps, and both formats sweep the SAME way',
      () async {
        for (final fixture in ['env_pan_sweep.xm', 'env_pan_sweep.it']) {
          final path = 'test/fixtures/env/$fixture';
          if (!File(path).existsSync()) {
            markTestSkipped('missing $path');
            return;
          }
          final bal = _balance(await renderWithOpenMpt(path));
          expect(
            bal.first,
            lessThan(-0.5),
            reason: '$fixture must START hard left',
          );
          expect(
            bal[30],
            greaterThan(0.5),
            reason: '$fixture must END hard right',
          );
        }
      },
      skip: !_ab,
    );
  });
}
