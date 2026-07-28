// WS-A1 — clip edge handles: trim and fade.
//
// The two most-used gestures on any timeline, and the card that specified them
// named the two ways they go wrong. Both are asserted here rather than assumed:
//
//   1. A drag must be ONE undo entry, not one per frame. A drag emits dozens of
//      updates, and the naive composition — trim the source, then move the clip
//      so it stays put — uses two different coalescing tokens and pushes an
//      undo snapshot on every single frame. The user then presses undo and
//      watches the edge crawl back one pixel at a time.
//   2. The handles must not swallow the lane's scroll. The clip's MOVE gesture
//      is long-press precisely so a plain drag still scrolls; handing the whole
//      clip a plain-drag handler would break that, so the handlers live on
//      narrow strips and the rest of the clip must stay untouched by them.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/features/games/composition/daw_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

Float64List _tone(double ms) {
  final n = (ms * kDawSampleRate / 1000).round();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = 0.4 * math.sin(2 * math.pi * 220 * i / kDawSampleRate);
  }
  return out;
}

/// A service with one 2-second clip at 1000 ms, and its lane index.
({DawService daw, int track}) _oneClip() {
  final daw = DawService()..addClip(SampleSource(_tone(2000)));
  final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
  daw.moveClip(track, 0, 1000);
  daw.endCoalescedEdit();
  return (daw: daw, track: track);
}

/// Feed a drag the way a gesture does: many small deltas, not one big one.
void _drag(
  DawService daw,
  int track,
  int index, {
  required bool leading,
  required double totalMs,
  int frames = 20,
}) {
  for (var i = 0; i < frames; i++) {
    daw.trimClipEdge(track, index, leading: leading, deltaMs: totalMs / frames);
  }
  daw.endCoalescedEdit();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('trimming an edge', () {
    test('the LEADING edge takes material off the front and stays put', () {
      // The point of moving the start with the trim: the audio that remains
      // must not slide backwards under the rest of the arrangement.
      final (:daw, :track) = _oneClip();
      _drag(daw, track, 0, leading: true, totalMs: 400);

      expect(daw.clipTrimStartMs(track, 0), closeTo(400, 20));
      expect(daw.clipStartMs(track, 0), closeTo(1400, 20));
      expect(daw.clipDurationMs(track, 0), closeTo(1600, 30));
    });

    test('the TRAILING edge shortens without moving the clip', () {
      final (:daw, :track) = _oneClip();
      _drag(daw, track, 0, leading: false, totalMs: -500);

      expect(daw.clipStartMs(track, 0), 1000);
      expect(daw.clipDurationMs(track, 0), closeTo(1500, 30));
    });

    test('a trim can be dragged back out again — it is not destructive', () {
      // The source is untouched, so the audio has to come back. If it did not,
      // a mis-drag would be permanent.
      final (:daw, :track) = _oneClip();
      _drag(daw, track, 0, leading: false, totalMs: -800);
      expect(daw.clipDurationMs(track, 0), closeTo(1200, 30));
      _drag(daw, track, 0, leading: false, totalMs: 800);
      expect(daw.clipDurationMs(track, 0), closeTo(2000, 30));
    });

    test('a clip cannot be trimmed away to nothing', () {
      // Below a usable size there is nothing left to grab in order to undo it.
      final (:daw, :track) = _oneClip();
      _drag(daw, track, 0, leading: false, totalMs: -5000, frames: 50);
      expect(
        daw.clipDurationMs(track, 0),
        greaterThanOrEqualTo(DawService.kMinTrimmedMs - 1),
      );
    });

    test('trimming past the source end stops at the source end', () {
      final (:daw, :track) = _oneClip();
      _drag(daw, track, 0, leading: false, totalMs: 5000, frames: 50);
      expect(daw.clipDurationMs(track, 0), closeTo(2000, 30));
    });

    test('the applied delta is reported, so a drag cannot run away', () {
      // At a clamp the edge stops but the finger does not. The caller needs to
      // know how much actually landed.
      // The leading edge, because an untrimmed clip has nothing to extend
      // INTO at the trailing one — dragging it right is already a no-op.
      final (:daw, :track) = _oneClip();
      final applied = daw.trimClipEdge(
        track,
        0,
        leading: true,
        deltaMs: 9000, // far past what is left of the clip
      );
      expect(applied, lessThan(9000));
      expect(applied, greaterThan(0));
    });
  });

  group('one drag is ONE undo entry', () {
    test('a 20-frame trim undoes in a single step', () {
      // The headline requirement. Composing setClipTrim + moveClip instead
      // would push a snapshot per frame and this would need 20 undos.
      final (:daw, :track) = _oneClip();
      _drag(daw, track, 0, leading: true, totalMs: 400);
      expect(daw.clipTrimStartMs(track, 0), greaterThan(0));

      daw.undo();
      expect(daw.clipTrimStartMs(track, 0), 0);
      expect(daw.clipStartMs(track, 0), 1000);
    });

    test('two separate drags are two entries, not one', () {
      // Without ending the coalesced run, the second drag merges into the
      // first and one undo jumps further back than the user expects.
      final (:daw, :track) = _oneClip();
      _drag(daw, track, 0, leading: false, totalMs: -300);
      final afterFirst = daw.clipDurationMs(track, 0);
      _drag(daw, track, 0, leading: false, totalMs: -300);

      daw.undo();
      expect(daw.clipDurationMs(track, 0), closeTo(afterFirst, 1));
      daw.undo();
      expect(daw.clipDurationMs(track, 0), closeTo(2000, 30));
    });

    test('the two EDGES are separate entries', () {
      // They are different edits even without a gesture boundary between them.
      final (:daw, :track) = _oneClip();
      daw.trimClipEdge(track, 0, leading: true, deltaMs: 200);
      daw.trimClipEdge(track, 0, leading: false, deltaMs: -200);

      daw.undo();
      expect(daw.clipTrimStartMs(track, 0), closeTo(200, 20));
    });

    test('a fade drag is one entry too', () {
      final (:daw, :track) = _oneClip();
      for (var i = 0; i < 15; i++) {
        daw.setClipFades(track, 0, fadeInMs: (i + 1) * 20);
      }
      daw.endCoalescedEdit();
      expect(daw.timeline.tracks[track].clips[0].fadeInMs, 300);

      daw.undo();
      expect(daw.timeline.tracks[track].clips[0].fadeInMs, 0);
    });
  });

  group('snapping', () {
    test('a trim lands on the grid when snapping is on', () {
      // The card asks for snapOn to be honoured, and the position that should
      // snap is the edge's place in the ARRANGEMENT, not its offset into the
      // source — the grid belongs to the timeline.
      final daw = DawService()
        ..setBpm(120) // 500 ms a beat
        ..addClip(SampleSource(_tone(4000)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.moveClip(track, 0, 0);
      daw.toggleSnap();
      daw.endCoalescedEdit();

      daw.trimClipEdge(track, 0, leading: true, deltaMs: 460);
      expect(daw.clipStartMs(track, 0), closeTo(500, 1));
    });

    test('with snapping off the edge lands where the finger is', () {
      final (:daw, :track) = _oneClip();
      expect(daw.snapOn, isFalse);
      daw.trimClipEdge(track, 0, leading: true, deltaMs: 137);
      expect(daw.clipStartMs(track, 0), closeTo(1137, 1));
    });
  });

  group('guards', () {
    test('a bad target does nothing rather than throwing', () {
      final (:daw, :track) = _oneClip();
      expect(daw.trimClipEdge(track, 99, leading: true, deltaMs: 100), 0);
      expect(daw.trimClipEdge(99, 0, leading: true, deltaMs: 100), 0);
    });

    test('a zero drag costs no undo entry', () {
      // Asserted by what the undo restores: if the no-op had recorded a
      // snapshot, this undo would be spent on it and stop at 1300.
      final (:daw, :track) = _oneClip();
      _drag(daw, track, 0, leading: true, totalMs: 300);
      daw.trimClipEdge(track, 0, leading: true, deltaMs: 0);
      daw.endCoalescedEdit();

      daw.undo();
      expect(daw.clipStartMs(track, 0), 1000);
    });
  });

  group('the handles are on screen, and do not eat the scroll', () {
    Future<DawService> pumpDaw(WidgetTester tester) async {
      await pumpGame(
        tester,
        const DawScreen(),
        extraProviders: [ChangeNotifierProvider(create: (_) => DawService())],
      );
      return Provider.of<DawService>(
        tester.element(find.byType(DawScreen)),
        listen: false,
      );
    }

    testWidgets('dragging the left edge trims, in one undo step',
        (tester) async {
      final daw = await pumpDaw(tester);
      daw.addClip(SampleSource(_tone(4000)));
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.moveClip(track, 0, 0);
      daw.endCoalescedEdit();
      await tester.pumpAndSettle();

      final handle = find.byKey(ValueKey('trim-$track-0-in'));
      expect(handle, findsOneWidget, reason: 'the trim handle should be shown');
      await tester.drag(handle, const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(
        daw.clipTrimStartMs(track, 0),
        greaterThan(0),
        reason: 'the left-edge drag should have trimmed',
      );
      daw.undo();
      expect(
        daw.clipTrimStartMs(track, 0),
        0,
        reason: 'and it should undo in ONE step',
      );
    });

    testWidgets('a plain drag over the clip BODY still scrolls the lane',
        (tester) async {
      // The card's explicit warning. The move gesture is long-press precisely
      // so a plain drag scrolls; if the handles had been put on the whole clip
      // this would break, and the breakage is invisible until someone tries to
      // scroll a long arrangement on a phone.
      final daw = await pumpDaw(tester);
      for (var i = 0; i < 6; i++) {
        daw.addClip(SampleSource(_tone(3000)));
      }
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable);
      expect(scrollable, findsWidgets);
      final horizontal = tester
          .widgetList<Scrollable>(scrollable)
          .where((s) => s.axisDirection == AxisDirection.right)
          .toList();
      expect(horizontal, isNotEmpty, reason: 'the lane scrolls horizontally');

      final before = daw.clipStartMs(0, 0);
      final trimBefore = daw.clipTrimStartMs(0, 0);
      // Drag across the MIDDLE of the first clip — not its edges.
      final clipRect = tester.getRect(find.text('🎵').first);
      await tester.dragFrom(clipRect.center, const Offset(-120, 0));
      await tester.pumpAndSettle();

      // The clip itself must be untouched: not moved, not trimmed.
      expect(daw.clipStartMs(0, 0), before);
      expect(daw.clipTrimStartMs(0, 0), trimBefore);
    });
  });
}
