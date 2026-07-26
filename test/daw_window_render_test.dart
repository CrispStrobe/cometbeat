// P2.1 slice 1 — the windowed timeline render.
//
// `renderTimelineStereo` allocates a full-length buffer PER LANE plus the
// master, so memory grows with tracks × arrangement length and playback has to
// bake everything before a sample is heard. `renderTimelineWindowStereo`
// renders just the asked-for span.
//
// The whole feature rests on one property: a window must be BYTE-IDENTICAL to
// the same slice of the full render. Nearly every test here is that claim under
// a different arrangement, because a windowed mixer that is subtly different is
// worse than none — it makes previews lie about the bake.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

const _rate = kDawSampleRate;

Float64List _tone(double freq, int samples, {double amp = 0.4}) =>
    Float64List.fromList([
      for (var i = 0; i < samples; i++)
        amp * math.sin(2 * math.pi * freq * i / _rate),
    ]);

/// The window must equal the full render's slice, sample for sample.
void _expectMatchesFull(
  DawTimeline timeline,
  int from,
  int to, {
  bool limit = true,
  String? reason,
}) {
  final full = renderTimelineStereo(timeline, cache: {}, limit: limit);
  final window = renderTimelineWindowStereo(
    timeline,
    fromSample: from,
    toSample: to,
    cache: {},
    limit: limit,
  );
  expect(window.left, hasLength(to - from), reason: reason);
  for (var i = from; i < to; i++) {
    final expectedL = i < full.left.length ? full.left[i] : 0.0;
    final expectedR = i < full.right.length ? full.right[i] : 0.0;
    expect(window.left[i - from], expectedL, reason: '${reason ?? ''} L@$i');
    expect(window.right[i - from], expectedR, reason: '${reason ?? ''} R@$i');
  }
}

DawTimeline _twoLanes() => DawTimeline(
      tracks: [
        DawTrack(
          name: 'A',
          clips: [
            Clip(source: SampleSource(_tone(220, _rate)), gain: 0.8),
            Clip(
              source: SampleSource(_tone(330, _rate ~/ 2)),
              startMs: 1500,
              pan: -0.5,
            ),
          ],
        ),
        DawTrack(
          name: 'B',
          gain: 0.6,
          clips: [
            Clip(
              source: SampleSource(_tone(440, _rate)),
              startMs: 500,
              fadeInMs: 100,
              fadeOutMs: 200,
            ),
          ],
        ),
      ],
    );

void main() {
  group('window == the same slice of the full render', () {
    test('a window in the middle of overlapping lanes', () {
      _expectMatchesFull(_twoLanes(), _rate ~/ 2, _rate);
    });

    test('a window that starts mid-fade', () {
      // The fade envelope is indexed from the CLIP's start, not the window's —
      // get that wrong and every windowed preview is at the wrong level.
      _expectMatchesFull(
        _twoLanes(),
        (_rate * 0.55).round(),
        (_rate * 0.7).round(),
      );
    });

    test('the very first samples', () {
      _expectMatchesFull(_twoLanes(), 0, 1000);
    });

    test('a window past the end zero-pads instead of truncating', () {
      final t = _twoLanes();
      final full = renderTimelineStereo(t, cache: {});
      _expectMatchesFull(t, full.left.length - 100, full.left.length + 500);
    });

    test('a window entirely past the end is silent', () {
      final t = _twoLanes();
      final full = renderTimelineStereo(t, cache: {});
      final w = renderTimelineWindowStereo(
        t,
        fromSample: full.left.length + 1000,
        toSample: full.left.length + 2000,
        cache: {},
      );
      expect(w.left.every((v) => v == 0), isTrue);
      expect(w.right.every((v) => v == 0), isTrue);
    });

    test('with clip effects (bounded per clip, so any window is exact)', () {
      final t = DawTimeline(
        tracks: [
          DawTrack(
            name: 'A',
            clips: [
              Clip(
                source: SampleSource(_tone(220, _rate)),
                effects: [
                  defaultDawClipEffect(DawClipEffectType.reverb),
                  defaultDawClipEffect(DawClipEffectType.lowpass),
                ],
              ),
            ],
          ),
        ],
      );
      _expectMatchesFull(t, _rate ~/ 4, _rate ~/ 2);
    });

    test('with a stereo clip and width', () {
      final t = DawTimeline(
        tracks: [
          DawTrack(
            name: 'A',
            clips: [
              Clip(
                source: StereoSampleSource(
                  _tone(220, _rate),
                  _tone(330, _rate),
                ),
                width: 1.6,
                pan: 0.3,
              ),
            ],
          ),
        ],
      );
      _expectMatchesFull(t, 1000, 20000);
    });

    test('with mute and solo', () {
      final t = _twoLanes();
      t.tracks[0].soloed = true;
      _expectMatchesFull(t, 0, 20000, reason: 'solo');
      t.tracks[0].soloed = false;
      t.tracks[1].muted = true;
      _expectMatchesFull(t, 0, 20000, reason: 'mute');
    });

    test('unlimited renders match too', () {
      _expectMatchesFull(_twoLanes(), 0, 30000, limit: false);
    });
  });

  group('lane-coupled arrangements stay correct', () {
    // These can't skip material — a reverb tail or an automation ramp reaches
    // into the window from outside it — so the windowed call renders the lane
    // in full and slices. Still exact; just no memory win.
    test('a track insert chain', () {
      final t = _twoLanes();
      t.tracks[0].effects = [defaultDawClipEffect(DawClipEffectType.delay)];
      expect(timelineWindowIsBounded(t), isFalse);
      _expectMatchesFull(t, _rate ~/ 4, _rate ~/ 2);
    });

    test('track gain automation', () {
      final t = _twoLanes();
      t.tracks[0].gainAutomation = [
        const DawAutomationPoint(ms: 0, value: 1),
        const DawAutomationPoint(ms: 2000, value: 0),
      ];
      expect(timelineWindowIsBounded(t), isFalse);
      _expectMatchesFull(t, 10000, 30000);
    });

    test('master effects', () {
      final t = _twoLanes()
        ..effects = [
          defaultDawClipEffect(DawClipEffectType.reverb),
        ];
      expect(timelineWindowIsBounded(t), isFalse);
      _expectMatchesFull(t, 5000, 25000);
    });
  });

  group('timelineWindowIsBounded', () {
    test('a plain arrangement of clips is bounded', () {
      expect(timelineWindowIsBounded(_twoLanes()), isTrue);
    });

    test('clip effects do NOT break boundedness', () {
      final t = _twoLanes();
      t.tracks[0].clips[0] = t.tracks[0].clips[0].copyWith(
        effects: [defaultDawClipEffect(DawClipEffectType.reverb)],
      );
      expect(timelineWindowIsBounded(t), isTrue);
    });

    test('a bus route breaks it', () {
      final t = _twoLanes();
      t.buses.add(DawBus(name: 'FX'));
      t.tracks[0].busIndex = 0;
      expect(timelineWindowIsBounded(t), isFalse);
    });
  });

  group('the point of it', () {
    test('a window skips clips it does not overlap', () {
      // 60 s of arrangement, a 100 ms window: the far clip must not be
      // rendered into anything. Verified by result (silence) rather than by
      // timing, so it can't go flaky on a loaded machine.
      final t = DawTimeline(
        tracks: [
          DawTrack(
            name: 'A',
            clips: [
              Clip(source: SampleSource(_tone(220, _rate))),
              Clip(
                source: SampleSource(_tone(440, _rate)),
                startMs: 59000,
              ),
            ],
          ),
        ],
      );
      final w = renderTimelineWindowStereo(
        t,
        fromSample: 30 * _rate,
        toSample: 30 * _rate + 4410,
        cache: {},
      );
      expect(w.left, hasLength(4410));
      expect(w.left.every((v) => v == 0), isTrue); // between the two clips
    });

    test('an empty window is empty, not an error', () {
      final w = renderTimelineWindowStereo(
        _twoLanes(),
        fromSample: 500,
        toSample: 500,
        cache: {},
      );
      expect(w.left, isEmpty);
      expect(w.right, isEmpty);
    });

    test('a negative start is clamped', () {
      final t = _twoLanes();
      final w = renderTimelineWindowStereo(
        t,
        fromSample: -100,
        toSample: 1000,
        cache: {},
      );
      expect(w.left, hasLength(1000));
    });
  });
}
