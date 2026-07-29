// lib/shared/undo/undo_history_sheet.dart
//
// WS-W4, last clause — the history LIST.
//
// The card's acceptance is "an edit made in Loop Studio is undoable from the
// Audio Editor's history list AND THE LABEL SAYS WHAT IT WAS". The first half
// is done and tested on both real screens. The second half was not: two
// surfaces went to real trouble to produce good labels — the Audio Editor got
// them free from its `_coalesceToken` ("Move clip"), Loop Studio derives them by
// diffing groove snapshots ("Tempo 100 → 140") — and **nothing rendered them**.
// `UndoService.history` and `nextUndoLabel` had no viewer at all.
//
// That is this ladder's recurring shape one level up. The usual version is a
// method nobody calls; this is an *output* nobody reads, which is harder to
// notice because every test passes and the data really is correct.
//
// TAPPING A ROW REVERTS TO IT, and that is a deliberate product call rather
// than a fallout of the implementation:
//
//   * A history you cannot navigate is a LOG. The reason to show the list at
//     all is to get back to a known-good point in one gesture.
//   * Reverting past another surface's edit is unavoidable, not a design
//     choice: the history is ONE ordered list, and an entry's `undo` closure
//     assumes everything after it has already been undone. Skipping entries
//     would restore into a state they were never captured against.
//   * It is safe BECAUSE IT IS ITSELF REVERSIBLE — `redo` puts every step back,
//     exactly as long as no new edit has been made. So this needs no
//     confirmation dialog; what it needs is to be honest on screen about how
//     many edits a tap will take back, and whose they are. Hence the count on
//     each row and the surface name on every entry.
//
// WHAT IT DELIBERATELY DOES NOT SHOW: the redo branch as a list. `UndoService`
// exposes `history` (the past) and `nextRedoLabel`, but no accessor for the
// future queue — and adding one to a file two other agents are folding into,
// for a nice-to-have, is not worth the collision. A labelled Redo action
// satisfies "the label says what it was" for the one entry that matters.

import 'package:comet_beat/core/services/undo_service.dart';
import 'package:flutter/material.dart';

/// Human names for undo scopes, so a row can say "Loop Studio" and not "loop".
///
/// A REGISTRY rather than a map baked in here, following `project_codec.dart`:
/// a shared widget that hard-coded every surface's scope would have to be
/// edited by whoever adds the next one, and would sit in `shared/` importing
/// half the feature tree to reach their constants. Each surface registers its
/// own name instead.
///
/// A scope with no registered name falls back to the raw scope id, which is
/// ugly but never wrong — and cannot happen in practice for a live surface,
/// since a surface's entries only exist while it does (its `dispose` calls
/// `clearScope`), and it registers when it mounts.
final Map<String, String> _scopeNames = {};

void registerUndoScopeName(String scope, String name) {
  _scopeNames[scope] = name;
}

/// The display name for [scope], or a sensible fallback.
String undoScopeName(String? scope) {
  if (scope == null) return 'Project';
  return _scopeNames[scope] ?? scope;
}

/// Show the shared edit history.
///
/// Follows `keymap_sheet.dart`: a `show…` entry point plus a separate body
/// widget, so a test can pump the contents without pushing a route.
Future<void> showUndoHistorySheet(
  BuildContext context, {
  required UndoService history,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, controller) => UndoHistorySheetBody(
        history: history,
        controller: controller,
      ),
    ),
  );
}

/// The sheet's contents.
class UndoHistorySheetBody extends StatelessWidget {
  const UndoHistorySheetBody({
    required this.history,
    super.key,
    this.controller,
  });

  final UndoService history;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    // Rebuilt from the service, not from a snapshot taken when the sheet
    // opened: entries can arrive or vanish underneath it — another surface can
    // push while this is open, and a screen closing calls `clearScope`, which
    // removes rows. A stale list would offer taps that revert the wrong thing.
    return ListenableBuilder(
      listenable: history,
      builder: (context, _) {
        final theme = Theme.of(context);
        // Newest first: the thing you most likely want back is the last thing
        // you did, and it should not be at the bottom of a scroll.
        final entries = history.history.reversed.toList();
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('Edit history', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              entries.isEmpty
                  ? 'Nothing has been edited yet.'
                  : 'Tap an edit to undo it and everything after it. '
                      'Redo puts it back.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (history.canRedo)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('undo-history-redo'),
                  onPressed: history.redo,
                  icon: const Icon(Icons.redo),
                  // The label is the point of the whole card: "Redo" alone
                  // makes you press it to find out what it does.
                  label: Text('Redo ${history.nextRedoLabel}'),
                ),
              ),
            for (var i = 0; i < entries.length; i++)
              _EntryRow(
                entry: entries[i],
                // Row 0 is the newest, so it alone reverts one edit; the row
                // below it reverts two, and so on.
                steps: i + 1,
                onTap: () {
                  // Repeated global `undo()` walks the one ordered list in the
                  // order the closures were captured in — the only order they
                  // can safely be run in.
                  for (var n = 0; n < i + 1; n++) {
                    history.undo();
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.steps,
    required this.onTap,
  });

  final UndoEntry entry;
  final int steps;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: Key('undo-history-row-$steps'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(entry.label),
      // Which surface it came from. The whole reason the history is shared is
      // that it holds more than one, and a row that does not say which is a row
      // you cannot act on with any confidence.
      subtitle: Text(
        undoScopeName(entry.scope),
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        steps == 1 ? 'Undo' : 'Undo $steps',
        style: TextStyle(color: scheme.primary),
      ),
      onTap: onTap,
    );
  }
}
