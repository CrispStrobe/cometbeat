// test/channel_fx_parity_test.dart
//
// A2 — the Tracker's seven hardcoded channel-effect presets, expressed in the
// shared FxSpec model.
//
// The whole point of the consolidation is that it changes NOTHING audible. The
// parity group below is the proof: for every preset, rendering through the
// shared FX rack must be SAMPLE-IDENTICAL to the old `applyChannelEffect`. If a
// param drifts — the rack's own fallback differs from the tracker's hardcoded
// value for flanger rateHz, and reverb's decay/roomSize are alternative
// controls for the same room — these fail immediately.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_codec.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _stem({int n = 8000}) {
  // Something with transients and sustain, so a delay/reverb tail is visible.
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final env = math.exp(-(i % 2000) / 400);
    out[i] = 0.6 * env * math.sin(2 * math.pi * 330 * i / kSampleRate);
  }
  return out;
}

void main() {
  group('preset parity — the shared rack must sound EXACTLY like the old path',
      () {
    for (final preset in TrackerChannelEffect.values) {
      test('$preset', () {
        final stem = _stem();
        final legacy = applyChannelEffect(stem, preset);
        final spec = fxForChannelPreset(preset);

        if (preset == TrackerChannelEffect.none) {
          expect(spec, isNull, reason: 'none must have no spec — dry is empty');
          expect(legacy, same(stem));
          return;
        }

        final shared = applyFxChain(stem, [spec!], kSampleRate);
        expect(shared.length, legacy.length, reason: 'length drift');
        for (var i = 0; i < legacy.length; i++) {
          expect(
            shared[i],
            legacy[i],
            reason: 'sample $i differs for $preset — a param does not match',
          );
        }
      });
    }

    test('a multi-preset chain matches the legacy chain, in order', () {
      const presets = [
        TrackerChannelEffect.crunch,
        TrackerChannelEffect.delay,
        TrackerChannelEffect.reverb,
      ];
      final stem = _stem();
      final legacy = applyChannelEffects(stem, presets);
      final shared =
          applyFxChain(stem, fxChainForChannelPresets(presets), kSampleRate);
      expect(shared.length, legacy.length);
      for (var i = 0; i < legacy.length; i++) {
        expect(shared[i], legacy[i], reason: 'sample $i');
      }
    });

    test('none entries drop out of the converted chain, as they always did',
        () {
      const presets = [
        TrackerChannelEffect.none,
        TrackerChannelEffect.chorus,
        TrackerChannelEffect.none,
      ];
      expect(fxChainForChannelPresets(presets), hasLength(1));
      final stem = _stem();
      final legacy = applyChannelEffects(stem, presets);
      final shared =
          applyFxChain(stem, fxChainForChannelPresets(presets), kSampleRate);
      for (var i = 0; i < legacy.length; i++) {
        expect(shared[i], legacy[i]);
      }
    });
  });

  group('engine rendering', () {
    TrackerEngine engineWithNote() {
      const timing = TrackerTiming(rows: 8);
      final engine = TrackerEngine(
        channels: defaultTrackerChannels(rows: timing.rows),
        timing: timing,
      );
      engine.setCell(0, 0, const TrackerCell(midi: 60));
      engine.setCell(0, 4, const TrackerCell(midi: 64));
      return engine;
    }

    test('a preset-only song renders byte-identically to before (no fxChain)',
        () {
      final a = engineWithNote()
        ..setChannelEffects(0, [TrackerChannelEffect.reverb]);
      final b = engineWithNote()
        ..setChannelEffects(0, [TrackerChannelEffect.reverb]);
      expect(
        a.channels[0].fxChain,
        isEmpty,
        reason: 'presets must not populate the chain',
      );
      final ra = a.renderLoopFloat();
      final rb = b.renderLoopFloat();
      expect(ra.length, rb.length);
      for (var i = 0; i < ra.length; i++) {
        expect(ra[i], rb[i]);
      }
    });

    test('an equivalent FxSpec chain renders the same as its preset', () {
      final viaPreset = engineWithNote()
        ..setChannelEffects(0, [TrackerChannelEffect.crunch]);
      final viaChain = engineWithNote()
        ..setChannelFxChain(
          0,
          [fxForChannelPreset(TrackerChannelEffect.crunch)!],
        );
      final a = viaPreset.renderLoopFloat();
      final b = viaChain.renderLoopFloat();
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(b[i], a[i], reason: 'sample $i');
      }
    });

    test('the chain can say things the presets cannot', () {
      // A lowpass is not one of the seven presets at all.
      final engine = engineWithNote()
        ..setChannelFxChain(
          0,
          [
            defaultFx(FxType.lowpass)
                .copyWith(params: {'freq': 300, 'q': 0.707, 'mix': 1}),
          ],
        );
      final filtered = engine.renderLoopFloat();
      final dry =
          (engineWithNote()..setChannelFxChain(0, const [])).renderLoopFloat();
      var differs = false;
      for (var i = 0; i < math.min(dry.length, filtered.length); i++) {
        if ((dry[i] - filtered[i]).abs() > 1e-9) {
          differs = true;
          break;
        }
      }
      expect(differs, isTrue, reason: 'the lowpass had no effect');
    });

    test('the two views cannot disagree — setting one clears the other', () {
      final engine = engineWithNote()
        ..setChannelFxChain(0, [defaultFx(FxType.phaser)]);
      expect(engine.channels[0].effects, isEmpty);
      expect(engine.channels[0].fxChain, hasLength(1));

      engine.setChannelEffects(0, [TrackerChannelEffect.delay]);
      expect(engine.channels[0].fxChain, isEmpty);
      expect(engine.channels[0].effects, [TrackerChannelEffect.delay]);
    });

    test('an empty chain returns the channel to dry', () {
      final engine = engineWithNote()
        ..setChannelFxChain(0, [defaultFx(FxType.reverb)])
        ..setChannelFxChain(0, const []);
      final dry = engineWithNote().renderLoopFloat();
      final back = engine.renderLoopFloat();
      expect(back.length, dry.length);
      for (var i = 0; i < dry.length; i++) {
        expect(back[i], dry[i]);
      }
    });
  });

  group('persistence', () {
    test('an FxSpec chain survives a save/load round-trip with its params', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine
        ..setCell(0, 0, const TrackerCell(midi: 60))
        ..setChannelFxChain(0, [
          defaultFx(FxType.lowpass)
              .copyWith(params: {'freq': 512, 'q': 0.9, 'mix': 0.8}),
          defaultFx(FxType.delay).copyWith(enabled: false),
        ]);
      final back = trackerSongFromJson(trackerSongToJson(song));
      final chain = back.channels[0].fxChain;
      expect(chain, hasLength(2));
      expect(chain[0].type, FxType.lowpass);
      expect(chain[0].params['freq'], 512);
      expect(chain[0].params['q'], 0.9);
      expect(chain[1].type, FxType.delay);
      expect(chain[1].enabled, isFalse);
    });

    test('a legacy preset-only song still loads, and writes no fxChain key',
        () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine
        ..setCell(0, 0, const TrackerCell(midi: 60))
        ..setChannelEffects(0, [TrackerChannelEffect.reverb]);
      final json = trackerSongToJson(song);
      final channel0 = (json['channels'] as List).first as Map;
      expect(
        channel0.containsKey('fxChain'),
        isFalse,
        reason: 'a preset-only song must produce a byte-identical file',
      );
      final back = trackerSongFromJson(json);
      expect(back.channels[0].effects, [TrackerChannelEffect.reverb]);
      expect(back.channels[0].fxChain, isEmpty);
    });

    test('an unknown effect type in a chain is dropped, not fatal', () {
      final song = TrackerSong(timing: const TrackerTiming(rows: 8));
      song.engine
        ..setCell(0, 0, const TrackerCell(midi: 60))
        ..setChannelFxChain(0, [defaultFx(FxType.reverb)]);
      final json = trackerSongToJson(song);
      final channel0 = (json['channels'] as List).first as Map;
      // Simulate a song written by a newer build with an effect we lack.
      channel0['fxChain'] = [
        {'type': 'quantumFlux', 'enabled': true, 'params': <String, double>{}},
        ...(channel0['fxChain'] as List),
      ];
      final back = trackerSongFromJson(Map<String, dynamic>.from(json));
      expect(back.channels[0].fxChain, hasLength(1));
      expect(back.channels[0].fxChain.single.type, FxType.reverb);
    });
  });
}
