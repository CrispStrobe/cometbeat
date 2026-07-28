// WS-T3 — what a key press MEANS, named once for the whole app.
//
// The tracker had 33 keyboard sites, the Audio Editor 4, and Loop Studio none —
// not even space-to-play. The bindings were not the problem; the problem was
// that they were expressed as `if (key == LogicalKeyboardKey.f5)` inside one
// screen's private method, so no other surface could reach them and no user
// could see or change them.
//
// An intent is the verb, not the key. Screens implement the verbs they have and
// ignore the rest, which is what lets three very different surfaces share one
// table: the Audio Editor has no concept of a pattern row, and does not need to
// know that `rowInsert` exists.

/// A named editing or transport action a key press can request.
///
/// ⚠️ These names are stored: a user's rebindings are persisted by name, so
/// **append, never rename or reorder**. A renamed intent silently drops
/// whatever the user had bound to it.
enum AppIntent {
  // ── Transport ────────────────────────────────────────────────────────────
  /// Play/stop — the one binding every surface should have.
  transportToggle,
  transportPlaySong,
  transportPlayPattern,
  transportPlayFromCursor,
  transportStop,

  // ── Cursor ───────────────────────────────────────────────────────────────
  cursorUp,
  cursorDown,
  cursorLeft,
  cursorRight,

  /// Same four, extending the selection rather than moving.
  selectUp,
  selectDown,
  selectLeft,
  selectRight,

  // ── Selection ────────────────────────────────────────────────────────────
  selectAll,
  selectNone,

  // ── Clipboard and editing ────────────────────────────────────────────────
  clipCopy,
  clipCut,
  clipPaste,
  clipPasteMix,
  editDelete,
  editUndo,
  editRedo,
  editInterpolate,

  // ── Pattern structure (tracker-shaped; other surfaces ignore these) ──────
  rowInsert,
  rowDelete,

  // ── Pitch ────────────────────────────────────────────────────────────────
  transposeUp,
  transposeDown,
  transposeOctaveUp,
  transposeOctaveDown,
  octaveUp,
  octaveDown,
}

/// A short label for the keymap sheet — an unlisted shortcut does not exist.
String appIntentLabel(AppIntent intent) => switch (intent) {
      AppIntent.transportToggle => 'Play / stop',
      AppIntent.transportPlaySong => 'Play song',
      AppIntent.transportPlayPattern => 'Play pattern',
      AppIntent.transportPlayFromCursor => 'Play from cursor',
      AppIntent.transportStop => 'Stop',
      AppIntent.cursorUp => 'Move up',
      AppIntent.cursorDown => 'Move down',
      AppIntent.cursorLeft => 'Move left',
      AppIntent.cursorRight => 'Move right',
      AppIntent.selectUp => 'Extend selection up',
      AppIntent.selectDown => 'Extend selection down',
      AppIntent.selectLeft => 'Extend selection left',
      AppIntent.selectRight => 'Extend selection right',
      AppIntent.selectAll => 'Select all',
      AppIntent.selectNone => 'Drop the selection',
      AppIntent.clipCopy => 'Copy',
      AppIntent.clipCut => 'Cut',
      AppIntent.clipPaste => 'Paste',
      AppIntent.clipPasteMix => 'Paste mixed',
      AppIntent.editDelete => 'Delete',
      AppIntent.editUndo => 'Undo',
      AppIntent.editRedo => 'Redo',
      AppIntent.editInterpolate => 'Interpolate',
      AppIntent.rowInsert => 'Insert a row',
      AppIntent.rowDelete => 'Delete the row',
      AppIntent.transposeUp => 'Transpose up a semitone',
      AppIntent.transposeDown => 'Transpose down a semitone',
      AppIntent.transposeOctaveUp => 'Transpose up an octave',
      AppIntent.transposeOctaveDown => 'Transpose down an octave',
      AppIntent.octaveUp => 'Octave up',
      AppIntent.octaveDown => 'Octave down',
    };

/// Which part of the sheet an intent belongs under.
enum AppIntentGroup { transport, cursor, selection, editing, pattern, pitch }

AppIntentGroup appIntentGroup(AppIntent intent) => switch (intent) {
      AppIntent.transportToggle ||
      AppIntent.transportPlaySong ||
      AppIntent.transportPlayPattern ||
      AppIntent.transportPlayFromCursor ||
      AppIntent.transportStop =>
        AppIntentGroup.transport,
      AppIntent.cursorUp ||
      AppIntent.cursorDown ||
      AppIntent.cursorLeft ||
      AppIntent.cursorRight =>
        AppIntentGroup.cursor,
      AppIntent.selectUp ||
      AppIntent.selectDown ||
      AppIntent.selectLeft ||
      AppIntent.selectRight ||
      AppIntent.selectAll ||
      AppIntent.selectNone =>
        AppIntentGroup.selection,
      AppIntent.clipCopy ||
      AppIntent.clipCut ||
      AppIntent.clipPaste ||
      AppIntent.clipPasteMix ||
      AppIntent.editDelete ||
      AppIntent.editUndo ||
      AppIntent.editRedo ||
      AppIntent.editInterpolate =>
        AppIntentGroup.editing,
      AppIntent.rowInsert || AppIntent.rowDelete => AppIntentGroup.pattern,
      AppIntent.transposeUp ||
      AppIntent.transposeDown ||
      AppIntent.transposeOctaveUp ||
      AppIntent.transposeOctaveDown ||
      AppIntent.octaveUp ||
      AppIntent.octaveDown =>
        AppIntentGroup.pitch,
    };

String appIntentGroupLabel(AppIntentGroup group) => switch (group) {
      AppIntentGroup.transport => 'Transport',
      AppIntentGroup.cursor => 'Moving around',
      AppIntentGroup.selection => 'Selecting',
      AppIntentGroup.editing => 'Editing',
      AppIntentGroup.pattern => 'Pattern',
      AppIntentGroup.pitch => 'Pitch',
    };
