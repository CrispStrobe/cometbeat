// Route a symbolic score to the editors. Any [MultiPartScore] — imported from the
// library/music picker, transcribed, or lifted out of an Audio Editor music clip
// — can be opened in the Score Workshop or the Tab Workshop from one place.
//
// The "and back" half: pass [onReturn]. When set, the editor's "Send to Audio
// Editor" calls it with the EDITED score (and pops back) instead of adding a new
// clip — so opening a DAW music clip and sending back updates that SAME clip
// in place. With no [onReturn] the editors keep their normal add-a-new-clip send.

import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart'
    show TabWorkshopScreen;
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart'
    show CompositionWorkshopScreen;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore;
import 'package:flutter/material.dart';

/// Called with the edited score when an editor "sends back" a round-trip edit.
typedef ScoreReturn = void Function(MultiPartScore edited);

/// Open [score] in the full Score Workshop (editable notation, all parts).
void openScoreInWorkshop(
  BuildContext context,
  MultiPartScore score, {
  List<String>? names,
  ScoreReturn? onReturn,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CompositionWorkshopScreen(
        initialScore: score,
        initialNames: names,
        onReturnToDaw: onReturn,
      ),
    ),
  );
}

/// Open [score] in the Tab Workshop — one editable tab track per part, so a
/// multi-instrument score keeps every instrument (no-op on an empty score).
void openScoreInTab(
  BuildContext context,
  MultiPartScore score, {
  List<String>? names,
  ScoreReturn? onReturn,
}) {
  if (score.parts.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TabWorkshopScreen(
        initialParts: score,
        initialNames: names,
        onReturnToDaw: onReturn,
      ),
    ),
  );
}

/// A bottom sheet that lets the user open [score] in a chosen editor (Score
/// Workshop or Tab Workshop). Pops itself, then pushes the editor. When
/// [onReturn] is set, edits sent back from the editor route through it.
Future<void> showScoreDestinations(
  BuildContext context,
  MultiPartScore score, {
  List<String>? names,
  ScoreReturn? onReturn,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.open_in_new, size: 20),
                const SizedBox(width: 8),
                Text(
                  l10n.scoreRouterTitle,
                  style: Theme.of(sheetCtx).textTheme.titleSmall,
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(l10n.workshopModeScore),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              openScoreInWorkshop(
                context,
                score,
                names: names,
                onReturn: onReturn,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.straighten),
            title: Text(l10n.workshopModeTab),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              openScoreInTab(context, score, names: names, onReturn: onReturn);
            },
          ),
        ],
      ),
    ),
  );
}
