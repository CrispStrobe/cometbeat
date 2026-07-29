// WS-W4 — the Audio Editor's edits join one cross-surface history.
//
// The card's instruction was to change **who owns the stack**, not how state is
// captured: `_capture`/`_restore` are proven and re-implementing them would be
// "a rewrite wearing a refactor's clothes". So the strongest evidence this
// fold-in is correct is not in this file at all — it is that every existing DAW
// undo test passes UNCHANGED, and none of them were touched.
//
// What IS new, and what these cover: a shared history, scoping (so the Audio
// Editor's undo button cannot rewind another surface's work), and labels (the
// reason a history is worth showing rather than just stepping through).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/core/services/undo_service.dart';
import 'package:flutter_test/flutter_test.dart';

DawService _daw({UndoService? history}) =>
    DawService(history: history)..addClip(SampleSource(Float64List(4410)));

void main() {
  group('by default nothing changes', () {
    test('a service with no history given keeps a private one', () {
      // Every existing caller constructs `DawService()`, so this is the path
      // almost all of the app takes.
      final a = _daw();
      final b = _daw();
      expect(a.canUndo, isTrue);
      a.undo();
      expect(a.canUndo, isFalse);
      expect(b.canUndo, isTrue, reason: 'b has its own stack');
    });

    test('undo still restores, which is the whole mechanism', () {
      final daw = _daw();
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.moveClip(track, 0, 2000);
      daw.endCoalescedEdit();
      expect(daw.clipStartMs(track, 0), 2000);
      daw.undo();
      expect(daw.clipStartMs(track, 0), isNot(2000));
    });
  });

  group('a shared history', () {
    test('the edit lands in it, with a label', () {
      // The point of the card: a history worth SHOWING. "Edit" everywhere would
      // technically satisfy a list and tell a user nothing.
      final history = UndoService();
      final daw = _daw(history: history);
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.moveClip(track, 0, 1500);
      daw.endCoalescedEdit();

      expect(history.history, isNotEmpty);
      expect(
        history.history.map((e) => e.label),
        contains('Move clip'),
        reason: 'the label should say what was done',
      );
      expect(
        history.history.every((e) => e.scope == DawService.kUndoScope),
        isTrue,
      );
    });

    test('a drag is ONE entry, not one per frame', () {
      // The coalescing the DAW already did, now expressed in the shared stack.
      final history = UndoService();
      final daw = _daw(history: history);
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      final before = history.history.length;
      for (var ms = 100.0; ms < 2000; ms += 100) {
        daw.moveClip(track, 0, ms);
      }
      daw.endCoalescedEdit();
      expect(history.history.length - before, 1);
    });

    test('two surfaces share one ordered list', () {
      // What "one history" buys: the Audio Editor can show what you just did
      // elsewhere.
      final history = UndoService();
      final daw = _daw(history: history);
      history.push(
        UndoEntry(
          label: 'Loop: add track',
          scope: 'loop',
          undo: () {},
          redo: () {},
        ),
      );
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.moveClip(track, 0, 900);
      daw.endCoalescedEdit();

      expect(
        history.history.map((e) => e.scope),
        containsAll(<String?>['loop', DawService.kUndoScope]),
      );
    });
  });

  group('scoping — the property that makes sharing safe', () {
    test("the DAW's undo does NOT rewind another surface's edit", () {
      // The failure this prevents: pressing undo in the Audio Editor silently
      // undoes something you did in Loop Studio, which you may not even be
      // looking at.
      final history = UndoService();
      final daw = _daw(history: history);
      var loopUndone = false;
      history.push(
        UndoEntry(
          label: 'Loop: add track',
          scope: 'loop',
          undo: () => loopUndone = true,
          redo: () {},
        ),
      );

      daw.undo();
      expect(loopUndone, isFalse, reason: 'the loop edit was left alone');
    });

    test('canUndo reports THIS surface, not the whole history', () {
      // Otherwise the Audio Editor's undo button lights up for work it cannot
      // undo, and pressing it does nothing.
      final history = UndoService();
      final daw = DawService(history: history);
      expect(daw.canUndo, isFalse, reason: 'this surface has done nothing');

      history.push(
        UndoEntry(
          label: 'Loop: something',
          scope: 'loop',
          undo: () {},
          redo: () {},
        ),
      );
      expect(history.canUndo, isTrue, reason: 'the history has an entry');
      expect(daw.canUndo, isFalse, reason: 'but not one of ours');
    });

    test('redo is scoped too — the asymmetry I had to close', () {
      // `UndoService` scoped undo but not redo. Without the mirror, the Audio
      // Editor's redo button would replay another surface's edit: the exact
      // thing undoScope prevents, in the other direction.
      final history = UndoService();
      final daw = _daw(history: history);
      var loopRedone = false;
      history.push(
        UndoEntry(
          label: 'Loop: add track',
          scope: 'loop',
          undo: () {},
          redo: () => loopRedone = true,
        ),
      );
      history.undoScope('loop'); // now on the redo side

      expect(daw.canRedo, isFalse, reason: 'not ours to redo');
      daw.redo();
      expect(loopRedone, isFalse);
    });

    test('the DAW can still redo its OWN edit', () {
      final history = UndoService();
      final daw = _daw(history: history);
      final track = daw.timeline.tracks.indexWhere((t) => t.clips.isNotEmpty);
      daw.moveClip(track, 0, 1200);
      daw.endCoalescedEdit();

      daw.undo();
      expect(daw.clipStartMs(track, 0), isNot(1200));
      expect(daw.canRedo, isTrue);
      daw.redo();
      expect(daw.clipStartMs(track, 0), 1200);
    });
  });

  group('opening a project', () {
    test('it clears only THIS surface from a shared history', () {
      // Its closures captured state that is going away; running them afterwards
      // would restore into nothing. But another surface's entries are still
      // perfectly good.
      final history = UndoService();
      final daw = _daw(history: history);
      history.push(
        UndoEntry(
          label: 'Loop: keep me',
          scope: 'loop',
          undo: () {},
          redo: () {},
        ),
      );
      daw.loadProject(daw.saveProject());

      expect(daw.canUndo, isFalse, reason: 'ours went');
      expect(
        history.history.map((e) => e.label),
        contains('Loop: keep me'),
        reason: "the other surface's history survived",
      );
    });
  });
}
