// lib/features/games/songs/import/midi_import.dart
//
// Standard MIDI File (SMF) import for SIMPLE, monophonic melodies: parses
// format 0/1, takes the first track that contains notes, drops overlapping
// notes (no polyphony), quantizes to a sixteenth grid and emits a Score.
// Polyphonic piano files are out of scope — that's a transcription problem,
// not a parsing one.

import 'dart:typed_data';

// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:crisp_notation/crisp_notation.dart'
    show
        Clef,
        DurationBase,
        Measure,
        MusicElement,
        NoteDuration,
        NoteElement,
        Pitch,
        RestElement,
        Score,
        Step;

class _MidiNote {
  final int startTicks;
  final int midi;
  int durationTicks;

  _MidiNote(this.startTicks, this.midi, this.durationTicks);
}

/// Parses [bytes] as an SMF and returns a quantized, monophonic [Score].
/// Throws [FormatException] on unusable input.
Score scoreFromMidi(Uint8List bytes, {int maxNotes = 64}) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 14 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'MThd') {
    throw const FormatException('Not a MIDI file (missing MThd)');
  }
  final division = data.getUint16(12);
  if (division & 0x8000 != 0) {
    throw const FormatException('SMPTE time division is not supported');
  }
  if (division == 0) {
    // 0 ticks/quarter would make the sixteenth grid divide by zero below
    // (Infinity/NaN.round() throws) — reject it as malformed here instead.
    throw const FormatException('Invalid MIDI time division (0)');
  }

  // Walk the chunks; collect notes from the first track that has any. A chunk
  // length is attacker-controlled, so the track slice is clamped to the buffer
  // — a corrupt/truncated MIDI can only yield a clean FormatException, never an
  // out-of-bounds RangeError.
  var offset = 8 + data.getUint32(4);
  List<_MidiNote>? notes;
  while (offset + 8 <= bytes.length && notes == null) {
    final chunkType = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkLength = data.getUint32(offset + 4);
    final chunkEnd = offset + 8 + chunkLength;
    if (chunkType == 'MTrk') {
      final track = _readTrack(
        bytes.sublist(
          offset + 8,
          chunkEnd <= bytes.length ? chunkEnd : bytes.length,
        ),
      );
      if (track.isNotEmpty) notes = track;
    }
    offset = chunkEnd;
  }
  if (notes == null) {
    throw const FormatException('No notes found in any track');
  }

  // Monophonic-ize: keep the earliest-sounding line, drop overlaps.
  notes.sort((a, b) => a.startTicks.compareTo(b.startTicks));
  final line = <_MidiNote>[];
  var lineEnd = -1;
  for (final note in notes) {
    if (note.startTicks >= lineEnd) {
      line.add(note);
      lineEnd = note.startTicks + note.durationTicks;
    }
  }

  // Quantize to sixteenths (division ticks per quarter -> /4 per 16th).
  final ticksPer16th = division / 4;
  const durations = <int, NoteDuration>{
    16: NoteDuration(DurationBase.whole),
    12: NoteDuration(DurationBase.half, dots: 1),
    8: NoteDuration(DurationBase.half),
    6: NoteDuration(DurationBase.quarter, dots: 1),
    4: NoteDuration(DurationBase.quarter),
    3: NoteDuration(DurationBase.eighth, dots: 1),
    2: NoteDuration(DurationBase.eighth),
    1: NoteDuration(DurationBase.sixteenth),
  };
  NoteDuration snap(int sixteenths) {
    for (final entry in durations.entries) {
      if (sixteenths >= entry.key) return entry.value;
    }
    return const NoteDuration(DurationBase.sixteenth);
  }

  final elements = <MusicElement>[];
  var cursor16 = -1; // set on the first note; leading silence is dropped
  var id = 0;
  for (final note in line.take(maxNotes)) {
    final start16 = (note.startTicks / ticksPer16th).round();
    final dur16 = (note.durationTicks / ticksPer16th).round().clamp(1, 16);
    if (cursor16 >= 0 && start16 > cursor16) {
      final gap = (start16 - cursor16).clamp(1, 16);
      elements.add(RestElement(snap(gap)));
    }
    elements.add(
      NoteElement.note(
        _pitchFromMidi(note.midi),
        snap(dur16),
        id: 'e${id++}',
      ),
    );
    cursor16 = start16 + dur16;
  }
  if (elements.whereType<NoteElement>().isEmpty) {
    throw const FormatException('No usable notes after quantization');
  }

  // Chunk into measures for line breaking (unmetered: sums unchecked).
  final measures = <Measure>[];
  for (var i = 0; i < elements.length; i += 8) {
    measures.add(
      Measure(
        elements.sublist(
          i,
          i + 8 > elements.length ? elements.length : i + 8,
        ),
      ),
    );
  }
  return Score(clef: Clef.treble, measures: measures);
}

/// Sharp-preferring spelling for a MIDI number.
Pitch _pitchFromMidi(int midi) {
  const steps = [
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
  final (step, alter) = steps[midi % 12];
  return Pitch(step, alter: alter, octave: midi ~/ 12 - 1);
}

List<_MidiNote> _readTrack(Uint8List track) {
  final notes = <_MidiNote>[];
  final open = <int, _MidiNote>{}; // midi -> sounding note
  var offset = 0;
  var ticks = 0;
  var runningStatus = 0;

  int readVarLen() {
    var value = 0;
    while (offset < track.length) {
      final byte = track[offset++];
      value = (value << 7) | (byte & 0x7f);
      if (byte & 0x80 == 0) break;
    }
    return value;
  }

  while (offset < track.length) {
    ticks += readVarLen();
    if (offset >= track.length) break;
    var status = track[offset];
    if (status & 0x80 != 0) {
      offset++;
    } else {
      status = runningStatus; // running status: reuse previous
    }

    if (status == 0xff) {
      offset++; // meta type
      final length = readVarLen();
      offset += length;
      continue;
    }
    if (status == 0xf0 || status == 0xf7) {
      final length = readVarLen();
      offset += length;
      continue;
    }

    runningStatus = status;
    final kind = status & 0xf0;
    final dataLength = (kind == 0xc0 || kind == 0xd0) ? 1 : 2;
    if (offset + dataLength > track.length) break;
    final d1 = track[offset];
    final d2 = dataLength == 2 ? track[offset + 1] : 0;
    offset += dataLength;

    if (kind == 0x90 && d2 > 0) {
      open[d1] = _MidiNote(ticks, d1, 0);
    } else if (kind == 0x80 || (kind == 0x90 && d2 == 0)) {
      final note = open.remove(d1);
      if (note != null) {
        note.durationTicks = ticks - note.startTicks;
        if (note.durationTicks > 0) notes.add(note);
      }
    }
  }
  return notes;
}
