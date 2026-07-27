// D2 — linked clips, and moving by a known amount.
//
// Grouping exists for the case where two clips ARE one musical event recorded
// twice — a DI and a mic on the same take, a kick and its sub. Sliding one
// without the other silently ruins the phase relationship that made them worth
// keeping together, and "silently" is the problem: the mix just sounds worse
// later. So the tests are about the link HOLDING through every way a clip can
// move, and about ungrouped clips being completely unaffected.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_project.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:flutter_test/flutter_test.dart';

void _addClip(DawService daw, int track, double startMs) {
  daw.addClip(SampleSource(Float64List(kDawSampleRate)), track: track);
  daw.moveClip(track, daw.timeline.tracks[track].clips.length - 1, startMs);
}

double _startOf(DawService daw, int track, int index) =>
    daw.timeline.tracks[track].clips[index].startMs;

void main() {
  group('grouping links clips', () {
    test('moving one member carries the others by the same delta', () {
      final daw = DawService();
      _addClip(daw, 0, 1000);
      _addClip(daw, 1, 1000);
      daw.groupClips([(track: 0, index: 0), (track: 1, index: 0)]);

      daw.moveClip(0, 0, 3000);

      expect(_startOf(daw, 0, 0), 3000);
      expect(_startOf(daw, 1, 0), 3000);
    });

    test('the DELTA is what travels, not the position', () {
      // Members do not need to start together — a mic further from the source
      // legitimately sits later — and flattening them onto one start would
      // destroy exactly the relationship grouping exists to protect.
      final daw = DawService();
      _addClip(daw, 0, 1000);
      _addClip(daw, 1, 1200);
      daw.groupClips([(track: 0, index: 0), (track: 1, index: 0)]);

      daw.moveClip(0, 0, 2000);

      expect(_startOf(daw, 0, 0), 2000);
      expect(_startOf(daw, 1, 0), 2200);
    });

    test('an UNGROUPED clip is entirely unaffected', () {
      final daw = DawService();
      _addClip(daw, 0, 1000);
      _addClip(daw, 1, 1000);
      daw.moveClip(0, 0, 5000);
      expect(_startOf(daw, 1, 0), 1000);
    });

    test('ungrouping breaks the link', () {
      final daw = DawService();
      _addClip(daw, 0, 1000);
      _addClip(daw, 1, 1000);
      daw.groupClips([(track: 0, index: 0), (track: 1, index: 0)]);
      daw.ungroupClips([(track: 0, index: 0)]);

      daw.moveClip(0, 0, 4000);

      expect(_startOf(daw, 1, 0), 1000);
    });

    test('ungrouping one member frees the WHOLE group', () {
      // A group with one member left is not a group; leaving the others linked
      // to each other would be a surprise nobody asked for.
      final daw = DawService();
      _addClip(daw, 0, 0);
      _addClip(daw, 1, 0);
      _addClip(daw, 2, 0);
      daw.groupClips([
        (track: 0, index: 0),
        (track: 1, index: 0),
        (track: 2, index: 0),
      ]);
      daw.ungroupClips([(track: 0, index: 0)]);

      daw.moveClip(1, 0, 2000);
      expect(_startOf(daw, 2, 0), 0);
    });

    test('a group of one is not a group', () {
      final daw = DawService();
      _addClip(daw, 0, 0);
      expect(daw.groupClips([(track: 0, index: 0)]), -1);
      expect(daw.timeline.tracks[0].clips.first.groupId, isNull);
    });

    test('grouping is undoable', () {
      final daw = DawService();
      _addClip(daw, 0, 1000);
      _addClip(daw, 1, 1000);
      daw.groupClips([(track: 0, index: 0), (track: 1, index: 0)]);
      daw.undo();
      daw.moveClip(0, 0, 4000);
      expect(_startOf(daw, 1, 0), 1000);
    });

    test('a member cannot be pushed before zero', () {
      final daw = DawService();
      _addClip(daw, 0, 2000);
      _addClip(daw, 1, 100);
      daw.groupClips([(track: 0, index: 0), (track: 1, index: 0)]);

      daw.moveClip(0, 0, 0);

      expect(_startOf(daw, 0, 0), 0);
      expect(_startOf(daw, 1, 0), 0);
    });
  });

  group('nudge', () {
    test('it shifts by exactly the amount asked for', () {
      // The point of nudging over dragging: a drag lands where the finger
      // lands, a nudge lands where you said.
      final daw = DawService();
      _addClip(daw, 0, 1000);
      daw.nudgeClips([(track: 0, index: 0)], 25);
      expect(_startOf(daw, 0, 0), 1025);
      daw.nudgeClips([(track: 0, index: 0)], -50);
      expect(_startOf(daw, 0, 0), 975);
    });

    test('snapping does NOT re-grid it', () {
      // A nudge is for the case where the grid is not where you want to be, so
      // snapping it back would defeat the verb entirely.
      final daw = DawService()
        ..setBpm(120)
        ..toggleSnap();
      _addClip(daw, 0, 1000);
      daw.nudgeClips([(track: 0, index: 0)], 30);
      expect(_startOf(daw, 0, 0), 1030);
    });

    test('it clamps at zero rather than going negative', () {
      final daw = DawService();
      _addClip(daw, 0, 10);
      daw.nudgeClips([(track: 0, index: 0)], -500);
      expect(_startOf(daw, 0, 0), 0);
    });

    test('it moves a whole group', () {
      final daw = DawService();
      _addClip(daw, 0, 1000);
      _addClip(daw, 1, 1000);
      daw.groupClips([(track: 0, index: 0), (track: 1, index: 0)]);
      daw.nudgeClips([(track: 0, index: 0)], 40);
      expect(_startOf(daw, 0, 0), 1040);
      expect(_startOf(daw, 1, 0), 1040);
    });

    test('nudging two members of one group moves it ONCE', () {
      // The obvious bug: collecting members per target and moving each time
      // would double the shift for a group whose members are both selected.
      final daw = DawService();
      _addClip(daw, 0, 1000);
      _addClip(daw, 1, 1000);
      daw.groupClips([(track: 0, index: 0), (track: 1, index: 0)]);
      daw.nudgeClips([(track: 0, index: 0), (track: 1, index: 0)], 40);
      expect(_startOf(daw, 0, 0), 1040);
      expect(_startOf(daw, 1, 0), 1040);
    });

    test('it is undoable, and a zero nudge costs no undo step', () {
      // Asserted by what the undo actually restores rather than by canUndo,
      // which is already true from placing the clip: if the no-op had recorded
      // a snapshot, this undo would be consumed by it and stop at 1100.
      final daw = DawService();
      _addClip(daw, 0, 1000);
      daw.nudgeClips([(track: 0, index: 0)], 100);
      expect(_startOf(daw, 0, 0), 1100);

      daw.nudgeClips([(track: 0, index: 0)], 0);
      expect(_startOf(daw, 0, 0), 1100);

      daw.undo();
      expect(_startOf(daw, 0, 0), 1000);
    });
  });

  group('persistence', () {
    test('a group survives save and reload', () {
      final daw = DawService();
      _addClip(daw, 0, 1000);
      _addClip(daw, 1, 1000);
      daw.groupClips([(track: 0, index: 0), (track: 1, index: 0)]);
      final saved = daw.saveProject();

      final reopened = DawService()..loadProject(saved);
      reopened.moveClip(0, 0, 3000);
      expect(_startOf(reopened, 1, 0), 3000);
    });

    test('a new group after loading does not collide with a loaded one', () {
      // Group ids come from a counter; reopening a project whose ids run higher
      // than a fresh counter would silently link clips the user never linked.
      final daw = DawService();
      _addClip(daw, 0, 0);
      _addClip(daw, 1, 0);
      daw.groupClips([(track: 0, index: 0), (track: 1, index: 0)]);
      final saved = daw.saveProject();

      final reopened = DawService()..loadProject(saved);
      _addClip(reopened, 0, 5000);
      _addClip(reopened, 1, 5000);
      final second = reopened.groupClips([
        (track: 0, index: 1),
        (track: 1, index: 1),
      ]);
      final first = reopened.timeline.tracks[0].clips.first.groupId;
      expect(second, isNot(first));

      // And moving the new group leaves the old one alone.
      reopened.moveClip(0, 1, 8000);
      expect(_startOf(reopened, 0, 0), 0);
    });

    test('an ungrouped clip writes no group key', () {
      final timeline = DawTimeline(
        tracks: [
          DawTrack(clips: [Clip(source: SampleSource(Float64List(100)))]),
        ],
      );
      expect(projectToJson(timeline).contains('groupId'), isFalse);
    });
  });
}
