// The Multitrack (DAW) arranger surface: add clips from modules, bake the
// arrangement, mute tracks. Audio is a no-op in the headless binding; assertions
// are on the arrangement + the bake.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart' show kDawSampleRate;
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

DawTester _daw(WidgetTester tester) =>
    tester.state<State<DawScreen>>(find.byType(DawScreen)) as DawTester;

Future<void> _pumpDaw(WidgetTester tester) => pumpGame(
      tester,
      const DawScreen(),
      extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('starts empty with two tracks', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    expect(daw.trackCount, 2);
    expect(daw.clipCount, 0);
    expect(daw.debugBakeLength(), 0); // nothing to bake
  });

  testWidgets('adding clips from modules bakes real, layered audio',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);

    daw.addDemoBeat(); // a DrumSource on track A
    daw.addDemoTune(); // a ScoreSource on track B, 2 s later
    await tester.pump();
    expect(daw.clipCount, 2);

    // The arrangement bakes to a non-empty buffer that runs at least until the
    // second clip's placement (2 s in).
    final len = daw.debugBakeLength();
    expect(len, greaterThan(2 * 44100));
  });

  testWidgets('muting a track shortens/changes the bake', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat(); // track A at 0
    await tester.pump();
    final withBeat = daw.debugBakeLength();
    expect(withBeat, greaterThan(0));

    daw.toggleTrackMute(0);
    await tester.pump();
    expect(daw.isTrackMuted(0), isTrue);
    expect(daw.debugBakeLength(), 0); // the only track is muted → silence
  });

  testWidgets('merge all flattens the arrangement into one baked take',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    daw.addDemoTune();
    await tester.pump();
    expect(daw.clipCount, 2);
    final before = daw.debugBakeLength();

    daw.mergeAll();
    await tester.pump();
    expect(daw.clipCount, 1);
    expect(daw.trackCount, 2); // lanes stay; only the clips collapse
    expect(daw.isClipFrozen(0, 0), isTrue);
    // Merging preserves the arrangement, so the bake length is unchanged.
    expect(daw.debugBakeLength(), before);
  });

  testWidgets('freeze converts a live clip to audio; remove drops it',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat(); // a live DrumSource
    await tester.pump();
    expect(daw.isClipFrozen(0, 0), isFalse);

    daw.freezeClip(0, 0);
    await tester.pump();
    expect(daw.isClipFrozen(0, 0), isTrue);
    expect(daw.debugBakeLength(), greaterThan(0));

    daw.removeClip(0, 0);
    await tester.pump();
    expect(daw.clipCount, 0);
  });

  testWidgets('clips draw to scale and can be dragged along the lane',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat(); // track A @ 0 ms
    await tester.pump();

    // A real, non-zero duration (drawn to scale), and it starts at 0.
    expect(daw.clipDurationMs(0, 0), greaterThan(0));
    expect(daw.clipStartMs(0, 0), 0);
    expect(daw.canExport, isTrue);

    // Long-press then drag the clip box to the right → later in time.
    final center = tester.getCenter(find.text('🥁'));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600)); // arm the long press
    await gesture.moveBy(const Offset(160, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(daw.clipStartMs(0, 0), greaterThan(0));
  });

  testWidgets('export is gated on having content', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    expect(daw.canExport, isFalse);
    daw.addDemoBeat();
    await tester.pump();
    expect(daw.canExport, isTrue);
  });

  testWidgets('tapping a clip opens the inspector; gain slider changes gain',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();
    expect(daw.clipGain(0, 0), 1.0);

    // Tap the clip box → the inspector sheet. Besides the gutter track faders
    // in the body, the inspector adds 5 sliders (gain, 2 fades, 2 trims); the
    // modal renders after the body, so those are the LAST 5.
    await tester.tap(find.text('🥁'));
    await tester.pumpAndSettle();
    final sliders = find.byType(Slider);
    final total = tester.widgetList(sliders).length;
    expect(total, greaterThanOrEqualTo(5));

    // Drag the gain slider (first of the inspector's 5) down; gain drops.
    await tester.drag(sliders.at(total - 5), const Offset(-80, 0));
    await tester.pump();
    expect(daw.clipGain(0, 0), lessThan(1.0));
  });

  testWidgets('Split cuts a clip in two at the playhead', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();
    expect(daw.clipCount, 1);

    // Put the playhead inside the clip, then open the inspector.
    daw.seekTo(daw.clipDurationMs(0, 0) / 2);
    await tester.pump();
    await tester.tap(find.text('🥁'));
    await tester.pumpAndSettle();

    // Tap Split → the one clip becomes two.
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    expect(daw.clipCount, 2);
  });

  testWidgets('Reverse bakes the clip to a backwards take', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();
    expect(daw.isClipFrozen(0, 0), isFalse); // a live DrumSource

    await tester.tap(find.text('🥁'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reverse'));
    await tester.pumpAndSettle();

    expect(daw.clipCount, 1); // reverse replaces in place
    expect(daw.isClipFrozen(0, 0), isTrue); // now a baked SampleSource take
  });

  testWidgets('Faster resamples the clip to a shorter baked take',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();
    final before = daw.clipDurationMs(0, 0);

    await tester.tap(find.text('🥁'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Faster'));
    await tester.pumpAndSettle();

    expect(daw.isClipFrozen(0, 0), isTrue); // baked take
    expect(daw.clipDurationMs(0, 0), closeTo(before / 2, before * 0.1)); // ~½
  });

  testWidgets('the snap toggle flips snapping and a ruler labels the timeline',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();

    // The time ruler labels seconds (0s at the origin).
    expect(find.text('0s'), findsOneWidget);
    expect(find.text('1s'), findsWidgets);

    // The grid button toggles snapping.
    expect(daw.snapOn, isFalse);
    await tester.tap(find.byTooltip('Snap to grid'));
    await tester.pump();
    expect(daw.snapOn, isTrue);
  });

  testWidgets('undo/redo reverse and replay edits', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    expect(daw.canUndo, isFalse);

    daw.addDemoBeat();
    daw.addDemoTune();
    await tester.pump();
    expect(daw.clipCount, 2);
    expect(daw.canUndo, isTrue);

    daw.undo();
    await tester.pump();
    expect(daw.clipCount, 1);

    daw.redo();
    await tester.pump();
    expect(daw.clipCount, 2);
  });

  testWidgets('clear empties every track', (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    daw.addDemoTune();
    await tester.pump();
    expect(daw.clipCount, 2);

    daw.clear();
    await tester.pump();
    expect(daw.clipCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a My Samples clip is arranged, resampled to the timeline rate',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);

    // 0.5 s at HALF the timeline rate → after resampling it should bake to
    // ~0.5 s at the timeline rate (twice as many samples as the source).
    const half = kDawSampleRate ~/ 2;
    final src = Float64List.fromList([
      for (var i = 0; i < half ~/ 2; i++)
        0.3 * math.sin(2 * math.pi * 220 * i / half),
    ]);
    daw.addSampleClip(
      SampleClip(name: 'zap', sampleRate: half, pcm: src),
    );

    expect(daw.clipCount, 1);
    expect(daw.trackCount, greaterThan(2)); // landed on a fresh lane
    // The bake spans the resampled clip: ~2x the source length (half-rate → full).
    expect(daw.debugBakeLength(), greaterThan(src.length));
  });

  testWidgets('the playhead advances during play and resets on stop',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat(); // gives the arrangement some length
    await tester.pump();

    expect(daw.playheadMs, 0);
    daw.play();
    expect(daw.isPlaying, isTrue);

    // The Ticker drives the playhead off its own elapsed, so tester.pump
    // advances it deterministically (no wall-clock). The first frame after
    // start() establishes the baseline (elapsed 0); it grows after that.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(daw.playheadMs, greaterThan(0));
    final mid = daw.playheadMs;
    await tester.pump(const Duration(milliseconds: 250));
    expect(daw.playheadMs, greaterThan(mid)); // it moved forward

    daw.stop();
    expect(daw.isPlaying, isFalse);
    expect(daw.playheadMs, 0); // reset
  });

  testWidgets('playback auto-stops when the playhead reaches the end',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();
    daw.play();

    // Pump well past the arrangement length; the ticker should trip stop().
    await tester.pump(); // baseline frame
    await tester.pump(const Duration(seconds: 30));
    expect(daw.isPlaying, isFalse);
    expect(daw.playheadMs, 0);
  });

  testWidgets('loop keeps playing past the end instead of stopping',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();

    expect(daw.loopOn, isFalse);
    daw.toggleLoop();
    expect(daw.loopOn, isTrue);

    daw.play();
    await tester.pump(); // baseline
    // Pump well past the arrangement length: without loop it would stop; with
    // loop it restarts and is still playing.
    await tester.pump(const Duration(seconds: 20));
    expect(daw.isPlaying, isTrue);

    daw.stop();
    expect(daw.isPlaying, isFalse);
  });

  testWidgets('seekTo moves the playhead and playback starts from it',
      (tester) async {
    await _pumpDaw(tester);
    final daw = _daw(tester);
    daw.addDemoBeat();
    await tester.pump();

    // Click-to-seek (via the seam): the resting playhead moves to the marker.
    daw.seekTo(400);
    await tester.pump();
    expect(daw.playheadMs, 400);

    // Playback begins from the marker (not 0), so after a baseline frame the
    // playhead is already at/after the seek point.
    daw.play();
    await tester.pump(); // ticker baseline
    expect(daw.playheadMs, greaterThanOrEqualTo(400));

    // Stop rests back at the marker, not 0.
    daw.stop();
    expect(daw.playheadMs, 400);
  });
}
