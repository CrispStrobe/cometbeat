// lib/core/interop/loop_tab.dart
//
// C2 — Loop Studio <-> Tab.
//
// A pitched loop track and a tab both describe "these notes, on this grid", so
// the conversion is mostly bookkeeping — with one genuinely musical step in the
// middle: a loop track says only WHICH PITCHES, and a tab has to decide which
// string and fret to play them on. That decision is not ours to invent here;
// `tab_arranger.dart` already solves it properly (candidate frettings scored by
// hand span and movement between columns), so this file calls it rather than
// picking the lowest fret and producing something unplayable.
//
// The other direction is exact: a tab already knows its strings and frets, so
// the pitches fall straight out of the tuning.
//
// Grids differ and that is the lossy part. A loop step is an EIGHTH
// ([LoopTiming.stepsPerBar] = 8 per 4/4 bar); a tab column carries an arbitrary
// note value. Anything shorter than an eighth cannot be a loop step, so it
// quantizes — and the [ConversionReport] says so rather than letting the user
// find out by ear.
//
// Velocity survives via the C0 side-car (a tab has no dynamics), so
// loop -> tab -> loop keeps it.
//
// Pure Dart, no Flutter.

import 'package:comet_beat/core/audio/loop_engine.dart'
    show LoopTiming, PatternCell;
import 'package:comet_beat/core/interop/annotation_codecs.dart';
import 'package:comet_beat/core/interop/symbolic_annotation.dart';
import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show arrangeTab;
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/shared/step_duration.dart';
import 'package:crisp_notation/crisp_notation.dart';

/// A loop step is an eighth note, so the loop grid is 2 steps per beat.
const int kLoopStepsPerBeat = 2;

/// The result of turning a pitched loop track into a tab.
class LoopToTabResult {
  LoopToTabResult({
    required this.doc,
    required this.annotations,
    required this.report,
  });

  final TabDocument doc;

  /// What the tab could not hold — currently per-note velocity. Hand it back to
  /// [loopCellsFromTabDocument] for an exact round-trip.
  final SymbolicAnnotations annotations;
  final ConversionReport report;
}

/// The result of turning a tab into loop cells.
class TabToLoopResult {
  TabToLoopResult({
    required this.cells,
    required this.annotations,
    required this.report,
  });

  final List<PatternCell> cells;

  /// What a loop track cannot hold: the tuning, the capo, and each column's
  /// string/fret placement. Hand this back to [tabDocumentFromLoopCells] and
  /// the tab comes out on the strings it was written on.
  final SymbolicAnnotations annotations;
  final ConversionReport report;
}

/// Converts a pitched loop track ([cells]) into a [TabDocument] on [tuning].
///
/// The string/fret choice comes from [arrangeTab], so the result is playable
/// rather than merely correct in pitch. Rests become empty columns.
LoopToTabResult tabDocumentFromLoopCells(
  List<PatternCell> cells,
  Tuning tuning, {
  SymbolicAnnotations? annotations,
  int capo = 0,
  int maxFret = 20,
}) {
  final report = ConversionReport();
  final notes = annotations ?? SymbolicAnnotations();
  final out = SymbolicAnnotations()
    ..docMeta[AnnotationKeys.sourceMode] = 'loop'
    ..docMeta[AnnotationKeys.capo] = capo;

  // Only the sounding columns go to the arranger — a rest has nothing to fret,
  // and feeding it an empty column would just cost a planning slot.
  final soundingIndices = <int>[];
  final soundingColumns = <List<int>>[];
  for (var i = 0; i < cells.length; i++) {
    final midis = cells[i].midis;
    if (midis == null || midis.isEmpty) continue;
    soundingIndices.add(i);
    soundingColumns.add(List<int>.of(midis));
  }

  final frettings = soundingColumns.isEmpty
      ? const <Map<int, int>>[]
      : arrangeTab(soundingColumns, tuning, capo: capo, maxFret: maxFret);

  final byIndex = <int, Map<int, int>>{};
  for (var i = 0; i < soundingIndices.length && i < frettings.length; i++) {
    byIndex[soundingIndices[i]] = frettings[i];
  }

  final columns = <TabColumn>[];
  var step = 0;
  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    final duration = _durationForLoopSteps(cell.steps, report);
    // A fretting the side-car remembers beats one the arranger invents — but
    // only if it still SOUNDS this cell. The loop may have been edited since,
    // and coordinates alone cannot tell; the pitches can. A stale fretting is
    // dropped and the arranger's choice stands.
    final remembered = _rememberedFretting(
      notes,
      EventAddress(track: 0, step: step),
      cell.midis,
      tuning,
      capo,
    );
    final fretting = remembered ?? byIndex[i] ?? const <int, int>{};

    if ((cell.midis?.isNotEmpty ?? false) && fretting.isEmpty) {
      report.addLost('notes outside the instrument\'s range');
    }
    if (cell.velocity != 1.0) {
      out.set(
        EventAddress(track: 0, step: step),
        AnnotationKeys.velocity,
        cell.velocity,
      );
      report.addLost('per-note velocity (a tab has no dynamics)');
    }

    columns.add(TabColumn(frets: fretting, duration: duration));
    step += cell.steps;
  }

  return LoopToTabResult(
    doc: TabDocument(tuning: tuning, columns: columns),
    annotations: out,
    report: report,
  );
}

/// Converts [doc] into loop cells on the eighth-note grid.
///
/// Chords stay chords — a [PatternCell] holds a list of pitches, so a strummed
/// tab column survives intact. [annotations] restores per-note velocity if this
/// tab came from a loop.
TabToLoopResult loopCellsFromTabDocument(
  TabDocument doc, {
  SymbolicAnnotations? annotations,
  int capo = 0,
}) {
  final report = ConversionReport();
  final notes = annotations ?? SymbolicAnnotations();
  final effectiveCapo =
      capo != 0 ? capo : (_asInt(notes.docMeta[AnnotationKeys.capo]) ?? 0);

  // Written, not read: what this conversion is about to drop. The incoming
  // [annotations] stay untouched — they belong to the caller.
  final out = SymbolicAnnotations()
    ..docMeta[AnnotationKeys.sourceMode] = 'tab'
    ..docMeta[AnnotationKeys.capo] = effectiveCapo
    ..docMeta[AnnotationKeys.tuning] = tuningToAnnotation(doc.tuning);

  final cells = <PatternCell>[];
  var step = 0;
  for (final column in doc.columns) {
    final steps = durationToSteps(column.duration, kLoopStepsPerBeat);
    if (steps < 1) {
      report.addApproximated(
        'notes shorter than an eighth were lengthened to one loop step',
      );
    }
    final safeSteps = steps < 1 ? 1 : steps;

    final midis = <int>[];
    for (final entry in column.frets.entries) {
      final string = entry.key;
      if (string < 0 || string >= doc.tuning.stringCount) continue;
      final open = doc.tuning.strings[string].midiNumber;
      midis.add(open + entry.value + effectiveCapo);
    }
    midis.sort();

    if (column.techniques.isNotEmpty) {
      report.addLost('playing techniques (a loop track has no articulation)');
    }
    if (column.tuplet != null) {
      report.addApproximated('tuplets snapped to the eighth-note grid');
    }

    final at = EventAddress(track: 0, step: step);
    final velocity = _asDouble(notes.get(at, AnnotationKeys.velocity)) ?? 1.0;

    // A loop cell is pitches; the strings these were played on are about to be
    // lost. Record them against the same address the reverse conversion uses,
    // so the way back can put them where they were instead of re-arranging.
    if (column.frets.isNotEmpty) {
      out.set(at, AnnotationKeys.fretting, frettingToAnnotation(column.frets));
      report.addLost('string and fret choice (a loop track carries pitches)');
    }

    cells.add(
      PatternCell(
        midis: midis.isEmpty ? null : midis,
        steps: safeSteps,
        velocity: velocity,
      ),
    );
    step += safeSteps;
  }

  final total = cells.fold<int>(0, (sum, c) => sum + c.steps);
  if (total % LoopTiming.stepsPerBar != 0) {
    report.addApproximated(
      'the tab does not fill whole bars — the loop will not be a clean length',
    );
  }

  return TabToLoopResult(cells: cells, annotations: out, report: report);
}

/// The fretting [notes] recorded at [at], if it still sounds exactly [midis].
///
/// The check is the whole point. An [EventAddress] is a position, and a loop
/// that has been edited since has different notes at the same positions — so a
/// remembered fretting is only trustworthy when playing it produces the pitches
/// actually in the cell. Anything else returns null and the arranger decides.
Map<int, int>? _rememberedFretting(
  SymbolicAnnotations notes,
  EventAddress at,
  List<int>? midis,
  Tuning tuning,
  int capo,
) {
  if (midis == null || midis.isEmpty) return null;
  final frets = frettingFromAnnotation(notes.get(at, AnnotationKeys.fretting));
  if (frets == null || frets.isEmpty) return null;

  final sounded = <int>[];
  for (final entry in frets.entries) {
    final string = entry.key;
    if (string < 0 || string >= tuning.stringCount) return null;
    if (entry.value < 0) return null;
    sounded.add(tuning.strings[string].midiNumber + entry.value + capo);
  }
  sounded.sort();

  final wanted = List<int>.of(midis)..sort();
  if (sounded.length != wanted.length) return null;
  for (var i = 0; i < wanted.length; i++) {
    if (sounded[i] != wanted[i]) return null;
  }
  return frets;
}

/// The note value covering [steps] eighth-note steps.
NoteDuration _durationForLoopSteps(int steps, ConversionReport report) {
  final ladder = durationLadder(kLoopStepsPerBeat);
  for (final (duration, length) in ladder) {
    if (length == steps) return duration;
  }
  // A loop cell can span any number of steps (a 5-step note is legal on the
  // grid but is not a single note value), so take the largest that fits and say
  // so — the alternative would be silently engraving the wrong length.
  report.addApproximated('note lengths rounded to the nearest note value');
  for (final (duration, length) in ladder) {
    if (length <= steps) return duration;
  }
  return ladder.isEmpty ? NoteDuration.quarter : ladder.last.$1;
}

int? _asInt(Object? raw) => switch (raw) {
      final int v => v,
      final double v => v.toInt(),
      final String v => int.tryParse(v),
      _ => null,
    };

double? _asDouble(Object? raw) => switch (raw) {
      final double v => v,
      final int v => v.toDouble(),
      final String v => double.tryParse(v),
      _ => null,
    };
