// lib/core/audio/mod/module_notation.dart
//
// The ModuleDoc ↔ notation bridge — the missing half of the conversion graph.
// ModuleDoc is the hub for module FORMATS (MOD/XM/S3M/IT); Score/MultiPartScore
// is the hub for NOTATION (MIDI, MusicXML, and every codec crisp_notation_core
// carries). This file joins them BOTH ways, so a module can become a real score
// (multi-part, one staff per channel) and a score can become a playable module —
// and either can round-trip through the other.
//
// Everything here is Flutter-free (imports crisp_notation_core, not the Flutter
// crisp_notation), so bin/notaconv.dart and the unit tests use it headlessly.
//
// Design:
//   • Module channel → notes: a channel's rows are flattened across the order
//     list into (midi?, steps) runs (an empty cell rings the previous note; a
//     DocCell.off ends it → a rest), then decomposed to tied notes + bar splits.
//     This is the notaconv logic, lifted into lib and generalized to multi-part.
//   • Notes → module channel: the inverse — a note triggers on its onset row and
//     rings (empty cells) for its duration; a rest emits a DocCell.off then rings
//     silence. That note-off is why a rest survives Score→doc→Score (an empty
//     cell alone would be swallowed by the held note). Chords split high→low
//     across channels, mirroring the Tracker's scoreToChannels.
//   • Multi-track MIDI: crisp_notation_core.scoreToMidi is single-Score / SMF
//     format 0, so this file assembles the format-1 file (one MTrk per part) and
//     splits it back — the multi-part MIDI round-trip the library lacks.

// ignore_for_file: depend_on_referenced_packages

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';

// ─── Pitch / duration helpers (shared with bin/notaconv.dart's port) ─────────

const _pcSpelling = <(Step, int)>[
  (Step.c, 0),
  (Step.c, 1),
  (Step.d, 0),
  (Step.d, 1),
  (Step.e, 0),
  (Step.f, 0),
  (Step.f, 1),
  (Step.g, 0),
  (Step.g, 1),
  (Step.a, 0),
  (Step.a, 1),
  (Step.b, 0),
];

/// MIDI note → a spelled [Pitch] (sharps). Inverse of [Pitch.midiNumber].
Pitch pitchFromMidi(int midi) {
  final (step, alter) = _pcSpelling[midi % 12];
  return Pitch(step, alter: alter, octave: (midi ~/ 12) - 1);
}

/// A [NoteDuration] as whole grid steps (rounded — off-grid values quantize).
int durationToSteps(NoteDuration d, int stepsPerBeat) {
  final (num, den) = d.fraction;
  return (num * (stepsPerBeat * 4) / den).round();
}

List<(NoteDuration, int)> _durationLadder(int stepsPerBeat) {
  final stepsPerWhole = stepsPerBeat * 4;
  const candidates = <(NoteDuration, double)>[
    (NoteDuration(DurationBase.whole), 1.0),
    (NoteDuration(DurationBase.half, dots: 1), 0.75),
    (NoteDuration(DurationBase.half), 0.5),
    (NoteDuration(DurationBase.quarter, dots: 1), 0.375),
    (NoteDuration(DurationBase.quarter), 0.25),
    (NoteDuration(DurationBase.eighth, dots: 1), 0.1875),
    (NoteDuration(DurationBase.eighth), 0.125),
    (NoteDuration(DurationBase.sixteenth, dots: 1), 0.09375),
    (NoteDuration(DurationBase.sixteenth), 0.0625),
  ];
  final out = <(NoteDuration, int)>[];
  for (final (dur, frac) in candidates) {
    final steps = frac * stepsPerWhole;
    if ((steps - steps.roundToDouble()).abs() < 1e-9) {
      out.add((dur, steps.round()));
    }
  }
  return out;
}

List<NoteDuration> _decompose(int steps, List<(NoteDuration, int)> ladder) {
  final out = <NoteDuration>[];
  var rem = steps;
  while (rem > 0) {
    final piece =
        ladder.firstWhere((d) => d.$2 <= rem, orElse: () => ladder.last);
    out.add(piece.$1);
    rem -= piece.$2;
  }
  return out;
}

// ─── Module → notation ───────────────────────────────────────────────────────

/// A channel's cells flattened across the [doc]'s order list into one row-per-
/// step list, encoded for [_runsFromEvents]: `>=0` a note trigger, `-1` a ring
/// (let the previous note sound), `-2` a key-off (stop → rest).
List<int> _flattenChannel(ModuleDoc doc, int channel) {
  final events = <int>[];
  for (final patIndex in doc.order) {
    if (patIndex < 0 || patIndex >= doc.patterns.length) continue;
    final pat = doc.patterns[patIndex];
    for (final row in pat.rows) {
      final cell = channel < row.length ? row[channel] : DocCell.empty;
      if (cell.noteOff) {
        events.add(-2);
      } else if (cell.note >= 0) {
        events.add(cell.note);
      } else {
        events.add(-1);
      }
    }
  }
  return events;
}

/// Per-step events → `(midi?, steps)` runs. A note starts a run; `-1` extends
/// whatever is sounding (note or rest); `-2` starts a fresh rest.
List<(int?, int)> _runsFromEvents(List<int> events) {
  final runs = <(int?, int)>[];
  for (final e in events) {
    if (e >= 0) {
      runs.add((e, 1));
    } else if (e == -2) {
      runs.add((null, 1));
    } else {
      if (runs.isEmpty) {
        runs.add((null, 1));
      } else {
        final (m, s) = runs.last;
        runs[runs.length - 1] = (m, s + 1);
      }
    }
  }
  return runs;
}

/// `(midi?, steps)` runs → per-bar element lists (4/4). Held runs decompose to
/// tied notes; runs split at barlines. [idPrefix] namespaces note ids so merged
/// voices in one [Score] don't collide. Trailing rests are dropped so a module →
/// notation → module → notation cycle is a clean fixed point from the first pass
/// (leading/internal rests are kept — they position notes).
List<List<MusicElement>> _runsToBars(
  List<(int?, int)> runs,
  int stepsPerBeat, {
  String idPrefix = 'n',
}) {
  final ladder = _durationLadder(stepsPerBeat);
  final barSteps = stepsPerBeat * 4;
  var end = runs.length;
  while (end > 0 && runs[end - 1].$1 == null) {
    end--;
  }
  final trimmed = end == runs.length ? runs : runs.sublist(0, end);

  final bars = <List<MusicElement>>[];
  var current = <MusicElement>[];
  var posInBar = 0;
  var idCounter = 0;

  void closeBar() {
    bars.add(current);
    current = [];
    posInBar = 0;
  }

  for (final (midi, steps) in trimmed) {
    var rem = steps;
    while (rem > 0) {
      final avail = barSteps - posInBar;
      final take = rem < avail ? rem : avail;
      final pieces = _decompose(take, ladder);
      for (var i = 0; i < pieces.length; i++) {
        final lastOfRun = rem - take == 0 && i == pieces.length - 1;
        if (midi == null) {
          current.add(RestElement(pieces[i]));
        } else {
          current.add(
            NoteElement.note(
              pitchFromMidi(midi),
              pieces[i],
              tieToNext: !lastOfRun,
              id: '$idPrefix${idCounter++}',
            ),
          );
        }
      }
      posInBar += take;
      rem -= take;
      if (posInBar >= barSteps) closeBar();
    }
  }
  if (current.isNotEmpty) closeBar();
  return bars;
}

/// `(midi?, steps)` runs → a single-staff [Score] on [clef].
Score runsToScore(
  List<(int?, int)> runs,
  int stepsPerBeat, {
  Clef clef = Clef.treble,
}) =>
    Score(
      clef: clef,
      measures: [
        for (final bar in _runsToBars(runs, stepsPerBeat)) Measure(bar),
      ],
    );

/// The index of the busiest channel (most note triggers) in [doc]; 0 if none.
int busiestChannel(ModuleDoc doc) {
  var best = 0, bestCount = -1;
  for (var c = 0; c < doc.channelCount; c++) {
    final count = _flattenChannel(doc, c).where((e) => e >= 0).length;
    if (count > bestCount) {
      bestCount = count;
      best = c;
    }
  }
  return best;
}

/// The mean MIDI of a channel's notes, or null if it has none.
double? _meanPitch(List<int> events) {
  var sum = 0, n = 0;
  for (final e in events) {
    if (e >= 0) {
      sum += e;
      n++;
    }
  }
  return n == 0 ? null : sum / n;
}

/// One module [channel] → a single-staff [Score]. The clef is chosen from the
/// channel's mean pitch (bass below ~middle C, treble otherwise) unless [clef]
/// is given.
Score moduleChannelToScore(
  ModuleDoc doc,
  int channel, {
  int stepsPerBeat = 4,
  Clef? clef,
}) {
  final events = _flattenChannel(doc, channel);
  final mean = _meanPitch(events);
  final chosen =
      clef ?? ((mean != null && mean < 55) ? Clef.bass : Clef.treble);
  return runsToScore(_runsFromEvents(events), stepsPerBeat, clef: chosen);
}

/// The whole module as a [MultiPartScore] — one staff per channel that has any
/// note (a percussion-free "full band" view). [nameOf] resolves a display name
/// for a channel index (default `Channel N`).
({MultiPartScore score, List<String> partNames}) moduleToMultiPart(
  ModuleDoc doc, {
  int stepsPerBeat = 4,
  String Function(int channel)? nameOf,
}) {
  final parts = <Score>[];
  final names = <String>[];
  for (var c = 0; c < doc.channelCount; c++) {
    final events = _flattenChannel(doc, c);
    if (!events.any((e) => e >= 0)) continue; // skip silent channels
    parts.add(moduleChannelToScore(doc, c, stepsPerBeat: stepsPerBeat));
    names.add(nameOf?.call(c) ?? 'Channel ${c + 1}');
  }
  return (score: MultiPartScore(parts), partNames: names);
}

/// The channel indices that actually sound, ordered busiest → quietest.
List<int> _soundingChannelsByBusyness(ModuleDoc doc) {
  final sounding = <(int, int)>[];
  for (var c = 0; c < doc.channelCount; c++) {
    final n = _flattenChannel(doc, c).where((e) => e >= 0).length;
    if (n > 0) sounding.add((c, n));
  }
  sounding.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final s in sounding) s.$1];
}

/// The module as ONE [Score] carrying up to [maxVoices] voices — the busiest
/// channel is voice 1, the next busiest voices 2–4 (a [Measure] holds 4 voices
/// max). This is for the single-Score writers that render OVERLAY voices — ABC
/// and MuseScore keep all of them; MEI/kern render voice 1 only. For UNBOUNDED
/// parts (every channel, one staff each) use [moduleToMultiPart] → MusicXML.
///
/// A module with more than [maxVoices] sounding channels keeps only the busiest;
/// [droppedChannels] reports how many were left out so a caller can warn.
Score moduleToVoicedScore(
  ModuleDoc doc, {
  int maxVoices = 4,
  int stepsPerBeat = 4,
}) {
  final all = _soundingChannelsByBusyness(doc);
  final voices = all.take(maxVoices).toList();
  if (voices.isEmpty) return const Score(clef: Clef.treble, measures: []);

  final barsPerVoice = [
    for (var v = 0; v < voices.length; v++)
      _runsToBars(
        _runsFromEvents(_flattenChannel(doc, voices[v])),
        stepsPerBeat,
        idPrefix: 'v${v}n',
      ),
  ];
  final maxBars = barsPerVoice.map((b) => b.length).fold(0, math.max);
  final mean = _meanPitch(_flattenChannel(doc, voices.first));
  final clef = (mean != null && mean < 55) ? Clef.bass : Clef.treble;

  // A missing bar is a whole-bar rest for voice 1 (keeps the measure full) and
  // simply absent for the overlay voices 2–4.
  List<MusicElement> barOf(int v, int i) => i < barsPerVoice[v].length
      ? barsPerVoice[v][i]
      : (v == 0
          ? const [RestElement(NoteDuration(DurationBase.whole))]
          : const []);

  return Score(
    clef: clef,
    measures: [
      for (var i = 0; i < maxBars; i++)
        Measure(
          barOf(0, i),
          voice2: voices.length > 1 ? barOf(1, i) : const [],
          voice3: voices.length > 2 ? barOf(2, i) : const [],
          voice4: voices.length > 3 ? barOf(3, i) : const [],
        ),
    ],
  );
}

/// How many channels actually sound (have at least one note).
int soundingChannelCount(ModuleDoc doc) =>
    _soundingChannelsByBusyness(doc).length;

/// How many sounding channels [moduleToVoicedScore] would drop (channels beyond
/// [maxVoices]) — for a caller to warn "kept the 4 busiest of N".
int voicedDroppedChannels(ModuleDoc doc, {int maxVoices = 4}) {
  final n = soundingChannelCount(doc);
  return n > maxVoices ? n - maxVoices : 0;
}

// ─── Notation → module ───────────────────────────────────────────────────────

/// A tiny single-cycle sine, the default instrument for a synthetic module so
/// the notes are actually audible and the format writers have PCM to store.
DocSample _defaultSample() {
  final pcm = Float64List(64);
  for (var i = 0; i < 64; i++) {
    pcm[i] = math.sin(2 * math.pi * i / 64);
  }
  return DocSample(name: 'note', pcm: pcm);
}

/// A [score] split across [channelCount] monophonic DocCell columns (each the
/// full length in steps). Chord pitches are dealt HIGH→LOW to channels 0,1,2…
/// (mirrors the Tracker's scoreToChannels); a rest emits a [DocCell.off] on the
/// top voice so the held note stops (and the rest survives a round-trip). Tied
/// note elements merge into one held trigger.
List<List<DocCell>> scoreToDocChannels(
  Score score, {
  int channelCount = 1,
  int stepsPerBeat = 4,
}) {
  final elements = [for (final m in score.measures) ...m.elements];
  // First pass: total length in steps (so we can size the columns).
  var total = 0;
  for (final el in elements) {
    if (el is NoteElement || el is RestElement) {
      total += durationToSteps(el.duration, stepsPerBeat);
    }
  }
  final columns = [
    for (var c = 0; c < channelCount; c++)
      List<DocCell>.filled(total, DocCell.empty),
  ];

  var i = 0;
  var step = 0;
  while (i < elements.length && step < total) {
    final el = elements[i];
    if (el is RestElement) {
      if (step < total) columns[0][step] = const DocCell.off();
      step += durationToSteps(el.duration, stepsPerBeat);
      i++;
      continue;
    }
    if (el is NoteElement) {
      var steps = durationToSteps(el.duration, stepsPerBeat);
      final voices = [for (final p in el.pitches) p.midiNumber]
        ..sort((a, b) => b.compareTo(a)); // high → low
      // Merge tied continuations into one held note.
      var cur = el;
      while (cur.tieToNext &&
          i + 1 < elements.length &&
          elements[i + 1] is NoteElement) {
        final next = elements[i + 1] as NoteElement;
        steps += durationToSteps(next.duration, stepsPerBeat);
        cur = next;
        i++;
      }
      for (var v = 0; v < voices.length && v < channelCount; v++) {
        columns[v][step] = DocCell(note: voices[v], instrument: 1);
      }
      step += steps;
      i++;
      continue;
    }
    i++; // barlines / other elements — skip
  }
  return columns;
}

/// Packs full-length DocCell [columns] (one per channel) into a [ModuleDoc] with
/// [rowsPerPattern]-row patterns (64 = safe for every format). One shared
/// instrument/sample backs all notes.
ModuleDoc _docFromColumns(
  List<List<DocCell>> columns, {
  required String title,
  required ModuleFormat format,
  DocSample? sample,
  int rowsPerPattern = 64,
  int initialSpeed = 6,
  int initialTempo = 125,
}) {
  final channelCount = columns.length;
  final total = columns.isEmpty ? 0 : columns.first.length;
  final numPatterns =
      total == 0 ? 1 : (total + rowsPerPattern - 1) ~/ rowsPerPattern;
  final patterns = <DocPattern>[];
  for (var p = 0; p < numPatterns; p++) {
    final rows = <List<DocCell>>[];
    for (var r = 0; r < rowsPerPattern; r++) {
      final step = p * rowsPerPattern + r;
      rows.add([
        for (var c = 0; c < channelCount; c++)
          if (step < total)
            columns[c][step]
          // Terminate the ring exactly at the content boundary so the last note
          // doesn't sound through the pattern padding (else doc→Score inflates
          // its duration to the end of the pattern).
          else if (step == total)
            const DocCell.off()
          else
            DocCell.empty,
      ]);
    }
    patterns.add(DocPattern(rows, channelCount));
  }
  return ModuleDoc(
    title: title,
    channelCount: channelCount == 0 ? 1 : channelCount,
    initialSpeed: initialSpeed,
    initialTempo: initialTempo,
    sourceFormat: format,
    order: [for (var p = 0; p < numPatterns; p++) p],
    patterns: patterns,
    samples: [sample ?? _defaultSample()],
  );
}

/// A [score] → a playable [ModuleDoc]. Chords split across [channelCount]
/// channels. The result carries one default sine instrument so it plays and the
/// format writers have PCM to store.
ModuleDoc scoreToModuleDoc(
  Score score, {
  int channelCount = 1,
  int stepsPerBeat = 4,
  String title = 'SCORE',
  ModuleFormat format = ModuleFormat.it,
  DocSample? sample,
}) {
  final columns = scoreToDocChannels(
    score,
    channelCount: channelCount,
    stepsPerBeat: stepsPerBeat,
  );
  return _docFromColumns(columns, title: title, format: format, sample: sample);
}

/// A [multiPart] score → a [ModuleDoc] with one channel per part (each part's
/// top voice). Parts of differing length are padded to the longest.
ModuleDoc multiPartToModuleDoc(
  MultiPartScore multiPart, {
  int stepsPerBeat = 4,
  String title = 'SCORE',
  ModuleFormat format = ModuleFormat.it,
  DocSample? sample,
}) {
  final perPart = [
    for (final part in multiPart.parts)
      scoreToDocChannels(part, stepsPerBeat: stepsPerBeat).first,
  ];
  if (perPart.isEmpty) {
    return _docFromColumns([], title: title, format: format, sample: sample);
  }
  final maxLen = perPart.map((c) => c.length).reduce(math.max);
  final columns = [
    for (final col in perPart)
      List<DocCell>.generate(
        maxLen,
        (i) => i < col.length ? col[i] : DocCell.empty,
        growable: false,
      ),
  ];
  return _docFromColumns(columns, title: title, format: format, sample: sample);
}

// ─── Multi-track MIDI (the format-1 round-trip the library lacks) ────────────

/// Reads one SMF chunk (`type` + big-endian length + body) at [offset]; returns
/// the whole chunk bytes and the offset past it.
(Uint8List chunk, int next) _readChunk(Uint8List smf, int offset) {
  final len = (smf[offset + 4] << 24) |
      (smf[offset + 5] << 16) |
      (smf[offset + 6] << 8) |
      smf[offset + 7];
  final end = offset + 8 + len;
  return (Uint8List.sublistView(smf, offset, end), end);
}

/// The first `MTrk` chunk (header + body) of a single-track SMF.
Uint8List _firstTrackChunk(Uint8List smf) {
  // MThd is 14 bytes (8 header + 6 body); the track follows.
  final (chunk, _) = _readChunk(smf, 14);
  return chunk;
}

Uint8List _u32(int v) => Uint8List.fromList(
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff],
    );
Uint8List _u16(int v) => Uint8List.fromList([(v >> 8) & 0xff, v & 0xff]);

/// Assembles several single-track SMFs into one format-1 file (one MTrk each) —
/// the multi-track export scoreToMidi can't do alone. All tracks share
/// [ticksPerQuarter], so pass the same value used to write [singleTrackSmfs].
Uint8List mergeToMultiTrackMidi(
  List<Uint8List> singleTrackSmfs, {
  int ticksPerQuarter = 480,
}) {
  final tracks = [for (final smf in singleTrackSmfs) _firstTrackChunk(smf)];
  final out = BytesBuilder();
  out.add(Uint8List.fromList('MThd'.codeUnits));
  out.add(_u32(6));
  out.add(_u16(1)); // format 1
  out.add(_u16(tracks.length));
  out.add(_u16(ticksPerQuarter));
  for (final t in tracks) {
    out.add(t);
  }
  return out.toBytes();
}

/// Splits a (format 0 or 1) SMF into one single-track format-0 SMF per `MTrk`,
/// so each can be read back with `scoreFromMidi`. Inverse of
/// [mergeToMultiTrackMidi] for round-trip verification.
List<Uint8List> splitMultiTrackMidi(Uint8List smf) {
  final division = (smf[12] << 8) | smf[13];
  final tracks = <Uint8List>[];
  var offset = 14; // past MThd
  while (offset + 8 <= smf.length) {
    final type = String.fromCharCodes(smf.sublist(offset, offset + 4));
    final (chunk, next) = _readChunk(smf, offset);
    if (type == 'MTrk') tracks.add(chunk);
    offset = next;
  }
  return [
    for (final t in tracks)
      (BytesBuilder()
            ..add(Uint8List.fromList('MThd'.codeUnits))
            ..add(_u32(6))
            ..add(_u16(0)) // format 0
            ..add(_u16(1))
            ..add(_u16(division))
            ..add(t))
          .toBytes(),
  ];
}

/// A [multiPart] score → a format-1 SMF, one track per part.
Uint8List multiPartToMidi(
  MultiPartScore multiPart, {
  double quarterBpm = 120,
  int ticksPerQuarter = 480,
}) =>
    mergeToMultiTrackMidi(
      [
        for (final part in multiPart.parts)
          scoreToMidi(
            part,
            quarterBpm: quarterBpm,
            ticksPerQuarter: ticksPerQuarter,
          ),
      ],
      ticksPerQuarter: ticksPerQuarter,
    );

// ─── Module ↔ MusicXML (through the notation multi-part hub) ─────────────────

/// The whole module as MusicXML (partwise), one part per sounding channel.
String moduleToMusicXml(ModuleDoc doc, {int stepsPerBeat = 4}) {
  final parts = moduleToMultiPart(doc, stepsPerBeat: stepsPerBeat);
  return multiPartToMusicXml(parts.score, partNames: parts.partNames);
}

/// MusicXML → a playable [ModuleDoc] (one channel per part).
ModuleDoc musicXmlToModuleDoc(
  String xml, {
  int stepsPerBeat = 4,
  String title = 'SCORE',
  ModuleFormat format = ModuleFormat.it,
}) =>
    multiPartToModuleDoc(
      multiPartScoreFromMusicXml(xml),
      stepsPerBeat: stepsPerBeat,
      title: title,
      format: format,
    );

// ─── Module ↔ MuseScore .mscz (zipped .mscx container) ───────────────────────

/// A single [score] → `.mscz` bytes (a zip wrapping the `.mscx` XML).
Uint8List scoreToMscz(Score score) => writeMsczFromMscx(scoreToMscx(score));

/// `.mscz` bytes → Score (unzips the `.mscx`, then parses it).
Score scoreFromMscz(Uint8List bytes) => scoreFromMscx(readMscxFromMscz(bytes));

/// [doc] → `.mscz` bytes. With no [channel], up to 4 channels become overlay
/// voices ([moduleToVoicedScore], which MuseScore renders); a specific [channel]
/// forces that one line.
Uint8List moduleToMscz(ModuleDoc doc, {int? channel, int stepsPerBeat = 4}) =>
    scoreToMscz(
      channel != null
          ? moduleChannelToScore(doc, channel, stepsPerBeat: stepsPerBeat)
          : moduleToVoicedScore(doc, stepsPerBeat: stepsPerBeat),
    );

/// `.mscz` bytes → a playable single-channel [ModuleDoc].
ModuleDoc msczToModuleDoc(
  Uint8List bytes, {
  int stepsPerBeat = 4,
  String title = 'SCORE',
  ModuleFormat format = ModuleFormat.it,
}) =>
    scoreToModuleDoc(
      scoreFromMscz(bytes),
      stepsPerBeat: stepsPerBeat,
      title: title,
      format: format,
    );

// ─── Module ↔ the single-Score text notations (ABC / MEI / kern / MuseScore /
//     LilyPond) — one channel each, through crisp_notation_core's codecs ───────

/// The text notation formats crisp_notation_core carries. All are readable
/// except [lilypond] (write-only in the library).
enum TextNotation { abc, kern, mei, musescore, lilypond }

/// True if this format can be parsed back to a Score (everything but LilyPond).
bool textNotationReadable(TextNotation fmt) => fmt != TextNotation.lilypond;

/// A [multiPart] score as ONE multi-voice ABC tune — each part becomes an ABC
/// `V:` voice. Unlike [scoreToAbc]'s 4-voices-on-one-staff cap, ABC `V:` voices
/// are separate staves and UNBOUNDED, so this keeps every instrument: the
/// orchestra case. [partNames] label the voices; each voice carries its part's
/// clef. (crisp_notation_core has no multi-part ABC writer, so we assemble it
/// from the per-part single-voice tunes.)
String multiPartToAbc(MultiPartScore multiPart, {List<String>? partNames}) {
  final parts = multiPart.parts;
  final out = StringBuffer()
    ..writeln('X:1')
    ..writeln('L:1/8')
    ..writeln('K:C');
  if (parts.isEmpty) return out.toString();

  String clefOf(Clef c) => c == Clef.bass ? 'bass' : 'treble';
  // Declare all voices first (readers expect the V: roster before the bodies).
  for (var i = 0; i < parts.length; i++) {
    final name = (partNames != null && i < partNames.length)
        ? partNames[i]
        : 'V${i + 1}';
    out.writeln('V:${i + 1} name="$name" clef=${clefOf(parts[i].clef)}');
  }
  // Then each voice's body — the per-part tune with its header fields stripped.
  final headerField = RegExp(r'^[A-Za-z]:');
  for (var i = 0; i < parts.length; i++) {
    out.writeln('V:${i + 1}');
    for (final line in scoreToAbc(parts[i]).split('\n')) {
      if (line.trim().isEmpty || headerField.hasMatch(line)) continue;
      out.writeln(line);
    }
  }
  return out.toString();
}

/// A single [score] serialized to [fmt] text.
String scoreToTextNotation(Score score, TextNotation fmt) => switch (fmt) {
      TextNotation.abc => scoreToAbc(score),
      TextNotation.kern => scoreToKern(score),
      TextNotation.mei => scoreToMei(score),
      TextNotation.musescore => scoreToMscx(score),
      TextNotation.lilypond => scoreToLilyPond(score),
    };

/// [text] in [fmt] parsed to a Score; null for a write-only format
/// ([TextNotation.lilypond]).
Score? textNotationToScore(String text, TextNotation fmt) => switch (fmt) {
      TextNotation.abc => scoreFromAbc(text),
      TextNotation.kern => scoreFromKern(text),
      TextNotation.mei => scoreFromMei(text),
      TextNotation.musescore => scoreFromMscx(text),
      TextNotation.lilypond => null, // write-only in the library
    };

/// [doc] serialized to [fmt] text. With no [channel], up to 4 channels are kept
/// as overlay voices ([moduleToVoicedScore]) — ABC and MuseScore render all of
/// them; MEI/kern show voice 1 only (their writers are single-voice). A specific
/// [channel] forces that one line. For EVERY channel on its own staff use
/// [moduleToMusicXml].
String moduleToTextNotation(
  ModuleDoc doc,
  TextNotation fmt, {
  int? channel,
  int stepsPerBeat = 4,
}) {
  if (channel != null) {
    return scoreToTextNotation(
      moduleChannelToScore(doc, channel, stepsPerBeat: stepsPerBeat),
      fmt,
    );
  }
  // ABC has unbounded V: voices → keep EVERY channel (the orchestra case).
  if (fmt == TextNotation.abc) {
    final mp = moduleToMultiPart(doc, stepsPerBeat: stepsPerBeat);
    return multiPartToAbc(mp.score, partNames: mp.partNames);
  }
  // The other single-Score writers cap at 4 overlay voices on one staff.
  return scoreToTextNotation(
    moduleToVoicedScore(doc, stepsPerBeat: stepsPerBeat),
    fmt,
  );
}

/// [text] in [fmt] → a playable single-channel [ModuleDoc]. Returns null for a
/// write-only format ([TextNotation.lilypond]).
ModuleDoc? textNotationToModuleDoc(
  String text,
  TextNotation fmt, {
  int stepsPerBeat = 4,
  String title = 'SCORE',
  ModuleFormat format = ModuleFormat.it,
}) {
  final score = textNotationToScore(text, fmt);
  if (score == null) return null;
  return scoreToModuleDoc(
    score,
    stepsPerBeat: stepsPerBeat,
    title: title,
    format: format,
  );
}
