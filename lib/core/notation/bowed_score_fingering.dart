// lib/core/notation/bowed_score_fingering.dart
//
// Score-level entry point for the bowed arranger: hand it a notated cello part,
// get a fingering for every note.
//
// The result is a SIDE TABLE keyed by note-element id, not a rebuilt Score. Two
// reasons: `NoteElement` has no `copyWith`, so reconstructing every note would
// mean re-listing its dozen fields and silently dropping whichever one gets added
// next; and crisp_notation already models per-note annotations this way
// (`Score.slurs`, `Score.tabVoicings`, `Score.bends` are all id-keyed side lists).
// Callers that want the digits engraved copy them into `NoteElement.fingerings`,
// which the layout engine already draws above the notehead, or write them out as
// MusicXML `<fingering>`, which the writer already emits.
//
// ⚠ Notes without an `id` are skipped — there is nothing to key them by. Builders
// that want fingerings must assign ids ('e0', 'e1', …), the same requirement
// `scoreToMidi` has.

import 'package:comet_beat/core/notation/bowed_arranger.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MusicElement, NoteElement, Score;

/// Fingers the voice-1 line of a single-staff [score].
///
/// Returns one entry per notated note element, keyed by its id: a list parallel
/// to that element's `pitches` (one [BowedFingering] per pitch, so a double stop
/// gets two). Only voice 1 is fingered — a cello part is one line, and a second
/// voice on the same staff is a different player's line or a divisi, which is a
/// separate arrange.
///
/// Slurs are read from [Score.slurs]: a note inside a slur span is marked as
/// slurred into the next one, which makes the arranger avoid shifting there.
Map<String, List<BowedFingering>> fingerBowedScore(
  Score score, {
  required BowedSkill skill,
  BowedInstrument? instrument,
  BowedArrangeCost? cost,
  BowedPositionModel? model,
}) {
  final ids = <String?>[];
  final columns = <List<int>>[];
  for (final measure in score.measures) {
    for (final MusicElement element in measure.elements) {
      if (element is! NoteElement) {
        // A rest (or any non-note) breaks the line: an empty column, which the
        // arranger treats as "the hand is free here".
        columns.add(const []);
        ids.add(null);
        continue;
      }
      columns.add([for (final p in element.pitches) p.midiNumber]);
      ids.add(element.id);
    }
  }
  if (columns.isEmpty) return const {};

  // Which columns sit inside a slur, so shifting across them costs more.
  final index = <String, int>{};
  for (var i = 0; i < ids.length; i++) {
    final id = ids[i];
    if (id != null) index[id] = i;
  }
  final slurToNext = List<bool>.filled(columns.length, false);
  for (final slur in score.slurs) {
    final from = index[slur.startId];
    final to = index[slur.endId];
    if (from == null || to == null) continue;
    for (var i = from; i < to && i < slurToNext.length; i++) {
      slurToNext[i] = true;
    }
  }

  final arranged = arrangeBowed(
    columns,
    instrument: instrument,
    skill: skill,
    cost: cost,
    slurToNext: slurToNext,
    model: model,
  );

  final out = <String, List<BowedFingering>>{};
  for (var i = 0; i < ids.length; i++) {
    final id = ids[i];
    if (id == null || arranged.columns[i].isEmpty) continue;
    out[id] = arranged.columns[i];
  }
  return out;
}

/// The same thing as engravable digits, ready to drop into
/// `NoteElement.fingerings`. The thumb comes back as [kThumb]; a caller that
/// engraves it needs a `T` glyph rather than a digit, so notes in thumb position
/// are omitted unless [includeThumb] is set.
Map<String, List<int>> bowedFingeringDigits(
  Score score, {
  required BowedSkill skill,
  BowedInstrument? instrument,
  bool includeThumb = false,
}) {
  final table = fingerBowedScore(score, instrument: instrument, skill: skill);
  final out = <String, List<int>>{};
  for (final entry in table.entries) {
    if (!includeThumb && entry.value.any((f) => f.finger == kThumb)) continue;
    out[entry.key] = [for (final f in entry.value) f.finger];
  }
  return out;
}
