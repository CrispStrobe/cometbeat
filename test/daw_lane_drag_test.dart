// Dragging a clip between the Audio Editor's rows — the GESTURE, not the method.
//
// `moveClipToTrack` has eight service-level tests and every one of them calls
// the method directly. Nothing drove the long-press-then-vertical-drag that a
// player actually makes, so "you can drag a clip between rows" was a claim from
// reading the widget tree. That is the same distinction that let a saved barre
// be silently dropped: the unit was right, and nothing checked the path to it.
//
// Two things here are easy to get wrong and invisible from the service tests:
//
//   * the re-parent happens on RELEASE, not during the drag — the code defers it
//     because re-parenting mid-gesture tears down the recognizer driving it, so
//     a test that asserts mid-drag would "prove" the feature broken;
//   * horizontal and vertical movement mean different things in ONE gesture
//     (retime vs change lane), so a diagonal drag has to do both, and a purely
//     horizontal one must not change lane at all.
//
// The menu route is covered too: the code comments say it exists because
// long-press drag is "fiddly (phones, precise moves)", which makes it the
// accessible path — and it was equally untested.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// The lane height the screen lays out with — a drag of this much is one lane.
const double _laneHeight = 108;

Future<DawService> _open(WidgetTester tester, {int tracks = 3}) async {
  final daw = DawService();
  await pumpGame(
    tester,
    const DawScreen(),
    extraProviders: [ChangeNotifierProvider<DawService>.value(value: daw)],
  );
  // Distinct clips on track 0 so a move is observable, and enough tracks to
  // move into.
  for (var t = 0; t < tracks; t++) {
    daw.addClip(SampleSource(Float64List(4410)), track: t);
  }
  await tester.pumpAndSettle();
  return daw;
}

Finder _clip(int track, int index) => find.byKey(Key('daw-clip-$track-$index'));

/// Long-presses the clip, drags by [offset], and releases.
Future<void> _longPressDrag(
  WidgetTester tester,
  Finder clip,
  Offset offset,
) async {
  final gesture = await tester.startGesture(tester.getCenter(clip));
  // Past the long-press threshold, or this is a scroll rather than a move.
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveBy(offset);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('vertical drag moves a clip to another lane', () {
    testWidgets('one lane down', (tester) async {
      final daw = await _open(tester);
      final before = daw.timeline.tracks[1].clips.length;

      await _longPressDrag(tester, _clip(0, 0), const Offset(0, _laneHeight));

      expect(
        daw.timeline.tracks[1].clips.length,
        before + 1,
        reason: 'it arrived in the lane below',
      );
      expect(daw.timeline.tracks[0].clips, isEmpty, reason: 'and left its own');
    });

    testWidgets('two lanes down in one gesture', (tester) async {
      final daw = await _open(tester);
      final before = daw.timeline.tracks[2].clips.length;

      await _longPressDrag(
        tester,
        _clip(0, 0),
        const Offset(0, _laneHeight * 2),
      );

      expect(daw.timeline.tracks[2].clips.length, before + 1);
      expect(daw.timeline.tracks[0].clips, isEmpty);
    });

    testWidgets('and back up again', (tester) async {
      final daw = await _open(tester);
      await _longPressDrag(tester, _clip(0, 0), const Offset(0, _laneHeight));
      expect(daw.timeline.tracks[0].clips, isEmpty);

      // The moved clip is now the last one in lane 1.
      final index = daw.timeline.tracks[1].clips.length - 1;
      await _longPressDrag(
        tester,
        _clip(1, index),
        const Offset(0, -_laneHeight),
      );
      expect(daw.timeline.tracks[0].clips, hasLength(1));
    });
  });

  group('what must NOT change lane', () {
    testWidgets('a purely horizontal drag retimes and stays put',
        (tester) async {
      // Horizontal and vertical mean different things inside ONE gesture, so a
      // sideways move must not leak into a lane change.
      final daw = await _open(tester);
      final startBefore = daw.clipStartMs(0, 0);

      await _longPressDrag(tester, _clip(0, 0), const Offset(120, 0));

      expect(daw.timeline.tracks[0].clips, hasLength(1), reason: 'still here');
      expect(
        daw.clipStartMs(0, 0),
        greaterThan(startBefore),
        reason: 'but later in time',
      );
    });

    testWidgets('a small vertical wobble is not a lane change', (tester) async {
      // The delta rounds to lanes, so half a lane must not count — otherwise
      // every imprecise finger re-parents the clip.
      final daw = await _open(tester);
      await _longPressDrag(
        tester,
        _clip(0, 0),
        const Offset(0, _laneHeight * 0.3),
      );
      expect(daw.timeline.tracks[0].clips, hasLength(1));
    });

    testWidgets('dragging past the last lane clamps instead of losing the clip',
        (tester) async {
      // The clip must end up somewhere. Falling off the bottom would be silent
      // data loss, which is the worst outcome available here.
      final daw = await _open(tester);
      final total = daw.timeline.tracks.length;

      await _longPressDrag(
        tester,
        _clip(0, 0),
        const Offset(0, _laneHeight * 12),
      );

      final placed = [
        for (var t = 0; t < total; t++) daw.timeline.tracks[t].clips.length,
      ].fold<int>(0, (a, b) => a + b);
      expect(placed, total, reason: 'nothing was lost off the end');
      expect(daw.timeline.tracks[total - 1].clips, hasLength(2));
    });
  });

  group('a diagonal drag does both', () {
    testWidgets('it changes lane AND retimes', (tester) async {
      final daw = await _open(tester);
      final startBefore = daw.clipStartMs(0, 0);

      await _longPressDrag(
        tester,
        _clip(0, 0),
        const Offset(150, _laneHeight),
      );

      expect(daw.timeline.tracks[0].clips, isEmpty);
      final moved = daw.timeline.tracks[1].clips.length - 1;
      expect(
        daw.clipStartMs(1, moved),
        greaterThan(startBefore),
        reason: 'the horizontal half of the same gesture still counted',
      );
    });
  });

  testWidgets('the lane change lands as ONE undoable step', (tester) async {
    // A move a player cannot take back is worse than one they cannot make.
    final daw = await _open(tester);
    await _longPressDrag(tester, _clip(0, 0), const Offset(0, _laneHeight));
    expect(daw.timeline.tracks[0].clips, isEmpty);

    daw.undo();
    await tester.pumpAndSettle();
    expect(
      daw.timeline.tracks[0].clips,
      hasLength(1),
      reason: 'undo brought it home',
    );
  });
}
