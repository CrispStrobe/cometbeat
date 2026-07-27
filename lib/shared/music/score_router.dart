// Route an editable document to the editor that owns it. Any [MultiPartScore] —
// imported from the library/music picker, transcribed, or lifted out of an Audio
// Editor music clip — can be opened in the Score Workshop or the Tab Workshop
// from one place; a tracker song, a drum grid and a groove have the same door
// here (they are not scores, but "which editor opens this?" is one question and
// deserves one answer).
//
// The "and back" half: pass [onReturn]. When set, the editor's "Send to Audio
// Editor" calls it with the EDITED score (and pops back) instead of adding a new
// clip — so opening a DAW music clip and sending back updates that SAME clip
// in place. With no [onReturn] the editors keep their normal add-a-new-clip send.

import 'package:comet_beat/core/audio/loop_engine.dart'
    show DrumRowsPattern, GrooveSpec, LoopTiming;
import 'package:comet_beat/core/audio/tracker_song.dart' show TrackerSong;
import 'package:comet_beat/features/games/composition/advanced_tracker_screen.dart';
import 'package:comet_beat/features/games/composition/loop_mixer_screen.dart'
    show LoopMixerScreen;
import 'package:comet_beat/features/games/composition/multipart_to_tracker.dart'
    show trackerSongFromMultiPart;
import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart'
    show TabWorkshopScreen;
import 'package:comet_beat/features/games/drums/drumkit_screen.dart'
    show DrumkitScreen;
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart'
    show CompositionWorkshopScreen;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore;
import 'package:flutter/material.dart';

/// Called with the edited score when an editor "sends back" a round-trip edit.
typedef ScoreReturn = void Function(MultiPartScore edited);

/// The tracker twin of [ScoreReturn] — the edited pattern song, unconverted.
typedef TrackerReturn = void Function(TrackerSong edited);

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

/// Open [score] in the Advanced Tracker using the lossy chromatic bridge.
void openScoreInTracker(BuildContext context, MultiPartScore score) {
  final song = trackerSongFromMultiPart(score);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AdvancedTrackerScreen(initialSong: song),
    ),
  );
}

/// Open a tracker [song] in the Advanced Tracker as-is.
///
/// Unlike [openScoreInTracker] there is no conversion here: an Audio Editor
/// clip that arrived from the Tracker still holds the song, so this hands back
/// the same document. Pass [onReturn] for the in-place round trip — the
/// Tracker's "Send to Audio Editor" then updates THAT clip instead of adding a
/// second copy of the same music to the timeline.
void openTrackerSong(
  BuildContext context,
  TrackerSong song, {
  TrackerReturn? onReturn,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AdvancedTrackerScreen(
        initialSong: song,
        onReturnToDaw: onReturn,
      ),
    ),
  );
}

/// Called with the edited beat when the Drum Kit sends a round-trip edit back.
typedef DrumReturn = void Function(DrumRowsPattern pattern, LoopTiming timing);

/// Called with the edited groove when the Loop Mixer sends one back.
typedef GrooveReturn = void Function(GrooveSpec edited);

/// Open a drum grid in the full Drum Kit, seeded with [pattern] at [timing].
///
/// The beat that arrived from an Audio Editor clip still IS a grid, so this is
/// exact retrieval — nothing is transcribed and nothing is approximated. Pass
/// [onReturn] for the in-place round trip.
void openDrumPattern(
  BuildContext context,
  DrumRowsPattern pattern, {
  LoopTiming? timing,
  DrumReturn? onReturn,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DrumkitScreen(
        initialBeat: pattern,
        initialTiming: timing,
        onReturnToDaw: onReturn,
      ),
    ),
  );
}

/// Open a groove in the Loop Mixer, seeded with [spec]. Exact retrieval, like
/// [openDrumPattern]; pass [onReturn] for the in-place round trip.
void openGroove(
  BuildContext context,
  GrooveSpec spec, {
  GrooveReturn? onReturn,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LoopMixerScreen(
        initialSpec: spec,
        onReturnToDaw: onReturn,
      ),
    ),
  );
}

/// A bottom sheet that lets the user open [score] in a chosen editor (Score
/// Workshop, Tab Workshop, or Advanced Tracker). Pops itself, then pushes the
/// editor. When
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
          ListTile(
            leading: const Icon(Icons.grid_on),
            title: Text(l10n.trackerAdvancedTitle),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              openScoreInTracker(context, score);
            },
          ),
        ],
      ),
    ),
  );
}
