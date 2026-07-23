// The shared DAW arrangement service: modules add clips, the arranger bakes.
// Pure, headless.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_sources.dart' show ScoreSource;
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show AdditiveInstrument;
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        Clef,
        DurationBase,
        Measure,
        MultiPartScore,
        NoteDuration,
        NoteElement,
        Pitch,
        Score,
        Step;
import 'package:flutter_test/flutter_test.dart';

MultiPartScore _editedScore() => MultiPartScore([
      Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(
              const Pitch(Step.d),
              const NoteDuration(DurationBase.half),
            ),
          ]),
        ],
      ),
    ]);

SampleSource _tone(double level, int samples) =>
    SampleSource(Float64List(samples)..fillRange(0, samples, level));

ScoreSource _scoreClip() => ScoreSource.single(
      Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(
              const Pitch(Step.c),
              const NoteDuration(DurationBase.quarter),
            ),
          ]),
        ],
      ),
    );

const _piano = AdditiveInstrument('piano', Instrument.piano);
const _cello = AdditiveInstrument('cello', Instrument.cello);

bool _silent(Iterable<double> pcm) => pcm.every((s) => s == 0);

void main() {
  test('starts with two empty tracks', () {
    final s = DawService();
    expect(s.timeline.tracks.length, 2);
    expect(s.clipCount, 0);
    expect(s.bake(), isEmpty);
  });

  test('addClip appends to the target track and lays clips out in time', () {
    final s = DawService()
      ..addClip(_tone(0.3, 100))
      ..addClip(_tone(0.3, 100), track: 1);
    expect(s.clipCount, 2);
    // Successive sends step 2 s apart, so the bake runs well past the first clip.
    expect(s.bake().length, greaterThan(100));
    // A track index beyond the existing lanes auto-creates tracks.
    s.addClip(_tone(0.3, 10), track: 4);
    expect(s.timeline.tracks.length, 5);
    expect(s.clipCount, 3);
  });

  test('muting a track removes it from the bake', () {
    final s = DawService()..addClip(_tone(0.5, 100)); // track 0 only
    expect(_silent(s.bake()), isFalse);
    s.toggleTrackMute(0);
    expect(s.bake(), isEmpty); // the only sounding track is muted
  });

  test('clear empties every track and the cache', () {
    final s = DawService()
      ..addClip(_tone(0.5, 100))
      ..addClip(_tone(0.5, 100), track: 1);
    expect(s.clipCount, 2);
    s.clear();
    expect(s.clipCount, 0);
    expect(s.bake(), isEmpty);
  });

  test('removeClip drops just that clip', () {
    final s = DawService()
      ..addClip(_tone(0.4, 100))
      ..addClip(_tone(0.4, 100));
    expect(s.clipCount, 2);
    s.removeClip(0, 0);
    expect(s.clipCount, 1);
  });

  test('freezeClip converts a live source to a baked audio take', () {
    // A live source whose render tracks a mutable list (a stand-in "vector").
    final live = _MutableSource([0.5, 0.5, 0.5]);
    final s = DawService()..addClip(live);
    expect(s.isClipFrozen(0, 0), isFalse);

    s.freezeClip(0, 0);
    expect(s.isClipFrozen(0, 0), isTrue);
    expect(s.clipCount, 1);
    final frozen = s.bake();
    expect(_silent(frozen), isFalse);

    // After freezing, mutating the original source no longer changes the bake.
    live.values.setAll(0, [0, 0, 0]);
    expect(_silent(s.bake()), isFalse); // still the frozen audio
  });

  test('mergeAll flattens every clip into one audio take at the earliest start',
      () {
    final s = DawService()
      ..addClip(_tone(0.3, 100)) // track 0 @ 0 ms
      ..addClip(_tone(0.3, 100), track: 1); // track 1 @ 2000 ms
    expect(s.clipCount, 2);
    final beforeLen = s.bake().length;

    s.mergeAll();
    expect(s.clipCount, 1);
    expect(s.isClipFrozen(0, 0), isTrue); // the merged take is baked audio
    // Merging preserves the arrangement length (the group renders in place).
    expect(s.bake().length, beforeLen);
    // The single take sits on track 0.
    expect(s.timeline.tracks[0].clips.length, 1);
    expect(s.timeline.tracks[1].clips, isEmpty);
  });

  test('mergeTrack flattens only its own lane', () {
    final s = DawService()
      ..addClip(_tone(0.3, 100))
      ..addClip(_tone(0.3, 100), track: 1);
    s.mergeTrack(1);
    expect(s.timeline.tracks[1].clips.length, 1);
    expect(s.isClipFrozen(1, 0), isTrue);
    expect(s.timeline.tracks[0].clips.length, 1); // untouched
  });

  test('moveClip repositions in time and clamps below zero', () {
    final s = DawService()..addClip(_tone(0.3, 100));
    expect(s.clipStartMs(0, 0), 0);
    s.moveClip(0, 0, 1500);
    expect(s.clipStartMs(0, 0), 1500);
    s.moveClip(0, 0, -400); // clamped
    expect(s.clipStartMs(0, 0), 0);
  });

  test('clipDurationMs is the render length in ms', () {
    // 44100 samples @ 44100 Hz = exactly 1000 ms.
    final s = DawService()..addClip(_tone(0.3, 44100));
    expect(s.clipDurationMs(0, 0), closeTo(1000, 0.001));
  });

  test('undo/redo step through edits', () {
    final s = DawService();
    expect(s.canUndo, isFalse);

    s.addClip(_tone(0.3, 100)); // edit 1
    s.addClip(_tone(0.3, 100)); // edit 2
    expect(s.clipCount, 2);
    expect(s.canUndo, isTrue);

    s.undo();
    expect(s.clipCount, 1);
    s.undo();
    expect(s.clipCount, 0);
    expect(s.canUndo, isFalse);
    expect(s.canRedo, isTrue);

    s.redo();
    expect(s.clipCount, 1);
    s.redo();
    expect(s.clipCount, 2);
  });

  test('a fresh edit clears the redo stack', () {
    final s = DawService()..addClip(_tone(0.3, 100));
    s.undo();
    expect(s.canRedo, isTrue);
    s.addClip(_tone(0.3, 100)); // diverges → redo dropped
    expect(s.canRedo, isFalse);
  });

  test('consecutive moves of one clip coalesce into a single undo', () {
    final s = DawService()..addClip(_tone(0.3, 100));
    s
      ..moveClip(0, 0, 500)
      ..moveClip(0, 0, 900)
      ..moveClip(0, 0, 1300); // one gesture
    expect(s.clipStartMs(0, 0), 1300);
    s.undo(); // undoes the whole drag at once, back to the pre-move start
    expect(s.clipStartMs(0, 0), 0);
  });

  test('setClipGain scales the bake and clamps at zero', () {
    final s = DawService()..addClip(_tone(0.4, 100));
    expect(s.bake()[0], closeTo(0.4, 1e-9));
    s.setClipGain(0, 0, 0.5);
    expect(s.clipGain(0, 0), 0.5);
    expect(s.bake()[0], closeTo(0.2, 1e-9));
    s.setClipGain(0, 0, -1); // clamped
    expect(s.clipGain(0, 0), 0);
  });

  test('setClipFades sets each side independently and clamps', () {
    final s = DawService()..addClip(_tone(0.4, 44100));
    s.setClipFades(0, 0, fadeInMs: 100);
    expect(s.clipFadeInMs(0, 0), 100);
    expect(s.clipFadeOutMs(0, 0), 0); // untouched
    s.setClipFades(0, 0, fadeOutMs: 250);
    expect(s.clipFadeInMs(0, 0), 100); // still set
    expect(s.clipFadeOutMs(0, 0), 250);
    s.setClipFades(0, 0, fadeInCurve: DawFadeCurve.exponential);
    expect(s.clipFadeInCurve(0, 0), DawFadeCurve.exponential);
    expect(s.clipFadeOutCurve(0, 0), DawFadeCurve.linear);
    s.setClipFades(0, 0, fadeInMs: -5); // clamped
    expect(s.clipFadeInMs(0, 0), 0);
  });

  test('fade curves change the rendered ramp shape', () {
    final linear = DawTimeline(
      tracks: [
        DawTrack(
          clips: [
            Clip(
              source: SampleSource(Float64List(10)..fillRange(0, 10, 1)),
              fadeInMs: 1000,
            ),
          ],
        ),
      ],
    );
    final exponential = DawTimeline(
      tracks: [
        DawTrack(
          clips: [
            Clip(
              source: SampleSource(Float64List(10)..fillRange(0, 10, 1)),
              fadeInMs: 1000,
              fadeInCurve: DawFadeCurve.exponential,
            ),
          ],
        ),
      ],
    );

    final linearOut = renderTimeline(linear, sampleRate: 10, limit: false);
    final exponentialOut = renderTimeline(
      exponential,
      sampleRate: 10,
      limit: false,
    );

    expect(linearOut[5], closeTo(0.5, 1e-9));
    expect(exponentialOut[5], closeTo(0.25, 1e-9));
  });

  test('a gain-slider sweep coalesces into one undo', () {
    final s = DawService()..addClip(_tone(0.4, 100));
    s
      ..setClipGain(0, 0, 0.8)
      ..setClipGain(0, 0, 0.6)
      ..setClipGain(0, 0, 0.4); // one sweep
    expect(s.clipGain(0, 0), 0.4);
    s.undo(); // back to the pre-sweep gain in one step
    expect(s.clipGain(0, 0), 1.0);
  });

  test('snapping rounds a moved clip to the grid', () {
    final s = DawService()..addClip(_tone(0.3, 100));
    expect(s.snapOn, isFalse);
    s.moveClip(0, 0, 1490); // no snap → exact
    expect(s.clipStartMs(0, 0), 1490);

    s.toggleSnap(); // beat grid at 120 BPM = 500 ms
    expect(s.snapOn, isTrue);
    s.moveClip(0, 0, 1490); // nearest beat → 1500
    expect(s.clipStartMs(0, 0), 1500);
    s.moveClip(0, 0, 1100); // → 1000
    expect(s.clipStartMs(0, 0), 1000);

    s.toggleSnap();
    expect(s.snapOn, isFalse);
  });

  test('the snap grid follows the project tempo', () {
    final s = DawService()..addClip(_tone(0.3, 100));
    expect(s.bpm, 120);
    s.setBpm(60); // one beat = 1000 ms
    s.toggleSnap();
    s.moveClip(0, 0, 1400); // nearest second → 1000
    expect(s.clipStartMs(0, 0), 1000);
    // Changing tempo while snapping re-grids.
    s.setBpm(120); // beat = 500 ms
    s.moveClip(0, 0, 1400); // → 1500
    expect(s.clipStartMs(0, 0), 1500);
    // BPM is clamped to a sane range.
    s.setBpm(9999);
    expect(s.bpm, 300);
  });

  test('duplicateClip drops a copy right after the original', () {
    final s = DawService()..addClip(_tone(0.5, 44100)); // 1000 ms
    expect(s.clipCount, 1);
    s.duplicateClip(0, 0);
    expect(s.clipCount, 2);
    // The copy sits at the original's end (start 0 + 1000 ms duration).
    expect(s.clipStartMs(0, 1), closeTo(1000, 1));
    s.undo();
    expect(s.clipCount, 1);
  });

  test('pasteClipCopies preserves relative starts and original lanes', () {
    final s = DawService()
      ..addClip(_tone(0.5, 44100))
      ..addClip(_tone(0.4, 44100), track: 1);
    s.moveClip(1, 0, 3000);
    final copies = [
      (track: 0, clip: s.timeline.tracks[0].clips[0]),
      (track: 1, clip: s.timeline.tracks[1].clips[0]),
    ];

    final pasted = s.pasteClipCopies(copies, 10000);

    expect(pasted, [(track: 0, index: 1), (track: 1, index: 1)]);
    expect(s.timeline.tracks[0].clips, hasLength(2));
    expect(s.timeline.tracks[1].clips, hasLength(2));
    expect(s.clipStartMs(0, 1), closeTo(10000, 0.1));
    expect(s.clipStartMs(1, 1), closeTo(13000, 0.1));

    s.undo();
    expect(s.timeline.tracks[0].clips, hasLength(1));
    expect(s.timeline.tracks[1].clips, hasLength(1));
  });

  test('removeClipTargets removes selected clips across lanes with one undo',
      () {
    final s = DawService()
      ..addClip(_tone(0.5, 44100))
      ..addClip(_tone(0.3, 44100))
      ..addClip(_tone(0.4, 44100), track: 1);

    final removed = s.removeClipTargets([
      (track: 0, index: 0),
      (track: 1, index: 0),
      (track: 0, index: 0), // deduped
    ]);

    expect(removed, 2);
    expect(s.timeline.tracks[0].clips, hasLength(1));
    expect(s.timeline.tracks[1].clips, isEmpty);
    s.undo();
    expect(s.timeline.tracks[0].clips, hasLength(2));
    expect(s.timeline.tracks[1].clips, hasLength(1));
  });

  test('crossfadeWithNext overlaps adjacent clips with opposing fades', () {
    final s = DawService()
      ..addClip(_tone(0.5, 44100))
      ..addClip(_tone(0.5, 44100));
    expect(s.canCrossfadeWithNext(0, 0), isTrue);
    expect(s.canCrossfadeWithNext(0, 1), isFalse);

    s.crossfadeWithNext(0, 0);
    expect(s.clipFadeOutMs(0, 0), 250);
    expect(s.clipFadeInMs(0, 1), 250);
    expect(s.clipStartMs(0, 1), closeTo(750, 1));

    s.crossfadeWithNext(0, 1); // no following clip
    expect(s.clipStartMs(0, 1), closeTo(750, 1));

    s.undo();
    expect(s.clipFadeOutMs(0, 0), 0);
    expect(s.clipFadeInMs(0, 1), 0);
    expect(s.clipStartMs(0, 1), closeTo(2000, 1));
  });

  test('undo restores after clear', () {
    final s = DawService()
      ..addClip(_tone(0.3, 100))
      ..addClip(_tone(0.3, 100), track: 1);
    expect(s.clipCount, 2);
    s.clear();
    expect(s.clipCount, 0);
    s.undo();
    expect(s.clipCount, 2);
  });

  test('setClipTrim windows a clip and clipDurationMs reflects it', () {
    final s = DawService()..addClip(_tone(0.5, 44100)); // 1000 ms at 44.1k
    expect(s.clipDurationMs(0, 0), closeTo(1000, 1));
    expect(s.clipSourceMs(0, 0), closeTo(1000, 1));

    s.setClipTrim(0, 0, trimStartMs: 200, trimEndMs: 700);
    expect(s.clipTrimStartMs(0, 0), 200);
    expect(s.clipTrimEndMs(0, 0), 700);
    expect(s.clipDurationMs(0, 0), closeTo(500, 1)); // windowed length
    expect(s.clipSourceMs(0, 0), closeTo(1000, 1)); // source unchanged

    // Clearing restores the full clip (non-destructive).
    s.setClipTrim(0, 0, trimStartMs: 0, trimEndMs: 0);
    expect(s.clipDurationMs(0, 0), closeTo(1000, 1));
  });

  test('saveProject / loadProject round-trips the arrangement', () {
    final s = DawService()
      ..addClip(_tone(0.5, 200))
      ..addClip(_tone(0.3, 200), track: 1);
    s.setClipTrim(0, 0, trimStartMs: 10, trimEndMs: 90);
    s.setTrackEffect(0, TrackEffect.echo);
    final json = s.saveProject();

    final fresh = DawService()..loadProject(json);
    expect(fresh.clipCount, 2);
    expect(fresh.trackEffect(0), TrackEffect.echo);
    expect(fresh.trackEffects(0).single.type, DawClipEffectType.delay);
    expect(fresh.clipTrimStartMs(0, 0), 10);
    expect(fresh.clipTrimEndMs(0, 0), 90);
    expect(fresh.isClipFrozen(0, 0), isTrue); // reopened clips are baked takes
    expect(fresh.canUndo, isFalse); // history reset on load
  });

  test('setTrackGain scales the whole track and coalesces one undo', () {
    final s = DawService()
      ..addClip(_tone(0.5, 100)) // track 0
      ..addClip(_tone(0.5, 100), track: 1);
    expect(s.trackGain(0), 1.0);

    // A fader sweep: several sets coalesce to a single undo entry.
    s.setTrackGain(0, 0.8);
    s.setTrackGain(0, 0.5);
    expect(s.trackGain(0), 0.5);
    final loud = renderTimeline(s.timeline, limit: false);

    // Halving track 0's gain must lower the mix where its clip plays.
    s.setTrackGain(0, 1.0);
    final restored = renderTimeline(s.timeline, limit: false);
    expect(restored[0].abs(), greaterThan(loud[0].abs()));

    // The whole sweep undoes in one step (coalesced), back to 1.0.
    s.undo();
    expect(s.trackGain(0), 1.0);
  });

  test('setTrackGainAutomationInRange writes breakpoints and undoes', () {
    final s = DawService()
      ..addClip(_tone(1, 100))
      ..addClip(_tone(1, 100), track: 1);

    final changed = s.setTrackGainAutomationInRange([0], 20, 80, 1, 0.25);
    expect(changed, 1);
    expect(s.trackGainAutomation(0), hasLength(2));
    expect(s.trackGainAutomation(0).first.ms, 20);
    expect(s.trackGainAutomation(0).first.value, closeTo(1, 1e-9));
    expect(s.trackGainAutomation(0).last.ms, 80);
    expect(s.trackGainAutomation(0).last.value, closeTo(0.25, 1e-9));
    expect(s.trackGainAutomation(1), isEmpty);

    final trackOnly = renderTimeline(
      DawTimeline(
        tracks: [
          DawTrack(
            clips: s.timeline.tracks[0].clips,
            gainAutomation: s.trackGainAutomation(0),
          ),
        ],
      ),
      sampleRate: 1000,
      limit: false,
    );
    expect(trackOnly[0], closeTo(1, 1e-9));
    expect(trackOnly[80], closeTo(0.25, 1e-9));

    s.undo();
    expect(s.trackGainAutomation(0), isEmpty);
    expect(s.trackGainAutomation(1), isEmpty);
  });

  test('add / remove / rename track', () {
    final s = DawService(); // starts with 2 tracks (A, B)
    expect(s.timeline.tracks.length, 2);

    s.addTrack();
    expect(s.timeline.tracks.length, 3);

    s.renameTrack(0, 'Drums');
    expect(s.trackName(0), 'Drums');

    s.removeTrack(1);
    expect(s.timeline.tracks.length, 2);
    expect(s.trackName(0), 'Drums'); // survivor kept

    // Never drops below one lane.
    s.removeTrack(0);
    s.removeTrack(0);
    expect(s.timeline.tracks.length, 1);

    // Every op is undoable.
    s.undo();
    expect(s.timeline.tracks.length, 2);
  });

  test('toggleTrackSolo isolates a track and undoes', () {
    final s = DawService()
      ..addClip(_tone(0.5, 100))
      ..addClip(_tone(0.5, 100), track: 1)
      ..moveClip(1, 0, 0); // align both at t=0 so they overlap at sample 0
    expect(s.isTrackSoloed(0), isFalse);
    final both = renderTimeline(s.timeline, limit: false)[0].abs();

    s.toggleTrackSolo(0);
    expect(s.isTrackSoloed(0), isTrue);
    final soloed = renderTimeline(s.timeline, limit: false)[0].abs();
    expect(soloed, lessThan(both)); // track 1 dropped out

    s.undo();
    expect(s.isTrackSoloed(0), isFalse);
  });

  test('clipPeaks summarizes a clip and reflects its trim', () {
    // A ramp 0..1 so peaks grow across the clip.
    final ramp = Float64List(1000);
    for (var i = 0; i < 1000; i++) {
      ramp[i] = i / 1000;
    }
    final s = DawService()..addClip(SampleSource(ramp));
    final peaks = s.clipPeaks(0, 0, buckets: 10);
    expect(peaks.length, 10);
    expect(
      peaks.first,
      lessThan(peaks.last),
    ); // amplitude rises across the clip
    expect(peaks.every((p) => p >= 0 && p <= 1), isTrue);

    // Trimming to the loud tail lifts the first bucket's peak.
    s.setClipTrim(0, 0, trimStartMs: 900 * 1000 / 44100); // last ~100 samples
    final trimmed = s.clipPeaks(0, 0, buckets: 10);
    expect(trimmed.first, greaterThan(peaks.first));
  });

  test('loadProject rejects a bad file without wrecking the arrangement', () {
    final s = DawService()..addClip(_tone(0.5, 100));
    expect(() => s.loadProject('garbage{'), throwsFormatException);
    expect(s.clipCount, 1); // unchanged — threw before mutating
  });

  group('splitClip', () {
    // A 1-second clip (44100 samples @ 44.1 kHz) landing at 0 on track 0.
    DawService oneSecond() => DawService()..addClip(_tone(0.5, 44100));

    test('splits one clip into two source-sharing windows', () {
      final s = oneSecond();
      expect(s.canSplitClip(0, 0, 400), isTrue);
      s.splitClip(0, 0, 400);
      expect(s.clipCount, 2);
      final left = s.timeline.tracks[0].clips[0];
      final right = s.timeline.tracks[0].clips[1];
      expect(left.trimEndMs, closeTo(400, 1)); // left ends at the cut
      expect(left.startMs, 0);
      expect(right.startMs, closeTo(400, 1)); // right placed at the cut
      expect(right.trimStartMs, closeTo(400, 1));
      expect(right.source, same(left.source)); // shared render, non-destructive
      // Durations sum back to the original second.
      expect(s.clipDurationMs(0, 0), closeTo(400, 2));
      expect(s.clipDurationMs(0, 1), closeTo(600, 2));
    });

    test('will not split at the edges or outside the clip', () {
      final s = oneSecond();
      expect(s.canSplitClip(0, 0, 0), isFalse); // at the start
      expect(s.canSplitClip(0, 0, 1000), isFalse); // at the end
      expect(s.canSplitClip(0, 0, 5000), isFalse); // past the clip
      s.splitClip(0, 0, 0);
      expect(s.clipCount, 1); // a no-op
    });

    test('the seam carries no fade; undo restores the single clip', () {
      final s = oneSecond()..setClipFades(0, 0, fadeInMs: 50, fadeOutMs: 50);
      s.splitClip(0, 0, 400);
      final left = s.timeline.tracks[0].clips[0];
      final right = s.timeline.tracks[0].clips[1];
      expect(left.fadeInMs, 50); // outer fade kept
      expect(left.fadeOutMs, 0); // no fade at the seam
      expect(right.fadeInMs, 0);
      expect(right.fadeOutMs, 50);
      s.undo();
      expect(s.clipCount, 1);
    });
  });

  group('reverseClip', () {
    Float64List ramp(int n) =>
        Float64List.fromList([for (var i = 0; i < n; i++) i / n]);

    test('flips the clip audio and round-trips on a second reverse', () {
      final s = DawService()..addClip(SampleSource(ramp(10)));
      s.reverseClip(0, 0);
      final rev = s.timeline.tracks[0].clips[0].source.render(kDawSampleRate);
      expect(rev.length, 10);
      expect(rev.first, closeTo(0.9, 1e-9)); // was the last sample
      expect(rev.last, closeTo(0.0, 1e-9)); // was the first
      // Reversing again restores the original order.
      s.reverseClip(0, 0);
      final back = s.timeline.tracks[0].clips[0].source.render(kDawSampleRate);
      expect(back.first, closeTo(0.0, 1e-9));
      expect(back.last, closeTo(0.9, 1e-9));
    });

    test('undo restores the original source', () {
      final src = SampleSource(ramp(8));
      final s = DawService()..addClip(src);
      s.reverseClip(0, 0);
      expect(s.timeline.tracks[0].clips[0].source, isNot(same(src)));
      s.undo();
      expect(s.timeline.tracks[0].clips[0].source, same(src));
    });
  });

  group('resampleClip', () {
    Float64List ramp(int n) =>
        Float64List.fromList([for (var i = 0; i < n; i++) i / n]);
    Float64List renderOf(DawService s) =>
        s.timeline.tracks[0].clips[0].source.render(kDawSampleRate);

    test('2x halves the length, 0.5x doubles it', () {
      final fast = DawService()..addClip(SampleSource(ramp(100)));
      fast.resampleClip(0, 0, 2.0);
      expect(renderOf(fast).length, 50);
      final slow = DawService()..addClip(SampleSource(ramp(100)));
      slow.resampleClip(0, 0, 0.5);
      expect(renderOf(slow).length, 200);
    });

    test('keeps the first sample and stays in range', () {
      final s = DawService()..addClip(SampleSource(ramp(100)));
      s.resampleClip(0, 0, 2.0);
      final out = renderOf(s);
      expect(out.first, closeTo(0.0, 1e-9));
      expect(out.every((v) => v >= 0 && v <= 1), isTrue);
    });

    test('a non-positive factor is a no-op; undo restores the source', () {
      final src = SampleSource(ramp(50));
      final s = DawService()..addClip(src);
      s.resampleClip(0, 0, 0); // no-op
      expect(s.timeline.tracks[0].clips[0].source, same(src));
      s.resampleClip(0, 0, 2.0);
      expect(s.timeline.tracks[0].clips[0].source, isNot(same(src)));
      s.undo();
      expect(s.timeline.tracks[0].clips[0].source, same(src));
    });
  });

  group('instrument sound (score clips)', () {
    test('a score clip is voiceable; a sample clip is not', () {
      final s = DawService()
        ..addClip(_scoreClip())
        ..addClip(_tone(0.3, 100), track: 1);
      expect(s.isScoreClip(0, 0), isTrue);
      expect(s.isScoreClip(1, 0), isFalse);
      expect(s.clipInstrument(0, 0), isNull);
    });

    test('clipScore exposes the engraved music (for opening in an editor)', () {
      final s = DawService()
        ..addClip(_scoreClip())
        ..addClip(_tone(0.3, 100), track: 1);
      final score = s.clipScore(0, 0);
      expect(score, isNotNull);
      expect(score!.parts, isNotEmpty); // round-trips back to a MultiPartScore
      expect(s.clipScore(1, 0), isNull); // a baked sample has no score
    });

    test('replaceScoreClipSource updates the SAME clip in place, keeping voice',
        () {
      final s = DawService()..setTrackInstrument(0, _cello);
      s.addClip(_scoreClip()); // score clip on track 0, adopts the cello voice
      final src = s.clipSourceAt(0, 0);
      final edited = _editedScore();
      s.replaceScoreClipSource(src, edited);
      expect(s.timeline.tracks[0].clips.length, 1); // replaced, not duplicated
      expect(s.clipScore(0, 0), same(edited)); // now the edited score
      expect(s.clipInstrument(0, 0)?.id, 'cello'); // voice preserved
    });

    test('replaceScoreClipSource adds a new clip when the source is gone', () {
      final s = DawService()..addClip(_scoreClip());
      final src = s.clipSourceAt(0, 0);
      s.removeClip(0, 0); // the clip vanished while "editing"
      s.replaceScoreClipSource(src, _editedScore());
      expect(s.clipCount, 1); // the edit still lands — nothing lost
    });

    test('setClipInstrument re-voices the clip, changing its source + cacheKey',
        () {
      final s = DawService()..addClip(_scoreClip());
      final before = s.timeline.tracks[0].clips[0].source;
      final beforeKey = before.cacheKey;
      s.setClipInstrument(0, 0, _piano);
      final after = s.timeline.tracks[0].clips[0].source;
      expect(after, isNot(same(before)));
      expect(after.cacheKey, isNot(beforeKey));
      expect(s.clipInstrument(0, 0)?.id, 'piano');
      // Undoable, and re-bakes to audible audio.
      expect(_silent(s.bake()), isFalse);
      s.undo();
      expect(s.clipInstrument(0, 0), isNull);
    });

    test('setClipInstrument is a no-op on a non-score clip', () {
      final s = DawService()..addClip(_tone(0.3, 100));
      final before = s.timeline.tracks[0].clips[0].source;
      s.setClipInstrument(0, 0, _piano);
      // The baked audio source is untouched — no re-voicing possible.
      expect(s.timeline.tracks[0].clips[0].source, same(before));
      expect(s.clipInstrument(0, 0), isNull);
    });

    test('setTrackInstrument voices every score clip on the track', () {
      final s = DawService()
        ..addClip(_scoreClip())
        ..addClip(_scoreClip()); // both land on track 0
      s.setTrackInstrument(0, _cello);
      expect(s.clipInstrument(0, 0)?.id, 'cello');
      expect(s.clipInstrument(0, 1)?.id, 'cello');
      expect(s.trackInstrument(0)?.id, 'cello');
    });

    test('a new score clip adopts the lane instrument; a sample clip does not',
        () {
      final s = DawService()..setTrackInstrument(0, _cello);
      s.addClip(_scoreClip()); // → track 0, should adopt cello
      expect(s.clipInstrument(0, 0)?.id, 'cello');
      s.addClip(_tone(0.3, 100)); // baked audio: unaffected
      expect(s.clipInstrument(0, 1), isNull);
    });

    test("a clip's own instrument is not overridden by the lane default", () {
      final s = DawService()..setTrackInstrument(0, _cello);
      s.addClip(_scoreClip().withInstrument(_piano)); // explicit voice wins
      expect(s.clipInstrument(0, 0)?.id, 'piano');
    });
  });

  group('track insert effect', () {
    test('defaults to none and is undoable', () {
      final s = DawService()..addClip(_tone(0.5, 4410));
      expect(s.trackEffect(0), TrackEffect.none);
      expect(s.trackEffects(0), isEmpty);
      s.setTrackEffect(0, TrackEffect.reverb);
      expect(s.trackEffect(0), TrackEffect.reverb);
      expect(s.trackEffects(0).single.type, DawClipEffectType.reverb);
      s.undo();
      expect(s.trackEffect(0), TrackEffect.none);
      expect(s.trackEffects(0), isEmpty);
    });

    test('reverb rings a tail into the silence after the click', () {
      // A click at t=0 in an otherwise-silent 1 s buffer defines the length.
      final s = DawService()
        ..addClip(SampleSource(Float64List(44100)..[0] = 1.0));
      final dry = s.bake();
      // dry: silent tail after the click.
      expect(dry.sublist(5000).every((x) => x.abs() < 1e-9), isTrue);
      s.setTrackEffect(0, TrackEffect.reverb);
      final wet = s.bake();
      expect(wet.length, dry.length); // same length…
      // …but the reverb tail is now audible well past the click.
      expect(wet.sublist(5000).any((x) => x.abs() > 1e-6), isTrue);
    });

    test('echo repeats the click ~300 ms later', () {
      final s = DawService()
        ..addClip(SampleSource(Float64List(44100)..[0] = 1.0));
      s.setTrackEffect(0, TrackEffect.echo);
      final out = s.bake();
      // 300 ms at 44100 Hz ≈ sample 13230 → the delayed repeat of the click.
      expect(out[13230].abs() > 1e-6 || out[13231].abs() > 1e-6, isTrue);
    });

    test('voice shaping processes any track audio at bake time', () {
      final sample = Float64List(4410)..fillRange(0, 4410, 0.4);
      final s = DawService()..addClip(SampleSource(sample));
      final dry = s.bake();
      s.setTrackEffect(0, TrackEffect.voiceRobot);
      final shaped = s.bake();

      expect(shaped.length, dry.length);
      expect(
        List.generate(
          shaped.length,
          (i) => (shaped[i] - dry[i]).abs(),
        ).reduce((a, b) => a > b ? a : b),
        greaterThan(0.05),
      );
    });

    test('with no effect the per-lane bake equals a flat sum (unchanged)', () {
      // Two lanes, both effect-free → identical to the old single-pass mix.
      final s = DawService()
        ..addClip(_tone(0.3, 1000))
        ..addClip(_tone(0.4, 1000), track: 1);
      final baked = s.bake();
      expect(baked[0], closeTo(0.3, 1e-9)); // only lane 0 sounds at t=0
    });

    test('ordered track FX chains have params, reorder and undo', () {
      final s = DawService()..addClip(_tone(0.4, 44100));
      s
        ..addTrackEffect(0, DawClipEffectType.highpass)
        ..addTrackEffect(0, DawClipEffectType.distortion)
        ..setTrackEffectParam(0, 1, 'drive', 8);

      expect(
        s.trackEffects(0).map((fx) => fx.type),
        [DawClipEffectType.highpass, DawClipEffectType.distortion],
      );
      expect(s.trackEffects(0)[1].params['drive'], 8);

      s.moveTrackEffect(0, 1, -1);
      expect(
        s.trackEffects(0).map((fx) => fx.type),
        [DawClipEffectType.distortion, DawClipEffectType.highpass],
      );

      s.toggleTrackEffect(0, 0);
      expect(s.trackEffects(0).first.enabled, isFalse);
      s.undo();
      expect(
        s.trackEffects(0).map((fx) => fx.type),
        [DawClipEffectType.distortion, DawClipEffectType.highpass],
      );
      expect(s.trackEffects(0).first.enabled, isTrue);
    });

    test('presets can be applied to several tracks at once', () {
      final s = DawService()
        ..addClip(_tone(0.3, 100))
        ..addClip(_tone(0.2, 100), track: 1);

      s.applyTrackEffectPresetToTracks(
        [0, 1],
        DawClipEffectPreset.wideSpace,
      );

      for (final track in [0, 1]) {
        expect(
          s.trackEffects(track).map((fx) => fx.type),
          [
            DawClipEffectType.chorus,
            DawClipEffectType.delay,
            DawClipEffectType.reverb,
          ],
        );
      }
    });

    test('copies one track FX chain to several tracks', () {
      final s = DawService()
        ..addClip(_tone(0.3, 100))
        ..addClip(_tone(0.2, 100), track: 1);

      s
        ..addTrackEffect(0, DawClipEffectType.highpass)
        ..addTrackEffect(0, DawClipEffectType.distortion)
        ..setTrackEffectParam(0, 1, 'drive', 7)
        ..copyTrackEffectsToTracks(0, [1]);

      expect(
        s.trackEffects(1).map((fx) => fx.type),
        [DawClipEffectType.highpass, DawClipEffectType.distortion],
      );
      expect(s.trackEffects(1)[1].params['drive'], 7);
    });

    test('master output FX chain has params, reorder and undo', () {
      final s = DawService()..addClip(_tone(0.4, 1000));
      s
        ..addMasterEffect(DawClipEffectType.highpass)
        ..addMasterEffect(DawClipEffectType.distortion)
        ..setMasterEffectParam(1, 'drive', 8);

      expect(
        s.masterEffects().map((fx) => fx.type),
        [DawClipEffectType.highpass, DawClipEffectType.distortion],
      );
      expect(s.masterEffects()[1].params['drive'], 8);

      s.moveMasterEffect(1, -1);
      expect(
        s.masterEffects().map((fx) => fx.type),
        [DawClipEffectType.distortion, DawClipEffectType.highpass],
      );

      s.toggleMasterEffect(0);
      expect(s.masterEffects().first.enabled, isFalse);
      s.undo();
      expect(s.masterEffects().first.enabled, isTrue);
      s.setMasterEffectAutomation(
        0,
        'drive',
        const [
          DawAutomationPoint(
            ms: 0,
            value: 2,
            curve: DawFadeCurve.exponential,
          ),
          DawAutomationPoint(ms: 500, value: 8),
        ],
      );
      expect(s.masterEffects().first.automation['drive'], hasLength(2));
      expect(
        s.masterEffects().first.automation['drive']!.first.curve,
        DawFadeCurve.exponential,
      );
      s.undo();
      expect(s.masterEffects().first.automation['drive'], isNull);
      s.removeMasterEffect(0);
      expect(s.masterEffects().single.type, DawClipEffectType.highpass);
    });

    test('group buses route tracks, edit FX, undo and clean removed routes',
        () {
      final s = DawService()
        ..addClip(_tone(0.4, 1000))
        ..addClip(_tone(0.2, 1000), track: 1);

      s
        ..addBus(name: 'Drum bus')
        ..addBus(name: 'FX bus')
        ..setTrackBusForTracks([0, 1], 1)
        ..addBusEffect(1, DawClipEffectType.highpass)
        ..addBusEffect(1, DawClipEffectType.distortion)
        ..setBusEffectParam(1, 1, 'drive', 8);

      expect(s.trackBus(0), 1);
      expect(s.trackBus(1), 1);
      expect(s.buses()[1].name, 'FX bus');
      expect(
        s.busEffects(1).map((fx) => fx.type),
        [DawClipEffectType.highpass, DawClipEffectType.distortion],
      );
      expect(s.busEffects(1)[1].params['drive'], 8);

      s.moveBusEffect(1, 1, -1);
      expect(
        s.busEffects(1).map((fx) => fx.type),
        [DawClipEffectType.distortion, DawClipEffectType.highpass],
      );

      s.toggleBusEffect(1, 0);
      expect(s.busEffects(1).first.enabled, isFalse);
      s.undo();
      expect(s.busEffects(1).first.enabled, isTrue);

      s.removeBus(0);
      expect(s.trackBus(0), 0);
      expect(s.trackBus(1), 0);
      s.removeBus(0);
      expect(s.trackBus(0), isNull);
      expect(s.trackBus(1), isNull);
    });

    test('aux bus sends have amounts, undo and shift with removed buses', () {
      final s = DawService()
        ..addClip(_tone(0.4, 1000))
        ..addBus(name: 'Delay')
        ..addBus(name: 'Verb');

      s
        ..setTrackSend(0, 1, 0.6)
        ..addBusEffect(1, DawClipEffectType.reverb);

      expect(s.trackSend(0, 1), closeTo(0.6, 1e-9));
      expect(s.timeline.tracks[0].busSends, {1: 0.6});

      s.setTrackSend(0, 1, 0.9);
      expect(s.trackSend(0, 1), closeTo(0.9, 1e-9));
      s.undo();
      expect(s.trackSend(0, 1), closeTo(0.6, 1e-9));

      s.removeBus(0);
      expect(s.trackSend(0, 0), closeTo(0.6, 1e-9));
      expect(s.busEffects(0).single.type, DawClipEffectType.reverb);

      s.setTrackSend(0, 0, 0);
      expect(s.timeline.tracks[0].busSends, isEmpty);
    });
  });

  group('clip effect chains', () {
    test('presets replace or append reusable ordered chains', () {
      final s = DawService()..addClip(_tone(0.4, 100));

      s.applyClipEffectPreset(0, 0, DawClipEffectPreset.vocalPolish);
      expect(
        s.clipEffects(0, 0).map((fx) => fx.type),
        [
          DawClipEffectType.highpass,
          DawClipEffectType.compressor,
          DawClipEffectType.reverb,
        ],
      );

      s.applyClipEffectPreset(0, 0, DawClipEffectPreset.robotVoice);
      expect(s.clipEffects(0, 0), hasLength(3));
      expect(s.clipEffects(0, 0).first.type, DawClipEffectType.voiceRobot);

      s.applyClipEffectPreset(
        0,
        0,
        DawClipEffectPreset.wideSpace,
        append: true,
      );
      expect(s.clipEffects(0, 0), hasLength(6));
      expect(s.clipEffects(0, 0).last.type, DawClipEffectType.reverb);
    });

    test('batch FX operations target several clips', () {
      final s = DawService()
        ..addClip(_tone(0.4, 100))
        ..addClip(_tone(0.2, 100), track: 1);

      s.applyClipEffectPresetToClips(
        [(track: 0, index: 0), (track: 1, index: 0)],
        DawClipEffectPreset.vocalPolish,
      );
      expect(s.clipEffects(0, 0).first.type, DawClipEffectType.highpass);
      expect(s.clipEffects(1, 0).first.type, DawClipEffectType.highpass);

      s.addClipEffectToClips(
        [(track: 1, index: 0)],
        DawClipEffectType.distortion,
      );
      expect(s.clipEffects(0, 0), hasLength(3));
      expect(s.clipEffects(1, 0).last.type, DawClipEffectType.distortion);

      s
        ..setClipEffectParam(1, 0, 3, 'drive', 8)
        ..copyClipEffectsToClips(1, 0, [(track: 0, index: 0)]);
      expect(s.clipEffects(0, 0), hasLength(4));
      expect(s.clipEffects(0, 0).last.params['drive'], 8);
    });

    test('range FX splits clips and targets only the marked segment', () {
      final s = DawService()
        ..addClip(_tone(0.4, kDawSampleRate))
        ..addClip(_tone(0.2, kDawSampleRate), track: 1);
      s.moveClip(1, 0, 0);

      final changed = s.addClipEffectToRange(
        [0, 1],
        250,
        750,
        DawClipEffectType.distortion,
      );

      expect(changed, 2);
      expect(s.timeline.tracks[0].clips, hasLength(3));
      expect(s.timeline.tracks[1].clips, hasLength(3));
      expect(s.clipEffects(0, 0), isEmpty);
      expect(s.clipEffects(0, 1).single.type, DawClipEffectType.distortion);
      expect(s.clipEffects(0, 2), isEmpty);
      expect(s.clipStartMs(0, 1), closeTo(250, 0.1));
      expect(s.clipDurationMs(0, 1), closeTo(500, 0.1));

      s.undo();
      expect(s.timeline.tracks[0].clips, hasLength(1));
      expect(s.timeline.tracks[1].clips, hasLength(1));
      expect(s.clipEffects(0, 0), isEmpty);
    });

    test('range gain splits clips and scales only the marked segment', () {
      final s = DawService()..addClip(_tone(0.4, kDawSampleRate));

      final changed = s.multiplyClipGainInRange([0], 250, 750, 0.5);

      expect(changed, 1);
      expect(s.timeline.tracks[0].clips, hasLength(3));
      expect(s.clipGain(0, 0), closeTo(1, 1e-9));
      expect(s.clipGain(0, 1), closeTo(0.5, 1e-9));
      expect(s.clipGain(0, 2), closeTo(1, 1e-9));
      expect(s.clipStartMs(0, 1), closeTo(250, 0.1));
      expect(s.clipDurationMs(0, 1), closeTo(500, 0.1));

      s.undo();
      expect(s.timeline.tracks[0].clips, hasLength(1));
      expect(s.clipGain(0, 0), closeTo(1, 1e-9));
    });

    test('range mute splits clips and toggles only the marked segment', () {
      final s = DawService()..addClip(_tone(0.4, kDawSampleRate));

      final changed = s.setClipMutedInRange([0], 250, 750, true);

      expect(changed, 1);
      expect(s.timeline.tracks[0].clips, hasLength(3));
      expect(s.timeline.tracks[0].clips[0].muted, isFalse);
      expect(s.timeline.tracks[0].clips[1].muted, isTrue);
      expect(s.timeline.tracks[0].clips[2].muted, isFalse);
      expect(s.clipStartMs(0, 1), closeTo(250, 0.1));
      expect(s.clipDurationMs(0, 1), closeTo(500, 0.1));

      s.setClipMutedInRange([0], 250, 750, false);
      expect(s.timeline.tracks[0].clips[1].muted, isFalse);

      s.undo();
      expect(s.timeline.tracks[0].clips[1].muted, isTrue);
      s.undo();
      expect(s.timeline.tracks[0].clips, hasLength(1));
      expect(s.timeline.tracks[0].clips[0].muted, isFalse);
    });

    test('range fades split clips and affect only the marked segment', () {
      final s = DawService()..addClip(_tone(0.4, kDawSampleRate));

      final changed = s.applyFadeInToRange([0], 250, 750);

      expect(changed, 1);
      expect(s.timeline.tracks[0].clips, hasLength(3));
      expect(s.clipFadeInMs(0, 0), 0);
      expect(s.clipFadeInMs(0, 1), closeTo(500, 0.1));
      expect(s.clipFadeInMs(0, 2), 0);
      expect(s.clipFadeInCurve(0, 1), DawFadeCurve.linear);

      s.applyFadeOutToRange([0], 250, 750, DawFadeCurve.sCurve);
      expect(s.clipFadeOutMs(0, 1), closeTo(500, 0.1));
      expect(s.clipFadeOutCurve(0, 1), DawFadeCurve.sCurve);

      s.undo();
      expect(s.clipFadeOutMs(0, 1), 0);
      s.undo();
      expect(s.timeline.tracks[0].clips, hasLength(1));
    });

    test('moveClipEffect reorders the chain, clamps invalid moves and undoes',
        () {
      final s = DawService()..addClip(_tone(0.4, 100));
      s
        ..addClipEffect(0, 0, DawClipEffectType.highpass)
        ..addClipEffect(0, 0, DawClipEffectType.distortion)
        ..addClipEffect(0, 0, DawClipEffectType.reverb);

      s.moveClipEffect(0, 0, 1, -1);
      expect(
        s.clipEffects(0, 0).map((fx) => fx.type),
        [
          DawClipEffectType.distortion,
          DawClipEffectType.highpass,
          DawClipEffectType.reverb,
        ],
      );

      s.moveClipEffect(0, 0, 0, -1);
      s.moveClipEffect(0, 0, 2, 1);
      expect(
        s.clipEffects(0, 0).map((fx) => fx.type),
        [
          DawClipEffectType.distortion,
          DawClipEffectType.highpass,
          DawClipEffectType.reverb,
        ],
      );

      s.undo();
      expect(
        s.clipEffects(0, 0).map((fx) => fx.type),
        [
          DawClipEffectType.highpass,
          DawClipEffectType.distortion,
          DawClipEffectType.reverb,
        ],
      );
    });
  });
}

/// A live source whose render reflects a mutable buffer — a stand-in for a
/// module's "vector" model, so freezing can be shown to snapshot it.
class _MutableSource implements ClipSource {
  _MutableSource(this.values);
  final List<double> values;
  @override
  Object get cacheKey => Object.hashAll(values);
  @override
  Float64List render(int sampleRate) => Float64List.fromList(values);
}
