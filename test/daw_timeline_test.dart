// The DAW timeline core (the "vector, not bitmap" model): clips reference a
// source that renders to PCM on demand + is cached, then are summed at their
// placement. Pure, headless.

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
}
