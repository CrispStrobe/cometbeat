// WS-W4 — one undo history.
//
// The card's acceptance is worded at the screen level ("an edit made in Loop
// Studio is undoable from the Audio Editor's history list, and the label says
// what it was"). No screen has been migrated yet, so the guarantee is proven
// here with two adapters standing for two surfaces sharing one history. The
// screen-level assertion lands with the migrations; this is the mechanism it
// will rest on.

import 'package:comet_beat/core/services/undo_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for a surface: owns a value, edits it, and records how to put it
/// back — exactly the shape `DawService`'s snapshot/restore already has.
class _Surface {
  _Surface(this.scope, this.undoService);

  final String scope;
  final UndoService undoService;
  int value = 0;

  void edit(int to, {required String label, Object? coalesceKey}) {
    final from = value;
    value = to;
    undoService.push(
      UndoEntry(
        label: label,
        scope: scope,
        coalesceKey: coalesceKey,
        undo: () => value = from,
        redo: () => value = to,
      ),
    );
  }
}

void main() {
  group('the cross-surface guarantee', () {
    test('an edit in one surface is undoable from the other, WITH its label',
        () {
      final undo = UndoService();
      final loop = _Surface('loop', undo);
      final audio = _Surface('audio', undo);

      loop.edit(7, label: 'Add a track');
      audio.edit(3, label: 'Move clip');

      // The Audio Editor's history panel can SEE what happened in Loop Studio —
      // the visible half of the feature, and the half three private stacks
      // could never provide.
      expect(undo.history.map((e) => e.label), ['Add a track', 'Move clip']);
      expect(undo.history.map((e) => e.scope), ['loop', 'audio']);

      // And a plain Cmd-Z from either surface walks the shared order back.
      expect(undo.nextUndoLabel, 'Move clip');
      undo.undo();
      expect(audio.value, 0);

      expect(undo.nextUndoLabel, 'Add a track');
      undo.undo();
      expect(
        loop.value,
        0,
        reason: 'the Audio Editor undid the Loop Studio edit',
      );
    });

    test('scoped undo does not rewind another surface', () {
      // The card's other half: "an undo in one surface cannot silently rewind
      // another's unrelated work."
      final undo = UndoService();
      final loop = _Surface('loop', undo);
      final audio = _Surface('audio', undo);

      loop.edit(7, label: 'Add a track');
      audio.edit(3, label: 'Move clip');

      expect(undo.undoScope('loop'), isTrue);
      expect(loop.value, 0);
      expect(audio.value, 3, reason: 'the Audio Editor edit stands');
    });

    test('scoped undo reports when there is nothing of that scope', () {
      final undo = UndoService();
      _Surface('loop', undo).edit(1, label: 'Add a track');
      expect(undo.undoScope('audio'), isFalse);
      expect(undo.canUndoScope('audio'), isFalse);
      expect(undo.canUndoScope('loop'), isTrue);
    });
  });

  group('ordinary stack behaviour', () {
    test('undo then redo restores the value and the order', () {
      final undo = UndoService();
      final s = _Surface('a', undo);

      s.edit(1, label: 'one');
      s.edit(2, label: 'two');
      undo.undo();
      expect(s.value, 1);
      expect(undo.nextRedoLabel, 'two');

      undo.redo();
      expect(s.value, 2);
      expect(undo.canRedo, isFalse);
    });

    test('a new edit invalidates the redo branch', () {
      final undo = UndoService();
      final s = _Surface('a', undo);

      s.edit(1, label: 'one');
      s.edit(2, label: 'two');
      undo.undo();
      expect(undo.canRedo, isTrue);

      s.edit(9, label: 'three');
      expect(undo.canRedo, isFalse);
    });

    test('undo and redo on an empty history are no-ops, not errors', () {
      final undo = UndoService();
      undo.undo();
      undo.redo();
      expect(undo.canUndo, isFalse);
      expect(undo.canRedo, isFalse);
    });

    test('the history is bounded, oldest dropped first', () {
      final undo = UndoService(maxEntries: 3);
      final s = _Surface('a', undo);
      for (var i = 1; i <= 5; i++) {
        s.edit(i, label: 'edit $i');
      }
      expect(undo.history.map((e) => e.label), ['edit 3', 'edit 4', 'edit 5']);
    });

    test('history is unmodifiable — a panel cannot corrupt the stack', () {
      final undo = UndoService();
      _Surface('a', undo).edit(1, label: 'one');
      expect(
        () => undo.history.clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('coalescing', () {
    test('a drag is ONE undo, and it goes all the way back', () {
      // 200 frames of a clip drag is one edit to a user. Without this the
      // shared stack would be 200 entries deep and Cmd-Z would nudge.
      final undo = UndoService();
      final s = _Surface('audio', undo);

      for (var x = 1; x <= 20; x++) {
        s.edit(x, label: 'Move clip', coalesceKey: 'drag-clip-3');
      }

      expect(undo.history.length, 1);
      expect(s.value, 20);

      undo.undo();
      expect(
        s.value,
        0,
        reason: 'the FIRST undo of the run is kept, so it reverses the whole '
            'gesture rather than one frame of it',
      );

      undo.redo();
      expect(s.value, 20, reason: 'and the LAST redo reproduces the result');
    });

    test('breakCoalescing ends the run, so a second drag is a second undo', () {
      final undo = UndoService();
      final s = _Surface('audio', undo);

      s.edit(5, label: 'Move clip', coalesceKey: 'drag');
      undo.breakCoalescing();
      s.edit(9, label: 'Move clip', coalesceKey: 'drag');

      expect(undo.history.length, 2);
      undo.undo();
      expect(s.value, 5, reason: 'only the second drag came back');
    });

    test('different scopes never coalesce, even on the same key', () {
      // Two surfaces both calling their gesture "drag" must not merge.
      final undo = UndoService();
      final loop = _Surface('loop', undo);
      final audio = _Surface('audio', undo);

      loop.edit(1, label: 'Move', coalesceKey: 'drag');
      audio.edit(2, label: 'Move', coalesceKey: 'drag');

      expect(undo.history.length, 2);
    });

    test('a null coalesceKey never merges', () {
      final undo = UndoService();
      final s = _Surface('a', undo);
      s.edit(1, label: 'one');
      s.edit(2, label: 'two');
      expect(undo.history.length, 2);
    });

    test('a coalesced run counts as ONE against the bound', () {
      final undo = UndoService(maxEntries: 2);
      final s = _Surface('a', undo);
      for (var x = 1; x <= 10; x++) {
        s.edit(x, label: 'Move', coalesceKey: 'drag');
      }
      expect(undo.history.length, 1);
    });
  });

  group('lifecycle', () {
    test('clearScope drops one surface without touching the others', () {
      // Closing a surface: its closures capture state that is going away, and
      // running them afterwards would restore into nothing.
      final undo = UndoService();
      final loop = _Surface('loop', undo);
      final audio = _Surface('audio', undo);

      loop.edit(7, label: 'Add a track');
      audio.edit(3, label: 'Move clip');

      undo.clearScope('loop');
      expect(undo.history.map((e) => e.label), ['Move clip']);

      undo.undo();
      expect(audio.value, 0);
      expect(loop.value, 7, reason: 'the closed surface edit was not run');
    });

    test('clear forgets both directions', () {
      final undo = UndoService();
      final s = _Surface('a', undo);
      s.edit(1, label: 'one');
      undo.undo();
      undo.clear();
      expect(undo.canUndo, isFalse);
      expect(undo.canRedo, isFalse);
    });

    test('every mutation notifies, and a no-op does not', () {
      final undo = UndoService();
      var notifications = 0;
      undo.addListener(() => notifications++);

      undo.undo();
      undo.redo();
      undo.clear();
      expect(notifications, 0, reason: 'nothing changed');

      _Surface('a', undo).edit(1, label: 'one');
      expect(notifications, 1);

      undo.undo();
      expect(notifications, 2);
    });

    test('clearScope on an unknown scope does not notify', () {
      final undo = UndoService();
      _Surface('a', undo).edit(1, label: 'one');
      var notifications = 0;
      undo.addListener(() => notifications++);
      undo.clearScope('nobody');
      expect(notifications, 0);
    });
  });
}
