// A4 — the channel/stereo-field ops.
//
// These are the only effects in the rack that cannot be run per-channel: each is
// defined by the RELATIONSHIP between the two channels. So the assertions are
// about that relationship — where a signal ends up, what survives a cancel, what
// a width control does to the middle — and there is one test whose whole job is
// to catch the specific way this can silently break: a channel op that reaches
// the per-channel fallback in the chain does nothing at all, and "nothing at
// all" is easy to mistake for "subtle".

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/stereo_ops.dart';
import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_params.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:flutter_test/flutter_test.dart';

const int _sr = 44100;

Float64List _tone(double hz, {int samples = 8820, double amp = 0.5}) {
  final out = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    out[i] = amp * math.sin(2 * math.pi * hz * i / _sr);
  }
  return out;
}

Float64List _silence([int samples = 8820]) => Float64List(samples);

double _rms(Float64List x) {
  var sum = 0.0;
  for (final v in x) {
    sum += v * v;
  }
  return math.sqrt(sum / x.length);
}

/// Run one effect through the real STEREO chain dispatch.
({Float64List left, Float64List right}) _fx(
  FxType type,
  Map<String, double> params,
  Float64List left,
  Float64List right,
) =>
    applyFxChainStereo(
      left,
      right,
      [
        defaultFx(type)
            .copyWith(params: {...defaultFx(type).params, ...params}),
      ],
      _sr,
    );

void main() {
  group('swap', () {
    test('the tone moves to the other side', () {
      final out = _fx(FxType.swapChannels, const {}, _tone(440), _silence());
      expect(_rms(out.left), lessThan(1e-12));
      expect(_rms(out.right), greaterThan(0.3));
    });

    test('swapping twice is the identity', () {
      final left = _tone(440);
      final right = _tone(660, amp: 0.2);
      final once = _fx(FxType.swapChannels, const {}, left, right);
      final twice = _fx(FxType.swapChannels, const {}, once.left, once.right);
      for (var i = 0; i < left.length; i++) {
        expect(twice.left[i], closeTo(left[i], 1e-12));
        expect(twice.right[i], closeTo(right[i], 1e-12));
      }
    });
  });

  group('the channel matrix', () {
    test('the identity passes audio through untouched', () {
      final left = _tone(440);
      final right = _tone(660, amp: 0.2);
      final out = _fx(FxType.remix, const {}, left, right);
      for (var i = 0; i < left.length; i++) {
        expect(out.left[i], closeTo(left[i], 1e-12));
        expect(out.right[i], closeTo(right[i], 1e-12));
      }
    });

    test('it can fold to mono', () {
      final out = _fx(
        FxType.remix,
        {
          'leftFromLeft': 0.5,
          'leftFromRight': 0.5,
          'rightFromLeft': 0.5,
          'rightFromRight': 0.5,
        },
        _tone(440),
        _silence(),
      );
      // Both sides now carry the same half-level signal.
      for (var i = 0; i < out.left.length; i++) {
        expect(out.left[i], closeTo(out.right[i], 1e-12));
      }
      expect(_rms(out.left), closeTo(_rms(_tone(440)) / 2, 1e-9));
    });

    test('it subsumes swap', () {
      final left = _tone(440);
      final right = _tone(660, amp: 0.2);
      final viaMatrix = _fx(
        FxType.remix,
        {
          'leftFromLeft': 0,
          'leftFromRight': 1,
          'rightFromLeft': 1,
          'rightFromRight': 0,
        },
        left,
        right,
      );
      final viaSwap = _fx(FxType.swapChannels, const {}, left, right);
      for (var i = 0; i < left.length; i++) {
        expect(viaMatrix.left[i], closeTo(viaSwap.left[i], 1e-12));
        expect(viaMatrix.right[i], closeTo(viaSwap.right[i], 1e-12));
      }
    });
  });

  group('stereo width', () {
    test('width 0 collapses to mono — both sides identical', () {
      final out = _fx(FxType.stereoWidth, {'width': 0}, _tone(440), _tone(660));
      for (var i = 0; i < out.left.length; i++) {
        expect(out.left[i], closeTo(out.right[i], 1e-12));
      }
    });

    test('width 1 changes nothing', () {
      final left = _tone(440);
      final right = _tone(660, amp: 0.2);
      final out = _fx(FxType.stereoWidth, {'width': 1}, left, right);
      for (var i = 0; i < left.length; i++) {
        expect(out.left[i], closeTo(left[i], 1e-12));
        expect(out.right[i], closeTo(right[i], 1e-12));
      }
    });

    test('widening grows the difference and leaves the centre alone', () {
      // The property that makes it a WIDTH control rather than a pan: the mid
      // (what the channels share) must not move.
      final left = _tone(440);
      final right = _tone(660, amp: 0.2);
      final out = _fx(FxType.stereoWidth, {'width': 2}, left, right);
      for (var i = 0; i < left.length; i++) {
        final midIn = (left[i] + right[i]) / 2;
        final midOut = (out.left[i] + out.right[i]) / 2;
        expect(midOut, closeTo(midIn, 1e-12));
      }
      // …while the side doubled.
      final sideIn = _rms(
        Float64List.fromList([
          for (var i = 0; i < left.length; i++) (left[i] - right[i]) / 2,
        ]),
      );
      final sideOut = _rms(
        Float64List.fromList([
          for (var i = 0; i < left.length; i++)
            (out.left[i] - out.right[i]) / 2,
        ]),
      );
      expect(sideOut, closeTo(sideIn * 2, 1e-9));
    });
  });

  group('centre cancel', () {
    test('a dead-centre signal disappears', () {
      final centred = _tone(440);
      final out = _fx(FxType.centreCancel, const {}, centred, centred);
      expect(_rms(out.left), lessThan(1e-12));
      expect(_rms(out.right), lessThan(1e-12));
    });

    test('a hard-panned signal survives', () {
      // The other half of the claim: it removes the CENTRE, not everything.
      final out = _fx(FxType.centreCancel, const {}, _tone(440), _silence());
      expect(_rms(out.left), greaterThan(0.1));
    });

    test('amount 0 leaves the signal alone', () {
      final centred = _tone(440);
      final out = _fx(FxType.centreCancel, {'amount': 0}, centred, centred);
      for (var i = 0; i < centred.length; i++) {
        expect(out.left[i], closeTo(centred[i], 1e-12));
      }
    });
  });

  group('crossfeed', () {
    test('a hard-panned tone starts to appear in the other ear', () {
      final out = _fx(
        FxType.crossfeed,
        const {},
        _tone(300),
        _silence(),
      );
      // The far ear now hears something…
      expect(_rms(out.right), greaterThan(0.01));
      // …but quieter than the near one, which is the point of a HEAD being in
      // the way rather than a mono fold.
      expect(_rms(out.right), lessThan(_rms(out.left) / 2));
    });

    test('amount 0 is a pass-through', () {
      final left = _tone(300);
      final right = _silence();
      final out = _fx(FxType.crossfeed, {'amount': 0}, left, right);
      for (var i = 0; i < left.length; i++) {
        expect(out.left[i], closeTo(left[i], 1e-12));
        expect(out.right[i], closeTo(right[i], 1e-12));
      }
    });
  });

  group('auto-pan', () {
    test('the image actually moves', () {
      // A centred signal swept slowly: the two halves of one LFO cycle must
      // favour opposite sides.
      final tone = _tone(440, samples: _sr);
      final out = _fx(
        FxType.autoPan,
        {'rateHz': 1, 'depth': 1, 'waveform': 0},
        tone,
        tone,
      );
      const quarter = _sr ~/ 4;
      final firstLeft = _rms(Float64List.sublistView(out.left, 0, quarter));
      final firstRight = _rms(Float64List.sublistView(out.right, 0, quarter));
      final thirdLeft = _rms(
        Float64List.sublistView(out.left, quarter * 2, quarter * 3),
      );
      final thirdRight = _rms(
        Float64List.sublistView(out.right, quarter * 2, quarter * 3),
      );
      // First quarter leans right (the sine LFO is positive), third leans left.
      expect(firstRight, greaterThan(firstLeft));
      expect(thirdLeft, greaterThan(thirdRight));
    });

    test('depth 0 leaves the image centred', () {
      final tone = _tone(440);
      final out = _fx(FxType.autoPan, {'depth': 0}, tone, tone);
      for (var i = 0; i < tone.length; i++) {
        expect(out.left[i], closeTo(out.right[i], 1e-12));
      }
    });
  });

  group('the wiring these ops can silently lose', () {
    test('every channel op is handled by the STEREO dispatch, not per-channel',
        () {
      // The failure mode this exists for: the chain's stereo path falls back to
      // running an effect on each channel independently, and a channel op run
      // that way does NOTHING — left processed alone cannot swap with a right
      // it cannot see. That reads as "the effect is subtle", not as a bug.
      //
      // So: give every channel op a stereo input it MUST change, and require a
      // change. A missing dispatch case fails here.
      final left = _tone(440);
      final right = _tone(660, amp: 0.15);
      const channelOps = {
        FxType.swapChannels: <String, double>{},
        FxType.stereoWidth: {'width': 2.0},
        FxType.centreCancel: <String, double>{},
        FxType.crossfeed: <String, double>{},
        FxType.autoPan: {'rateHz': 2.0, 'depth': 1.0},
        FxType.remix: {'leftFromRight': 1.0},
      };
      for (final entry in channelOps.entries) {
        final out = _fx(entry.key, entry.value, left, right);
        var changed = false;
        for (var i = 0; i < left.length && !changed; i++) {
          if ((out.left[i] - left[i]).abs() > 1e-9 ||
              (out.right[i] - right[i]).abs() > 1e-9) {
            changed = true;
          }
        }
        expect(
          changed,
          isTrue,
          reason: '${entry.key.name} did nothing — it is probably missing its '
              'case in the stereo dispatch and fell through to per-channel',
        );
      }
    });

    test('on MONO they pass through, deliberately', () {
      // There is no second channel to relate to, so the honest answer is to do
      // nothing rather than invent one.
      final mono = _tone(440);
      for (final type in [
        FxType.swapChannels,
        FxType.stereoWidth,
        FxType.centreCancel,
        FxType.crossfeed,
        FxType.autoPan,
        FxType.remix,
      ]) {
        final out = applyFxChain(mono, [defaultFx(type)], _sr);
        expect(out, orderedEquals(mono), reason: type.name);
      }
    });
  });

  group('registry', () {
    test('all six are stereo-category, labelled, with described params', () {
      const added = [
        FxType.remix,
        FxType.swapChannels,
        FxType.stereoWidth,
        FxType.centreCancel,
        FxType.crossfeed,
        FxType.autoPan,
      ];
      for (final type in added) {
        expect(fxCategory(type), FxCategory.stereo, reason: type.name);
        expect(fxTypeLabel(type), isNotEmpty, reason: type.name);
        for (final key in defaultFx(type).params.keys) {
          expect(
            hasFxParamSpec(type, key),
            isTrue,
            reason: '${type.name}.$key has no descriptor',
          );
        }
      }
    });

    test('the crossfeed delay is scaled for a head, not for an echo', () {
      // The general delayMs range reaches 2 seconds; on a crossfeed that would
      // make the whole useful span a pixel wide.
      final spec = fxParamSpec(FxType.crossfeed, 'delayMs');
      expect(spec.max, lessThanOrEqualTo(2));
    });

    test('the direct DSP and the chain agree', () {
      final left = _tone(440);
      final right = _tone(660, amp: 0.2);
      final direct = stereoWidthFx(left, right, width: 2);
      final chained = _fx(FxType.stereoWidth, {'width': 2}, left, right);
      for (var i = 0; i < left.length; i++) {
        expect(chained.left[i], closeTo(direct.left[i], 1e-12));
        expect(chained.right[i], closeTo(direct.right[i], 1e-12));
      }
    });
  });
}
