// DAW project persistence: bake the timeline to a portable JSON snapshot and
// rebuild it. Every clip comes back as a baked SampleSource, with its
// placement/gain/fades/trim intact.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_project.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

SampleSource _tone(double level, int n) =>
    SampleSource(Float64List(n)..fillRange(0, n, level));

void main() {
  test('round-trips tracks, clips and every placement field', () {
    final timeline = DawTimeline(
      effects: [
        defaultDawClipEffect(DawClipEffectType.compressor).copyWith(
          params: {'thresholdDb': -18, 'ratio': 3},
        ),
      ],
      buses: [
        DawBus(
          name: 'Drum bus',
          effects: [
            defaultDawClipEffect(DawClipEffectType.highpass).copyWith(
              params: {'cutoffHz': 180},
            ),
          ],
        ),
      ],
      tracks: [
        DawTrack(
          name: 'Drums',
          gain: 0.8,
          effect: TrackEffect.echo,
          busIndex: 0,
          busSends: {0: 0.35},
          gainAutomation: const [
            DawAutomationPoint(ms: 100, value: 1),
            DawAutomationPoint(ms: 400, value: 0.4),
          ],
          clips: [
            Clip(
              source: _tone(0.5, 64),
              startMs: 250,
              gain: 0.7,
              fadeInMs: 40,
              fadeOutMs: 60,
              fadeInCurve: DawFadeCurve.exponential,
              fadeOutCurve: DawFadeCurve.sCurve,
              trimStartMs: 10,
              trimEndMs: 30,
              effects: [
                defaultDawClipEffect(DawClipEffectType.delay).copyWith(
                  enabled: false,
                  params: {'delayMs': 120, 'feedback': 0.2, 'mix': 0.4},
                  automation: const {
                    'mix': [
                      DawAutomationPoint(
                        ms: 0,
                        value: 0.1,
                        curve: DawFadeCurve.sCurve,
                      ),
                      DawAutomationPoint(ms: 250, value: 0.8),
                    ],
                  },
                ),
              ],
            ),
          ],
        ),
        DawTrack(
          name: 'Bass',
          muted: true,
          soloed: true,
          clips: [Clip(source: _tone(0.3, 8))],
        ),
      ],
    );

    final back = projectFromJson(projectToJson(timeline));

    expect(back.tracks.length, 2);
    expect(back.effects.single.type, DawClipEffectType.compressor);
    expect(back.effects.single.params['thresholdDb'], -18);
    expect(back.buses.single.name, 'Drum bus');
    expect(back.buses.single.effects.single.type, DawClipEffectType.highpass);
    expect(back.buses.single.effects.single.params['cutoffHz'], 180);
    expect(back.tracks[0].name, 'Drums');
    expect(back.tracks[0].gain, closeTo(0.8, 1e-9));
    expect(back.tracks[0].busIndex, 0);
    expect(back.tracks[0].busSends[0], closeTo(0.35, 1e-9));
    expect(back.tracks[0].effect, TrackEffect.echo);
    expect(back.tracks[0].effects.single.type, DawClipEffectType.delay);
    expect(back.tracks[0].gainAutomation, hasLength(2));
    expect(back.tracks[0].gainAutomation.first.ms, 100);
    expect(back.tracks[0].gainAutomation.last.value, closeTo(0.4, 1e-9));
    expect(back.tracks[1].muted, isTrue);
    expect(back.tracks[1].soloed, isTrue);

    final clip = back.tracks[0].clips.single;
    expect(clip.startMs, 250);
    expect(clip.gain, closeTo(0.7, 1e-9));
    expect(clip.fadeInMs, 40);
    expect(clip.fadeOutMs, 60);
    expect(clip.fadeInCurve, DawFadeCurve.exponential);
    expect(clip.fadeOutCurve, DawFadeCurve.sCurve);
    expect(clip.trimStartMs, 10);
    expect(clip.trimEndMs, 30);
    expect(clip.effects.single.type, DawClipEffectType.delay);
    expect(clip.effects.single.enabled, isFalse);
    expect(clip.effects.single.params['delayMs'], 120);
    expect(clip.effects.single.automation['mix'], hasLength(2));
    expect(
      clip.effects.single.automation['mix']!.last.value,
      closeTo(0.8, 1e-9),
    );
    expect(
      clip.effects.single.automation['mix']!.first.curve,
      DawFadeCurve.sCurve,
    );
    expect(clip.source, isA<SampleSource>()); // baked to audio
    expect((clip.source as SampleSource).pcm.length, 64);
    // PCM survives the 16-bit round-trip within a quantization step.
    expect((clip.source as SampleSource).pcm.first, closeTo(0.5, 1 / 32000));
  });

  test('a saved project renders identically to the original (within 16-bit)',
      () {
    final timeline = DawTimeline(
      tracks: [
        DawTrack(
          effects: [
            defaultDawClipEffect(DawClipEffectType.delay).copyWith(
              params: {'delayMs': 120, 'feedback': 0.2, 'mix': 0.4},
            ),
          ],
          gainAutomation: const [
            DawAutomationPoint(ms: 20, value: 1),
            DawAutomationPoint(ms: 80, value: 0.5),
          ],
          clips: [Clip(source: _tone(0.4, 100), startMs: 20)],
        ),
        DawTrack(clips: [Clip(source: _tone(0.2, 100), startMs: 50)]),
      ],
    );
    final before = renderTimeline(timeline, sampleRate: 1000, limit: false);
    final after = renderTimeline(
      projectFromJson(projectToJson(timeline, sampleRate: 1000)),
      sampleRate: 1000,
      limit: false,
    );
    expect(after.length, before.length);
    for (var i = 0; i < before.length; i++) {
      expect(after[i], closeTo(before[i], 1 / 32000));
    }
  });

  test('uses the injected render (so the service can bake through its cache)',
      () {
    var calls = 0;
    final timeline = DawTimeline(
      tracks: [
        DawTrack(clips: [Clip(source: _tone(0.5, 4))]),
      ],
    );
    projectToJson(
      timeline,
      render: (s) {
        calls++;
        return s.render(44100);
      },
    );
    expect(calls, 1);
  });

  group('malformed input throws FormatException, never a raw error', () {
    test('not JSON', () {
      expect(() => projectFromJson('nope{'), throwsFormatException);
    });
    test('wrong version', () {
      expect(
        () => projectFromJson('{"v":99,"tracks":[]}'),
        throwsFormatException,
      );
    });
    test('no tracks list', () {
      expect(
        () => projectFromJson('{"v":1,"tracks":"x"}'),
        throwsFormatException,
      );
    });
    test('a clip with unreadable PCM is skipped, the load still succeeds', () {
      final t = projectFromJson(
        '{"v":1,"tracks":[{"name":"A","clips":['
        '{"startMs":0,"pcm":"!!not-base64!!"}]}]}',
      );
      expect(t.tracks.single.clips, isEmpty); // bad clip dropped
    });
  });
}
