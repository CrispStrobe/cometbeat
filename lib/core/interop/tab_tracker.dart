// lib/core/interop/tab_tracker.dart
//
// C1 — Tab <-> Tracker, directly.
//
// Both modes could already reach `Score`, so a tab COULD become a tracker song
// by going Tab -> Score -> Tracker. That route throws away exactly the thing
// that makes a tab a tab: which string a note is played on. `Score` carries
// pitches; the fret/string choice is re-derived on the way back, so a carefully
// fingered passage comes home fingered differently.
//
// The direct route keeps it, because the two models line up better than they
// look: a tracker channel is a monophonic lane, and so is a guitar string. So
// **one channel per string** — string 0 (the top tab line) becomes channel 0 —
// and the fingering survives NATIVELY, as channel index + MIDI note, with no
// side-car needed for the notes themselves.
//
// What the tracker genuinely cannot hold — techniques, chord diagrams, tuplets,
// repeats, voltas, sections, the tuning itself — goes into the C0
// [SymbolicAnnotations] side-car, so `tab -> tracker -> tab` is IDENTITY when
// the side-car is carried along, and a sensible best-effort tab when it is not.
//
// Where a technique has a real tracker equivalent it is ALSO emitted as an
// effect-column command, so the song actually sounds right when opened in the
// Tracker rather than merely round-tripping: slide -> 3xx tone portamento,
// vibrato -> 4xy, bend -> 1xx pitch slide up.
//
// Pure Dart, no Flutter.

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replay.dart' show kFxSetVolume;
import 'package:comet_beat/core/audio/tracker_replayer.dart'
    show kExNoteCut, kFxExtended, kFxPortaUp, kFxTonePorta, kFxVibrato;
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/interop/annotation_codecs.dart';
import 'package:comet_beat/core/interop/symbolic_annotation.dart';
import 'package:comet_beat/core/interop/tracker_song_flatten.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/shared/step_duration.dart';
import 'package:crisp_notation/crisp_notation.dart';

/// The grid a tab converts on: 8 steps per beat = a 32nd-note row, which is the
/// resolution [TabDocument] itself authors at. Coarser grids are allowed but
/// quantize, and the conversion says so in its [ConversionReport].
const int kTabTrackerStepsPerBeat = 8;

/// The default effect parameter for each technique's tracker command. Chosen to
/// be audible but gentle — the exact depth is not recoverable from a tab, which
/// only says "there is a bend here".
const int _kSlideParam = 0x20;
const int _kVibratoParam = 0x44; // speed 4, depth 4
const int _kBendParam = 0x18;
const int _kDeadCutTicks = 2; // ECx — cut a dead/muted note at tick 2 (a chick)
const int _kGhostVolume = 0x18; // Cxx — a ghost note at ~⅜ volume

/// The result of converting a tab into a tracker song.
class TabToTrackerResult {
  TabToTrackerResult({
    required this.song,
    required this.annotations,
    required this.report,
  });

  final TrackerSong song;

  /// Everything the tracker model could not hold. Pass it back to
  /// [tabDocumentFromTrackerSong] for an exact round-trip.
  final SymbolicAnnotations annotations;
  final ConversionReport report;
}

/// The result of converting a tracker song into a tab.
class TrackerToTabResult {
  TrackerToTabResult({required this.doc, required this.report});

  final TabDocument doc;
  final ConversionReport report;
}

/// Converts [doc] into a [TrackerSong] with one channel per string.
///
/// Each column occupies as many rows as its written duration, at
/// [stepsPerBeat]; the note sits on the column's first row and the remaining
/// rows stay empty (the note rings, exactly as a tracker sustains). [capo] is
/// baked into the sounding pitch and recorded in the side-car so the reverse
/// can subtract it again.
///
/// [instrument] voices every channel; pass a plucked/guitar-ish instrument for
/// something that sounds like the tab.
TabToTrackerResult trackerSongFromTabDocument(
  TabDocument doc, {
  int stepsPerBeat = kTabTrackerStepsPerBeat,
  int capo = 0,
  int tempoBpm = 120,
  TrackerInstrument? instrument,
}) {
  final report = ConversionReport();
  final annotations = SymbolicAnnotations()
    ..docMeta[AnnotationKeys.sourceMode] = 'tab'
    ..docMeta[AnnotationKeys.capo] = capo
    ..docMeta[AnnotationKeys.tuning] = tuningToAnnotation(doc.tuning)
    ..docMeta[AnnotationKeys.timeSignature] = [
      doc.timeSignature.beats,
      doc.timeSignature.beatUnit,
    ]
    ..docMeta[AnnotationKeys.keySignature] = doc.keySignature.fifths;

  // Lay the columns out on the grid first, so we know how many rows we need.
  final starts = <int>[];
  var totalSteps = 0;
  for (final column in doc.columns) {
    starts.add(totalSteps);
    final steps = durationToSteps(column.duration, stepsPerBeat);
    if (steps < 1) {
      report.addApproximated('very short notes quantized to one step');
    }
    totalSteps += steps < 1 ? 1 : steps;
  }
  final rows = totalSteps < 1 ? 1 : totalSteps;

  final stringCount = doc.stringCount;
  // A plucked string is the honest default voice for a tab.
  final voice = instrument ?? const KarplusInstrument('tabString');
  final channels = [
    for (var s = 0; s < stringCount; s++)
      TrackerChannel(
        id: 'string${s + 1}',
        instrument: voice,
        rows: rows,
      ),
  ];

  final cells = [
    for (var s = 0; s < stringCount; s++)
      List<TrackerCell>.filled(rows, TrackerCell.empty, growable: true),
  ];

  for (var i = 0; i < doc.columns.length; i++) {
    final column = doc.columns[i];
    final row = starts[i];
    if (row >= rows) break;

    // Everything about the column the tracker has no field for. Written on the
    // column's own address (its first string, or string 0 for an empty column)
    // so the reverse can rebuild the column even when it holds no note.
    final anchor = EventAddress(track: 0, step: row);
    annotations.put(anchor, {
      AnnotationKeys.duration: column.duration.toString(),
      if (column.tieToNext) AnnotationKeys.tieToNext: true,
      if (column.tuplet != null)
        AnnotationKeys.tuplet: [column.tuplet!.$1, column.tuplet!.$2],
      if (column.startRepeat) AnnotationKeys.startRepeat: true,
      if (column.endRepeat) AnnotationKeys.endRepeat: true,
      if (column.volta != null) AnnotationKeys.volta: column.volta,
      if (column.navigation != null)
        AnnotationKeys.navigation: column.navigation!.name,
      if (column.section != null) AnnotationKeys.section: column.section,
      if (column.techniques.isNotEmpty)
        AnnotationKeys.techniques: [
          for (final t in column.techniques) t.name,
        ],
      // Not members of `techniques` — TabColumn keeps them as their own flags,
      // so listing the set alone let a palm-muted riff come back open.
      if (column.palmMute) AnnotationKeys.palmMute: true,
      if (column.letRing) AnnotationKeys.letRing: true,
    });

    if (column.tuplet != null) {
      report.addApproximated('tuplets play at their written length');
    }
    if (column.chord != null) {
      report.addLost('chord diagrams');
    }
    if (column.navigation != null ||
        column.startRepeat ||
        column.endRepeat ||
        column.volta != null) {
      report.addLost('repeat structure and voltas');
    }

    final (fxCmd, fxParam) = _trackerFxForTechniques(column.techniques);
    if (column.techniques.isNotEmpty) {
      final mapped = fxCmd != 0;
      report.addApproximated(
        mapped
            ? 'playing techniques become effect-column commands'
            : 'playing techniques are kept but not played',
      );
    }

    for (final entry in column.frets.entries) {
      final string = entry.key;
      if (string < 0 || string >= stringCount) continue;
      final midi = doc.tuning.strings[string].midiNumber + entry.value + capo;
      cells[string][row] = TrackerCell(
        midi: midi,
        fxCmd: fxCmd,
        fxParam: fxParam,
      );
    }
  }

  final timing = TrackerTiming(
    tempoBpm: tempoBpm,
    rows: rows,
    stepsPerBeat: stepsPerBeat,
  );
  final song = TrackerSong.fromParts(
    channels: channels,
    timing: timing,
    patterns: [TrackerPattern(name: 'tab', cells: cells)],
    order: const [0],
  );
  return TabToTrackerResult(
    song: song,
    annotations: annotations,
    report: report,
  );
}

/// Converts [song] back into a [TabDocument], treating channel *n* as string
/// *n* — the inverse of [trackerSongFromTabDocument].
///
/// With the [annotations] that conversion produced, this is an exact
/// round-trip: durations, techniques, tuning, capo, repeats and sections all
/// come back. Without them it is a best-effort tab — durations are inferred
/// from the row spacing and the tuning falls back to [fallbackTuning].
TrackerToTabResult tabDocumentFromTrackerSong(
  TrackerSong song, {
  SymbolicAnnotations? annotations,
  Tuning? fallbackTuning,
}) {
  final report = ConversionReport();
  final notes = annotations ?? SymbolicAnnotations();
  // The whole song, not `song.channels` — that is the currently-loaded pattern,
  // so reading it dropped every pattern after the first (see
  // tracker_song_flatten.dart).
  final channels = trackerChannelsAcrossOrder(song);
  final rows = channels.isEmpty ? 0 : channels.first.cells.length;

  final capo = _asInt(notes.docMeta[AnnotationKeys.capo]) ?? 0;
  final tuning = tuningFromAnnotation(notes.docMeta[AnnotationKeys.tuning]) ??
      fallbackTuning ??
      Tuning.standardGuitar;
  if (notes.docMeta[AnnotationKeys.tuning] == null) {
    report.addApproximated('tuning assumed — the song did not carry one');
  }
  if (channels.length != tuning.stringCount) {
    report.addApproximated(
      'channel count (${channels.length}) does not match the '
      '${tuning.stringCount}-string tuning',
    );
  }

  // A column starts at every row where ANY channel attacks a note, plus every
  // row the side-car annotated (so a rest column survives too).
  final starts = <int>{
    for (final address in notes.events.keys)
      if (address.step >= 0 && address.step < rows) address.step,
  };
  for (var row = 0; row < rows; row++) {
    for (final channel in channels) {
      if (channel.cells[row].midi != null) {
        starts.add(row);
        break;
      }
    }
  }
  final startRows = starts.toList()..sort();

  final stepsPerBeat = song.timing.stepsPerBeat;
  final columns = <TabColumn>[];
  for (var i = 0; i < startRows.length; i++) {
    final row = startRows[i];
    final anchor = EventAddress(track: 0, step: row);
    final meta = notes.at(anchor);

    final frets = <int, int>{};
    for (var s = 0; s < channels.length && s < tuning.stringCount; s++) {
      final midi = channels[s].cells[row].midi;
      if (midi == null) continue;
      final fret = midi - tuning.strings[s].midiNumber - capo;
      if (fret < 0) {
        report.addApproximated(
          'a note below string ${s + 1} open was clamped to the nut',
        );
      }
      frets[s] = fret < 0 ? 0 : fret;
    }

    // Duration: the annotation is authoritative; otherwise infer it from the
    // gap to the next column start.
    final spanRows = (i + 1 < startRows.length ? startRows[i + 1] : rows) - row;
    final duration = _durationFrom(meta[AnnotationKeys.duration]) ??
        _durationForSteps(spanRows, stepsPerBeat, report);

    final techniques = <TabTechnique>{};
    final raw = meta[AnnotationKeys.techniques];
    if (raw is List) {
      for (final name in raw) {
        for (final t in TabTechnique.values) {
          if (t.name == name) techniques.add(t);
        }
      }
    } else {
      // No side-car — recover what the effect column can tell us.
      final cell = _firstSounding(channels, row);
      final inferred = _techniqueForTrackerFx(cell?.fxCmd ?? 0);
      if (inferred != null) {
        techniques.add(inferred);
        report.addApproximated(
          'techniques inferred from effect commands',
        );
      }
    }

    final tuplet = meta[AnnotationKeys.tuplet];
    columns.add(
      TabColumn(
        frets: frets,
        duration: duration,
        techniques: techniques,
        tieToNext: meta[AnnotationKeys.tieToNext] == true,
        tuplet: tuplet is List && tuplet.length == 2
            ? (_asInt(tuplet[0]) ?? 3, _asInt(tuplet[1]) ?? 2)
            : null,
        startRepeat: meta[AnnotationKeys.startRepeat] == true,
        endRepeat: meta[AnnotationKeys.endRepeat] == true,
        volta: _asInt(meta[AnnotationKeys.volta]),
        navigation: _navigationFrom(meta[AnnotationKeys.navigation]),
        section: meta[AnnotationKeys.section] as String?,
        palmMute: meta[AnnotationKeys.palmMute] == true,
        letRing: meta[AnnotationKeys.letRing] == true,
      ),
    );
  }

  final doc = TabDocument(
    tuning: tuning,
    columns: columns,
    timeSignature:
        _timeSignatureFrom(notes.docMeta[AnnotationKeys.timeSignature]) ??
            TimeSignature.fourFour,
    keySignature: KeySignature(
      _asInt(notes.docMeta[AnnotationKeys.keySignature]) ?? 0,
    ),
  );
  return TrackerToTabResult(doc: doc, report: report);
}

// ─── technique <-> effect column ────────────────────────────────────────────

/// The effect-column command a technique set maps to. Only one command fits in
/// a cell, so the most pitch-relevant technique wins; the full set is always in
/// the side-car regardless.
(int, int) _trackerFxForTechniques(Set<TabTechnique> techniques) {
  if (techniques.contains(TabTechnique.slide)) {
    return (kFxTonePorta, _kSlideParam);
  }
  if (techniques.contains(TabTechnique.bend)) {
    return (kFxPortaUp, _kBendParam);
  }
  if (techniques.contains(TabTechnique.vibrato)) {
    return (kFxVibrato, _kVibratoParam);
  }
  // Articulations (lower priority than the pitch techniques above, so a
  // slide+dead column still slides): a dead/muted note becomes a percussive
  // ECx note-cut; a ghost note becomes a soft Cxx set-volume. Both are honored
  // by the replayer's tick voice (and the tab "articulate" preview's baked
  // procedural path), so they actually sound.
  if (techniques.contains(TabTechnique.dead)) {
    return (kFxExtended, (kExNoteCut << 4) | _kDeadCutTicks);
  }
  if (techniques.contains(TabTechnique.ghost)) {
    return (kFxSetVolume, _kGhostVolume);
  }
  return (0, 0);
}

/// The inverse, for a song that arrived without a side-car.
TabTechnique? _techniqueForTrackerFx(int fxCmd) => switch (fxCmd) {
      kFxTonePorta => TabTechnique.slide,
      kFxPortaUp => TabTechnique.bend,
      kFxVibrato => TabTechnique.vibrato,
      _ => null,
    };

// ─── small parsers (all null-tolerant: a corrupt side-car costs fidelity,
//     never the document) ────────────────────────────────────────────────────

TrackerCell? _firstSounding(List<TrackerChannel> channels, int row) {
  for (final channel in channels) {
    final cell = channel.cells[row];
    if (cell.midi != null) return cell;
  }
  return null;
}

int? _asInt(Object? raw) => switch (raw) {
      final int v => v,
      final double v => v.toInt(),
      final String v => int.tryParse(v),
      _ => null,
    };

NoteDuration? _durationFrom(Object? raw) {
  if (raw is! String) return null;
  for (final base in DurationBase.values) {
    for (var dots = 0; dots <= 2; dots++) {
      final candidate = NoteDuration(base, dots: dots);
      if (candidate.toString() == raw) return candidate;
    }
  }
  return null;
}

/// The closest single note value to [steps] grid steps, for a song that arrived
/// without duration annotations.
NoteDuration _durationForSteps(
  int steps,
  int stepsPerBeat,
  ConversionReport report,
) {
  final ladder = durationLadder(stepsPerBeat);
  for (final (duration, length) in ladder) {
    if (length == steps) return duration;
  }
  report.addApproximated('note lengths rounded to the nearest note value');
  for (final (duration, length) in ladder) {
    if (length <= steps) return duration;
  }
  return ladder.isEmpty ? NoteDuration.quarter : ladder.last.$1;
}

TimeSignature? _timeSignatureFrom(Object? raw) {
  if (raw is! List || raw.length != 2) return null;
  final beats = _asInt(raw[0]);
  final beatUnit = _asInt(raw[1]);
  if (beats == null || beatUnit == null) return null;
  return TimeSignature(beats, beatUnit);
}

NavigationMark? _navigationFrom(Object? raw) {
  if (raw is! String) return null;
  for (final mark in NavigationMark.values) {
    if (mark.name == raw) return mark;
  }
  return null;
}
