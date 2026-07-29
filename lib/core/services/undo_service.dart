// lib/core/services/undo_service.dart
//
// WS-W4 — one undo history.
//
// Three surfaces, three private stacks: `DawService` snapshots its timeline,
// `LoopStack` holds loop state, the tracker screen keeps its own block history.
// None of them can show you what you did in another surface, and none of them
// has a LABEL — so "undo" is a step into the dark even within one surface.
//
// WHAT THIS DOES NOT DO: replace the snapshot mechanisms. They are proven, and
// re-implementing capture/restore for four document types would be a rewrite
// wearing a refactor's clothes. A surface keeps capturing exactly as it does
// today and hands this service a pair of closures plus a name. This owns the
// STACK and the ORDER; the surfaces keep owning their state.
//
// SCOPE vs ORDER, which sound contradictory in the card and are not:
//   • The history is ONE ordered list, so the Audio Editor can show what you
//     just did in Loop Studio. That is the visible half of the feature.
//   • [undo] takes the most recent entry regardless of scope, because that is
//     what a user pressing Cmd-Z means.
//   • [undoScope] takes the most recent entry OF ONE SCOPE, so a surface that
//     wants "undo my last edit" cannot silently rewind another surface's
//     unrelated work. Both exist because both are real requests.
//
// COALESCING is first-class, not an afterthought: a 200-frame clip drag is one
// edit to a user and 200 entries to a naive stack. `DawService` already solved
// this with a token; the same idea lives here so every surface inherits it.

import 'package:flutter/foundation.dart';

/// One reversible edit.
@immutable
class UndoEntry {
  const UndoEntry({
    required this.label,
    required this.undo,
    required this.redo,
    this.scope,
    this.coalesceKey,
  });

  /// What the user did, in their words — "Move clip", "Add track". The whole
  /// reason the history is worth showing rather than just stepping through.
  final String label;

  /// Restores the state from before the edit, and its inverse.
  ///
  /// Closures rather than snapshots: each surface already knows how to capture
  /// and restore its own document, and none of them capture the same way.
  final VoidCallback undo;
  final VoidCallback redo;

  /// Which surface or track this belongs to. Null means project-wide.
  final String? scope;

  /// Consecutive entries sharing a non-null key collapse into one — a drag is
  /// one edit. The FIRST entry's undo is kept (it restores the state from
  /// before the whole gesture) and the LAST entry's redo (it reproduces the
  /// final result), which is what makes a coalesced run reversible in one step.
  final Object? coalesceKey;

  UndoEntry _mergedWith(UndoEntry later) => UndoEntry(
        label: later.label,
        undo: undo,
        redo: later.redo,
        scope: scope,
        coalesceKey: coalesceKey,
      );
}

/// The shared, labelled, cross-surface undo history.
class UndoService extends ChangeNotifier {
  UndoService({this.maxEntries = 50}) : assert(maxEntries > 0);

  /// Matches `DawService._maxUndo`, so folding that stack in changes no
  /// behaviour the user can observe.
  final int maxEntries;

  final List<UndoEntry> _past = [];
  final List<UndoEntry> _future = [];

  /// Oldest first — the order a history panel lists them in.
  List<UndoEntry> get history => List.unmodifiable(_past);

  /// Labels of what would be undone / redone next, for a menu item that can say
  /// "Undo Move clip" rather than "Undo".
  String? get nextUndoLabel => _past.isEmpty ? null : _past.last.label;
  String? get nextRedoLabel => _future.isEmpty ? null : _future.last.label;

  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;

  bool canUndoScope(String scope) => _past.any((e) => e.scope == scope);

  /// Records an edit that has ALREADY happened.
  ///
  /// Push-after-doing, not do-through-the-service: every surface here performs
  /// its edit directly and eagerly, and forcing them through a command object
  /// would mean rewriting all three. This meets them where they are.
  void push(UndoEntry entry) {
    // A new edit invalidates the redo branch — the standard rule, and the one
    // every existing stack here already follows.
    _future.clear();

    final last = _past.isNotEmpty ? _past.last : null;
    if (last != null &&
        entry.coalesceKey != null &&
        last.coalesceKey == entry.coalesceKey &&
        last.scope == entry.scope) {
      _past[_past.length - 1] = last._mergedWith(entry);
      notifyListeners();
      return;
    }

    _past.add(entry);
    if (_past.length > maxEntries) _past.removeAt(0);
    notifyListeners();
  }

  /// Ends any coalescing run, so the next edit starts a new entry.
  ///
  /// Call it when a gesture ends. Without it a second drag of the same clip
  /// would merge into the first and the two become one undo.
  void breakCoalescing() {
    if (_past.isEmpty) return;
    final last = _past.last;
    if (last.coalesceKey == null) return;
    _past[_past.length - 1] = UndoEntry(
      label: last.label,
      undo: last.undo,
      redo: last.redo,
      scope: last.scope,
    );
  }

  /// Undoes the most recent edit in ANY surface — what Cmd-Z means.
  void undo() {
    if (_past.isEmpty) return;
    final entry = _past.removeLast();
    entry.undo();
    _future.add(entry);
    notifyListeners();
  }

  /// Undoes the most recent edit **of one scope**, leaving other surfaces'
  /// work where it is.
  ///
  /// Returns whether anything was undone, so a caller can fall back or beep
  /// rather than assume.
  bool undoScope(String scope) {
    final index = _past.lastIndexWhere((e) => e.scope == scope);
    if (index < 0) return false;
    final entry = _past.removeAt(index);
    entry.undo();
    _future.add(entry);
    notifyListeners();
    return true;
  }

  void redo() {
    if (_future.isEmpty) return;
    final entry = _future.removeLast();
    entry.redo();
    _past.add(entry);
    notifyListeners();
  }

  /// Whether one scope has anything to redo.
  ///
  /// ⚠️ Added by @daw-suite during the Audio Editor fold-in: the service scoped
  /// UNDO but not redo, and a surface needs both or its redo button offers to
  /// replay another surface's edit — the exact thing `undoScope` exists to
  /// prevent, in the other direction.
  bool canRedoScope(String scope) => _future.any((e) => e.scope == scope);

  /// Redoes the most recent undone edit **of one scope**.
  ///
  /// Returns whether anything was redone, mirroring [undoScope].
  bool redoScope(String scope) {
    final index = _future.lastIndexWhere((e) => e.scope == scope);
    if (index < 0) return false;
    final entry = _future.removeAt(index);
    entry.redo();
    _past.add(entry);
    notifyListeners();
    return true;
  }

  /// Forgets everything — opening a different project, not an edit.
  void clear() {
    if (_past.isEmpty && _future.isEmpty) return;
    _past.clear();
    _future.clear();
    notifyListeners();
  }

  /// Drops one scope's entries without touching the others.
  ///
  /// For closing a surface: its closures capture state that is going away, and
  /// running them afterwards would restore into nothing.
  void clearScope(String scope) {
    final before = _past.length + _future.length;
    _past.removeWhere((e) => e.scope == scope);
    _future.removeWhere((e) => e.scope == scope);
    if (_past.length + _future.length != before) notifyListeners();
  }
}
