// lib/core/notation/playing_state.dart
//
// PIZZICATO / ARCO — whether the string is plucked or bowed (SE-C1).
//
// This is a STATE, not a per-note property, and modelling it that way is the
// whole point. A printed part says "pizz." once and every note after it is
// plucked until "arco" countermands it; nobody marks each note. So the score
// carries the CHANGE POINTS, exactly as an engraver would set them, and
// [playingStates] resolves them into "what is this note?" for anything that
// needs to know.
//
// It rides on [Annotation], which the app already writes (the Roman string
// numerals do) and which MusicXML reads and writes as `<words>`. That means
// pizz./arco survives save, export and re-import today, with no new field in the
// interchange model and no reader work — and it is how real scores encode it, so
// a file exported from here says the same thing to any other program.
//
// ⚠ PLAYBACK IS DELIBERATELY NOT WIRED. A plucked cello sounds nothing like a
// bowed one, and we have no plucked sample; approximating it with a generic
// pluck or a shortened bow note would make the preview lie about the page, which
// is worse than a preview that is honestly incomplete. [playingStates] is the
// seam a renderer will consume when there is a sample worth playing. Until then
// the mark is notation only, and that is a stated limitation rather than a gap.
//
// Pure Dart (crisp_notation_core only).

import 'package:crisp_notation_core/crisp_notation_core.dart';

/// How the string is being made to sound.
enum PlayingState {
  /// Bowed — the default for a bowed instrument, so it is never written at the
  /// start of a part, only to cancel a preceding [pizzicato].
  arco,

  /// Plucked with the finger.
  pizzicato,
}

/// The text an engraver prints for each state. Abbreviated, because that is what
/// is printed — "pizzicato" in full is a programme note, not a part marking.
const Map<PlayingState, String> kPlayingStateMarks = {
  PlayingState.arco: 'arco',
  PlayingState.pizzicato: 'pizz.',
};

/// Reads a printed marking back to a state, or null when the text is not one.
///
/// ⚠ Tolerant on purpose. This has to recognise what OTHER programs and
/// engravers write, not only what we write: "pizz.", "pizz", "Pizzicato",
/// "PIZZ." and the same for arco all mean the same thing, and a score imported
/// from MusicXML will contain whichever the original engraver chose. Being
/// strict here would silently drop the marking on every imported part while
/// looking like it worked on ours.
PlayingState? playingStateFromMark(String text) {
  final t = text.trim().toLowerCase().replaceAll('.', '');
  if (t == 'pizz' || t == 'pizzicato') return PlayingState.pizzicato;
  if (t == 'arco') return PlayingState.arco;
  return null;
}

/// What each note of [score] is played with, keyed by note-element id.
///
/// Resolved by reading in order: every note carries whatever state was last
/// declared, and a part with no marking at all is [PlayingState.arco]
/// throughout. Notes without ids are skipped.
Map<String, PlayingState> playingStates(Score score) {
  final marks = <String, PlayingState>{};
  for (final annotation in score.annotations) {
    final state = playingStateFromMark(annotation.text);
    if (state != null) marks[annotation.elementId] = state;
  }

  final out = <String, PlayingState>{};
  var current = PlayingState.arco;
  for (final measure in score.measures) {
    for (final element in measure.elements) {
      if (element is! NoteElement || element.id == null) continue;
      // The mark takes effect ON the note it is attached to, not after it.
      current = marks[element.id!] ?? current;
      out[element.id!] = current;
    }
  }
  return out;
}

/// [score] with [state] declared from [fromElementId] onward.
///
/// Returns [score] unchanged when the note already plays that way — re-stating
/// a state that is already in force is exactly the redundant marking an editor
/// should not add, and an engraver would not.
///
/// Any *later* declaration of the SAME state is dropped as newly redundant; a
/// later declaration of the other state is kept, because it still means
/// something. Without that, marking a passage pizz. would leave a stale "arco"
/// in the middle of it saying the opposite.
Score scoreWithPlayingState(
  Score score, {
  required String fromElementId,
  required PlayingState state,
}) {
  final resolved = playingStates(score);
  if (resolved[fromElementId] == state) return score;

  // Which ids come at or after the anchor, in reading order.
  final ids = <String>[];
  for (final measure in score.measures) {
    for (final element in measure.elements) {
      if (element is NoteElement && element.id != null) ids.add(element.id!);
    }
  }
  final from = ids.indexOf(fromElementId);
  if (from < 0) return score;
  final after = ids.sublist(from).toSet();

  final kept = <Annotation>[
    for (final a in score.annotations)
      if (!(after.contains(a.elementId) &&
          playingStateFromMark(a.text) == state))
        a,
  ];
  return score.copyWith(
    annotations: [
      ...kept,
      Annotation(fromElementId, kPlayingStateMarks[state]!),
    ],
  );
}
