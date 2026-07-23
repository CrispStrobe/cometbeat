// The DAW timeline core (the "vector, not bitmap" model): clips reference a
// source that renders to PCM on demand + is cached, then are summed at their
// placement. Pure, headless.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// A source that renders a constant-level buffer of [ms] and counts its renders
/// (so a test can prove the cache re-renders only when the source changes).
class _ToneSource implements ClipSource {
  _ToneSource(this.level, this.ms, {Object? key}) : cacheKey = key ?? Object();
  final double level;
  final int ms;
  int renders = 0;
  @override
  final Object cacheKey;
  @override
  Float64List render(int sampleRate) {
    renders++;
    final n = ms * sampleRate ~/ 1000;
    return Float64List(n)..fillRange(0, n, level);
  }
}

const _sr = 1000; // 1 sample per ms — keeps the arithmetic obvious

Float64List _sine(int n, {int sampleRate = 44100}) => Float64List.fromList([
      for (var i = 0; i < n; i++)
        0.4 * math.sin(2 * math.pi * 220 * i / sampleRate),
    ]);

void main() {
  test('a silent timeline renders an empty buffer', () {
    expect(renderTimeline(DawTimeline(), sampleRate: _sr), isEmpty);
    final t = DawTimeline(tracks: [DawTrack(muted: true)]);
    expect(renderTimeline(t, sampleRate: _sr), isEmpty);
  });

  test('a clip is placed at its start time and scaled by clip x track gain',
      () {
    final src = _ToneSource(0.5, 10); // 10 samples of 0.5 at _sr=1000
    final t = DawTimeline(
      tracks: [
        DawTrack(
          gain: 0.5,
          clips: [Clip(source: src, startMs: 5, gain: 0.5)],
        ),
      ],
    );
    final mix = renderTimeline(t, sampleRate: _sr, limit: false);
    expect(mix.length, 15); // start 5 + 10 samples
    expect(mix[4], 0.0); // silence before the clip
    // 0.5 (level) * 0.5 (clip) * 0.5 (track) = 0.125
    expect(mix[5], closeTo(0.125, 1e-9));
    expect(mix[14], closeTo(0.125, 1e-9));
  });

  test('track gain automation ramps within its authored span only', () {
    final src = _ToneSource(1, 100);
    final t = DawTimeline(
      tracks: [
        DawTrack(
          clips: [Clip(source: src)],
          gainAutomation: const [
            DawAutomationPoint(ms: 20, value: 0),
            DawAutomationPoint(ms: 80, value: 1),
          ],
        ),
      ],
    );

    final mix = renderTimeline(t, sampleRate: _sr, limit: false);
    expect(mix[0], closeTo(1, 1e-9));
    expect(mix[20], closeTo(0, 1e-9));
    expect(mix[50], closeTo(0.5, 1e-9));
    expect(mix[80], closeTo(1, 1e-9));
    expect(mix[90], closeTo(1, 1e-9));
  });

  test('overlapping clips sum sample-accurately', () {
    final a = _ToneSource(0.2, 10);
    final b = _ToneSource(0.3, 10);
    final t = DawTimeline(
      tracks: [
        DawTrack(clips: [Clip(source: a)]),
        DawTrack(clips: [Clip(source: b, startMs: 5)]),
      ],
    );
    final mix = renderTimeline(t, sampleRate: _sr, limit: false);
    expect(mix[0], closeTo(0.2, 1e-9)); // only a
    expect(mix[5], closeTo(0.5, 1e-9)); // a + b overlap
    expect(mix[12], closeTo(0.3, 1e-9)); // only b's tail
  });

  test('solo isolates: only soloed (unmuted) tracks are heard', () {
    final a = _ToneSource(0.5, 10);
    final b = _ToneSource(0.5, 10);
    final c = _ToneSource(0.5, 10);
    final t = DawTimeline(
      tracks: [
        DawTrack(soloed: true, clips: [Clip(source: a)]),
        DawTrack(clips: [Clip(source: b)]), // not soloed → silent
        DawTrack(
          soloed: true,
          muted: true,
          clips: [Clip(source: c)],
        ), // muted wins
      ],
    );
    final mix = renderTimeline(t, sampleRate: _sr, limit: false);
    // Only track A plays → its level, not summed with B or C.
    expect(mix[0], closeTo(0.5, 1e-9));
    // With no solo anywhere, A and B would sum to 1.0; assert solo removed B.
    final noSolo = DawTimeline(
      tracks: [
        DawTrack(clips: [Clip(source: _ToneSource(0.5, 10))]),
        DawTrack(clips: [Clip(source: _ToneSource(0.5, 10))]),
      ],
    );
    expect(
      renderTimeline(noSolo, sampleRate: _sr, limit: false)[0],
      closeTo(1.0, 1e-9),
    );
  });

  test('muted clips and muted tracks drop out', () {
    final a = _ToneSource(0.5, 10);
    final b = _ToneSource(0.5, 10);
    final t = DawTimeline(
      tracks: [
        DawTrack(clips: [Clip(source: a, muted: true)]),
        DawTrack(muted: true, clips: [Clip(source: b)]),
      ],
    );
    expect(renderTimeline(t, sampleRate: _sr), isEmpty);
  });

  test('render is on demand + cached: one render per distinct source', () {
    final src = _ToneSource(0.4, 10, key: 'shared');
    // The same source used by two clips renders ONCE.
    final t = DawTimeline(
      tracks: [
        DawTrack(
          clips: [
            Clip(source: src),
            Clip(source: src, startMs: 20),
          ],
        ),
      ],
    );
    final cache = <Object, Float64List>{};
    renderTimeline(t, sampleRate: _sr, cache: cache);
    expect(src.renders, 1);

    // Re-baking with the same cache does NOT re-render (nothing changed) —
    // the "only changed clips re-render" property.
    renderTimeline(t, sampleRate: _sr, cache: cache);
    expect(src.renders, 1);
  });

  test('the limiter tames a hot sum without touching quiet material', () {
    final quiet = _ToneSource(0.3, 4);
    final hot = _ToneSource(1.5, 4); // above the rails on its own
    DawTimeline one(ClipSource s) => DawTimeline(
          tracks: [
            DawTrack(clips: [Clip(source: s)]),
          ],
        );
    final q = renderTimeline(one(quiet), sampleRate: _sr);
    final h = renderTimeline(one(hot), sampleRate: _sr);
    expect(q[0], closeTo(0.3, 1e-9)); // quiet passes through untouched
    expect(h[0], lessThan(1.0)); // hot is pulled below the rail
    expect(h[0], greaterThan(0.6)); // ...but stays loud (soft knee)
  });

  test('clip gain scales the whole clip', () {
    final src = _ToneSource(0.4, 4);
    final t = DawTimeline(
      tracks: [
        DawTrack(clips: [Clip(source: src, gain: 0.5)]),
      ],
    );
    final out = renderTimeline(t, sampleRate: _sr, limit: false);
    expect(out[0], closeTo(0.2, 1e-9)); // 0.4 * 0.5
  });

  test('fade-in ramps up and fade-out ramps down at the clip edges', () {
    // 10 samples of 0.5; 4-sample fade-in, 4-sample fade-out (_sr=1000 → ms).
    final src = _ToneSource(0.5, 10);
    final t = DawTimeline(
      tracks: [
        DawTrack(
          clips: [Clip(source: src, fadeInMs: 4, fadeOutMs: 4)],
        ),
      ],
    );
    final out = renderTimeline(t, sampleRate: _sr, limit: false);
    expect(out[0], closeTo(0.0, 1e-9)); // fade-in starts at 0
    expect(out[2], closeTo(0.5 * 2 / 4, 1e-9)); // halfway up the ramp
    expect(out[5], closeTo(0.5, 1e-9)); // full level in the middle
    expect(out[9], closeTo(0.5 * 1 / 4, 1e-9)); // last sample, near the end
  });

  test('a clip trim plays only the [start,end) window of its source', () {
    // A 100 ms source (1 sample/ms → 100 samples); trim to [20, 60) = 40 ms.
    final src = _ToneSource(0.5, 100);
    final t = DawTimeline(
      tracks: [
        DawTrack(
          clips: [Clip(source: src, trimStartMs: 20, trimEndMs: 60)],
        ),
      ],
    );
    final mix = renderTimeline(t, sampleRate: _sr, limit: false);
    expect(mix.length, 40); // only the window is placed
    expect(mix.every((v) => v == 0.5), isTrue); // still the tone
    expect(
      src.renders,
      1,
    ); // the full source rendered once (cached), then sliced
  });

  test('trimEndMs 0 means "to the end"; trimStartMs 0 means "from the top"',
      () {
    final t = DawTimeline(
      tracks: [
        DawTrack(
          clips: [Clip(source: _ToneSource(0.5, 100), trimStartMs: 30)],
        ),
      ],
    );
    expect(renderTimeline(t, sampleRate: _sr, limit: false).length, 70);
  });

  test('an inverted / empty trim window contributes nothing', () {
    final t = DawTimeline(
      tracks: [
        DawTrack(
          clips: [
            Clip(source: _ToneSource(0.5, 100), trimStartMs: 60, trimEndMs: 40),
          ],
        ),
      ],
    );
    expect(renderTimeline(t, sampleRate: _sr, limit: false), isEmpty);
  });

  test('trimmedDurationMs reports the windowed length', () {
    final rendered = Float64List(100)..fillRange(0, 100, 0.5);
    final src = SampleSource(Float64List(0));
    final clip = Clip(source: src, trimStartMs: 10, trimEndMs: 50);
    expect(trimmedDurationMs(clip, rendered, sampleRate: _sr), 40);
    // Untrimmed → full length.
    expect(
      trimmedDurationMs(Clip(source: src), rendered, sampleRate: _sr),
      100,
    );
  });

  test('per-clip effect chains process the trimmed segment before mixing', () {
    final src = _ToneSource(0.5, 20);
    final t = DawTimeline(
      tracks: [
        DawTrack(
          clips: [
            Clip(
              source: src,
              trimStartMs: 5,
              trimEndMs: 15,
              effects: [
                defaultDawClipEffect(DawClipEffectType.ringMod).copyWith(
                  params: {'carrierHz': 50, 'mix': 1},
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final out = renderTimeline(t, sampleRate: _sr, limit: false);
    expect(out.length, 10);
    expect(out.any((v) => (v - 0.5).abs() > 0.1), isTrue);
  });

  test('disabled clip effects are bypassed', () {
    final src = _ToneSource(0.5, 10);
    final t = DawTimeline(
      tracks: [
        DawTrack(
          clips: [
            Clip(
              source: src,
              effects: [
                defaultDawClipEffect(DawClipEffectType.distortion).copyWith(
                  enabled: false,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final out = renderTimeline(t, sampleRate: _sr, limit: false);
    expect(out.every((v) => (v - 0.5).abs() < 1e-9), isTrue);
  });

  test('voice FX honour the shared wet/dry mix parameter', () {
    final dry = _sine(4410);
    final bypassed = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.voiceRobot).copyWith(
          params: {'mix': 0},
        ),
      ],
      44100,
    );
    final wet = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.voiceRobot).copyWith(
          params: {'mix': 1},
        ),
      ],
      44100,
    );

    expect(bypassed, equals(dry));
    expect(wet.length, dry.length);
    expect(wet, isNot(equals(dry)));
  });

  test('adjustable voice shape FX exposes real shaping parameters', () {
    final dry = _sine(4410);
    final bypassed = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.voiceShape).copyWith(
          params: {
            'formant': 0.4,
            'carrierHz': 90,
            'carrierMix': 0.5,
            'grit': 0.3,
            'radioMix': 0.4,
            'mix': 0,
          },
        ),
      ],
      44100,
    );
    final shaped = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.voiceShape).copyWith(
          params: {
            'formant': -0.4,
            'carrierHz': 90,
            'carrierMix': 0.5,
            'grit': 0.3,
            'radioLowHz': 400,
            'radioHighHz': 2400,
            'radioMix': 0.4,
            'mix': 1,
          },
        ),
      ],
      44100,
    );

    expect(bypassed, equals(dry));
    expect(shaped.length, dry.length);
    expect(shaped, isNot(equals(dry)));
  });

  test('pitch and time FX process audio while preserving DAW span', () {
    final dry = _sine(4410);
    final pitchBypassed = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.pitchShift).copyWith(
          params: {'semitones': 12, 'mix': 0},
        ),
      ],
      44100,
    );
    final pitched = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.pitchShift).copyWith(
          params: {'semitones': 12, 'mix': 1},
        ),
      ],
      44100,
    );
    final stretched = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.timeStretch).copyWith(
          params: {'speed': 0.6, 'mix': 1},
        ),
      ],
      44100,
    );

    expect(pitchBypassed, equals(dry));
    expect(pitched.length, dry.length);
    expect(stretched.length, dry.length);
    expect(pitched, isNot(equals(dry)));
    expect(stretched, isNot(equals(dry)));
  });

  test('pitch and time FX are safe on the master bus', () {
    final t = DawTimeline(
      effects: [
        defaultDawClipEffect(DawClipEffectType.pitchShift),
        defaultDawClipEffect(DawClipEffectType.timeStretch),
      ],
      tracks: [
        DawTrack(clips: [Clip(source: _ToneSource(0.2, 100))]),
      ],
    );

    final out = renderTimeline(t, sampleRate: _sr, limit: false);
    expect(out.length, 100);
    expect(out.every((v) => v.isFinite), isTrue);
  });

  test('tremolo and vocoder FX process audio and preserve length', () {
    final dry = _sine(4410);
    final tremoloBypassed = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.tremolo).copyWith(
          params: {'rateHz': 5, 'depth': 1, 'mix': 0},
        ),
      ],
      44100,
    );
    final tremolo = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.tremolo).copyWith(
          params: {'rateHz': 5, 'depth': 1, 'mix': 1},
        ),
      ],
      44100,
    );
    final vocoder = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.vocoder).copyWith(
          params: {'carrierHz': 120, 'depth': 1, 'mix': 1},
        ),
      ],
      44100,
    );

    expect(tremoloBypassed, equals(dry));
    expect(tremolo.length, dry.length);
    expect(vocoder.length, dry.length);
    expect(tremolo, isNot(equals(dry)));
    expect(vocoder, isNot(equals(dry)));
    expect(vocoder.every((v) => v.isFinite), isTrue);
  });

  test('gain FX scales audio and preserves length', () {
    final dry = Float64List.fromList([0.25, -0.5, 0.75]);
    final bypassed = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.gain).copyWith(
          params: {'gainDb': 12, 'mix': 0},
        ),
      ],
      44100,
    );
    final boosted = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.gain).copyWith(
          params: {'gainDb': 6, 'mix': 1},
        ),
      ],
      44100,
    );

    expect(bypassed, equals(dry));
    expect(boosted.length, dry.length);
    expect(boosted[0], closeTo(0.25 * math.pow(10, 6 / 20), 1e-9));
    expect(boosted[1], closeTo(-0.5 * math.pow(10, 6 / 20), 1e-9));
  });

  test('effect parameter automation is rendered over time', () {
    final dry = _sine(220);
    final automated = applyClipEffectChain(
      dry,
      [
        defaultDawClipEffect(DawClipEffectType.tremolo).copyWith(
          params: {'rateHz': 5, 'depth': 0, 'mix': 1},
          automation: const {
            'depth': [
              DawAutomationPoint(ms: 0, value: 0),
              DawAutomationPoint(ms: 128, value: 1),
            ],
          },
        ),
      ],
      1000,
    );

    expect(automated.length, dry.length);
    expect(automated[10], closeTo(dry[10], 1e-9));
    expect(automated[180], isNot(closeTo(dry[180], 1e-4)));
  });

  test('master FX process the full mix before limiting', () {
    final src = _ToneSource(0.4, 100);
    final dryTimeline = DawTimeline(
      tracks: [
        DawTrack(clips: [Clip(source: src)]),
      ],
    );
    final wetTimeline = DawTimeline(
      effects: [
        defaultDawClipEffect(DawClipEffectType.distortion).copyWith(
          params: {'drive': 9, 'mix': 1},
        ),
      ],
      tracks: [
        DawTrack(clips: [Clip(source: _ToneSource(0.4, 100))]),
      ],
    );

    final dry = renderTimeline(dryTimeline, sampleRate: _sr, limit: false);
    final wet = renderTimeline(wetTimeline, sampleRate: _sr, limit: false);
    expect(wet.length, dry.length);
    expect(wet[0], isNot(closeTo(dry[0], 1e-6)));
  });

  test('group bus FX process routed tracks before the master bus', () {
    final dryTimeline = DawTimeline(
      tracks: [
        DawTrack(clips: [Clip(source: _ToneSource(0.2, 100))]),
        DawTrack(clips: [Clip(source: _ToneSource(0.2, 100))]),
      ],
    );
    final wetTimeline = DawTimeline(
      buses: [
        DawBus(
          name: 'Drum bus',
          effects: [
            defaultDawClipEffect(DawClipEffectType.distortion).copyWith(
              params: {'drive': 10, 'mix': 1},
            ),
          ],
        ),
      ],
      tracks: [
        DawTrack(
          busIndex: 0,
          clips: [Clip(source: _ToneSource(0.2, 100))],
        ),
        DawTrack(
          busIndex: 0,
          clips: [Clip(source: _ToneSource(0.2, 100))],
        ),
      ],
    );

    final dry = renderTimeline(dryTimeline, sampleRate: _sr, limit: false);
    final wet = renderTimeline(wetTimeline, sampleRate: _sr, limit: false);
    expect(wet.length, dry.length);
    expect(wet[0], isNot(closeTo(dry[0], 1e-6)));
  });

  test('tracks with an invalid bus route still reach the master bus', () {
    final t = DawTimeline(
      buses: [DawBus(name: 'Valid')],
      tracks: [
        DawTrack(
          busIndex: 99,
          clips: [Clip(source: _ToneSource(0.3, 10))],
        ),
      ],
    );

    final mix = renderTimeline(t, sampleRate: _sr, limit: false);
    expect(mix[0], closeTo(0.3, 1e-9));
  });

  test('bus sends feed shared FX in parallel with the normal track route', () {
    final dryTimeline = DawTimeline(
      tracks: [
        DawTrack(clips: [Clip(source: _ToneSource(0.2, 100))]),
      ],
    );
    final sentTimeline = DawTimeline(
      buses: [
        DawBus(
          name: 'Parallel crush',
          effects: [
            defaultDawClipEffect(DawClipEffectType.distortion).copyWith(
              params: {'drive': 10, 'mix': 1},
            ),
          ],
        ),
      ],
      tracks: [
        DawTrack(
          busSends: {0: 1},
          clips: [Clip(source: _ToneSource(0.2, 100))],
        ),
      ],
    );

    final dry = renderTimeline(dryTimeline, sampleRate: _sr, limit: false);
    final sent = renderTimeline(sentTimeline, sampleRate: _sr, limit: false);
    expect(sent.length, dry.length);
    expect(sent[0], greaterThan(dry[0]));
  });
}
