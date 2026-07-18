// lib/features/games/widgets/reading_staff.dart
//
// A StaffView that honours the app-wide "note names under the staff" reading
// scaffold (SettingsService.showNoteNames), spelled per the note-naming setting.
//
// Use it in games where naming the note is NOT the task (rhythm, articulation,
// beaming, playing). The note-naming quizzes build StaffView directly, so the
// scaffold never prints — and reveals — their answer.
//
// Names are spelled per the app's note-naming setting (English letters / German
// with H / solfège) via `noteNameStyleFor`.

import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/playing_staff.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

class ReadingStaffView extends StatelessWidget {
  const ReadingStaffView({
    super.key,
    required this.score,
    this.staffSpace = 18,
    this.theme,
    this.playback,
  });

  final Score score;
  final double staffSpace;

  /// Defaults to [kidsScoreTheme] (the games' theme) when omitted.
  final CrispNotationTheme? theme;

  /// When set, the notes light up in time with playback (the reading scaffold
  /// is kept). Drive it from the game's play method — see [PlayingStaffView].
  final ScorePlayback? playback;

  @override
  Widget build(BuildContext context) {
    final show = context.watch<SettingsService>().showNoteNames;
    final style = show ? noteNameStyleFor(context) : NoteNameStyle.letter;
    final controller = playback;
    if (controller != null) {
      return PlayingStaffView(
        score: score,
        controller: controller,
        staffSpace: staffSpace,
        theme: theme ?? kidsScoreTheme,
        showNoteNames: show,
        noteNameStyle: style,
      );
    }
    return StaffView(
      score: score,
      staffSpace: staffSpace,
      theme: theme ?? kidsScoreTheme,
      showNoteNames: show,
      noteNameStyle: style,
    );
  }
}
