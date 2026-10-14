// lib/features/review/review_router.dart
//
// Where the home screen's "N to review" button goes.
//
// Every game records spaced-repetition items under its own namespace
// (`<module>.<skill>.<detail>`), but only a handful of quizzes can be handed a
// list of specific items to re-ask. Until this router existed the button
// counted ALL due items and could only launch those few — so a child whose due
// items were rhythm, keyboard or ear-training ones tapped it and got "coming
// soon".
//
// Two kinds of route, picked per skill by longest matching prefix:
//
//   * a DEDICATED runner re-asks exactly the due items (the quizzes that take
//     `reviewItemIds`);
//   * otherwise the GAME that drills the skill is opened for a normal round.
//     That does not guarantee each due item comes up, so the bucket is marked
//     handed-out for the session: the count drops and the next tap moves on to
//     a different skill instead of offering the same game again.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/cello/cello_string_quiz_screen.dart';
import 'package:comet_beat/features/games/chords/chord_quiz_screen.dart';
import 'package:comet_beat/features/games/chords/interval_ear_screen.dart';
import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/features/games/guitar/fretboard_find_screen.dart';
import 'package:comet_beat/features/games/guitar/guitar_string_quiz_screen.dart';
import 'package:comet_beat/features/games/harmony/function_ear_screen.dart';
import 'package:comet_beat/features/games/harmony/harmony_quiz_screen.dart';
import 'package:comet_beat/features/games/keyboard/grand_staff_read_screen.dart';
import 'package:comet_beat/features/games/keyboard/key_find_screen.dart';
import 'package:comet_beat/features/games/keyboard/key_name_screen.dart';
import 'package:comet_beat/features/games/measures/meter_detective_screen.dart';
import 'package:comet_beat/features/games/measures/time_signature_screen.dart';
import 'package:comet_beat/features/games/measures/which_beat_screen.dart';
import 'package:comet_beat/features/games/note_reading/note_reading_quiz_screen.dart';
import 'package:comet_beat/features/games/note_values/note_value_quiz_screen.dart';
import 'package:comet_beat/features/games/note_values/rhythm_tap_screen.dart';
import 'package:comet_beat/features/games/scales/key_signature_screen.dart';
import 'package:comet_beat/features/games/scales/scale_detective_screen.dart';
import 'package:comet_beat/features/games/tutorial_gate.dart';
import 'package:crisp_notation/crisp_notation.dart' show Clef;
import 'package:flutter/material.dart';

/// Most items a dedicated runner is handed in one session.
const kReviewSessionSize = 10;

/// Quizzes that can re-ask a given list of items, by SRI prefix.
final Map<String, Widget Function(List<String> ids)> kReviewRunners = {
  'note_values.symbol.': (ids) => NoteValueQuizScreen(reviewItemIds: ids),
  'note_reading.treble.': (ids) =>
      NoteReadingQuizScreen(clef: Clef.treble, reviewItemIds: ids),
  'note_reading.bass.': (ids) =>
      NoteReadingQuizScreen(clef: Clef.bass, reviewItemIds: ids),
  'note_reading.tenor.': (ids) =>
      NoteReadingQuizScreen(clef: Clef.tenor, reviewItemIds: ids),
  'scales.spot.': (ids) => ScaleDetectiveScreen(reviewItemIds: ids),
  'chords.triad.': (ids) => ChordQuizScreen(reviewItemIds: ids),
  'harmony.function.': (ids) => HarmonyQuizScreen(reviewItemIds: ids),
  'harmony.hear.': (ids) => FunctionEarScreen(reviewItemIds: ids),
  'key_sig.': (ids) => KeySignatureScreen(reviewItemIds: ids),
  'keyboard.name.': (ids) => KeyNameScreen(reviewItemIds: ids),
  'measures.timesig.': (ids) => TimeSignatureScreen(reviewItemIds: ids),
  'measures.meter.': (ids) => MeterDetectiveScreen(reviewItemIds: ids),
  'keyboard.find.': (ids) => KeyFindScreen(reviewItemIds: ids),
  'note_values.rhythm.': (ids) => RhythmTapScreen(reviewItemIds: ids),
  'guitar.string.': (ids) => GuitarStringQuizScreen(reviewItemIds: ids),
  'cello.string.': (ids) => CelloStringQuizScreen(reviewItemIds: ids),
  'keyboard.grand.': (ids) => GrandStaffReadScreen(reviewItemIds: ids),
  'guitar.fret.': (ids) => FretboardFindScreen(reviewItemIds: ids),
  'chords.interval.': (ids) => IntervalEarScreen(reviewItemIds: ids),
  'measures.beat.': (ids) => WhichBeatScreen(reviewItemIds: ids),
};

/// The game that drills each remaining skill, by SRI prefix → game id. A new
/// game that records under a new namespace needs a line here;
/// `review_router_test` fails until it has one.
const Map<String, String> kReviewGameBySkill = {
  'cello.bowing.': 'bowing',
  'cello.finger.': 'cello_finger_quiz',
  'cello.play.': 'cello_play_it',
  'cello.play_along': 'cello_play_along',
  'chords.build.': 'chord_builder',
  'chords.hear.': 'seventh_ear',
  'chords.name.': 'name_that_chord',
  'chords.play_along': 'chord_play_along',
  'chords.quality.': 'major_minor_sort',
  'chords.symbol.': 'chord_chart',
  'composition.answer.': 'question_answer',
  'composition.closure.': 'ending_detective',
  'composition.form.': 'form_read',
  'expression.hear.': 'charades',
  'guitar.capo.': 'capo_match',
  'guitar.play_along': 'guitar_play_along',
  'guitar.power.': 'power_chord',
  'harmony.cadence.': 'cadence_workshop',
  'harmony.degree.': 'connect_degrees',
  'harmony.parallels.': 'spot_parallels',
  'harmony.roman.': 'roman_numeral',
  'keyboard.chord.': 'key_chord',
  'keyboard.ear.': 'key_ear',
  'keyboard.melody.': 'key_melody',
  'keyboard.play_along': 'keyboard_play_along',
  'measures.accent.': 'strong_beat',
  'measures.fill.': 'measure_fill',
  'measures.syncopation.': 'sync_read',
  'measures.upbeat.': 'spot_upbeat',
  'note_reading.dictation.': 'melody_dictation',
  'note_reading.ear_voice.': 'hear_voice',
  'note_reading.ledger.': 'ledger_leap',
  'note_reading.line_space.': 'line_space',
  'note_reading.melody.': 'melody_echo',
  'note_reading.order.': 'note_order',
  'note_reading.ornament.': 'ornament_read',
  'note_reading.place_bass.': 'place_note_bass',
  'note_reading.place_treble.': 'place_note_treble',
  'note_reading.spacing.': 'spacing_read',
  'note_reading.voice.': 'which_voice',
  'note_values.beats.': 'beat_count',
  'note_values.dot.': 'dotted_sort',
  'note_values.order.': 'value_order',
  'note_values.rest.': 'connect_rests',
  'note_values.tuplet.': 'triplet_read',
  'scales.build.': 'scale_builder',
  'scales.hear.': 'major_minor_ear',
  'scales.member.': 'in_scale',
  'scales.mode.': 'mode_ear',
  'scales.modulation.': 'modulation_ear',
  'songs.tune.': 'tune_quiz',
  'transpose.': 'concert_pitch',
};

/// The route prefix that claims [itemId] — the longest one that matches, so
/// `note_reading.place_treble.` is not swallowed by a shorter sibling. Null
/// when nothing can review this item.
String? reviewPrefixFor(String itemId) {
  String? best;
  for (final prefix in kReviewRunners.keys.followedBy(
    kReviewGameBySkill.keys,
  )) {
    if (itemId.startsWith(prefix) &&
        (best == null || prefix.length > best.length)) {
      best = prefix;
    }
  }
  return best;
}

/// One review session: which items, and what opens for them.
class ReviewPlan {
  const ReviewPlan._({
    required this.prefix,
    required this.itemIds,
    this.game,
  });

  /// The SRI prefix being reviewed.
  final String prefix;

  /// The due items this session covers.
  final List<String> itemIds;

  /// The game opened for a normal round; null for a dedicated runner.
  final GameInfo? game;

  /// Whether a dedicated runner re-asks exactly [itemIds].
  bool get dedicated => game == null;

  /// Opens the session. A game round marks its bucket handed-out on [sri] so
  /// the next review moves on (see the file header).
  Route<void> open(SriService sri) {
    final game = this.game;
    if (game == null) {
      return MaterialPageRoute<void>(
        builder: (_) => kReviewRunners[prefix]!(itemIds),
      );
    }
    sri.markHandedOut(itemIds);
    return gameRoute(game);
  }
}

/// The review session to offer now — the skill with the most due items — or
/// null when nothing due can be reviewed. Read-only: safe to call from build.
ReviewPlan? planReview(SriService sri) {
  final handedOut = sri.handedOutThisSession;
  final buckets = <String, List<String>>{};
  for (final id in sri.dueItemIds()) {
    final prefix = reviewPrefixFor(id);
    if (prefix == null) continue;
    final dedicated = kReviewRunners.containsKey(prefix);
    if (!dedicated) {
      // A game round was already offered for these this session.
      if (handedOut.contains(id)) continue;
      if (gameInfoById(kReviewGameBySkill[prefix]!) == null) continue;
    }
    buckets.putIfAbsent(prefix, () => []).add(id);
  }
  if (buckets.isEmpty) return null;

  // Biggest bucket wins; on a tie, the runner that re-asks the exact items.
  final prefix = buckets.keys.reduce((a, b) {
    final bySize = buckets[b]!.length.compareTo(buckets[a]!.length);
    if (bySize != 0) return bySize > 0 ? b : a;
    return kReviewRunners.containsKey(b) && !kReviewRunners.containsKey(a)
        ? b
        : a;
  });
  final ids = buckets[prefix]!;
  if (kReviewRunners.containsKey(prefix)) {
    return ReviewPlan._(
      prefix: prefix,
      itemIds: ids.take(kReviewSessionSize).toList(),
    );
  }
  return ReviewPlan._(
    prefix: prefix,
    itemIds: ids,
    game: gameInfoById(kReviewGameBySkill[prefix]!),
  );
}
