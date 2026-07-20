// Bridges the cost-based tab arranger to crisp_notation's GPIF export: runs
// [arrangeTab] over a score's note columns and shapes the result as a
// [GpFretPlan] (`elementId -> {string: fret}`) so `scoreToGpif` /
// `multiPartToGpif` emit the arranged positions instead of the greedy per-pitch
// fallback. Flutter-free — used by `bin/tabconv.dart` and unit-testable without
// a widget tree.
import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show arrangeTab;
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Arranges [score]'s notes on [tuning] and returns a per-note GPIF fret plan.
///
/// Notes are taken in reading order (measures → elements), one arranger column
/// per [NoteElement]; rests don't contribute. The plan keys on each element's
/// `id` (importers assign them), so any element without an id is simply left to
/// the writer's `Tuning.fretFor`. Frets are absolute from the nut — the arranger
/// returns capo-relative frets (`midi − open − capo`), so [capo] is added back.
GpFretPlan gpFretPlanFor(Score score, Tuning tuning, {int capo = 0}) {
  final notes = <NoteElement>[
    for (final m in score.measures)
      for (final e in m.elements)
        if (e is NoteElement) e,
  ];
  final columns = [
    for (final n in notes) [for (final p in n.pitches) p.midiNumber],
  ];
  final frettings = arrangeTab(columns, tuning, capo: capo);
  final plan = <String, Map<int, int>>{};
  for (var i = 0; i < notes.length && i < frettings.length; i++) {
    final id = notes[i].id;
    if (id == null) continue;
    plan[id] = {for (final e in frettings[i].entries) e.key: e.value + capo};
  }
  return plan;
}
