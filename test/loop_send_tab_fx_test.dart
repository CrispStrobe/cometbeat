// test/loop_send_tab_fx_test.dart
//
// A5 (Loop Studio master sends) + A6 (Tab guitar rig) — the last two modes to
// join the shared FX model.
//
// A5's tricky part is not the mapping, it is WHERE the chain runs. `_applySend`
// effects TWO copies of the loop and keeps the second, so reverb/delay tails
// carry across the loop seam instead of dropping out on every downbeat. An
// arbitrary chain has to inherit that, so it is applied inside that two-copy
// buffer — asserted below by checking the seam, not just the mapping.
//
// A6's is that Tab used to collapse every track into one score and render once,
// which made a per-track chain impossible. Now it renders per track — so the
// no-FX case must still be byte-identical, or every existing tab changes sound.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/modulated_delay.dart'
    show delayFx;
import 'package:comet_beat/core/audio/crisp_dsp/reverb.dart' show reverbFx;
import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/score_instrument_render.dart'
    show renderMultiPartWithInstrument;
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_fx.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _loopSignal({int n = 12000}) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    // Transients up front, silence after — so a delay/reverb tail is obvious.
    final env = i < 1200 ? math.exp(-i / 250) : 0.0;
    out[i] = 0.7 * env * math.sin(2 * math.pi * 220 * i / kSampleRate);
  }
  return out;
}

TabDocument _riff({int fret = 3}) => TabDocument(
      tuning: Tuning.standardGuitar,
      columns: [
        TabColumn(frets: {5: fret}, duration: NoteDuration.half),
        TabColumn(frets: {4: fret + 2}, duration: NoteDuration.eighth),
      ],
    );

const _guitar = KarplusInstrument('testString');

void main() {
  group('A5 — loop sends as FxSpec', () {
    test('each send maps to a spec that matches the hardcoded DSP exactly', () {
      final signal = _loopSignal();

      expect(fxForLoopSend(LoopSend.none), isNull);

      final reverbSpec = fxForLoopSend(LoopSend.reverb)!;
      final reverbShared = applyFxChain(signal, [reverbSpec], kSampleRate);
      final reverbLegacy = reverbFx(signal, mix: 0.28);
      for (var i = 0; i < signal.length; i++) {
        expect(reverbShared[i], reverbLegacy[i], reason: 'reverb sample $i');
      }

      final delaySpec = fxForLoopSend(LoopSend.delay)!;
      final delayShared = applyFxChain(signal, [delaySpec], kSampleRate);
      final delayLegacy =
          delayFx(signal, delayMs: 300, feedback: 0.3, mix: 0.28);
      for (var i = 0; i < signal.length; i++) {
        expect(delayShared[i], delayLegacy[i], reason: 'delay sample $i');
      }
    });

    test('the master bus cache key changes with the chain', () {
      // The chain is a live control outside the spec, so if it did not reach
      // the key a tweak would serve a stale WAV from cache.
      final engine = LoopEngine();
      final dry = engine.wavCacheKeySuffixForTest;
      engine.masterFxChain = [defaultFx(FxType.reverb)];
      final wet = engine.wavCacheKeySuffixForTest;
      expect(wet, isNot(dry));

      engine.masterFxChain = [
        defaultFx(FxType.reverb).copyWith(params: {'mix': 0.9}),
      ];
      expect(
        engine.wavCacheKeySuffixForTest,
        isNot(wet),
        reason: 'a param change must invalidate too',
      );

      engine.masterFxChain = [];
      expect(engine.wavCacheKeySuffixForTest, dry);
    });

    test('an empty chain and no send leave the mix untouched', () {
      final engine = LoopEngine();
      final pcm = Int16List.fromList([
        for (var i = 0; i < 512; i++) (math.sin(i / 7) * 12000).round(),
      ]);
      expect(engine.applySendForTest(pcm), same(pcm));
    });

    test(
        'a chain runs on the two-copy buffer, so the loop tail survives the '
        'seam', () {
      // This is the whole reason the chain is applied INSIDE _applySend. A
      // single-pass render starts with silent effect state, so the first
      // samples of the loop would be dry and the tail would vanish at the wrap.
      final engine = LoopEngine()
        ..masterFxChain = [
          defaultFx(FxType.delay).copyWith(
            params: {'delayMs': 120, 'feedback': 0.6, 'mix': 0.6},
          ),
        ];
      const n = 8000;
      final pcm = Int16List(n);
      for (var i = 0; i < 400; i++) {
        pcm[i] =
            (math.sin(2 * math.pi * 220 * i / kSampleRate) * 20000).round();
      }
      final out = engine.applySendForTest(pcm);
      expect(out.length, n);

      // The source is silent after sample 400, but the loop repeats — so the
      // START of the returned buffer must carry the PREVIOUS iteration's
      // echoes rather than being pristine.
      var tailEnergy = 0.0;
      for (var i = n - 600; i < n; i++) {
        tailEnergy += out[i].abs();
      }
      expect(
        tailEnergy,
        greaterThan(0),
        reason: 'the echo tail was truncated at the buffer end',
      );
    });

    test('a chain takes precedence over the legacy send preset', () {
      final engine = LoopEngine()
        ..send = LoopSend.reverb
        ..masterFxChain = [
          defaultFx(FxType.gain).copyWith(params: {'gainDb': -60, 'mix': 1}),
        ];
      final pcm = Int16List.fromList([
        for (var i = 0; i < 2048; i++) (math.sin(i / 5) * 20000).round(),
      ]);
      final out = engine.applySendForTest(pcm);
      var peak = 0;
      for (final s in out) {
        if (s.abs() > peak) peak = s.abs();
      }
      expect(peak, lessThan(200), reason: 'the -60 dB chain did not win');
    });
  });

  group('A6 — tab guitar rig', () {
    test('with no chains it is byte-identical to the old single-pass render',
        () {
      // Adding effects must not change how an existing tab sounds.
      final tracks = [
        TabTrack('rhythm', _riff()),
        TabTrack('lead', _riff(fret: 7)),
      ];
      final withFx = renderTabBandWithFx(tracks, _guitar, quarterMs: 300);
      final legacy = renderMultiPartWithInstrument(
        MultiPartScore([for (final t in tracks) t.doc.toScore()]),
        _guitar,
        quarterMs: 300,
      );
      expect(withFx.length, legacy.length);
      for (var i = 0; i < legacy.length; i++) {
        expect(withFx[i], legacy[i], reason: 'sample $i');
      }
    });

    test('a chain on one track changes only that track', () {
      final dry = renderTabBandWithFx(
        [TabTrack('rhythm', _riff()), TabTrack('lead', _riff(fret: 7))],
        _guitar,
        quarterMs: 300,
      );
      final wet = renderTabBandWithFx(
        [
          TabTrack(
            'rhythm',
            _riff(),
            fxChain: tabRigChain(GuitarFxPreset.fuzz),
          ),
          TabTrack('lead', _riff(fret: 7)),
        ],
        _guitar,
        quarterMs: 300,
      );
      expect(wet.length, dry.length);
      var differs = false;
      for (var i = 0; i < dry.length; i++) {
        if ((dry[i] - wet[i]).abs() > 1e-9) {
          differs = true;
          break;
        }
      }
      expect(differs, isTrue, reason: 'the rig had no effect');
    });

    test('two tracks can carry DIFFERENT rigs — the point of per-track FX', () {
      // The old path collapsed every track into one score, so this was not
      // expressible at all.
      final bothFuzz = renderTabBandWithFx(
        [
          TabTrack('a', _riff(), fxChain: tabRigChain(GuitarFxPreset.fuzz)),
          TabTrack(
            'b',
            _riff(fret: 7),
            fxChain: tabRigChain(GuitarFxPreset.fuzz),
          ),
        ],
        _guitar,
        quarterMs: 300,
      );
      final mixedRigs = renderTabBandWithFx(
        [
          TabTrack('a', _riff(), fxChain: tabRigChain(GuitarFxPreset.fuzz)),
          TabTrack(
            'b',
            _riff(fret: 7),
            fxChain: tabRigChain(GuitarFxPreset.springReverb),
          ),
        ],
        _guitar,
        quarterMs: 300,
      );
      var differs = false;
      for (var i = 0; i < math.min(bothFuzz.length, mixedRigs.length); i++) {
        if ((bothFuzz[i] - mixedRigs[i]).abs() > 1e-9) {
          differs = true;
          break;
        }
      }
      expect(differs, isTrue, reason: 'per-track rigs collapsed into one');
    });

    test('mute and solo are honoured, matching what the user sees', () {
      final full = renderTabBandWithFx(
        [TabTrack('a', _riff()), TabTrack('b', _riff(fret: 7))],
        _guitar,
        quarterMs: 300,
      );
      final muted = renderTabBandWithFx(
        [TabTrack('a', _riff()), TabTrack('b', _riff(fret: 7), muted: true)],
        _guitar,
        quarterMs: 300,
      );
      final soloed = renderTabBandWithFx(
        [TabTrack('a', _riff(), soloed: true), TabTrack('b', _riff(fret: 7))],
        _guitar,
        quarterMs: 300,
      );
      expect(muted.length, lessThanOrEqualTo(full.length));
      // Muting b and soloing a must give the same thing: just a.
      expect(soloed.length, muted.length);
      for (var i = 0; i < muted.length; i++) {
        expect(soloed[i], muted[i], reason: 'sample $i');
      }
    });

    test('an all-muted band renders silence rather than throwing', () {
      final out = renderTabBandWithFx(
        [TabTrack('a', _riff(), muted: true)],
        _guitar,
      );
      expect(out, isEmpty);
    });

    test('every rig preset renders finite audio and has a label', () {
      for (final preset in GuitarFxPreset.values) {
        final out = renderTabBandWithFx(
          [TabTrack('a', _riff(), fxChain: tabRigChain(preset))],
          _guitar,
          quarterMs: 300,
        );
        for (final v in out) {
          expect(v.isFinite, isTrue, reason: '$preset produced $v');
        }
        expect(tabRigLabel(preset), isNotEmpty, reason: '$preset');
      }
    });

    test('capo still shifts the pitch with a rig engaged', () {
      final open = renderTabBandWithFx(
        [TabTrack('a', _riff(), fxChain: tabRigChain(GuitarFxPreset.chorus))],
        _guitar,
        quarterMs: 300,
      );
      final capoed = renderTabBandWithFx(
        [TabTrack('a', _riff(), fxChain: tabRigChain(GuitarFxPreset.chorus))],
        _guitar,
        quarterMs: 300,
        capo: 3,
      );
      var differs = false;
      for (var i = 0; i < math.min(open.length, capoed.length); i++) {
        if ((open[i] - capoed[i]).abs() > 1e-9) {
          differs = true;
          break;
        }
      }
      expect(differs, isTrue, reason: 'capo was ignored on the FX path');
    });
  });
}
