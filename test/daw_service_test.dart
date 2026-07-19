// The shared DAW arrangement service: modules add clips, the arranger bakes.
// Pure, headless.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:flutter_test/flutter_test.dart';

SampleSource _tone(double level, int samples) =>
    SampleSource(Float64List(samples)..fillRange(0, samples, level));

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
    s.setClipFades(0, 0, fadeInMs: -5); // clamped
    expect(s.clipFadeInMs(0, 0), 0);
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
