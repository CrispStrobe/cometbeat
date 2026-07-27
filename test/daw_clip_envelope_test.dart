// D3 — a gain envelope that belongs to the CLIP.
//
// The lane already had automation, so the question this has to answer is why a
// second kind exists. The answer is what these tests pin: lane automation is
// anchored to the TIMELINE and stays put when a clip moves under it (right for
// a fade across a section); a clip envelope belongs to the take and travels
// with it (right for riding one phrase). Without the second kind, shaping a
// single take means splitting it just to set a gain.
//
// The other load-bearing property is that the windowed renderer agrees with the
// full one. They are separate code paths and there is already a test pinning
// them byte-identical; an envelope indexed from the wrong origin would break
// that only for clips that do not start at zero.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_project.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A steady full-scale buffer, so any level change in the render is the
/// envelope's doing and nothing else's.
Float64List _flat(int ms) => Float64List(ms * kDawSampleRate ~/ 1000)
  ..fillRange(0, ms * kDawSampleRate ~/ 1000, 0.5);

double _rmsBetween(Float64List pcm, double fromMs, double toMs) {
  final from = (fromMs * kDawSampleRate / 1000).round().clamp(0, pcm.length);
  final to = (toMs * kDawSampleRate / 1000).round().clamp(0, pcm.length);
  if (to <= from) return 0;
  var sum = 0.0;
  for (var i = from; i < to; i++) {
    sum += pcm[i] * pcm[i];
  }
  return math.sqrt(sum / (to - from));
}

/// A ramp from full to silent across [ms].
List<DawAutomationPoint> _fadeOut(double ms) => [
      const DawAutomationPoint(ms: 0, value: 1),
      DawAutomationPoint(ms: ms, value: 0),
    ];

void main() {
  group('the envelope shapes the clip', () {
    test('a ramp really attenuates, progressively', () {
      final timeline = DawTimeline(
        tracks: [
          DawTrack(
            clips: [
              Clip(
                source: SampleSource(_flat(1000)),
                gainAutomation: _fadeOut(1000),
              ),
            ],
          ),
        ],
      );
      final mix = renderTimeline(timeline, limit: false);
      final early = _rmsBetween(mix, 50, 150);
      final middle = _rmsBetween(mix, 450, 550);
      final late = _rmsBetween(mix, 850, 950);
      expect(early, greaterThan(middle));
      expect(middle, greaterThan(late));
      expect(late, lessThan(early * 0.3));
    });

    test('no envelope is exactly the unshaped render', () {
      DawTimeline build({List<DawAutomationPoint> envelope = const []}) =>
          DawTimeline(
            tracks: [
              DawTrack(
                clips: [
                  Clip(
                    source: SampleSource(_flat(500)),
                    gainAutomation: envelope,
                  ),
                ],
              ),
            ],
          );
      final plain = renderTimeline(build(), limit: false);
      final empty = renderTimeline(build(), limit: false);
      expect(plain, orderedEquals(empty));
    });

    test('outside the authored points the clip is left alone', () {
      // A partial envelope must not silence the rest of the take.
      final timeline = DawTimeline(
        tracks: [
          DawTrack(
            clips: [
              Clip(
                source: SampleSource(_flat(1000)),
                gainAutomation: const [
                  DawAutomationPoint(ms: 0, value: 1),
                  DawAutomationPoint(ms: 200, value: 0.25),
                ],
              ),
            ],
          ),
        ],
      );
      final mix = renderTimeline(timeline, limit: false);
      // Well past the last point, the level is back to (or still at) full.
      expect(_rmsBetween(mix, 700, 900), closeTo(0.5, 0.02));
    });
  });

  test('the envelope TRAVELS with the clip — the whole point', () {
    // Lane automation would stay where it was; this must not. Same clip, two
    // start times: the shaped part has to move with it.
    Float64List renderAt(double startMs) => renderTimeline(
          DawTimeline(
            tracks: [
              DawTrack(
                clips: [
                  Clip(
                    source: SampleSource(_flat(500)),
                    startMs: startMs,
                    gainAutomation: _fadeOut(500),
                  ),
                ],
              ),
            ],
          ),
          limit: false,
        );

    final atZero = renderAt(0);
    final atOne = renderAt(1000);
    // The fade's quiet end sits at the END of the clip in both cases.
    expect(_rmsBetween(atZero, 400, 490), lessThan(0.1));
    expect(_rmsBetween(atOne, 1400, 1490), lessThan(0.1));
    // …and the moved clip's OPENING is still loud, which a timeline-anchored
    // envelope would have faded.
    expect(_rmsBetween(atOne, 1010, 1100), greaterThan(0.4));
  });

  test('the windowed render agrees with the full one', () {
    // Two separate code paths, already pinned byte-identical elsewhere. An
    // envelope indexed from the wrong origin breaks that only for clips that
    // do not start at zero, which is exactly what this uses.
    final timeline = DawTimeline(
      tracks: [
        DawTrack(
          clips: [
            Clip(
              source: SampleSource(_flat(800)),
              startMs: 300,
              gainAutomation: _fadeOut(800),
            ),
          ],
        ),
      ],
    );
    final full = renderTimelineStereo(timeline, limit: false);
    const from = 400 * kDawSampleRate ~/ 1000;
    const to = 900 * kDawSampleRate ~/ 1000;
    final windowed = renderTimelineWindowStereo(
      timeline,
      fromSample: from,
      toSample: to,
      limit: false,
    );
    for (var i = 0; i < to - from; i++) {
      expect(
        windowed.left[i],
        closeTo(full.left[from + i], 1e-12),
        reason: 'sample ${from + i}',
      );
    }
  });

  group('the service and the file format', () {
    test('setting an envelope is undoable', () {
      final daw = DawService();
      daw.addClip(SampleSource(_flat(500)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.setClipGainAutomation(track, 0, _fadeOut(500));
      expect(daw.clipGainAutomation(track, 0), hasLength(2));
      daw.undo();
      expect(daw.clipGainAutomation(track, 0), isEmpty);
    });

    test('points are kept sorted however they arrive', () {
      final daw = DawService();
      daw.addClip(SampleSource(_flat(500)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.setClipGainAutomation(track, 0, const [
        DawAutomationPoint(ms: 400, value: 0),
        DawAutomationPoint(ms: 0, value: 1),
      ]);
      expect(
        daw.clipGainAutomation(track, 0).map((p) => p.ms),
        orderedEquals([0, 400]),
      );
    });

    test('it survives save and reload', () {
      final timeline = DawTimeline(
        tracks: [
          DawTrack(
            clips: [
              Clip(
                source: SampleSource(_flat(300)),
                gainAutomation: _fadeOut(300),
              ),
            ],
          ),
        ],
      );
      final back = projectFromJson(projectToJson(timeline));
      final envelope = back.tracks.single.clips.single.gainAutomation;
      expect(envelope, hasLength(2));
      expect(envelope.first.value, 1);
      expect(envelope.last.value, 0);
      expect(envelope.last.ms, 300);
    });

    test('a clip without one writes nothing', () {
      final timeline = DawTimeline(
        tracks: [
          DawTrack(clips: [Clip(source: SampleSource(_flat(100)))]),
        ],
      );
      expect(projectToJson(timeline).contains('gainAutomation'), isFalse);
    });
  });
}
